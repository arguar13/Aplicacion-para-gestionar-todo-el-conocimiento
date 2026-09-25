/// La insignia «un mes de consolidación semanal» (F17, D7): si cada semana
/// del mes de [today], hasta donde ya pasó, tuvo alguna actividad que
/// cuenta para la racha.
///
/// «Semana» acá son tramos fijos de 7 días desde el día 1 del mes —no la
/// semana de calendario—: decisión propia, porque el proyecto no fija en
/// ningún otro lado si una semana empieza lunes o domingo, y un tramo fijo
/// evita esa dependencia sin cambiar el espíritu de «ninguna semana se
/// salteó». Solo se exige de las semanas que ya empezaron: una semana que
/// todavía no llegó no puede haber tenido actividad todavía, y contarla en
/// contra dejaría la insignia imposible hasta el último día del mes.
bool hasMonthOfWeeklyConsolidation(
  Set<DateTime> activeDays, {
  required DateTime today,
}) {
  final normalized = activeDays
      .map((d) => DateTime(d.year, d.month, d.day))
      .toSet();

  for (var weekStart = 1; weekStart <= today.day; weekStart += 7) {
    final weekEnd = (weekStart + 6) < today.day ? weekStart + 6 : today.day;
    final hasActivity = [
      for (var day = weekStart; day <= weekEnd; day++)
        DateTime(today.year, today.month, day),
    ].any(normalized.contains);
    if (!hasActivity) return false;
  }
  return true;
}
