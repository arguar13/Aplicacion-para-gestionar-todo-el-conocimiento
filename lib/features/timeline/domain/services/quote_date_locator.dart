import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_expressions.dart';

/// Dónde, dentro de la cita [excerpt] de un hecho, está escrita su fecha (F40):
/// la expresión cuyo tramo `[start, end)` resalta la ficha. `null` si la cita
/// no la escribe —el hecho se fechó a mano o la fecha se editó después—: es
/// mejor no resaltar nada que resaltar otra fecha.
///
/// Entre las expresiones de la cita elige la que lee **lo mismo** que el
/// hecho: la misma fecha y, si es un tramo, el mismo fin. Si hay una que
/// coincide en todo, esa; si no, la primera que coincide en la fecha de
/// inicio. El «circa» no cuenta: es del hecho entero, y «hacia 1500» y «1500»
/// son la misma fecha leída con y sin él.
TemporalExpression? locateEventDate(
  String excerpt, {
  required HistoricalDate date,
  HistoricalDate? end,
}) {
  TemporalExpression? sameStart;
  for (final expression in findTemporalExpressions(excerpt)) {
    if (!_sameDate(expression.date, date)) continue;
    final expressionEnd = expression.endDate;
    final sameEnd = end == null
        ? expressionEnd == null
        : expressionEnd != null && _sameDate(expressionEnd, end);
    if (sameEnd) return expression;
    sameStart ??= expression;
  }
  return sameStart;
}

/// Si [a] y [b] dicen el mismo día, mes, año, década o siglo, sin mirar el
/// «circa».
bool _sameDate(HistoricalDate a, HistoricalDate b) =>
    a.astronomicalYear == b.astronomicalYear &&
    a.precision == b.precision &&
    a.month == b.month &&
    a.day == b.day;
