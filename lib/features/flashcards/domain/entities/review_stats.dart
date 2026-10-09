import 'package:meta/meta.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';

/// Cuántos días mira el pronóstico, contando hoy.
const kForecastDays = 30;

/// Cuánto historial cuentan los botones usados.
enum StatsPeriod {
  /// Los últimos 30 días de estudio.
  days30(30),

  /// Los últimos 90 días de estudio.
  days90(90),

  /// El historial entero.
  all(null);

  const StatsPeriod(this.days);

  /// Cuántos días de estudio incluye; `null` = todos.
  final int? days;
}

/// Cuántas tarjetas vencen un día de estudio (F31, ola 2, decisión 72).
@immutable
class ForecastDay {
  const ForecastDay({required this.start, required this.count});

  /// Cuándo empieza ese día de estudio (las 4:00, hora local).
  final DateTime start;

  /// Cuántas vencen ese día. En el de hoy incluye lo atrasado y lo que se
  /// aprende.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is ForecastDay && other.start == start && other.count == count;

  @override
  int get hashCode => Object.hash(start, count);
}

/// Lo que viene: el pronóstico de los próximos [kForecastDays] días de estudio.
@immutable
class ReviewForecast {
  const ReviewForecast({required this.days, required this.overdue});

  /// Un renglón por día de estudio, el de hoy primero: siempre [kForecastDays].
  final List<ForecastDay> days;

  /// Cuántas de las de hoy están atrasadas (les tocaba antes de que empiece el
  /// día de estudio de hoy). Ya están sumadas en `days.first`.
  final int overdue;

  /// Cuántas vencen en total dentro del pronóstico.
  int get total => days.fold(0, (sum, day) => sum + day.count);

  /// El día con más tarjetas, para escalar el gráfico.
  int get peak => days.fold(0, (m, day) => day.count > m ? day.count : m);
}

/// El reparto de todas las tarjetas por etapa (F31, ola 2, decisión 72): una
/// PARTICIÓN —cada tarjeta en una sola—, con la pausa por encima de la etapa.
@immutable
class CardDistribution {
  const CardDistribution({
    required this.newCards,
    required this.learning,
    required this.young,
    required this.mature,
    required this.suspended,
  });

  const CardDistribution.empty()
    : newCards = 0,
      learning = 0,
      young = 0,
      mature = 0,
      suspended = 0;

  final int newCards;
  final int learning;

  /// Se repasan en días, con menos de [kMatureIntervalDays] de intervalo.
  final int young;

  /// Se repasan en días, con [kMatureIntervalDays] o más.
  final int mature;

  final int suspended;

  int get total => newCards + learning + young + mature + suspended;

  @override
  bool operator ==(Object other) =>
      other is CardDistribution &&
      other.newCards == newCards &&
      other.learning == learning &&
      other.young == young &&
      other.mature == mature &&
      other.suspended == suspended;

  @override
  int get hashCode => Object.hash(newCards, learning, young, mature, suspended);
}

/// En qué etapa estaba la tarjeta cuando se la contestó.
enum StatsStage {
  /// Era nueva: la primera respuesta.
  newCard,

  /// Se aprendía o se reaprendía (pasos de minutos).
  learning,

  /// Un repaso en días con menos de [kMatureIntervalDays] de intervalo.
  young,

  /// Un repaso en días con [kMatureIntervalDays] o más.
  mature,
}

/// Cuántas veces se apretó cada botón en una etapa.
@immutable
class ButtonUsage {
  const ButtonUsage({
    this.again = 0,
    this.hard = 0,
    this.good = 0,
    this.easy = 0,
  });

  final int again;
  final int hard;
  final int good;
  final int easy;

  int get total => again + hard + good + easy;

  /// Las respuestas que no fueron «De nuevo».
  int get correct => hard + good + easy;

  /// Qué parte de las respuestas NO fue «De nuevo» (0 a 1), o `null` si no hubo
  /// ninguna: «sin datos» no es «0 % de acierto».
  ///
  /// Es el «correcto» de Anki. NO es la retención de la curva semanal, que
  /// cuenta como retenido solo «Bien» y «Fácil».
  double? get accuracy => total == 0 ? null : correct / total;

  @override
  bool operator ==(Object other) =>
      other is ButtonUsage &&
      other.again == again &&
      other.hard == hard &&
      other.good == good &&
      other.easy == easy;

  @override
  int get hashCode => Object.hash(again, hard, good, easy);
}

/// Los botones usados, por etapa.
@immutable
class ButtonUsageByStage {
  const ButtonUsageByStage(this.byStage);

  const ButtonUsageByStage.empty() : byStage = const {};

  final Map<StatsStage, ButtonUsage> byStage;

  ButtonUsage of(StatsStage stage) => byStage[stage] ?? const ButtonUsage();

  /// Todas las etapas juntas.
  ButtonUsage get overall => ButtonUsage(
    again: _sum((u) => u.again),
    hard: _sum((u) => u.hard),
    good: _sum((u) => u.good),
    easy: _sum((u) => u.easy),
  );

  int _sum(int Function(ButtonUsage) pick) =>
      StatsStage.values.fold(0, (sum, stage) => sum + pick(of(stage)));
}

/// Las estadísticas de repaso que se calculan sobre las tarjetas y su historial
/// (F31, ola 2, decisión 72). La racha, las insignias, el calendario de
/// actividad, la retención semanal y las más difíciles ya existían (F17) y se
/// leen de `ReviewHistory`; no se repiten acá.
///
/// No hay «tiempo estudiado»: `review_log` no guarda cuánto se tardó en cada
/// respuesta, y no se inventa.
@immutable
class ReviewStats {
  const ReviewStats({
    required this.forecast,
    required this.distribution,
    required this.buttons,
    required this.period,
  });

  final ReviewForecast forecast;
  final CardDistribution distribution;
  final ButtonUsageByStage buttons;

  /// El período con el que se contaron los botones.
  final StatsPeriod period;
}
