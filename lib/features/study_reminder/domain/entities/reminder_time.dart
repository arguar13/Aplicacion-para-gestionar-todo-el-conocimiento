import 'package:meta/meta.dart';

/// La hora del día a la que suena el aviso para repasar (F31): hora y minuto
/// locales, sin fecha. El aviso es diario, así que lo único que se elige es
/// a qué hora.
@immutable
class ReminderTime {
  const ReminderTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24, 'La hora va de 0 a 23.'),
      assert(minute >= 0 && minute < 60, 'El minuto va de 0 a 59.');

  /// A los minutos desde la medianoche (0 a 1439). Fuera de rango se rechaza
  /// con un [RangeError]: un valor guardado que ya no sirve no es una hora.
  factory ReminderTime.fromMinutesOfDay(int minutes) {
    RangeError.checkValueInInterval(minutes, 0, 24 * 60 - 1, 'minutes');
    return ReminderTime(minutes ~/ 60, minutes % 60);
  }

  /// La hora que se propone al prender el aviso: la tarde, cuando ya pasó la
  /// jornada y se puede dedicar un rato.
  static const standard = ReminderTime(20, 0);

  final int hour;
  final int minute;

  /// Minutos desde la medianoche, para guardarla en un solo número.
  int get minutesOfDay => hour * 60 + minute;

  /// La próxima vez que esta hora ocurre **después** de [now]: hoy si todavía
  /// no pasó, mañana si ya pasó o es justo ahora. Con la hora de la pared del
  /// reloj local, así que un cambio de horario no la corre.
  ///
  /// Es el momento hasta el que hay que contar las tarjetas que vencen para
  /// el texto del aviso: las que ya vencieron más las que van a vencer antes
  /// de que suene.
  DateTime nextOccurrence(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    return today.isAfter(now)
        ? today
        : DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  /// `07:05`, `20:00`: para mostrar.
  String format24() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'ReminderTime(${format24()})';
}
