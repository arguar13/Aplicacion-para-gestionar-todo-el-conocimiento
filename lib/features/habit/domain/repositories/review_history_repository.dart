import 'package:sinapsis/features/habit/domain/entities/review_history.dart';

/// El historial de repasos (F17, D8): curva de retención, tarjetas
/// difíciles y calendario de constancia.
abstract interface class ReviewHistoryRepository {
  Future<ReviewHistory> current();

  /// Se vuelve a emitir sola con cada repaso nuevo.
  Stream<ReviewHistory> watch();
}
