import 'dart:math' as math;

import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_target.dart';
import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/source_quote_locator.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';

/// Hasta cuántos caracteres del texto ve el modelo por pedido. Gemma tiene
/// una ventana de 2048 tokens para todo, y en español cuenta unos 3,5
/// caracteres por token: 3000 caracteres son ~860 tokens, más ~150 de
/// instrucciones y ~90 por tarjeta de respuesta (pregunta, respuesta y la
/// cita textual), con lugar de sobra para [kMaxFlashcardsPerCall].
const kFlashcardPartChars = 3000;

/// Cuántas tarjetas se le piden, como mucho, por tramo: más que esto no
/// entra en la respuesta junto con el tramo.
const kMaxFlashcardsPerCall = 4;

/// Cuántas tarjetas se esperan de cada tramo leído: con 12 por hacer se leen
/// 6 tramos repartidos por el texto, no 12 seguidos del principio.
const kFlashcardsPerVisit = 2;

/// Una tarjeta más de las que hacen falta por tramo: las que no anclan o
/// repiten se descartan, y pedir justo las necesarias dejaría corto el total.
const kSpareFlashcardsPerCall = 1;

/// Las tarjetas de repaso de un elemento, hechas por la IA (F27, decisión
/// D): de 3 a 12 según el largo (`flashcardTargetFor`), y entran solas al
/// repaso.
///
/// El modelo nunca ve el texto entero: se corta en tramos que entran en su
/// ventana (`splitIntoParts`) y se leen algunos, repartidos parejo por el
/// texto (`spreadIndices`), de modo que un libro da tarjetas de todo el libro
/// y no solo del primer capítulo.
///
/// Cada tarjeta trae la frase de la que sale; se busca textual en el tramo
/// (`locateQuote`), y **la que no aparece se descarta**: a mano se guardaba
/// igual, sin fragmento, porque la persona la había leído; acá nadie la lee
/// antes, y una cita que no está es la señal más clara de que el modelo
/// inventó. Tampoco repite una pregunta que el elemento ya tiene ni una que
/// la persona dijo que «no era».
class AutoFlashcardsStep implements AiOrganizeStep {
  const AutoFlashcardsStep({
    required FlashcardGenerator generator,
    required FlashcardRepository flashcards,
    required AiRunRepository runs,
  }) : _generator = generator,
       _flashcards = flashcards,
       _runs = runs;

  final FlashcardGenerator _generator;
  final FlashcardRepository _flashcards;
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

    final known = {
      for (final card in existing) flashcardRejectionFingerprint(card.front),
    };
    final parts = splitIntoParts(text, maxChars: kFlashcardPartChars);
    final visits = spreadIndices(
      parts.length,
      (wanted / kFlashcardsPerVisit).ceil(),
    );
    var created = 0;
    for (var visit = 0; visit < visits.length && created < wanted; visit++) {
      final part = parts[visits[visit]];
      if (part.text.trim().isEmpty) continue;

      // Lo que falta, repartido entre los tramos que quedan: si uno da menos
      // —citas que no anclan, preguntas repetidas—, los siguientes lo
      // compensan, y ninguno se lleva todas.
      final quota = ((wanted - created) / (visits.length - visit)).ceil();
      final drafts = await _generator.generate(
        content: part.text,
        count: math.min(kMaxFlashcardsPerCall, quota + kSpareFlashcardsPerCall),
      );
      var fromPart = 0;
      for (final draft in drafts) {
        if (fromPart >= quota) break;

        final anchor = locateQuote(part.text, draft.quote);
        if (anchor == null) continue;
        if (!known.add(flashcardRejectionFingerprint(draft.front))) continue;
        final rejected = (await _runs.isFlashcardRejected(
          itemId: item.id,
          question: draft.front,
        )).orThrowStep('leer lo que «no era»');
        if (rejected) continue;

        (await _flashcards.create(
          itemId: item.id,
          front: draft.front,
          back: draft.back,
          sourceCharStart: sourceText == null
              ? null
              : part.start + anchor.start,
          sourceCharEnd: sourceText == null ? null : part.start + anchor.end,
          ai: AiProvenance(runId: runId),
        )).orThrowStep('guardar una tarjeta');
        created++;
        fromPart++;
      }
    }
    return AiStepReport(applied: created);
  }
}
