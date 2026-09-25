import 'package:sinapsis/features/habit/domain/entities/streak.dart';

/// La racha de hoy (F17, D6).
// ignore: one_member_abstracts
abstract interface class StreakRepository {
  /// Recalculada de cero: sin caché propia, mismo criterio que las demás
  /// lecturas puntuales de la app.
  Future<Streak> current();
}
