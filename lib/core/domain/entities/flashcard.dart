import 'package:freezed_annotation/freezed_annotation.dart';

part 'flashcard.freezed.dart';

/// Una tarjeta de repaso: pregunta, respuesta, y el estado de repetición
/// espaciada que decide cuándo volver a mostrarla.
///
/// El estado SM-2 vive en la entidad y no en un servicio aparte porque es
/// justamente lo que se guarda: la tarjeta *es* su historial de repasos, no
/// solo su contenido.
@freezed
sealed class Flashcard with _$Flashcard {
  const factory Flashcard({
    required String id,
    required String itemId,
    required String front,
    required String back,
    required DateTime dueAt,
    required DateTime createdAt,
    @Default(2.5) double easeFactor,
    @Default(0) int intervalDays,
    @Default(0) int repetitions,
    DateTime? lastReviewedAt,

    /// El fragmento de la fuente del que salió la tarjeta (F11): el rango de
    /// caracteres de la forma principal del elemento, y el chunk que lo
    /// contiene. `null` en las tarjetas escritas a mano y en las que ya
    /// existían.
    ///
    /// El rango es lo que vale para volver a la fuente: el id de un chunk
    /// desaparece cuando el texto se rehace y sus chunks se reemplazan; el
    /// rango sigue señalando el mismo lugar mientras el texto no cambie.
    String? sourceChunkId,
    int? sourceCharStart,
    int? sourceCharEnd,

    /// Cuándo se exportó por última vez a un `.apkg` con éxito (F17, D4).
    /// `null` en una tarjeta que nunca entró en una exportación: es lo que
    /// el camino incremental usa para decidir qué es «nuevo».
    DateTime? lastExportedAt,
  }) = _Flashcard;

  const Flashcard._();

  /// Si se sabe de qué fragmento de la fuente salió.
  bool get hasSourceRange => sourceCharStart != null && sourceCharEnd != null;

  /// Si ya toca repasarla.
  bool isDue(DateTime now) => !dueAt.isAfter(now);
}
