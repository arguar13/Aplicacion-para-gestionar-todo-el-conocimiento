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

  /// Las vueltas de los anillos concéntricos y las partes de la cuadrícula
  /// de cien: con más, no se distinguen.
  static const int maxRings = 4;

  /// Las marcas de una escala: más se pisan.
  static const int maxScaleMarks = 3;

  /// El gráfico de [chart]: el que pidió la IA si los datos lo sostienen, o el
  /// que dicen los datos:
  ///
  /// - un dato que es «N de M» con M hasta 20 → pictograma;
  /// - un porcentaje solo, o partes que suman 100 % → anillo;
  /// - un dato con su total → avance;
  /// - lo demás → barras.
  ///
  /// Los de F45 solo si los pide la IA —o, la escala, si trae su mínimo— y
  /// los datos los sostienen; si no, el que corresponde de los de F43.
  static InfographicChartKind kindOf(ChartBlock chart) {
    final data = chart.data;
    final requested = chart.chartKind;
    final fallback = data.length == 1
        ? InfographicChartKind.progress
        : InfographicChartKind.bars;
    switch (requested) {
      case InfographicChartKind.pictogram
          when pictogramTotal(chart) == null || data.length > maxPictogramRows:
        // Un pictograma de 3.000.000 de íconos, o de diez filas, no se lee.
        return fallback;
      case InfographicChartKind.columns when data.length < 2:
        // Una columna sola no compara nada.
        return fallback;
      case InfographicChartKind.rings when data.length > maxRings:
        return InfographicChartKind.bars;
      case InfographicChartKind.waffle
          when data.length > maxRings || _wholeOf(chart) == null:
        // Cien cuadraditos cuentan un todo: sin uno, no hay qué contar.
        return fallback;
      case InfographicChartKind.scale
          when data.length > maxScaleMarks || scaleRange(chart) == null:
        return fallback;
      case final InfographicChartKind kind:
        return kind;
      case null:
        break;
    }
    if (chart.minimum != null &&
        data.length <= maxScaleMarks &&
        scaleRange(chart) != null) {
      return InfographicChartKind.scale;
    }
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
    if (which == InfographicChartKind.scale) {
      // En una escala, la fracción es dónde cae entre sus dos puntas, con los
      // valores tal cual (un mínimo puede ser negativo).
      final (low, high) = scaleRange(chart) ?? (0.0, largest);
      return [
        for (final d in data)
          InfographicChartPoint(
            label: d.label,
            text: textOf(d, chart.unit),
            value: d.value,
            fraction: high <= low
                ? 0
                : ((d.value - low) / (high - low)).clamp(0, 1).toDouble(),
          ),
      ];
    }
    final reference = switch (which) {
      InfographicChartKind.bars || InfographicChartKind.columns => largest,
      InfographicChartKind.ring =>
        data.length == 1 ? (chart.total ?? 100.0) : sum,
      InfographicChartKind.progress ||
      InfographicChartKind.pictogram ||
      InfographicChartKind.rings =>
        chart.total ?? (_isPercent(chart) ? 100.0 : largest),
      InfographicChartKind.waffle => _wholeOf(chart) ?? sum,
      InfographicChartKind.scale => largest,
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

  /// Las dos puntas de la escala de [chart]: su mínimo (o cero) y su total
  /// (o 100 si son porcentajes); null si no hay un máximo que la cierre o si
  /// no queda por encima del mínimo.
  static (double, double)? scaleRange(ChartBlock chart) {
    final high = chart.total ?? (_isPercent(chart) ? 100.0 : null);
    if (high == null) return null;
    final low = chart.minimum ?? 0;
    return high > low ? (low, high) : null;
  }

  /// El todo de la cuadrícula de cien: el total, o 100 si son porcentajes; o
  /// la suma de las partes, si son varias. Null si no hay un todo (un dato
  /// suelto sin total ni porcentaje) o si las partes lo pasan.
  static double? _wholeOf(ChartBlock chart) {
    final data = chart.data;
    final sum = data.fold<double>(0, (a, d) => a + math.max(0, d.value));
    final whole =
        chart.total ??
        (_isPercent(chart) ? 100.0 : (data.length > 1 ? sum : null));
    if (whole == null || whole <= 0 || sum > whole * 1.001) return null;
    return whole;
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
  ///
  /// Una escala dice además sus dos puntas, sin palabras propias —con sus
  /// nombres, si los tiene, o sus números—: «pH: 7 (Ácido – Básico)».
  static String describe(ChartBlock chart) {
    final kind = kindOf(chart);
    final points = InfographicChartData.points(chart, kind);
    var values = [
      for (final p in points)
        if (p.label.isEmpty) p.text else '${p.label}: ${p.text}',
    ].join('; ');
    if (kind == InfographicChartKind.scale) {
      final (low, high) = scaleRange(chart)!;
      final ends = scaleEnds(chart, low, high);
      values = '$values (${ends.$1} – ${ends.$2})';
    }
    if (chart.title.isEmpty) return values;
    return '${chart.title}. $values';
  }

  /// Cómo se escriben las dos puntas de la escala: sus nombres, o sus
  /// números con la unidad.
  static (String, String) scaleEnds(ChartBlock chart, double low, double high) {
    String number(double value) =>
        textOf(InfographicDatum(label: '', value: value), chart.unit);
    return (
      chart.minLabel.isNotEmpty ? chart.minLabel : number(low),
      chart.maxLabel.isNotEmpty ? chart.maxLabel : number(high),
    );
  }

  static bool _isPercent(ChartBlock chart) =>
      chart.unit.trim() == '%' ||
      (chart.data.isNotEmpty &&
          chart.data.every((d) => d.display.contains('%')));
}
