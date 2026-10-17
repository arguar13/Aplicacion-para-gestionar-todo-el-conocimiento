import 'dart:math' as math;

import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_item_reviewer.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_reviewer.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

/// Lo más largo que se le muestra al revisor alrededor de cada tarjeta, aunque
/// la ventana del modelo dé para más: un par de párrafos alcanzan para juzgar
/// una pregunta y su respuesta, y cada carácter de más sale de la cuota de la
/// persona.
const kMaxReviewPassageChars = 2400;

/// Lo más corto: con menos, el revisor no ve de dónde sale la respuesta.
const kMinReviewPassageChars = 400;

/// Revisa las tarjetas que hizo la IA en un elemento, con el modelo elegido
/// ahora (F33, «Revisar con otro modelo»), y deja en «Revisión» lo que propone
/// corregir o sacar. **No cambia ninguna tarjeta**: eso pasa solo si la persona
/// acepta la corrección.
///
/// Solo mira lo que **sigue siendo de la IA**: una tarjeta que la persona
/// editó es suya y no se revisa nunca. De las de la IA, las de pregunta y
/// respuesta —las que hace sola—.
///
/// A cada tarjeta la acompaña su pasaje: el pedazo del texto donde se ubicó su
/// cita (`passageForReview`), del largo que el modelo elegido lee por pedido
/// (`textBudget`, F32) repartido entre las tarjetas de cada pedido. Una de una
/// nota sin lugar en el texto va con el principio del texto.
///
/// No vuelve a proponer lo que ya está para decidir —una tarjeta con una
/// corrección pendiente no se revisa otra vez— ni lo que la persona descartó:
/// la misma corrección sobre la misma tarjeta, o sacar la misma tarjeta.
class ReviewFlashcardsStep implements AiItemReviewer {
  const ReviewFlashcardsStep({
    required FlashcardReviewer reviewer,
    required FlashcardRepository flashcards,
    required SuggestionRepository suggestions,
    required AiRunRepository runs,
    required ModelTextBudget Function() textBudget,
  }) : _reviewer = reviewer,
       _flashcards = flashcards,
       _suggestions = suggestions,
       _runs = runs,
       _textBudget = textBudget;

  final FlashcardReviewer _reviewer;
  final FlashcardRepository _flashcards;
  final SuggestionRepository _suggestions;
  final AiRunRepository _runs;

  /// Cuánto lee por pedido el modelo elegido: se pregunta al empezar cada
  /// elemento, como al hacer las tarjetas.
  final ModelTextBudget Function() _textBudget;

  /// Revisa las tarjetas de [item] dentro de la pasada de revisión [runId] de
  /// [model]. Con [exceptMadeBy], deja afuera las que hizo ese modelo.
  /// Devuelve cuántas correcciones dejó para decidir.
  @override
  Future<AiStepReport> review(
    KnowledgeItem item, {
    required String runId,
    String? model,
    String? exceptMadeBy,
  }) async {
    var cards = [
      for (final card in await _flashcards.watchForItem(item.id).first)
        if (_isAiCard(card)) card,
    ];
    if (cards.isEmpty) return AiStepReport.nothing;
    if (exceptMadeBy != null) {
      final made = {
        for (final run in (await _runs.listRuns(
          itemId: item.id,
          limit: 1000,
        )).orThrowStep('leer qué modelo hizo cada tarjeta'))
          run.id: run.model,
      };
      cards = [
        for (final card in cards)
          if (made[card.aiRunId] != exceptMadeBy) card,
      ];
      if (cards.isEmpty) return AiStepReport.nothing;
    }

    final known = (await _suggestions.suggestionsFor(
      item.id,
    )).orThrowStep('leer las correcciones que ya hay');
    final corrections = known.whereType<CorrectionSuggestion>();
    final waiting = {
      for (final correction in corrections)
        if (correction.status == SuggestionStatus.pending) correction.subjectId,
    };
    final discarded = {
      for (final correction in corrections)
        if (correction.status == SuggestionStatus.rejected)
          _keyOf(correction.subjectId, correction.after),
    };
    final toReview = [
      for (final card in cards)
        if (!waiting.contains(card.id)) card,
    ];
    if (toReview.isEmpty) return AiStepReport.nothing;

    // El mismo texto contra el que se ubicó la cita de cada tarjeta.
    final sourceText = extractableRendition(item)?.content;
    final text = sourceText ?? item.searchableText;
    final budget = _textBudget();
    final perCall = math.max(1, budget.maxDraftsPerCall);
    final passageChars = (budget.partChars ~/ perCall).clamp(
      kMinReviewPassageChars,
      kMaxReviewPassageChars,
    );

    var proposed = 0;
    for (var from = 0; from < toReview.length; from += perCall) {
      final batch = toReview.sublist(
        from,
        math.min(from + perCall, toReview.length),
      );
      final verdicts = await _reviewer.reviewFlashcards([
        for (final card in batch)
          FlashcardToReview(
            front: card.front,
            back: card.back,
            passage: passageForReview(
              text,
              start: sourceText == null ? null : card.sourceCharStart,
              end: sourceText == null ? null : card.sourceCharEnd,
              chars: passageChars,
            ),
          ),
      ]);
      for (final verdict in verdicts) {
        if (verdict.index < 0 || verdict.index >= batch.length) continue;
        final card = batch[verdict.index];
        final after = switch (verdict) {
          FlashcardCorrection(:final front, :final back) => {
            FlashcardCorrectionField.front: front,
            FlashcardCorrectionField.back: back,
          },
          FlashcardRemoval() => null,
        };
        if (discarded.contains(_keyOf(card.id, after))) continue;
        (await _suggestions.createCorrectionSuggestion(
          targetItemId: item.id,
          subject: CorrectionSubject.flashcard,
          subjectId: card.id,
          before: {
            FlashcardCorrectionField.front: card.front,
            FlashcardCorrectionField.back: card.back,
          },
          after: after,
          reason: verdict.reason,
          aiRunId: runId,
          model: model,
        )).orThrowStep('dejar una corrección para decidir');
        proposed++;
      }
    }
    return AiStepReport(forReview: proposed);
  }

  static bool _isAiCard(Flashcard card) =>
      card.origin == ContentOrigin.ai &&
      card.aiRunId != null &&
      card.kind == FlashcardKind.freeRecall;

  /// Cómo se reconoce la misma corrección: la tarjeta y lo que propone, sin
  /// mayúsculas ni espacios de más. Sacarla es una sola.
  static String _keyOf(String cardId, Map<String, String>? after) {
    if (after == null) return '$cardId\u001fsacar';
    String plain(String? text) =>
        (text ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return '$cardId\u001f${plain(after[FlashcardCorrectionField.front])}'
        '\u001f${plain(after[FlashcardCorrectionField.back])}';
  }
}
