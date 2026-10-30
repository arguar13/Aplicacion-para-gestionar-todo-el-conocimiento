import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';

/// Las estadísticas de repaso de un recorte (F43, M17; F31, decisión 72): lo
/// de hoy, lo que viene, los repasos por día, el reparto por etapa, los
/// botones, los intervalos, la facilidad, las horas y lo agregado. La
/// retención, la constancia y las difíciles son de `ReviewHistoryRepository`.
///
/// Sigue al selector de Repasar: cuenta solo las tarjetas de [StudyScope] y su
/// historial. No cuenta las de un elemento en la papelera.
abstract interface class ReviewStatsRepository {
  /// Las estadísticas de ahora de [scope].
  Future<Either<Failure, ReviewStats>> load({required StudyScope scope});

  /// Lo mismo, actualizándose solo ante cambios en las tarjetas, en el
  /// historial o en aquello de lo que está hecho el recorte. Un fallo viaja
  /// por el stream.
  Stream<ReviewStats> watch({required StudyScope scope});
}
