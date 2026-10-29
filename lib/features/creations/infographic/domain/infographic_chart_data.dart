import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_numbers.dart';

/// Un dato listo para dibujar: su rótulo, cómo se escribe y qué parte del
/// gráfico ocupa (de 0 a 1).
@immutable
class InfographicChartPoint {
  const InfographicChartPoint({
    required this.label,
    required this.text,
    required this.fraction,
    required this.value,
  });

  final String label;

  /// La cifra como se ve: la que escribió la IA, o el número con su unidad.
  final String text;

  /// El largo de la barra, la porción del anillo o el avance.
  final double fraction;

  final double value;
}

/// Las cuentas de los gráficos (F43: «Gráficos dibujados por la app»): qué
/// gráfico va si la IA no lo dijo, cuánto mide cada dato y cómo se escribe.
/// Sin dibujo: el dibujo lo hacen los pintores de `infographic_charts.dart`,
/// con estos números.
abstract final class InfographicChartData {
  /// El tope de íconos de un pictograma: más ya no se cuentan de un vistazo.
  static const int maxPictogram = 20;

  /// Las filas de un pictograma: con más, cada fila queda chica.
  static const int maxPictogramRows = 3;

  /// El gráfico de [chart]: el que pidió la IA si los datos lo sostienen, o el
  /// que dicen los datos:
  ///
  /// - un dato que es «N de M» con M hasta 20 → pictograma;
  /// - un porcentaje solo, o partes que suman 100 % → anillo;
  /// - un dato con su total → avance;
  /// - lo demás → barras.
  static InfographicChartKind kindOf(ChartBlock chart) {
    final data = chart.data;
    final requested = chart.chartKind;
    if (requested == InfographicChartKind.pictogram &&
        (pictogramTotal(chart) == null || data.length > maxPictogramRows)) {
      // Un pictograma de 3.000.000 de íconos, o de diez filas, no se lee:
      // avance o barras.
      return data.length == 1
          ? InfographicChartKind.progress
          : InfographicChartKind.bars;
    }
    if (requested != null) return requested;
    if (data.length == 1) {
      if (pictogramTotal(chart) != null && chart.total != null) {
        return InfographicChartKind.pictogram;
      }
      if (_isPercent(chart) && chart.total == null) {
        return InfographicChartKind.ring;
      }
      return InfographicChartKind.progress;
    }
    final sum = data.fold<double>(0, (a, d) => a + d.value);
    if (_isPercent(chart) && (sum - 100).abs() <= 1) {
      return InfographicChartKind.ring;
    }
    return InfographicChartKind.bars;
  }

  /// Los datos de [chart] con su fracción, según [kind]:
  ///
  /// - barras: contra el mayor;
  /// - anillo: un dato solo contra su total (o 100); varios, su parte de la
  ///   suma;
  /// - avance y pictograma: contra el total (o 100 si son porcentajes, o el
  ///   mayor).
  static List<InfographicChartPoint> points(
    ChartBlock chart, [
    InfographicChartKind? kind,
  ]) {
    final data = chart.data;
    if (data.isEmpty) return const [];
    final which = kind ?? kindOf(chart);
    final values = [for (final d in data) math.max(0, d.value).toDouble()];
    final largest = values.reduce(math.max);
    final sum = values.fold<double>(0, (a, v) => a + v);
    final reference = switch (which) {
      InfographicChartKind.bars => largest,
      InfographicChartKind.ring =>
        data.length == 1 ? (chart.total ?? 100.0) : sum,
      InfographicChartKind.progress || InfographicChartKind.pictogram =>
        chart.total ?? (_isPercent(chart) ? 100.0 : largest),
    };
    return [
      for (var i = 0; i < data.length; i++)
        InfographicChartPoint(
          label: data[i].label,
          text: textOf(data[i], chart.unit),
          value: data[i].value,
          fraction: reference <= 0
              ? 0
              : (values[i] / reference).clamp(0, 1).toDouble(),
        ),
    ];
  }

  /// La cifra de [datum] como se ve: la que escribió la IA, o el número en
  /// castellano con su unidad («40 %», «3 años»).
  static String textOf(InfographicDatum datum, String unit) {
    if (datum.display.isNotEmpty) return datum.display;
    final number = InfographicNumbers.format(datum.value);
    if (unit.isEmpty) return number;
    return unit == '%' ? '$number %' : '$number $unit';
  }

  /// Cuántos íconos lleva el pictograma de [chart] (su total, o 10 si los
  /// valores son de hasta 10 y no lo dice), o null si no se puede dibujar
  /// como pictograma (más de [maxPictogram]).
  static int? pictogramTotal(ChartBlock chart) {
    final total =
        chart.total ??
        (chart.data.every((d) => d.value <= 10)
            ? 10
            : chart.data.map((d) => d.value).fold<double>(0, math.max));
    if (total <= 0 || total > maxPictogram) return null;
    if (chart.data.any((d) => d.value > total)) return null;
    return total.round();
  }

  /// Lo que dice el gráfico, en palabras: para quien no lo ve (el lector de
  /// pantalla).
  static String describe(ChartBlock chart) {
    final points = InfographicChartData.points(chart);
    final values = [
      for (final p in points)
        if (p.label.isEmpty) p.text else '${p.label}: ${p.text}',
    ].join('; ');
    if (chart.title.isEmpty) return values;
    return '${chart.title}. $values';
  }

  static bool _isPercent(ChartBlock chart) =>
      chart.unit.trim() == '%' ||
      (chart.data.isNotEmpty &&
          chart.data.every((d) => d.display.contains('%')));
}
