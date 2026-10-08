/// A qué hora cambia el día de estudio: las 4:00, como en Anki.
///
/// Quien repasa de madrugada no empieza «otro día» a medianoche: a las 00:30
/// sigue estudiando lo de ayer, con los límites de ayer. Tampoco hay una tarea
/// pendiente que «venza» a las 00:00 mientras la persona todavía no durmió.
const kStudyDayStartHour = 4;

/// El día de estudio (F31, decisión 69): el tramo de 24 horas que va de las
/// 4:00 de un día a las 4:00 del siguiente, en la HORA LOCAL.
///
/// Es el «hoy» de todo lo que cuenta por día: cuántas tarjetas nuevas y cuántos
/// repasos se hicieron (los límites), hasta cuándo vence un repaso para
/// entrar en la sesión de hoy, y hasta cuándo se pospone una tarjeta
/// («hasta mañana»).
///
/// ## La regla, en concreto
///
/// - Los límites de [startOf] y [endOf] se calculan siempre en la zona horaria
///   ACTUAL del dispositivo, con el calendario de esa zona: una hora local es
///   `DateTime(año, mes, día, 4)`, no «86.400 segundos después». Así el día que
///   cambia el horario de verano mide 23 o 25 horas, y las 4:00 siguen siendo
///   las 4:00.
/// - Si la persona viaja y cambia la zona, el día de estudio se recalcula con
///   la zona nueva: lo ya repasado se cuenta en el día que le toca según el
///   reloj de ahora. Puede hacer que, justo en el cambio, un día cuente de más
///   o de menos horas; nada se pierde ni se repite.
/// - Un instante en UTC se convierte a hora local antes de decidir el día.
///
/// Es una clase sin estado y no funciones sueltas para poder cambiar la hora
/// de corte en una prueba, o si algún día se vuelve un ajuste.
class StudyDay {
  const StudyDay({this.startHour = kStudyDayStartHour})
    : assert(startHour >= 0 && startHour < 24, 'Una hora del día, de 0 a 23');

  /// La hora local a la que empieza el día de estudio.
  final int startHour;

  /// Cuando empezó el día de estudio al que pertenece [now]: las 4:00 de hoy,
  /// o las de ayer si todavía no son las 4:00.
  DateTime startOf(DateTime now) {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day, startHour);
    return local.isBefore(today)
        ? DateTime(local.year, local.month, local.day - 1, startHour)
        : today;
  }

  /// Cuando empieza el SIGUIENTE día de estudio: el fin del de [now]. Una hora
  /// que ya es este instante pertenece al día nuevo, no al anterior.
  DateTime endOf(DateTime now) {
    final start = startOf(now);
    return DateTime(start.year, start.month, start.day + 1, startHour);
  }

  /// Si [a] y [b] caen en el mismo día de estudio.
  bool isSameDay(DateTime a, DateTime b) =>
      startOf(a).isAtSameMomentAs(startOf(b));
}
