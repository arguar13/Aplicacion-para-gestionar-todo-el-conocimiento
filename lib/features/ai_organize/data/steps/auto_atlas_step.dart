import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_atlas.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_atlas_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_atlas_rules.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_intro.dart';
import 'package:sinapsis/features/ai_organize/domain/services/topic_parent_chooser.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

/// El Atlas, hecho por la IA (F27, decisión A): lo que hasta acá era trabajo a
/// mano. Corre al final de la pasada de cada elemento, con lo que los pasos
/// anteriores dejaron —sus temas—, y hace tres cosas:
///
/// 1. **El árbol de temas.** Un tema del elemento que está suelto —sin padre
///    ni subtemas— se ubica bajo uno del árbol que eligió el modelo. Se aplica
///    solo si el modelo está seguro y el tema es NUEVO —nació desde que la IA
///    organiza—: un tema viejo en la raíz pudo haberlo dejado ahí la persona,
///    y la base no guarda quién movió qué, así que para esos solo se propone.
///    Lo dudoso va a «Para revisar». Nunca crea temas, nunca mueve uno que
///    tiene padre o subtemas, y nunca vuelve sobre un tema del que ya decidió
///    algo —lo aplicó, lo propuso, se descartó o se deshizo—.
/// 2. **Las notas mapa.** El tema del elemento y sus ancestros, si juntan
///    material suficiente (`kAiMapNoteMinItems`) y no tienen nota mapa,
///    reciben una de la IA: el índice con enlaces a lo que hay y una
///    introducción del modelo. La de la IA se actualiza cuando entra o sale
///    material, mientras nadie la edite; editada, es de la persona. Lo que la
///    persona le sacó a un tema no vuelve.
/// 3. **La madurez.** Si el elemento es una nota viva que creció
///    (`grownMaturity`), queda en «Para revisar» subirle la madurez. Nunca la
///    cambia: es el juicio de la persona.
///
/// El modelo trabaja con el turno de la cola (`GemmaChatModel.background`) y
/// con pedidos acotados a su ventana: hasta [kAtlasPlacementsPerItem]
/// preguntas por el árbol y [kAiMapNotesPerItem] introducciones por elemento.
class AutoAtlasStep implements AiOrganizeStep {
  AutoAtlasStep({
    required AiAtlasRepository atlas,
    required LibraryRepository library,
    required SuggestionRepository suggestions,
    required TopicParentChooser chooseParent,
    required MapIntroWriter writeIntro,
    required Future<DateTime> Function() epoch,
    required String Function() modelName,
    required Clock clock,
  }) : _atlas = atlas,
       _library = library,
       _suggestions = suggestions,
       _chooseParent = chooseParent,
       _writeIntro = writeIntro,
       _epoch = epoch,
       _modelName = modelName,
       _clock = clock;

  final AiAtlasRepository _atlas;
  final LibraryRepository _library;
  final SuggestionRepository _suggestions;
  final TopicParentChooser _chooseParent;
  final MapIntroWriter _writeIntro;

  /// Desde cuándo organiza la IA (`AiOrganizeMemory.epoch`): un tema nacido
  /// después es nuevo.
  final Future<DateTime> Function() _epoch;

  /// Qué modelo escribe: queda en la nota mapa, como en un derivado de F16.
  final String Function() _modelName;
  final Clock _clock;

  /// Los temas para los que el modelo no eligió ningún padre en esta sesión:
  /// no se le vuelve a preguntar por cada elemento que los traiga. No se
  /// guarda en la base —no es una decisión de nadie—: en la próxima sesión,
  /// con el árbol quizá más armado, se pregunta de nuevo.
  final _noParent = <String>{};

  @override
  AiOrganizeToggle get toggle => AiOrganizeToggle.atlas;

  @override
  Future<AiStepReport> organize(
    KnowledgeItem item, {
    required String runId,
  }) async {
    // Los temas los pusieron los pasos anteriores de esta misma pasada: se
    // relee el elemento, no se usa el que la cola leyó al empezar.
    final current = (await _library.findById(
      item.id,
    )).orThrowStep('releer el elemento');
    if (current == null) return AiStepReport.nothing;

    var tree = (await _atlas.topicTree()).orThrowStep('leer el árbol de temas');
    final topicIds = [
      for (final tag in current.tags)
        if (tree[tag.id] != null) tag.id,
    ];

    final placed = await _placeLooseTopics(current, tree, topicIds, runId);
    if (placed.applied > 0) {
      tree = (await _atlas.topicTree()).orThrowStep('releer el árbol de temas');
    }
    final mapped = await _keepMapNotes(tree, topicIds);
    final maturity = await _proposeMaturity(current);

    return AiStepReport(
      applied: placed.applied + mapped.applied,
      forReview: placed.forReview + maturity.forReview,
    );
  }

  // -------------------------------------------------------------------------
  // El árbol de temas
  // -------------------------------------------------------------------------

  Future<AiStepReport> _placeLooseTopics(
    KnowledgeItem item,
    AtlasTopicTree tree,
    List<String> topicIds,
    String runId,
  ) async {
    final epoch = await _epoch();
    var applied = 0;
    var forReview = 0;
    var asked = 0;
    for (final valueId in topicIds) {
      if (asked >= kAtlasPlacementsPerItem) break;
      if (!tree.isLoose(valueId) || _noParent.contains(valueId)) continue;
      final decided = (await _atlas.hasPlacementRecord(
        valueId,
      )).orThrowStep('leer lo que la IA ya decidió del tema');
      if (decided) continue;

      final candidates = rankParentCandidates(
        tree,
        valueId,
        coTopicIds: topicIds,
      );
      // Sin árbol no hay dónde ubicar nada, ni este tema ni los otros.
      if (candidates.isEmpty) break;

      asked++;
      final topic = tree[valueId]!;
      final choice = await _chooseParent(
        topic: topic.label,
        itemTitle: item.title,
        candidates: [for (final id in candidates) tree.pathOf(id)],
      );
      if (choice == null) {
        _noParent.add(valueId);
        continue;
      }

      final parentId = candidates[choice.index];
      final isNew = !topic.createdAt.isBefore(epoch);
      if (isNew && choice.certainty == AiCertainty.high) {
        final done = (await _atlas.applyTopicPlacement(
          itemId: item.id,
          runId: runId,
          valueId: valueId,
          parentId: parentId,
        )).orThrowStep('ubicar el tema');
        if (done) applied++;
      } else {
        (await _atlas.proposeTopicPlacement(
          itemId: item.id,
          valueId: valueId,
          parentId: parentId,
        )).orThrowStep('dejar el lugar del tema para revisar');
        forReview++;
      }
    }
    return AiStepReport(applied: applied, forReview: forReview);
  }

  // -------------------------------------------------------------------------
  // Las notas mapa
  // -------------------------------------------------------------------------

  Future<AiStepReport> _keepMapNotes(
    AtlasTopicTree tree,
    List<String> topicIds,
  ) async {
    // El material de un tema también es de sus ancestros: un elemento de
    // «Roma» suma a «Historia antigua». De lo más específico a lo más
    // general, sin repetir.
    final targets = <String>{
      for (final id in topicIds) ...[id, ...tree.tree.ancestorsOf(id)],
    };
    var applied = 0;
    var written = 0;
    for (final topicId in targets) {
      if (written >= kAiMapNotesPerItem) break;
      final topic = tree[topicId]!;
      final material = (await _atlas.topicMaterial({
        topicId,
        ...tree.tree.descendantsOf(topicId),
      })).orThrowStep('leer el material del tema');
      if (material.length < kAiMapNoteMinItems) continue;

      final plan = planMapNote(
        tree: tree,
        topicId: topicId,
        material: material,
      );
      final maps = (await _atlas.mapNotesOf(
        topicId,
      )).orThrowStep('leer las notas mapa del tema');

      if (maps.isEmpty) {
        final declined = (await _atlas.mapNoteDeclined(
          topicId,
        )).orThrowStep('leer si la persona le sacó la nota mapa');
        if (declined) continue;
        written++;
        final created = (await _atlas.createMapNote(
          valueId: topicId,
          title: aiMapNoteTitle(topic.label),
          blocks: mapNoteBlocks(plan, intro: await _intro(topic, plan)),
          model: _modelName(),
        )).orThrowStep('crear la nota mapa');
        if (created != null) applied++;
        continue;
      }

      // Una de la IA que sigue siendo suya, si hay; las de la persona no se
      // tocan, ni la de la IA que alguien editó.
      final mine = maps.where((note) => note.keptByAi).firstOrNull;
      if (mine == null) continue;
      if (setEquals(linkedTitlesOf(mine.blocksContent), plan.linkedTitles)) {
        continue;
      }
      written++;
      final updated = (await _atlas.updateMapNote(
        noteId: mine.itemId,
        expectedContent: mine.blocksContent,
        blocks: mapNoteBlocks(plan, intro: await _intro(topic, plan)),
      )).orThrowStep('actualizar la nota mapa');
      if (updated) applied++;
    }
    return AiStepReport(applied: applied);
  }

  /// La introducción del modelo para el índice [plan], ya limpia; vacía si no
  /// dijo nada que sirva —la nota sale igual, sin introducción—.
  Future<String> _intro(AtlasTopic topic, MapNotePlan plan) async {
    final shown = plan.entries.take(kAiMapIntroEntries).toList();
    final excerpts = (await _atlas.excerptsOf([
      for (final entry in shown) entry.itemId,
    ], chars: kMapIntroExcerptChars)).orThrowStep('leer los fragmentos');
    final raw = await _writeIntro(
      topic: topic.label,
      entries: [
        for (final entry in shown)
          MapIntroEntry(
            title: entry.title,
            excerpt: excerpts[entry.itemId] ?? '',
          ),
      ],
    );
    return cleanMapIntro(raw);
  }

  // -------------------------------------------------------------------------
  // La madurez
  // -------------------------------------------------------------------------

  Future<AiStepReport> _proposeMaturity(KnowledgeItem item) async {
    if (item.source.kind != SourceKind.manualNote) return AiStepReport.nothing;
    final growth = (await _atlas.noteGrowth(
      item.id,
    )).orThrowStep('leer cuánto creció la nota');
    if (growth == null || growth.noteKind != NoteKind.living) {
      return AiStepReport.nothing;
    }
    final next = grownMaturity(
      current: growth.maturity,
      textLength: item.searchableText.trim().length,
      connections: growth.connections,
      age: _clock().difference(growth.createdAt),
    );
    if (next == null) return AiStepReport.nothing;

    // Una a la vez, y nunca de nuevo la que la persona ya respondió.
    final asked = (await _suggestions.suggestionsFor(item.id))
        .orThrowStep('leer las sugerencias de la nota')
        .whereType<MaturitySuggestion>();
    if (asked.any(
      (s) => s.status == SuggestionStatus.pending || s.to == next,
    )) {
      return AiStepReport.nothing;
    }
    (await _atlas.proposeMaturity(
      itemId: item.id,
      from: growth.maturity,
      to: next,
    )).orThrowStep('proponer la madurez');
    return const AiStepReport(forReview: 1);
  }
}
