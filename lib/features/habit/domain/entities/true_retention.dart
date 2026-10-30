/// Los tramos de la retención real, como en Anki (F43, M16).
enum RetentionPeriod {
  /// El día de estudio de hoy.
  today(1, 0),

  /// El de ayer, solo.
  yesterday(1, 1),

  /// Los últimos 7 días de estudio, hoy incluido.
  week(7, 0),

  /// Los últimos 30.
  month(30, 0),

  /// Los últimos 365.
  year(365, 0);

  const RetentionPeriod(this.days, this.offset);

  /// Cuántos días de estudio junta.
  final int days;

  /// Cuántos días antes de hoy termina: 1 para «ayer».
  final int offset;
}

/// Cuántos repasos se recordaron y cuántos no.
class PassFail {
  const PassFail({this.passed = 0, this.failed = 0});

  final int passed;
  final int failed;

  int get total => passed + failed;

  /// Lo recordado (0 a 1), o `null` sin repasos: sin dato no hay porcentaje.
  double? get ratio => total == 0 ? null : passed / total;

  PassFail operator +(PassFail other) =>
      PassFail(passed: passed + other.passed, failed: failed + other.failed);
}

/// Una fila de la retención real: los repasos jóvenes (menos de 21 días de
/// intervalo) y los maduros de un tramo.
class TrueRetentionRow {
  const TrueRetentionRow({
    required this.period,
    required this.young,
    required this.mature,
  });

  final RetentionPeriod period;
  final PassFail young;
  final PassFail mature;

  PassFail get total => young + mature;
}
