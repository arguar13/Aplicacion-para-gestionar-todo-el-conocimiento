import 'package:meta/meta.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';

/// Cuántos días mira el pronóstico, contando hoy: el tramo más largo que se
/// puede elegir (tres meses). Los más cortos son el principio de este.
const kForecastDays = 90;

/// Desde cuántas respuestas en una hora se la puede llamar «tu mejor hora»:
/// con menos, un 100 % de dos respuestas ganaría por casualidad.
const kBestHourMinAnswers = 10;

/// Cuánto adelante mira «Lo que viene» (F43, M17).
enum ForecastRange {
  days7(7),
  days30(30),
  months3(90);

  const ForecastRange(this.days);

  /// Cuántos días de estudio muestra, contando hoy.
  final int days;
}

/// Cuánto historial cuentan los botones, los repasos por día y las agregadas.
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

/// Lo que viene: cuántas vencen cada uno de los próximos días de estudio.
@immutable
class ReviewForecast {
  const ReviewForecast({required this.days, required this.overdue});

  /// Un renglón por día de estudio, el de hoy primero.
  final List<ForecastDay> days;

  /// Cuántas de las de hoy están atrasadas (les tocaba antes de que empiece el
  /// día de estudio de hoy). Ya están sumadas en `days.first`.
  final int overdue;

  /// Lo mismo, solo los primeros días de [range]: el pronóstico se lee una vez
  /// entero, y elegir otro tramo no vuelve a consultar la base.
  ReviewForecast window(ForecastRange range) => ReviewForecast(
    days: days.take(range.days).toList(growable: false),
    overdue: overdue,
  );

  /// Cuántas vencen hoy, contando lo atrasado.
  int get today => days.isEmpty ? 0 : days.first.count;

  /// Cuántas vencen en total dentro del pronóstico.
  int get total => days.fold(0, (sum, day) => sum + day.count);

  /// La carga promedio por día: el total entre los días que mira.
  double get averagePerDay => days.isEmpty ? 0 : total / days.length;

  /// El día con más tarjetas, para escalar el gráfico.
  int get peak => days.fold(0, (m, day) => day.count > m ? day.count : m);
}

/// El reparto de las tarjetas por etapa (F31, ola 2, decisión 72): una
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

/// En qué etapa estaba la tarjeta cuando se la contestó, para los botones.
enum StatsStage {
  /// Era nueva: la primera respuesta.
  newCard,

  /// Se aprendía o se reaprendía (pasos de minutos).
  learning,

  /// Un repaso en días con menos de [kMatureIntervalDays] de intervalo.
  young,

  /// Un repaso en días con [kMatureIntervalDays] o más.
  mature;

  /// La etapa de los botones de una etapa del registro: aprender y reaprender
  /// van juntos, como en Anki.
  static StatsStage of(ReviewLogStage stage) => switch (stage) {
    ReviewLogStage.newCard => newCard,
    ReviewLogStage.learning || ReviewLogStage.relearning => learning,
    ReviewLogStage.young => young,
    ReviewLogStage.mature => mature,
  };
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
  /// Es el «correcto» de Anki, el mismo de la retención del historial.
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

  @override
  bool operator ==(Object other) =>
      other is ButtonUsageByStage &&
      StatsStage.values.every((stage) => other.of(stage) == of(stage));

  @override
  int get hashCode => Object.hashAll(StatsStage.values.map(of));
}

/// Lo de hoy (F43, M17): el día de estudio que empezó a las 4:00.
@immutable
class TodayStats {
  const TodayStats({
    required this.cards,
    required this.answers,
    required this.correct,
    required this.newCards,
  });

  const TodayStats.empty() : cards = 0, answers = 0, correct = 0, newCards = 0;

  /// Cuántas tarjetas distintas se contestaron.
  final int cards;

  /// Cuántas respuestas hubo (una tarjeta que se aprende vuelve varias veces).
  final int answers;

  /// Cuántas de esas respuestas no fueron «De nuevo».
  final int correct;

  /// Cuántas nuevas se vieron por primera vez.
  final int newCards;

  /// El acierto (0 a 1), o `null` sin respuestas.
  double? get accuracy => answers == 0 ? null : correct / answers;

  @override
  bool operator ==(Object other) =>
      other is TodayStats &&
      other.cards == cards &&
      other.answers == answers &&
      other.correct == correct &&
      other.newCards == newCards;

  @override
  int get hashCode => Object.hash(cards, answers, correct, newCards);
}

/// Qué tipo de respuesta fue, para apilar los «Repasos por día» como Anki.
enum DailyReviewKind {
  newCard,
  learning,
  review,
  relearning;

  static DailyReviewKind of(ReviewLogStage stage) => switch (stage) {
    ReviewLogStage.newCard => newCard,
    ReviewLogStage.learning => learning,
    ReviewLogStage.young || ReviewLogStage.mature => review,
    ReviewLogStage.relearning => relearning,
  };
}

/// Las respuestas de un día de estudio, por tipo.
@immutable
class DayReviews {
  const DayReviews({required this.day, required this.byKind});

  /// Cuándo empieza el día de estudio (las 4:00, hora local).
  final DateTime day;

  /// Cuántas de cada [DailyReviewKind], en el orden del enum.
  final List<int> byKind;

  int of(DailyReviewKind kind) => byKind[kind.index];

  int get total => byKind.fold(0, (sum, n) => sum + n);

  @override
  bool operator ==(Object other) =>
      other is DayReviews &&
      other.day == day &&
      other.byKind.length == byKind.length &&
      [
        for (var i = 0; i < byKind.length; i++) i,
      ].every((i) => other.byKind[i] == byKind[i]);

  @override
  int get hashCode => Object.hash(day, Object.hashAll(byKind));
}

/// Los tramos del intervalo, como en Anki: un día, la semana, tres semanas,
/// tres meses y lo que pasa de ahí.
enum IntervalRange {
  oneDay(0, 1),
  upToWeek(2, 7),
  upToThreeWeeks(8, 21),
  upToThreeMonths(22, 90),
  longer(91, null);

  const IntervalRange(this.from, this.to);

  /// El primer día del tramo y el último (`null` = sin tope).
  final int from;
  final int? to;

  /// El tramo de un intervalo de [days] días.
  static IntervalRange of(int days) =>
      values.firstWhere((r) => r.to == null || days <= r.to!);
}

/// Cuántas tarjetas tienen una facilidad: el factor de SM-2 en por ciento
/// (250 = 2,5), redondeado.
@immutable
class EaseCount {
  const EaseCount({required this.percent, required this.count});

  final int percent;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is EaseCount && other.percent == percent && other.count == count;

  @override
  int get hashCode => Object.hash(percent, count);
}

/// El acierto de una hora del día.
@immutable
class HourAccuracy {
  const HourAccuracy({
    required this.hour,
    required this.answers,
    required this.correct,
  });

  /// De 0 a 23: las respuestas de las 9:00 a las 9:59 son la hora 9.
  final int hour;
  final int answers;
  final int correct;

  double? get accuracy => answers == 0 ? null : correct / answers;

  @override
  bool operator ==(Object other) =>
      other is HourAccuracy &&
      other.hour == hour &&
      other.answers == answers &&
      other.correct == correct;

  @override
  int get hashCode => Object.hash(hour, answers, correct);
}

/// Cuántas tarjetas se agregaron un día de estudio.
@immutable
class DayCount {
  const DayCount({required this.day, required this.count});

  /// Cuándo empieza el día de estudio (las 4:00, hora local).
  final DateTime day;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is DayCount && other.day == day && other.count == count;

  @override
  int get hashCode => Object.hash(day, count);
}

/// Las estadísticas de repaso de un recorte (F43, M17; F31, decisión 72), en
/// el orden de la pantalla: de lo de hoy a lo de siempre.
///
/// Se lee una sola vez, con el historial entero: los tramos que se eligen en
/// la pantalla (7 días o 3 meses, 30 días o el historial completo) son cortes
/// de esto, y cambiar uno no vuelve a consultar la base.
///
/// No hay «tiempo estudiado»: `review_log` no guarda cuánto se tardó en cada
/// respuesta, y no se inventa (decisión N).
@immutable
class ReviewStats {
  const ReviewStats({
    required this.today,
    required this.forecast,
    required this.daily,
    required this.distribution,
    required this.buttons,
    required this.intervals,
    required this.ease,
    required this.hours,
    required this.added,
  });

  final TodayStats today;

  /// Los próximos [kForecastDays] días de estudio.
  final ReviewForecast forecast;

  /// Los días de estudio con alguna respuesta, del más viejo al de hoy.
  final List<DayReviews> daily;

  final CardDistribution distribution;

  /// Los botones de cada período.
  final Map<StatsPeriod, ButtonUsageByStage> buttons;

  /// Cuántas tarjetas en repaso hay en cada tramo del intervalo.
  final Map<IntervalRange, int> intervals;

  /// Cuántas tarjetas en repaso tienen cada facilidad, de la menor a la mayor.
  final List<EaseCount> ease;

  /// Las 24 horas del día, de la 0 a la 23, con el historial entero.
  final List<HourAccuracy> hours;

  /// Los días de estudio en que se agregó alguna tarjeta, del más viejo al de
  /// hoy.
  final List<DayCount> added;

  ButtonUsageByStage buttonsFor(StatsPeriod period) =>
      buttons[period] ?? const ButtonUsageByStage.empty();

  /// Cuántas tarjetas en repaso hay: lo que cuentan los intervalos y la
  /// facilidad.
  int get reviewCards => intervals.values.fold(0, (sum, n) => sum + n);

  /// La facilidad promedio de las tarjetas en repaso, en por ciento, o `null`
  /// si no hay ninguna.
  double? get averageEase {
    final cards = ease.fold(0, (n, e) => n + e.count);
    if (cards == 0) return null;
    return ease.fold(0, (n, e) => n + e.percent * e.count) / cards;
  }

  /// La hora del día con mejor acierto, entre las que tienen al menos
  /// [kBestHourMinAnswers] respuestas; a igual acierto, la de más respuestas.
  /// `null` si ninguna llega.
  HourAccuracy? get bestHour {
    HourAccuracy? best;
    for (final hour in hours) {
      if (hour.answers < kBestHourMinAnswers) continue;
      final current = best;
      if (current == null ||
          hour.accuracy! > current.accuracy! ||
          (hour.accuracy == current.accuracy &&
              hour.answers > current.answers)) {
        best = hour;
      }
    }
    return best;
  }
}
