/// Cuántas respuestas hubo un día de estudio y cuántas no fueron «De nuevo»
/// (F17, D8; F43, M16): una celda del calendario de constancia, incluidos los
/// días en cero.
class DailyActivity {
  const DailyActivity({
    required this.day,
    required this.count,
    this.correct = 0,
  });

  /// El principio del día de estudio (las 4:00, hora local).
  final DateTime day;
  final int count;

  /// Cuántas de las [count] no fueron «De nuevo».
  final int correct;

  /// El acierto (0 a 1), o `null` en un día sin respuestas.
  double? get accuracy => count == 0 ? null : correct / count;
}
