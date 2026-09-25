import 'package:sinapsis/features/habit/domain/entities/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/entities/difficult_card.dart';
import 'package:sinapsis/features/habit/domain/entities/weekly_retention.dart';

/// Las tres piezas del historial de repasos (F17, D8), juntas: la curva de
/// retención, las tarjetas difíciles y el calendario de constancia.
/// Agrupadas en una sola entidad —igual que `Streak` junta cuatro orígenes
/// y `earned()` junta seis insignias— para que la pantalla dependa de una
/// sola lectura, no de tres.
class ReviewHistory {
  const ReviewHistory({
    required this.retentionByWeek,
    required this.hardestCards,
    required this.activityByDay,
  });

  /// De la más vieja a la más nueva, la semana de hoy al final.
  final List<WeeklyRetention> retentionByWeek;

  /// De la más difícil a la menos, ya recortada al tope a mostrar.
  final List<DifficultCard> hardestCards;

  /// Del día más viejo al de hoy, un día por celda.
  final List<DailyActivity> activityByDay;
}
