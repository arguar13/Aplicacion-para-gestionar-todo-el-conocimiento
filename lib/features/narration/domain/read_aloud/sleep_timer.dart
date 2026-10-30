import 'package:flutter/foundation.dart';

/// Las opciones del Temporizador para dormir (F47, paso 2): 15, 30, 45 o 60
/// minutos, o al terminar lo que suena.
enum SleepTimerChoice {
  minutes15(Duration(minutes: 15)),
  minutes30(Duration(minutes: 30)),
  minutes45(Duration(minutes: 45)),
  minutes60(Duration(minutes: 60)),

  /// Al terminar lo que suena, sin seguir con la cola.
  endOfReading(null);

  const SleepTimerChoice(this.after);

  /// Cuánto falta al elegirlo; `null` para [endOfReading].
  final Duration? after;
}

/// Un Temporizador para dormir en marcha (F47, paso 2): cuándo se pausa la
/// lectura.
///
/// Los tiempos son los de un reloj que solo avanza —el de
/// `narrationClockProvider`—, no la hora del día: cambiar la hora del
/// teléfono a mitad de la noche no lo adelanta ni lo atrasa.
@immutable
class SleepTimer {
  /// Elegido ahora, en [now].
  factory SleepTimer.start(SleepTimerChoice choice, {required Duration now}) {
    final after = choice.after;
    return SleepTimer._(choice, after == null ? null : now + after);
  }

  const SleepTimer._(this.choice, this.deadline);

  final SleepTimerChoice choice;

  /// Cuándo se pausa; `null` si es al terminar lo que suena.
  final Duration? deadline;

  /// Si se pausa al terminar lo que suena, en vez de a una hora.
  bool get atEndOfReading => deadline == null;

  /// Cuánto falta en [now]; nunca menos que nada. `null` si es al terminar
  /// lo que suena.
  Duration? remaining(Duration now) {
    final deadline = this.deadline;
    if (deadline == null) return null;
    final left = deadline - now;
    return left.isNegative ? Duration.zero : left;
  }

  /// Los minutos que faltan, para decirlos: redondeados para arriba —con 30
  /// segundos todavía falta «1 min», no «0»—.
  int? minutesLeft(Duration now) {
    final left = remaining(now);
    if (left == null) return null;
    return (left.inMicroseconds / Duration.microsecondsPerMinute).ceil();
  }

  @override
  bool operator ==(Object other) =>
      other is SleepTimer &&
      other.choice == choice &&
      other.deadline == deadline;

  @override
  int get hashCode => Object.hash(choice, deadline);
}
