/// Cuántos repasos hubo en una semana y cuántos se recordaron (F17, D8; F43,
/// M16).
///
/// Cuenta como Anki: solo los repasos en días —no las nuevas ni los pasos de
/// minutos—, y se recordó todo lo que no fue «De nuevo». Es la cifra que SM-2
/// intenta dejar cerca del 90 %.
class WeeklyRetention {
  const WeeklyRetention({
    required this.weekStart,
    required this.total,
    required this.retained,
  });

  /// El principio del primer día de estudio del tramo de 7.
  final DateTime weekStart;

  /// Cuántos repasos hubo esa semana, cero incluido —una semana sin
  /// repasos aparece igual, para que la curva no tenga huecos—.
  final int total;

  /// Cuántos de esos no fueron «De nuevo».
  final int retained;

  /// `0` con cero repasos: sin dato no hay nada que reprochar, no una
  /// racha cortada.
  double get ratio => total == 0 ? 0 : retained / total;
}
