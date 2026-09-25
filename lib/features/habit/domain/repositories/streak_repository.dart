import 'package:sinapsis/features/habit/domain/entities/streak.dart';

/// La racha de hoy (F17, D6).
abstract interface class StreakRepository {
  /// Recalculada de cero: sin caché propia, mismo criterio que las demás
  /// lecturas puntuales de la app.
  Future<Streak> current();

  /// Se vuelve a emitir sola cuando cambia algo que puede mover la racha
  /// —repasar, editar una nota viva, extraer una atómica, triar la
  /// Bandeja o resolver algo en Vocabulario— (F17, commit 8: el
  /// indicador es la primera pantalla que necesita esto de verdad, mismo
  /// criterio que `NotebookRepository.watchById` en F16).
  Stream<Streak> watch();
}
