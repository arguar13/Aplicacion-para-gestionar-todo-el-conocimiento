/// Los pasos cortos del calendario de repaso (F31, decisión 69) y los
/// intervalos con los que una tarjeta sale de ellos.
///
/// Una tarjeta nueva, o una que se olvidó en un repaso, no pasa directo a
/// repasarse en días: primero vuelve en unos minutos, dentro de la misma
/// sesión. Es lo que hace que lo nuevo se fije antes de espaciarse.
///
/// Hoy es una constante ([standard]); es un objeto y no números sueltos para
/// que `scheduleNext` y la vista previa de los botones lean lo MISMO, y para
/// que, si algún día los pasos se vuelven un ajuste, haya un único lugar que
/// cambiar.
class LearningSteps {
  const LearningSteps({
    this.learning = const [Duration(minutes: 1), Duration(minutes: 10)],
    this.relearning = const [Duration(minutes: 10)],
    this.graduatingIntervalDays = 1,
    this.easyIntervalDays = 4,
  }) : assert(graduatingIntervalDays >= 1, 'El intervalo mínimo es un día'),
       assert(
         easyIntervalDays > graduatingIntervalDays,
         '«Fácil» tiene que ir más lejos que «Bien»',
       );

  /// Los pasos de una tarjeta nueva: 1 minuto y 10 minutos. Tiene que haber al
  /// menos uno (`scheduleNext` lo exige).
  final List<Duration> learning;

  /// Los pasos de una tarjeta que se olvidó en un repaso: 10 minutos. Tiene
  /// que haber al menos uno.
  final List<Duration> relearning;

  /// A cuántos días sale de aprender contestando «Bien» en el último paso.
  final int graduatingIntervalDays;

  /// A cuántos días sale de aprender contestando «Fácil» (en cualquier paso).
  final int easyIntervalDays;

  /// Lo que usa la app: los pasos de Anki por defecto.
  static const standard = LearningSteps();
}

/// El intervalo más largo que el calendario le da a una tarjeta: 100 años, el
/// mismo tope que usa Anki (`maxIvl`, 36.500 días y es lo que el exportador
/// declara).
///
/// Sin tope, contestar «Fácil» durante unas decenas de repasos multiplica el
/// intervalo por 2,5 cada vez hasta que la fecha ya no cabe en un `DateTime`
/// (la cuenta en microsegundos desborda y la fecha cae en el pasado: la
/// tarjeta vuelve YA).
const kMaxIntervalDays = 36500;
