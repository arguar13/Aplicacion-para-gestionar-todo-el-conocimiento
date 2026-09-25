import 'package:sinapsis/features/habit/domain/entities/streak.dart';

/// Cuántos días de gracia por semana, por defecto (F17, D6): «para que una
/// semana ocupada de verdad no corte una racha larga sin necesidad».
const kDefaultGraceDaysPerWeek = 2;

/// La racha (F17, D6): pura, sobre los días con actividad que ya resolvió
/// quien llama —`StreakRepository`, uniendo `review_log`, `field_version`
/// de notas vivas, `item.created_at` de notas atómicas y `habit_event`—.
///
/// Camina hacia atrás desde hoy (o desde ayer, si hoy todavía no tuvo
/// actividad: el día no terminó, así que no cuenta ni corta nada). Un día
/// sin actividad no corta la racha si todavía queda gracia disponible en
/// los últimos 7 días —una ventana que se desliza con el propio
/// recorrido, no la semana del calendario—: cuando ese cupo se agota, el
/// primer día sin actividad y sin gracia corta la cuenta ahí.
Streak calculateStreak(
  Set<DateTime> activeDays, {
  required DateTime today,
  int graceDaysPerWeek = kDefaultGraceDaysPerWeek,
}) {
  final normalizedToday = _dateOnly(today);
  final normalizedActiveDays = activeDays.map(_dateOnly).toSet();
  final activeToday = normalizedActiveDays.contains(normalizedToday);

  var length = 0;
  var cursor = activeToday
      ? normalizedToday
      : normalizedToday.subtract(const Duration(days: 1));
  // Los días —normalizados— donde se gastó un cupo de gracia, del más
  // reciente al más viejo: para saber cuántos quedan dentro de la ventana
  // de 7 días que termina en [cursor].
  final graceUsed = <DateTime>[];

  while (true) {
    if (normalizedActiveDays.contains(cursor)) {
      length++;
      cursor = cursor.subtract(const Duration(days: 1));
      continue;
    }
    graceUsed.removeWhere((d) => cursor.difference(d).inDays > 6);
    if (graceUsed.length >= graceDaysPerWeek) break;
    graceUsed.add(cursor);
    cursor = cursor.subtract(const Duration(days: 1));
  }

  return Streak(days: length, activeToday: activeToday);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
