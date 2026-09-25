import 'package:freezed_annotation/freezed_annotation.dart';

part 'flashcard_option.freezed.dart';

/// Una opción de una tarjeta de opción múltiple (F20): su texto, si es la
/// correcta, y su propia procedencia.
///
/// No se ancla por `relations`/`extractedFrom`: esa tabla tiene
/// `UNIQUE(from_item_id, to_item_id, kind)`, y dos opciones de la MISMA
/// pregunta citando el mismo elemento fuente es esperable, no un caso raro.
/// Mismo patrón que `Flashcard` ya usa para su propia procedencia.
@freezed
sealed class FlashcardOption with _$FlashcardOption {
  const factory FlashcardOption({
    required String id,
    required String flashcardId,
    required String content,
    required bool isCorrect,

    /// El orden en el que se muestra. Sin esto, el orden de lectura de la
    /// tabla no tiene por qué coincidir con el que el usuario vio al
    /// revisar la pregunta.
    required int position,

    /// Igual que `Flashcard.sourceChunkId`: nulo si el texto de la fuente
    /// se rehizo y sus chunks se reemplazaron. El rango de caracteres sigue
    /// valiendo mientras el texto no cambie.
    String? sourceChunkId,
    int? sourceCharStart,
    int? sourceCharEnd,

    /// El elemento dueño de [sourceCharStart]/[sourceCharEnd] —no
    /// necesariamente el mismo que el de la tarjeta: un distractor por
    /// diseño suele venir de OTRO elemento (F20, `DistractorSourcer`)—.
    ///
    /// Campo PROPIO, no derivado de [sourceChunkId] (esquema v30): a
    /// diferencia del chunk —que se pierde si el texto de la fuente se
    /// rehace—, esto sigue valiendo mientras el rango siga valiendo, mismo
    /// criterio que `Flashcard.itemId` (que tampoco depende de su chunk).
    String? sourceItemId,
  }) = _FlashcardOption;

  const FlashcardOption._();

  /// Si se sabe de qué fragmento de la fuente salió.
  bool get hasSourceRange => sourceCharStart != null && sourceCharEnd != null;
}
