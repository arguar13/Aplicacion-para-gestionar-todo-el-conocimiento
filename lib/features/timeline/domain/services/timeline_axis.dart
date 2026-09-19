import 'package:sinapsis/core/domain/entities/historical_date.dart';

/// Dónde cae un día en el eje de la línea de tiempo.
///
/// El eje es continuo y se mide en años astronómicos con fracción: el año 1
/// d.C. empieza en `1.0`, el 1 a.C. en `0.0`, el 44 a.C. en `-43.0`. No hay
/// un salto en el cero porque `HistoricalDate.astronomicalYear` ya es
/// monótono con el tiempo real; las etiquetas "a.C."/"d.C." se ponen recién
/// al mostrar, con `HistoricalDate.fromAstronomicalYear`.
///
/// Un día ocupa `[axisStart, axisEnd)`: termina donde empieza el siguiente,
/// así que un mes, un año o un siglo se apoyan uno contra otro sin huecos ni
/// solapes, también en año bisiesto.
double axisStart(DatePoint day) =>
    day.year + (_dayOfYear(day) - 1) / _daysInYear(day.year);

/// El final del día [day] en el eje: donde empieza el siguiente.
double axisEnd(DatePoint day) =>
    day.year + _dayOfYear(day) / _daysInYear(day.year);

/// El primer día del mes [month] (1–12) del año astronómico [year].
double axisStartOfMonth(int year, int month) =>
    axisStart((year: year, month: month, day: 1));

int _daysInYear(int year) => isLeapYear(year) ? 366 : 365;

/// El ordinal del día dentro de su año: el 1 de enero es 1.
int _dayOfYear(DatePoint day) {
  var days = day.day;
  for (var month = 1; month < day.month; month++) {
    days += daysInMonth(day.year, month);
  }
  return days;
}
