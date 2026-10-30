import 'package:meta/meta.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';

/// En qué etapa estaba la tarjeta cuando se la contestó (F43, M16 y M17), con
/// el aprender separado del reaprender: los «Repasos por día» los apilan por
/// separado, y la retención real separa los repasos jóvenes de los maduros.
///
/// Sale de `review_log.phase_before` y, en un repaso, del intervalo de antes.
enum ReviewLogStage {
  /// Era nueva: la primera respuesta.
  newCard,

  /// Se aprendía (los pasos de minutos de una nueva).
  learning,

  /// Se reaprendía (los pasos de minutos después de un olvido).
  relearning,

  /// Un repaso en días con menos de 21 de intervalo.
  young,

  /// Un repaso en días con 21 o más.
  mature;

  /// Si es un repaso en días: lo único que cuenta la retención, como en Anki.
  bool get isReview => this == young || this == mature;
}

/// Cuántas respuestas hubo en un cuarto de hora, en una etapa y con un botón
/// (F43, M16 y M17).
///
/// Es lo que la base agrupa una sola vez, y de donde salen los repasos por
/// día, los botones de cada período, las horas, la retención y el calendario.
/// El cuarto de hora es la medida justa: toda zona horaria del mundo está
/// corrida en múltiplos de 15 minutos, así que las 4:00 locales —el cambio del
/// día de estudio— y cada hora en punto caen siempre en un borde, sin partir
/// ningún tramo.
@immutable
class ReviewActivityBucket {
  const ReviewActivityBucket({
    required this.start,
    required this.stage,
    required this.grade,
    required this.count,
  });

  /// Cuándo empieza el cuarto de hora, en la hora local.
  final DateTime start;

  final ReviewLogStage stage;
  final ReviewGrade grade;
  final int count;

  /// Si no fue «De nuevo»: el «correcto» de Anki.
  bool get passed => grade != ReviewGrade.again;

  @override
  bool operator ==(Object other) =>
      other is ReviewActivityBucket &&
      other.start == start &&
      other.stage == stage &&
      other.grade == grade &&
      other.count == count;

  @override
  int get hashCode => Object.hash(start, stage, grade, count);
}
