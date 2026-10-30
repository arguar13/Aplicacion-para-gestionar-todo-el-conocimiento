import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/habit/domain/entities/review_history.dart';

/// El historial de repasos de un recorte (F17, D8; F43, M16): la curva de
/// retención y la retención real, el calendario de constancia con sus rachas
/// y las tarjetas difíciles. Sigue al selector de Repasar, como las
/// estadísticas.
abstract interface class ReviewHistoryRepository {
  Future<ReviewHistory> current(StudyScope scope);

  /// Se vuelve a emitir sola con cada repaso nuevo, o si cambia aquello de lo
  /// que está hecho el recorte.
  Stream<ReviewHistory> watch(StudyScope scope);
}
