import 'package:meta/meta.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';

/// Las cuentas de las estadísticas (F43, M17) sobre las respuestas ya
/// agrupadas por la base: puras, sin base ni reloj, para probarlas sueltas.

/// Las respuestas de cada día de estudio, por tipo, del más viejo al más
/// nuevo. Solo los días con alguna.
List<DayReviews> dailyReviews(
  Iterable<ReviewActivityBucket> buckets, {
  StudyDay day = const StudyDay(),
}) {
  final perDay = <DateTime, List<int>>{};
  for (final bucket in buckets) {
    final counts = perDay.putIfAbsent(
      day.startOf(bucket.start),
      () => List.filled(DailyReviewKind.values.length, 0),
    );
    counts[DailyReviewKind.of(bucket.stage).index] += bucket.count;
  }
  final days = perDay.keys.toList()..sort();
  return [
    for (final d in days)
      DayReviews(day: d, byKind: List.unmodifiable(perDay[d]!)),
  ];
}

/// Desde cuándo cuenta [period], si [now] es ahora: el principio del primero
/// de sus días de estudio; `null` = desde siempre.
DateTime? periodStart(
  StatsPeriod period,
  DateTime now, {
  StudyDay day = const StudyDay(),
}) {
  final days = period.days;
  if (days == null) return null;
  final today = day.startOf(now);
  return DateTime(
    today.year,
    today.month,
    today.day - (days - 1),
    day.startHour,
  );
}

/// Los botones de cada período, de una sola pasada. La etapa es la que tenía
/// la tarjeta ANTES de contestarla; un repaso se reparte entre joven y maduro
/// por el intervalo de antes.
Map<StatsPeriod, ButtonUsageByStage> buttonsByPeriod(
  Iterable<ReviewActivityBucket> buckets, {
  required DateTime now,
  StudyDay day = const StudyDay(),
}) {
  final since = {
    for (final period in StatsPeriod.values)
      period: periodStart(period, now, day: day),
  };
  // Por período y etapa: De nuevo, Difícil, Bien y Fácil.
  final tally = {
    for (final period in StatsPeriod.values)
      period: {for (final stage in StatsStage.values) stage: List.filled(4, 0)},
  };
  for (final bucket in buckets) {
    final stage = StatsStage.of(bucket.stage);
    for (final period in StatsPeriod.values) {
      final from = since[period];
      if (from != null && bucket.start.isBefore(from)) continue;
      tally[period]![stage]![bucket.grade.index] += bucket.count;
    }
  }
  return {
    for (final period in StatsPeriod.values)
      period: ButtonUsageByStage({
        for (final stage in StatsStage.values)
          if (tally[period]![stage]!.any((n) => n > 0))
            stage: ButtonUsage(
              again: tally[period]![stage]![ReviewGrade.again.index],
              hard: tally[period]![stage]![ReviewGrade.hard.index],
              good: tally[period]![stage]![ReviewGrade.good.index],
              easy: tally[period]![stage]![ReviewGrade.easy.index],
            ),
      }),
  };
}

/// El acierto de cada hora del día, de la 0 a la 23, con todo el historial.
List<HourAccuracy> hourAccuracy(Iterable<ReviewActivityBucket> buckets) {
  final answers = List.filled(24, 0);
  final correct = List.filled(24, 0);
  for (final bucket in buckets) {
    final hour = bucket.start.hour;
    answers[hour] += bucket.count;
    if (bucket.passed) correct[hour] += bucket.count;
  }
  return [
    for (var h = 0; h < 24; h++)
      HourAccuracy(hour: h, answers: answers[h], correct: correct[h]),
  ];
}

/// Lo agregado cada día de estudio, de [quarters] (el principio de cada cuarto
/// de hora y cuántas tarjetas se crearon en él), del más viejo al más nuevo.
List<DayCount> addedPerDay(
  Iterable<({DateTime start, int count})> quarters, {
  StudyDay day = const StudyDay(),
}) {
  final perDay = <DateTime, int>{};
  for (final quarter in quarters) {
    final d = day.startOf(quarter.start);
    perDay[d] = (perDay[d] ?? 0) + quarter.count;
  }
  final days = perDay.keys.toList()..sort();
  return [for (final d in days) DayCount(day: d, count: perDay[d]!)];
}

/// Una barra de una serie por días: un día, o una semana cuando el tramo es
/// largo.
@immutable
class SeriesBar {
  const SeriesBar({
    required this.start,
    required this.days,
    required this.values,
  });

  /// El principio del primer día de estudio de la barra.
  final DateTime start;

  /// Cuántos días junta: 1, o 7 en un tramo largo.
  final int days;

  /// Lo apilado, de abajo hacia arriba.
  final List<int> values;

  int get total => values.fold(0, (sum, n) => sum + n);
}

/// Hasta cuántos días se dibuja una barra por día; con más, una por semana.
const kDailyBarsMax = 90;

/// Las barras de [period] para una serie por días de estudio —[valuesOf] da lo
/// apilado de cada día, `null` para un día sin nada—, del día más viejo a hoy,
/// con los días sin nada en cero: una serie con huecos se lee peor que una que
/// baja a cero.
///
/// «Todo» empieza en [first], el día más viejo con algo. Más de
/// [kDailyBarsMax] días van de a semanas, que terminan hoy.
List<SeriesBar> daySeries({
  required StatsPeriod period,
  required DateTime now,
  required DateTime? first,
  required int width,
  required List<int>? Function(DateTime day) valuesOf,
  StudyDay day = const StudyDay(),
}) {
  final today = day.startOf(now);
  DateTime dayAt(int back) =>
      DateTime(today.year, today.month, today.day - back, day.startHour);

  var span = period.days;
  if (span == null) {
    final from = first == null ? today : day.startOf(first);
    // Días de calendario entre los dos, sin depender de que cada uno mida 24
    // horas: se cuentan las fechas.
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(today.year, today.month, today.day);
    span = b.difference(a).inDays + 1;
    if (span < 1) span = 1;
  }
  final step = span > kDailyBarsMax ? 7 : 1;
  final bars = (span / step).ceil();
  return [
    for (var bar = bars - 1; bar >= 0; bar--)
      () {
        final values = List.filled(width, 0);
        for (var k = 0; k < step; k++) {
          final dayValues = valuesOf(dayAt(bar * step + k));
          if (dayValues == null) continue;
          for (var i = 0; i < width; i++) {
            values[i] += dayValues[i];
          }
        }
        return SeriesBar(
          start: dayAt(bar * step + step - 1),
          days: step,
          values: values,
        );
      }(),
  ];
}

/// Una franja de la facilidad: desde [from] por ciento hasta [to] (`null` =
/// sin tope).
@immutable
class EaseBand {
  const EaseBand({required this.from, required this.to, required this.count});

  final int from;
  final int? to;
  final int count;
}

/// El tope de abajo de la facilidad en SM-2: 1,3.
const kMinEasePercent = 130;

/// De cuánto es cada franja de la facilidad, en puntos.
const kEaseBandWidth = 20;

/// Cuántas franjas: de 130 % a 289 % de a veinte, y la última de 290 % para
/// arriba.
const kEaseBands = 9;

/// El reparto de la facilidad en franjas de [kEaseBandWidth] puntos desde
/// [kMinEasePercent].
List<EaseBand> easeBands(Iterable<EaseCount> ease) {
  final counts = List.filled(kEaseBands, 0);
  for (final e in ease) {
    final index = ((e.percent - kMinEasePercent) ~/ kEaseBandWidth).clamp(
      0,
      kEaseBands - 1,
    );
    counts[index] += e.count;
  }
  return [
    for (var i = 0; i < kEaseBands; i++)
      EaseBand(
        from: kMinEasePercent + i * kEaseBandWidth,
        to: i == kEaseBands - 1
            ? null
            : kMinEasePercent + (i + 1) * kEaseBandWidth - 1,
        count: counts[i],
      ),
  ];
}
