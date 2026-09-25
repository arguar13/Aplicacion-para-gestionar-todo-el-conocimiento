/// Cuántos repasos hubo en una semana y cuántos se retuvieron —se
/// calificaron `good` o `easy`, no `again`/`hard`— (F17, D8).
class WeeklyRetention {
  const WeeklyRetention({
    required this.weekStart,
    required this.total,
    required this.retained,
  });

  /// El primer día del tramo de 7 días.
  final DateTime weekStart;

  /// Cuántos repasos hubo esa semana, cero incluido —una semana sin
  /// repasos aparece igual, para que la curva no tenga huecos—.
  final int total;

  /// Cuántos de esos se calificaron `good` o `easy`.
  final int retained;

  /// `0` con cero repasos: sin dato no hay nada que reprochar, no una
  /// racha cortada.
  double get ratio => total == 0 ? 0 : retained / total;
}
