import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';

/// Las estadísticas de repaso de F31 (ola 2, decisión 72): el pronóstico, el
/// reparto por etapa y los botones usados. Lo demás —racha, insignias,
/// actividad, retención, difíciles— es de `ReviewHistoryRepository`.
///
/// No cuenta las tarjetas ni el historial de un elemento en la papelera.
abstract interface class ReviewStatsRepository {
  /// Las estadísticas de ahora; los botones, con el historial de [period].
  Future<Either<Failure, ReviewStats>> load({required StatsPeriod period});

  /// Lo mismo, actualizándose solo ante cambios en las tarjetas o en el
  /// historial. Un fallo viaja por el stream.
  Stream<ReviewStats> watch({required StatsPeriod period});
}
