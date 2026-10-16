/// El día de la cuota gratuita de Gemini (F32): Google la renueva a la
/// medianoche de la hora del Pacífico de Estados Unidos, no a la de acá.
///
/// Sin base de zonas horarias (no vale una dependencia por esto): la hora del
/// Pacífico es UTC−8 en invierno y UTC−7 en verano, y el verano va del
/// segundo domingo de marzo a las 2:00 al primer domingo de noviembre a las
/// 2:00, hora de allá. Esa regla rige desde 2007.
library;

/// Si [utc] cae en el horario de verano del Pacífico.
bool isPacificDaylightTime(DateTime utc) {
  final at = utc.toUtc();
  final year = at.year;
  // 2:00 PST (UTC−8) = 10:00 UTC; 2:00 PDT (UTC−7) = 9:00 UTC.
  final starts = DateTime.utc(year, 3, _nthSunday(year, 3, 2), 10);
  final ends = DateTime.utc(year, 11, _nthSunday(year, 11, 1), 9);
  return !at.isBefore(starts) && at.isBefore(ends);
}

/// La diferencia con UTC de la hora del Pacífico en [utc].
Duration pacificOffset(DateTime utc) =>
    Duration(hours: isPacificDaylightTime(utc) ? -7 : -8);

/// El día de la cuota en que cae [instant]: «2026-10-16», en la hora del
/// Pacífico.
String quotaDayOf(DateTime instant) {
  final utc = instant.toUtc();
  final local = utc.add(pacificOffset(utc));
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// Cuándo se renueva la cuota que se está usando en [instant]: la próxima
/// medianoche del Pacífico, en UTC.
DateTime nextQuotaReset(DateTime instant) {
  final utc = instant.toUtc();
  final local = utc.add(pacificOffset(utc));
  // La medianoche siguiente, como si fuera UTC, y vuelta a UTC real con la
  // diferencia que rija EN ESA medianoche (puede ser otra si cambia la hora).
  final midnight = DateTime.utc(local.year, local.month, local.day + 1);
  final guess = midnight.subtract(pacificOffset(midnight));
  return midnight.subtract(pacificOffset(guess));
}

/// El día del [n]-ésimo domingo de [month] de [year].
int _nthSunday(int year, int month, int n) {
  final first = DateTime.utc(year, month);
  // weekday: lunes = 1 … domingo = 7.
  final firstSunday = 1 + (DateTime.sunday - first.weekday) % 7;
  return firstSunday + (n - 1) * 7;
}
