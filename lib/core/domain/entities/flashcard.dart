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
  }) = _Flashcard;

  const Flashcard._();

  /// Si ya toca repasarla.
  bool isDue(DateTime now) => !dueAt.isAfter(now);
}
