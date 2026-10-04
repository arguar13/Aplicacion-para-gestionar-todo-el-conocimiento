import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/quote_anchor.dart';

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

/// Una tarjeta que propuso el modelo, con el pasaje del texto del que sale.
@immutable
class PartDraft {
  const PartDraft({required this.draft, required this.anchor});

  final FlashcardDraft draft;

  /// Dónde está su cita en el texto **entero** (`anchorQuote`), o `null` si
  /// no se ubicó: no se sabe de qué pasaje sale, y puede ser inventada.
  final QuoteAnchor? anchor;
}

/// Qué hizo quien recibió una [PartDraft]: si cuenta para las que se piden,
/// o si la dejó afuera —repetida, o una que la persona dijo que «no era»—.
enum PartDraftOutcome { kept, skipped }

/// Le pide al modelo hasta [wanted] tarjetas sobre [text] **por partes**
/// (F27, F30): el modelo nunca ve el texto entero, que en un libro o la
/// transcripción de un video de horas no entra en su ventana. Se corta en
/// tramos de [kFlashcardPartChars] (`splitIntoParts`) y se leen algunos,
/// repartidos parejo por el texto (`spreadIndices`): un libro da tarjetas de
/// cada parte, y no solo del primer capítulo.
///
/// Cada tarjeta llega a [onDraft] con su pasaje ya ubicado en el texto
/// entero, en el orden en que el modelo la propuso; las que [onDraft] guarda
/// ([PartDraftOutcome.kept]) cuentan para [wanted], y lo que falta se reparte
/// entre los tramos que quedan: si uno da menos, los siguientes lo
/// compensan. [onProgress] dice cuántos tramos se leyeron de cuántos, antes
/// de cada uno y al final.
///
/// Lo que lance el modelo —es de terceros— sale de acá tal cual: quien llama
/// sabe si cortar todo o informar lo que alcanzó a juntar. Devuelve cuántas
/// se guardaron.
Future<int> generateFlashcardsByParts({
  required FlashcardGenerator generator,
  required String text,
  required int wanted,
  required Future<PartDraftOutcome> Function(PartDraft draft) onDraft,
  void Function(int read, int total)? onProgress,
}) async {
  if (wanted <= 0 || text.trim().isEmpty) return 0;

  final parts = splitIntoParts(text, maxChars: kFlashcardPartChars);
  final visits = spreadIndices(
    parts.length,
    (wanted / kFlashcardsPerVisit).ceil(),
  );
  var kept = 0;
  for (var visit = 0; visit < visits.length && kept < wanted; visit++) {
    onProgress?.call(visit, visits.length);
    final part = parts[visits[visit]];
    if (part.text.trim().isEmpty) continue;

    // Lo que falta, repartido entre los tramos que quedan: ninguno se lleva
    // todas.
    final quota = ((wanted - kept) / (visits.length - visit)).ceil();
    final drafts = await generator.generate(
      content: part.text,
      count: math.min(kMaxFlashcardsPerCall, quota + kSpareFlashcardsPerCall),
    );
    var fromPart = 0;
    for (final draft in drafts) {
      if (fromPart >= quota) break;
      final anchor = anchorQuote(part.text, draft.quote);
      final outcome = await onDraft(
        PartDraft(
          draft: draft,
          anchor: anchor == null
              ? null
              : QuoteAnchor(
                  start: part.start + anchor.start,
                  end: part.start + anchor.end,
                  exact: anchor.exact,
                ),
        ),
      );
      if (outcome == PartDraftOutcome.kept) {
        kept++;
        fromPart++;
      }
    }
  }
  onProgress?.call(visits.length, visits.length);
  return kept;
}
