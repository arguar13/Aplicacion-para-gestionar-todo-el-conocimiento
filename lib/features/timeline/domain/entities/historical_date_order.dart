import 'package:sinapsis/core/domain/entities/historical_date.dart';

/// Cómo se ordenan y se comparan las fechas históricas entre sí (F40), por el
/// primer día que cubre cada una —el mismo criterio con que la línea de
/// tiempo las pone sobre el eje—.
extension HistoricalDateOrder on HistoricalDate {
  /// Negativo si esta fecha empieza antes que [other], cero si empiezan el
  /// mismo día —aunque una sea de año y la otra de día—, positivo si después.
  ///
  /// El año astronómico es monótono con el tiempo real, así que cruza el
  /// cero sin ningún caso especial para a.C./d.C.
  int compareStart(HistoricalDate other) {
    final a = rangeStart;
    final b = other.rangeStart;
    if (a.year != b.year) return a.year.compareTo(b.year);
    if (a.month != b.month) return a.month.compareTo(b.month);
    return a.day.compareTo(b.day);
  }

  /// Si es la misma fecha leída en el texto, sin mirar el «circa»: que el
  /// autor diga «hacia 1500» o «1500» no cambia a qué año se refiere.
  bool sameReading(HistoricalDate other) =>
      year == other.year &&
      precision == other.precision &&
      month == other.month &&
      day == other.day &&
      isBce == other.isBce;
}
