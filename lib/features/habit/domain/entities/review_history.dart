import 'package:sinapsis/features/habit/domain/entities/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/entities/difficult_card.dart';
import 'package:sinapsis/features/habit/domain/entities/true_retention.dart';
import 'package:sinapsis/features/habit/domain/entities/weekly_retention.dart';

/// El historial de repasos de un recorte (F17, D8; F43, M16), junto: la curva
/// de retención con la retención real debajo, el calendario de constancia con
/// sus rachas y las tarjetas difíciles. Una sola entidad —igual que `Streak`
/// junta cuatro orígenes— para que la pantalla dependa de una sola lectura.
class ReviewHistory {
  const ReviewHistory({
    required this.retentionByWeek,
    required this.hardestCards,
    required this.activityByDay,
    this.trueRetention = const [],
    this.currentRun = 0,
    this.longestRun = 0,
  });

  /// De la más vieja a la más nueva, la semana de hoy al final.
  final List<WeeklyRetention> retentionByWeek;

  /// Hoy, ayer, la última semana, el último mes y el último año.
  final List<TrueRetentionRow> trueRetention;

  /// De la más difícil a la menos, ya recortada al tope a mostrar.
  final List<DifficultCard> hardestCards;

  /// Del día más viejo al de hoy, un día de estudio por celda.
  final List<DailyActivity> activityByDay;

  /// Cuántos días de estudio seguidos, hasta hoy, tuvieron algún repaso del
  /// recorte. Si hoy todavía no, cuenta hasta ayer: el día no terminó.
  final int currentRun;

  /// La tirada más larga de días seguidos con algún repaso, en todo el
  /// historial del recorte.
  final int longestRun;
}
