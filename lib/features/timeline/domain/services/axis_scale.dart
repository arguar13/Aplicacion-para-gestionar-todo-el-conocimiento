import 'dart:math' as math;

import 'package:sinapsis/features/timeline/domain/services/timeline_axis.dart';

/// De qué es cada marca del eje.
enum AxisUnit {
  /// Comienzos de año, cada [AxisScale.step] años.
  years,

  /// Comienzos de mes, cada [AxisScale.step] meses.
  months,
}

/// Una marca del eje: el comienzo de un año o de un mes.
///
/// `year` es astronómico, igual que el eje; `month` es 1–12 y vale 1 en las
/// marcas de año. Para escribir la etiqueta se convierte con
/// `HistoricalDate.fromAstronomicalYear`: el 0 es "1 a.C.", el -99 es
/// "100 a.C.".
typedef AxisTick = ({double position, int year, int month});

/// Las marcas que le corresponden a una ventana del eje.
class AxisScale {
  const AxisScale({
    required this.unit,
    required this.step,
    required this.ticks,
  });

  final AxisUnit unit;

  /// Cada cuántas [unit] va una marca.
  final int step;

  /// En orden de izquierda a derecha, todas dentro de la ventana.
  final List<AxisTick> ticks;
}

/// Cuántos meses puede haber entre marcas cuando el zoom es de menos de un
/// año por marca.
const _monthSteps = [1, 2, 3, 6];

/// Elige la escala de la ventana `[from, to]`, con unas [targetCount] marcas.
///
/// El paso sale de la serie 1, 2, 5 × 10ⁿ años —la que usa cualquier regla—;
/// por debajo de un año se pasa a meses. Siempre da a lo sumo [targetCount]
/// marcas más una de la era, así que el costo no depende de cuán lejos esté
/// el zoom.
///
/// Las marcas son el comienzo real de cada año, con la etiqueta que le toca:
/// no hay año cero, así que a.C. y d.C. no se cuentan igual. Las marcas de a.C.
/// caen en `1 - N` ("100 a.C." en -99), las de d.C. en `N`, y cuando el paso
/// es mayor que un año se agrega el "1 d.C." para que el paso por la era se
/// vea: el hueco entre "100 a.C." y "1 d.C." es de cien años, no de doscientos.
AxisScale axisScale({
  required double from,
  required double to,
  int targetCount = 8,
}) {
  assert(targetCount > 0, 'Hace falta al menos una marca.');
  if (!from.isFinite || !to.isFinite || to <= from) {
    return const AxisScale(unit: AxisUnit.years, step: 1, ticks: []);
  }

  final raw = (to - from) / targetCount;
  if (raw < 1) {
    for (final months in _monthSteps) {
      if (months / 12 >= raw) return _monthlyScale(from, to, months);
    }
    // Entre medio año y un año por marca: el año entero es el paso que sigue.
    return _yearlyScale(from, to, 1);
  }
  return _yearlyScale(from, to, _niceStep(raw));
}

/// El menor 1, 2, 5 × 10ⁿ que no queda por debajo de [raw] (que es ≥ 1).
int _niceStep(double raw) {
  var magnitude = 1;
  while (magnitude * 10 <= raw) {
    magnitude *= 10;
  }
  for (final factor in const [1, 2, 5]) {
    if (factor * magnitude >= raw) return factor * magnitude;
  }
  return 10 * magnitude;
}

AxisScale _yearlyScale(double from, double to, int step) {
  final ticks = <AxisTick>[];

  // El año N a.C. empieza en 1 - N. Para que las posiciones crezcan, se
  // recorre de la N más grande a la más chica.
  final firstBce = math.max(1, ((1 - to) / step).ceil());
  final lastBce = ((1 - from) / step).floor();
  for (var m = lastBce; m >= firstBce; m--) {
    final year = 1 - m * step;
    ticks.add((position: year.toDouble(), year: year, month: 1));
  }

  // Con paso 1 el propio "1" de la serie es el comienzo de la era.
  if (step > 1 && from <= 1 && 1 <= to) {
    ticks.add((position: 1, year: 1, month: 1));
  }

  final firstCe = math.max(1, (from / step).ceil());
  final lastCe = (to / step).floor();
  for (var m = firstCe; m <= lastCe; m++) {
    final year = m * step;
    ticks.add((position: year.toDouble(), year: year, month: 1));
  }

  return AxisScale(unit: AxisUnit.years, step: step, ticks: ticks);
}

AxisScale _monthlyScale(double from, double to, int step) {
  final ticks = <AxisTick>[];
  for (var year = from.floor(); year <= to.floor(); year++) {
    for (var month = 1; month <= 12; month += step) {
      final position = axisStartOfMonth(year, month);
      if (position < from || position > to) continue;
      ticks.add((position: position, year: year, month: month));
    }
  }
  return AxisScale(unit: AxisUnit.months, step: step, ticks: ticks);
}
