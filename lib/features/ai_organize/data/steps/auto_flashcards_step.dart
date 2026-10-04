import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_target.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcards_by_parts.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

/// Las tarjetas de repaso de un elemento, hechas por la IA (F27, decisión
/// D): de 3 a 12 según el largo (`flashcardTargetFor`), y entran solas al
/// repaso.
///
/// El modelo nunca ve el texto entero: lo lee por partes
/// (`generateFlashcardsByParts`), repartidas por todo el texto.
///
/// Cada tarjeta trae la frase de la que sale, y se ubica en el texto aunque
/// el modelo la haya parafraseado (`anchorQuote`, F30). **La que no se ubica
/// no entra sola al repaso**: a mano se guardaba igual, sin fragmento, porque
/// la persona la había leído; acá nadie la lee antes, y una cita que no es de
/// ningún pasaje es la señal más clara de que el modelo inventó. Hasta F30 se
/// descartaba; ahora va a «Para revisar» —hasta [kMaxFlashcardsForReview] por
/// pasada—, donde la persona la acepta o la descarta.
///
/// No repite una pregunta que el elemento ya tiene, una que ya está para
/// revisar o se descartó ahí, ni una que la persona dijo que «no era».
/// Cuántas tarjetas sin pasaje deja para revisar, como mucho, una pasada: un
/// modelo que inventa todo no tiene que llenar «Para revisar» de un libro.
const kMaxFlashcardsForReview = 3;

class AutoFlashcardsStep implements AiOrganizeStep {
  const AutoFlashcardsStep({
    required FlashcardGenerator generator,
    required FlashcardRepository flashcards,
    required SuggestionRepository suggestions,
    required AiRunRepository runs,
  }) : _generator = generator,
       _flashcards = flashcards,
       _suggestions = suggestions,
       _runs = runs;

  final FlashcardGenerator _generator;
  final FlashcardRepository _flashcards;
  final SuggestionRepository _suggestions;
  final AiRunRepository _runs;

  @override
  AiOrganizeToggle get toggle => AiOrganizeToggle.flashcards;

  @override
  Future<AiStepReport> organize(
    KnowledgeItem item, {
    required String runId,
  }) async {
    // El mismo texto que abre la lectura —como el botón a mano—: el rango de
    // una cita tiene que ser de ESE texto para que «Ver en la fuente» caiga en
    // el lugar. Una nota de bloques no tiene: se usa el texto que se busca, y
    // la tarjeta queda sin fragmento.
    final sourceText = extractableRendition(item)?.content;
    final text = sourceText ?? item.searchableText;
    if (text.trim().isEmpty) return AiStepReport.nothing;

    // Lo que ya tiene cuenta: una nota que se vuelve a organizar porque
    // creció completa lo que le falta, no suma otra tanda entera.
    final existing = await _flashcards.watchForItem(item.id).first;
    final wanted = flashcardTargetFor(text) - existing.length;
    if (wanted <= 0) return AiStepReport.nothing;

    // Las que ya están para revisar, o que la persona descartó ahí, tampoco
    // se vuelven a proponer.
    final reviewed = (await _suggestions.suggestionsFor(
      item.id,
    )).orThrowStep('leer las tarjetas para revisar');
    final known = {
      for (final card in existing) flashcardRejectionFingerprint(card.front),
      for (final suggestion in reviewed.whereType<FlashcardSuggestion>())
        flashcardRejectionFingerprint(suggestion.front),
    };
    var forReview = 0;
    final created = await generateFlashcardsByParts(
      generator: _generator,
      text: text,
      wanted: wanted,
      onDraft: (candidate) async {
        final anchor = candidate.anchor;
        final draft = candidate.draft;
        if (anchor == null && forReview >= kMaxFlashcardsForReview) {
          return PartDraftOutcome.skipped;
        }
        if (!known.add(flashcardRejectionFingerprint(draft.front))) {
          return PartDraftOutcome.skipped;
        }
        final rejected = (await _runs.isFlashcardRejected(
          itemId: item.id,
          question: draft.front,
        )).orThrowStep('leer lo que «no era»');
        if (rejected) return PartDraftOutcome.skipped;

        // Sin pasaje no entra sola: espera en «Para revisar». No cuenta para
        // las que se piden —los tramos que siguen buscan las que faltan—.
        if (anchor == null) {
          (await _suggestions.createFlashcardSuggestion(
            targetItemId: item.id,
            front: draft.front,
            back: draft.back,
            quote: draft.quote,
          )).orThrowStep('dejar una tarjeta para revisar');
          forReview++;
          return PartDraftOutcome.skipped;
        }

        (await _flashcards.create(
          itemId: item.id,
          front: draft.front,
          back: draft.back,
          sourceCharStart: sourceText == null ? null : anchor.start,
          sourceCharEnd: sourceText == null ? null : anchor.end,
          ai: AiProvenance(runId: runId),
        )).orThrowStep('guardar una tarjeta');
        return PartDraftOutcome.kept;
      },
    );
    return AiStepReport(applied: created, forReview: forReview);
  }
}
