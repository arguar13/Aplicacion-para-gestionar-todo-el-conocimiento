import 'dart:math' as math;

import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/reviewable_ai_thing.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_atlas_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_item_reviewer.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/things_reviewer.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_parser.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

/// Cuántas cosas van en un pedido, como mucho: cada una lleva su valor, sus
/// opciones y, un vínculo, el comienzo del otro elemento. Dentro de eso, las
/// que el modelo elegido escribe por pedido (`maxDraftsPerCall`: cuatro en
/// Gemma, ocho con una ventana grande).
const kMaxThingsPerCall = 8;

/// Cuánto del otro elemento de un vínculo ve el revisor: alcanza para saber
/// de qué trata.
const kRelatedExcerptChars = 240;

/// Lo más largo y lo más corto del fragmento del elemento que acompaña cada
/// pedido: un cuarto de lo que el modelo lee por pedido, y el resto para lo
/// que se revisa.
const kMaxItemExcerptChars = 2000;
const kMinItemExcerptChars = 400;

/// Revisa lo demás que hizo la IA en un elemento —los vínculos, las
/// etiquetas, el tema, los datos de la referencia, la introducción de una
/// nota mapa—, con el modelo elegido ahora (F33, «Revisar con otro modelo»),
/// y deja en «Revisión» lo que propone corregir o sacar. **No cambia nada**:
/// eso pasa solo si la persona acepta.
///
/// Qué se revisa lo dice el núcleo de las correcciones
/// (`AiRunRepository.reviewableThings`): lo que sigue siendo de la IA, con lo
/// que vale al corregirlo. Lo que se le muestra al modelo es lo que después
/// se puede aplicar.
///
/// Como las tarjetas, no vuelve a proponer lo que ya está para decidir ni lo
/// que la persona descartó.
class ReviewThingsStep implements AiItemReviewer {
  const ReviewThingsStep({
    required ThingsReviewer reviewer,
    required AiRunRepository runs,
    required AiAtlasRepository atlas,
    required SuggestionRepository suggestions,
    required ModelTextBudget Function() textBudget,
  }) : _reviewer = reviewer,
       _runs = runs,
       _atlas = atlas,
       _suggestions = suggestions,
       _textBudget = textBudget;

  final ThingsReviewer _reviewer;
  final AiRunRepository _runs;
  final AiAtlasRepository _atlas;
  final SuggestionRepository _suggestions;
  final ModelTextBudget Function() _textBudget;

  @override
  Future<AiStepReport> review(
    KnowledgeItem item, {
    required String runId,
    String? model,
    String? exceptMadeBy,
  }) async {
    final all = (await _runs.reviewableThings(
      item.id,
    )).orThrowStep('leer lo que hizo la IA');
    final known = (await _suggestions.suggestionsFor(
      item.id,
    )).orThrowStep('leer las correcciones que ya hay');
    final corrections = known.whereType<CorrectionSuggestion>();
    final waiting = {
      for (final correction in corrections)
        if (correction.status == SuggestionStatus.pending)
          (correction.subject, correction.subjectId),
    };
    final discarded = {
      for (final correction in corrections)
        if (correction.status == SuggestionStatus.rejected)
          _keyOf(correction.subject, correction.subjectId, correction.after),
    };
    final things = [
      for (final thing in all)
        if (exceptMadeBy == null || thing.model != exceptMadeBy)
          if (!waiting.contains((thing.subject, thing.subjectId))) thing,
    ];
    if (things.isEmpty) return AiStepReport.nothing;

    final related = {
      for (final thing in things)
        if (thing.relatedItemId case final id?) id,
    };
    final excerpts = related.isEmpty
        ? const <String, String>{}
        : (await _atlas.excerptsOf(
            related.toList(),
            chars: kRelatedExcerptChars,
          )).orThrowStep('leer los otros elementos');

    final budget = _textBudget();
    final perCall = budget.maxDraftsPerCall.clamp(1, kMaxThingsPerCall);
    final excerptChars = (budget.partChars ~/ 4).clamp(
      kMinItemExcerptChars,
      kMaxItemExcerptChars,
    );
    final itemExcerpt = _cut(
      extractableRendition(item)?.content ?? item.searchableText,
      excerptChars,
    );

    var proposed = 0;
    for (var from = 0; from < things.length; from += perCall) {
      final batch = things.sublist(
        from,
        math.min(from + perCall, things.length),
      );
      final verdicts = await _reviewer.reviewThings(
        itemTitle: item.title,
        itemExcerpt: itemExcerpt,
        things: [
          for (final thing in batch)
            _toReview(thing, item: item, excerpts: excerpts),
        ],
      );
      for (final verdict in verdicts) {
        if (verdict.index < 0 || verdict.index >= batch.length) continue;
        final thing = batch[verdict.index];
        final after = switch (verdict) {
          ThingCorrection() => _afterOf(thing, verdict),
          ThingRemoval() => null,
        };
        // Una corrección que no se puede leer de vuelta no se propone.
        if (verdict is ThingCorrection && after == null) continue;
        if (discarded.contains(_keyOf(thing.subject, thing.subjectId, after))) {
          continue;
        }
        (await _suggestions.createCorrectionSuggestion(
          targetItemId: item.id,
          subject: thing.subject,
          subjectId: thing.subjectId,
          before: thing.before,
          after: after,
          reason: verdict.reason,
          aiRunId: runId,
          model: model,
          label: thing.label,
        )).orThrowStep('dejar una corrección para decidir');
        proposed++;
      }
    }
    return AiStepReport(forReview: proposed);
  }

  /// [thing] como se le muestra al modelo: con las palabras del pedido.
  static ThingToReview _toReview(
    ReviewableAiThing thing, {
    required KnowledgeItem item,
    required Map<String, String> excerpts,
  }) {
    final before = thing.before;
    return switch (thing.subject) {
      CorrectionSubject.relation => ThingToReview(
        subject: thing.subject,
        name: 'vínculo con «${thing.label ?? ''}»',
        value: _token(before[RelationCorrectionField.kind]),
        note: before[RelationCorrectionField.note],
        options: [for (final option in thing.options) _token(option.id)],
        canFix: thing.canFix,
        canRemove: thing.canRemove,
        context: excerpts[thing.relatedItemId] ?? '',
      ),
      CorrectionSubject.property => ThingToReview(
        subject: thing.subject,
        name: before[PropertyCorrectionField.category] == kTemaCategoryName
            ? 'etiqueta'
            : 'propiedad «${before[PropertyCorrectionField.category]}»',
        value: before[PropertyCorrectionField.value] ?? '',
        options: [for (final option in thing.options) option.label],
        canFix: thing.canFix,
        canRemove: thing.canRemove,
      ),
      CorrectionSubject.space => ThingToReview(
        subject: thing.subject,
        name: 'tema de la biblioteca',
        value: before[SpaceCorrectionField.name] ?? '',
        options: [for (final option in thing.options) option.label],
        canFix: thing.canFix,
        canRemove: thing.canRemove,
      ),
      CorrectionSubject.reference => ThingToReview(
        subject: thing.subject,
        name:
            '${_referenceName(before[ReferenceCorrectionField.field])} de la '
            'referencia',
        value: before[ReferenceCorrectionField.value] ?? '',
        canFix: thing.canFix,
        canRemove: thing.canRemove,
      ),
      CorrectionSubject.mapIntro => ThingToReview(
        subject: thing.subject,
        name: 'introducción de esta nota mapa, que reúne lo de un tema',
        value: before[MapIntroCorrectionField.text] ?? '',
        canFix: thing.canFix,
        canRemove: thing.canRemove,
        context: _gathered(item),
      ),
      // Las tarjetas tienen su propio revisor.
      CorrectionSubject.flashcard => throw StateError(
        'Una tarjeta no se revisa como lo demás.',
      ),
    };
  }

  /// El después de [thing] según [verdict], como lo lee la corrección; `null`
  /// si lo que dijo el modelo no se puede traducir de vuelta.
  static Map<String, String>? _afterOf(
    ReviewableAiThing thing,
    ThingCorrection verdict,
  ) {
    final before = thing.before;
    switch (thing.subject) {
      case CorrectionSubject.relation:
        final kind = relationKindForToken(verdict.value);
        if (kind == null) return null;
        return {
          RelationCorrectionField.kind: kind.name,
          RelationCorrectionField.note: verdict.note ?? '',
        };
      case CorrectionSubject.property:
        final option = _optionNamed(thing, verdict.value);
        if (option == null) return null;
        return {
          PropertyCorrectionField.category:
              before[PropertyCorrectionField.category] ?? '',
          PropertyCorrectionField.value: option.id,
        };
      case CorrectionSubject.space:
        final option = _optionNamed(thing, verdict.value);
        if (option == null) return null;
        return {
          SpaceCorrectionField.id: option.id,
          SpaceCorrectionField.name: option.label,
        };
      case CorrectionSubject.reference:
        return {...before, ReferenceCorrectionField.value: verdict.value};
      case CorrectionSubject.mapIntro:
        return {MapIntroCorrectionField.text: verdict.value};
      case CorrectionSubject.flashcard:
        return null;
    }
  }

  static ReviewOption? _optionNamed(ReviewableAiThing thing, String label) {
    for (final option in thing.options) {
      if (option.label == label) return option;
    }
    return null;
  }

  /// La palabra del pedido para el tipo de vínculo guardado como [name].
  static String _token(String? name) {
    final kind = RelationKind.values.asNameMap()[name];
    return (kind == null ? null : relationKindToken(kind)) ?? name ?? '';
  }

  /// Cómo se le nombra al modelo el dato de la referencia [field]
  /// (`AiChangedField.name`).
  static String _referenceName(String? field) =>
      switch (AiChangedField.values.asNameMap()[field]) {
        AiChangedField.containerTitle => 'Publicado en (revista o libro)',
        AiChangedField.publisher => 'Editorial',
        AiChangedField.publisherPlace => 'Lugar de publicación',
        AiChangedField.edition => 'Edición',
        AiChangedField.volume => 'Volumen',
        AiChangedField.issue => 'Número',
        AiChangedField.pages => 'Páginas',
        AiChangedField.isbn => 'ISBN',
        AiChangedField.issn => 'ISSN',
        AiChangedField.doi => 'DOI',
        _ => field ?? '',
      };

  /// Lo que reúne la nota mapa [item]: los títulos de sus secciones y de lo
  /// que enlaza, para juzgar si la introducción les hace justicia.
  static String _gathered(KnowledgeItem item) {
    final titles = <String>[];
    for (final rendition in item.renditions.whereType<TextRendition>()) {
      if (rendition.kind != RenditionKind.blocks) continue;
      for (final block
          in tryDecodeContentBlocks(rendition.content) ?? const []) {
        switch (block) {
          case HeadingBlock(:final text) || BulletItemBlock(:final text):
            titles.add(text.replaceAll('[[', '').replaceAll(']]', '').trim());
          default:
        }
      }
    }
    return _cut(titles.where((t) => t.isNotEmpty).join(', '), 800);
  }

  /// Cómo se reconoce la misma corrección: lo corregido y lo que propone,
  /// sin mayúsculas ni espacios de más. Sacarlo es una sola.
  static String _keyOf(
    CorrectionSubject subject,
    String subjectId,
    Map<String, String>? after,
  ) {
    final base = '${subject.name}\u001f$subjectId';
    if (after == null) return '$base\u001fsacar';
    String plain(String text) =>
        text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final keys = after.keys.toList()..sort();
    return [
      base,
      for (final key in keys) '$key=${plain(after[key]!)}',
    ].join('\u001f');
  }

  /// [text] hasta [max] caracteres, cortado en una palabra entera.
  static String _cut(String text, int max) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= max) return flat;
    final head = flat.substring(0, max);
    final space = head.lastIndexOf(' ');
    return '${head.substring(0, space > max ~/ 2 ? space : max).trim()}…';
  }
}
