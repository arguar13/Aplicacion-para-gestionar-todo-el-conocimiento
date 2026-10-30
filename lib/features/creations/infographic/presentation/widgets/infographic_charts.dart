import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_icons.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_chart_data.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style.dart';

/// Un gráfico dibujado por la app —barras, anillo, avance o pictograma
/// (F43); columnas, anillos concéntricos, cuadrícula de cien o escala
/// (F45)—, con los números de [chart] y los colores del estilo.
///
/// Ocupa el lugar que le den y nunca desborda: los rótulos y las cifras son
/// textos que se ajustan (los lee el lector de pantalla, con
/// `InfographicChartData.describe`), y las formas las pinta un
/// `CustomPainter`. Sin animaciones: el gráfico se dibuja entero de una vez,
/// igual en la pantalla, en la imagen y en el PDF.
class InfoChart extends StatelessWidget {
  const InfoChart({
    required this.style,
    required this.chart,
    required this.surface,
    this.ink,
    super.key,
  });

  final InfographicStyle style;
  final ChartBlock chart;

  /// El color sobre el que queda el gráfico: los colores se ajustan para
  /// verse sobre él.
  final Color surface;

  /// El color del texto, si no es el del estilo (un bloque destacado).
  final Color? ink;

  /// El color del dato [index]: los tres de la paleta y, después, mezclas
  /// de ellos con el texto, legibles sobre [surface].
  static Color colorOf(InfographicStyle style, int index, Color surface) {
    final base = style.tint(index);
    final mixed = index < 3
        ? base
        : Color.lerp(base, style.palette.text, 0.18 + 0.12 * (index ~/ 3))!;
    return CreationContrast.ensure(mixed, surface, minimum: 3);
  }

  @override
  Widget build(BuildContext context) {
    final kind = InfographicChartData.kindOf(chart);
    final points = InfographicChartData.points(chart, kind);
    final text = ink ?? style.ink;
    final muted = ink ?? style.muted;
    final track = text.withValues(alpha: 0.12);
    final Widget body = switch (kind) {
      InfographicChartKind.bars => _Bars(
        style: style,
        points: points,
        surface: surface,
        text: text,
        muted: muted,
        track: track,
      ),
      InfographicChartKind.ring => _Ring(
        style: style,
        points: points,
        surface: surface,
        text: text,
        muted: muted,
        track: track,
        single: points.length == 1,
      ),
      InfographicChartKind.progress => _Progress(
        style: style,
        points: points,
        surface: surface,
        text: text,
        muted: muted,
        track: track,
      ),
      InfographicChartKind.pictogram => _Pictogram(
        style: style,
        chart: chart,
        points: points,
        surface: surface,
        text: text,
        muted: muted,
        track: track,
      ),
      InfographicChartKind.columns => _Columns(
        style: style,
        points: points,
        surface: surface,
        text: text,
        muted: muted,
        track: track,
      ),
      InfographicChartKind.rings => _Rings(
        style: style,
        points: points,
        surface: surface,
        text: text,
        track: track,
      ),
      InfographicChartKind.waffle => _Waffle(
        style: style,
        points: points,
        surface: surface,
        text: text,
        muted: muted,
        track: track,
      ),
      InfographicChartKind.scale => _Scale(
        style: style,
        chart: chart,
        points: points,
        surface: surface,
        text: text,
        muted: muted,
      ),
    };
    return Semantics(
      label: InfographicChartData.describe(chart),
      container: true,
      child: ExcludeSemantics(child: body),
    );
  }
}

/// Barras horizontales: el rótulo, la barra contra el mayor y la cifra.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.style,
    required this.points,
    required this.surface,
    required this.text,
    required this.muted,
    required this.track,
  });

  final InfographicStyle style;
  final List<InfographicChartPoint> points;
  final Color surface;
  final Color text;
  final Color muted;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final n = points.length;
        // Entre fila y fila, a lo sumo un cuarto de lo que toca a cada una.
        final gap = math.min(
          style.gap * 0.45,
          constraints.maxHeight / n * 0.25,
        );
        final double rowHeight = math.max(
          0,
          math.min(
            style.bodySize * 2.6,
            (constraints.maxHeight - gap * (n - 1)) / n - 0.5,
          ),
        );
        // En un lugar angosto, el rótulo va arriba de la barra.
        final stacked = width < 520;
        final labelWidth = stacked ? width * 0.68 : width * 0.3;
        final valueWidth = stacked ? width * 0.3 : width * 0.2;
        final largest = points.indexed.fold<int>(
          0,
          (best, e) => e.$2.value > points[best].value ? e.$1 : best,
        );
        final labelStyle = style.body(size: style.smallSize, color: text);
        final valueStyle = style.figure(
          size: style.smallSize * 1.15,
          color: text,
          weight: 700,
        );
        Widget bar(int i, double height) => SizedBox(
          height: height,
          child: CustomPaint(
            size: Size.infinite,
            painter: InfoBarPainter(
              fraction: points[i].fraction,
              color: InfoChart.colorOf(style, i == largest ? 0 : 1, surface),
              track: track,
            ),
          ),
        );
        Widget label(int i, double height) => SizedBox(
          width: labelWidth,
          height: height,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FitText(
              points[i].label,
              style: labelStyle,
              maxLines: stacked ? 1 : 2,
              minScale: 0.45,
            ),
          ),
        );
        Widget value(int i, double height) => SizedBox(
          width: valueWidth,
          height: height,
          child: Align(
            alignment: Alignment.centerRight,
            child: FitText(
              points[i].text,
              style: valueStyle,
              maxLines: 1,
              minScale: 0.3,
              textAlign: TextAlign.end,
            ),
          ),
        );
        final rows = <Widget>[];
        for (var i = 0; i < n; i++) {
          if (i > 0) rows.add(SizedBox(height: gap));
          if (stacked) {
            final half = rowHeight * 0.55;
            rows.add(
              SizedBox(
                height: rowHeight,
                child: Column(
                  children: [
                    Row(
                      children: [
                        label(i, half),
                        const Spacer(),
                        value(i, half),
                      ],
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: bar(i, rowHeight * 0.26),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            rows.add(
              SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    label(i, rowHeight),
                    SizedBox(width: gap),
                    Expanded(child: bar(i, rowHeight * 0.5)),
                    SizedBox(width: gap),
                    value(i, rowHeight),
                  ],
                ),
              ),
            );
          }
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: rows,
        );
      },
    );
  }
}

/// Una barra: el riel entero, tenue, y encima la parte [fraction] de color,
/// con las puntas redondas.
class InfoBarPainter extends CustomPainter {
  const InfoBarPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final height = size.height;
    final radius = Radius.circular(height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    if (fraction <= 0) return;
    // Aun la más chica se ve: al menos un círculo.
    final width = math.min(
      size.width,
      math.max(height, size.width * fraction.clamp(0, 1)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, height), radius),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(InfoBarPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}

/// Un anillo: un dato solo (el avance contra su total, con la cifra en el
/// medio), o varios (las partes de un todo, con su leyenda).
class _Ring extends StatelessWidget {
  const _Ring({
    required this.style,
    required this.points,
    required this.surface,
    required this.text,
    required this.muted,
    required this.track,
    required this.single,
  });

  final InfographicStyle style;
  final List<InfographicChartPoint> points;
  final Color surface;
  final Color text;
  final Color muted;
  final Color track;
  final bool single;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final colors = [
          for (var i = 0; i < points.length; i++)
            InfoChart.colorOf(style, i, surface),
        ];
        Widget ring(double side) => SizedBox.square(
          dimension: side,
          child: CustomPaint(
            painter: InfoRingPainter(
              fractions: [for (final p in points) p.fraction],
              colors: colors,
              track: track,
              single: single,
            ),
            child: single
                ? Padding(
                    padding: EdgeInsets.all(side * 0.22),
                    child: Center(
                      child: FitText(
                        points.first.text,
                        style: style.figure(size: side * 0.24, color: text),
                        maxLines: 1,
                        minScale: 0.2,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : null,
          ),
        );
        if (single) {
          final label = points.first.label;
          final labelHeight = label.isEmpty
              ? 0.0
              : math.min<double>(h * 0.28, 90);
          final double side = math.max(0, math.min(w, h - labelHeight));
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ring(side),
              if (label.isNotEmpty)
                SizedBox(
                  width: w,
                  height: labelHeight,
                  child: Center(
                    child: FitText(
                      label,
                      style: style.small(color: muted, weight: 600),
                      maxLines: 2,
                      minScale: 0.45,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          );
        }
        // Con leyenda: al costado si hay ancho, si no debajo.
        final beside = w > h * 1.3;
        final side = beside ? math.min(h, w * 0.46) : math.min(w, h * 0.55);
        final legendSize = beside
            ? Size(w - side - style.gap, h)
            : Size(w, h - side - style.gap * 0.6);
        final legend = _Legend(
          style: style,
          points: points,
          colors: colors,
          text: text,
          size: legendSize,
        );
        return beside
            ? Row(
                children: [
                  ring(side),
                  SizedBox(width: style.gap),
                  legend,
                ],
              )
            : Column(
                children: [
                  ring(side),
                  SizedBox(height: style.gap * 0.6),
                  legend,
                ],
              );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.style,
    required this.points,
    required this.colors,
    required this.text,
    required this.size,
  });

  final InfographicStyle style;
  final List<InfographicChartPoint> points;
  final List<Color> colors;
  final Color text;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final n = points.length;
    final double rowHeight = math.max(
      0,
      math.min(style.smallSize * 2, size.height / n - 0.5),
    );
    final double swatch = math.min(rowHeight * 0.5, 22);
    return SizedBox.fromSize(
      size: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < n; i++)
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  Container(
                    width: swatch,
                    height: swatch,
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(swatch * 0.3),
                    ),
                  ),
                  SizedBox(width: swatch * 0.6),
                  Expanded(
                    child: FitText(
                      points[i].label.isEmpty
                          ? points[i].text
                          : '${points[i].label} · ${points[i].text}',
                      style: style.body(size: style.smallSize, color: text),
                      maxLines: 1,
                      minScale: 0.4,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// El anillo: el riel tenue y, encima, un arco por dato (uno solo desde
/// arriba, o las partes una detrás de otra con un respiro entre ellas).
class InfoRingPainter extends CustomPainter {
  const InfoRingPainter({
    required this.fractions,
    required this.colors,
    required this.track,
    required this.single,
  });

  final List<double> fractions;
  final List<Color> colors;
  final Color track;
  final bool single;

  /// Los ángulos (desde arriba, en el sentido del reloj) de cada arco: el
  /// comienzo y el barrido. Público para que la prueba mida lo que se pinta.
  static List<(double, double)> sweeps(
    List<double> fractions, {
    required bool single,
  }) {
    const start = -math.pi / 2;
    if (single) {
      return [(start, math.pi * 2 * fractions.first.clamp(0, 1))];
    }
    final gap = fractions.length > 1 ? 0.04 : 0.0;
    final out = <(double, double)>[];
    var at = start;
    for (final f in fractions) {
      final double sweep = math.max(0, math.pi * 2 * f - gap);
      out.add((at + gap / 2, sweep));
      at += math.pi * 2 * f;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.13;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    for (final (i, (start, sweep)) in sweeps(
      fractions,
      single: single,
    ).indexed) {
      if (sweep <= 0) continue;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = single ? StrokeCap.round : StrokeCap.butt
          ..color = colors[i % colors.length],
      );
    }
  }

  @override
  bool shouldRepaint(InfoRingPainter oldDelegate) =>
      oldDelegate.fractions != fractions ||
      oldDelegate.colors != colors ||
      oldDelegate.track != track ||
      oldDelegate.single != single;
}

/// Barras de avance: cada dato con su rótulo y su cifra arriba, y el riel
/// con lo que lleva de su total.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.style,
    required this.points,
    required this.surface,
    required this.text,
    required this.muted,
    required this.track,
  });

  final InfographicStyle style;
  final List<InfographicChartPoint> points;
  final Color surface;
  final Color text;
  final Color muted;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = points.length;
        final gap = math.min(style.gap * 0.6, constraints.maxHeight / n * 0.25);
        final double rowHeight = math.max(
          0,
          math.min(
            style.bodySize * 3.2,
            (constraints.maxHeight - gap * (n - 1)) / n - 0.5,
          ),
        );
        final w = constraints.maxWidth;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(height: gap),
              SizedBox(
                height: rowHeight,
                child: Column(
                  children: [
                    SizedBox(
                      height: rowHeight * 0.58,
                      child: Row(
                        children: [
                          SizedBox(
                            width: w * 0.62,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: FitText(
                                points[i].label,
                                style: style.body(
                                  size: style.smallSize,
                                  color: text,
                                ),
                                maxLines: 1,
                                minScale: 0.4,
                              ),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: w * 0.34,
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: FitText(
                                points[i].text,
                                style: style.figure(
                                  size: style.bodySize * 1.2,
                                  color: text,
                                ),
                                maxLines: 1,
                                minScale: 0.3,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: rowHeight * 0.1),
                    SizedBox(
                      height: rowHeight * 0.26,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: InfoBarPainter(
                          fraction: points[i].fraction,
                          color: InfoChart.colorOf(style, i, surface),
                          track: track,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// El pictograma: «7 de cada 10» como diez íconos, siete de color.
class _Pictogram extends StatelessWidget {
  const _Pictogram({
    required this.style,
    required this.chart,
    required this.points,
    required this.surface,
    required this.text,
    required this.muted,
    required this.track,
  });

  final InfographicStyle style;
  final ChartBlock chart;
  final List<InfographicChartPoint> points;
  final Color surface;
  final Color text;
  final Color muted;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final total = InfographicChartData.pictogramTotal(chart) ?? 10;
    final icon = CreationIcons.resolve(chart.icon ?? 'person');
    // A lo sumo tres filas (con más, `kindOf` elige barras).
    final shown = points;
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = shown.length;
        final gap = math.min(style.gap * 0.6, constraints.maxHeight / n * 0.25);
        final double rowHeight = math.max(
          0,
          (constraints.maxHeight - gap * (n - 1)) / n - 0.5,
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(height: gap),
              SizedBox(
                height: rowHeight,
                child: Column(
                  children: [
                    SizedBox(
                      height: rowHeight * 0.3,
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FitText(
                                shown[i].label,
                                style: style.body(
                                  size: style.smallSize,
                                  color: text,
                                ),
                                maxLines: 1,
                                minScale: 0.4,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: constraints.maxWidth * 0.3,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FitText(
                                '${shown[i].text} / $total',
                                style: style.figure(
                                  size: style.bodySize * 1.15,
                                  color: text,
                                ),
                                maxLines: 1,
                                minScale: 0.3,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: rowHeight * 0.06),
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: InfoPictogramPainter(
                          icon: icon,
                          total: total,
                          filled: shown[i].value.round().clamp(0, total),
                          color: InfoChart.colorOf(style, i, surface),
                          track: track,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Los íconos del pictograma, en una grilla que entra en el lugar: los
/// primeros [filled] de [color], el resto en el tono tenue.
class InfoPictogramPainter extends CustomPainter {
  const InfoPictogramPainter({
    required this.icon,
    required this.total,
    required this.filled,
    required this.color,
    required this.track,
  });

  final IconData icon;
  final int total;
  final int filled;
  final Color color;
  final Color track;

  /// Cuántas columnas y de qué lado cada ícono, para que [total] entren en
  /// [size] lo más grandes posible.
  static (int columns, double side) grid(int total, Size size) {
    var best = (total, 0.0);
    for (var rows = 1; rows <= total; rows++) {
      final columns = (total / rows).ceil();
      final side = math.min(size.width / columns, size.height / rows);
      if (side > best.$2) best = (columns, side);
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || size.isEmpty) return;
    final (columns, side) = grid(total, size);
    final rows = (total / columns).ceil();
    final left = (size.width - columns * side) / 2;
    final top = (size.height - rows * side) / 2;
    for (var i = 0; i < total; i++) {
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: side * 0.86,
            height: 1,
            color: i < filled ? color : track,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final cell = Offset(
        left + (i % columns) * side,
        top + (i ~/ columns) * side,
      );
      painter
        ..paint(
          canvas,
          cell +
              Offset((side - painter.width) / 2, (side - painter.height) / 2),
        )
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(InfoPictogramPainter oldDelegate) =>
      oldDelegate.icon != icon ||
      oldDelegate.total != total ||
      oldDelegate.filled != filled ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}

// ---------------------------------------------------------------------
// Los cuatro de F45.

/// Columnas: una barra parada por dato contra el mayor, con su cifra arriba y
/// su rótulo abajo; la mayor, del primario.
class _Columns extends StatelessWidget {
  const _Columns({
    required this.style,
    required this.points,
    required this.surface,
    required this.text,
    required this.muted,
    required this.track,
  });

  final InfographicStyle style;
  final List<InfographicChartPoint> points;
  final Color surface;
  final Color text;
  final Color muted;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = points.length;
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final slot = w / n;
        final valueHeight = math.min(style.smallSize * 1.7, h * 0.18);
        final labelHeight = math.min(style.smallSize * 2.7, h * 0.26);
        final double barArea = math.max(0, h - valueHeight - labelHeight);
        final largest = points.indexed.fold<int>(
          0,
          (best, e) => e.$2.value > points[best].value ? e.$1 : best,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < n; i++)
              SizedBox(
                width: slot,
                child: Column(
                  children: [
                    // La cifra, pegada arriba de su columna.
                    SizedBox(
                      height: barArea * (1 - points[i].fraction) + valueHeight,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          height: valueHeight,
                          width: slot * 0.94,
                          child: Center(
                            child: FitText(
                              points[i].text,
                              style: style.figure(
                                size: style.smallSize * 1.15,
                                color: text,
                                weight: 700,
                              ),
                              maxLines: 1,
                              minScale: 0.3,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: slot * 0.56,
                          decoration: BoxDecoration(
                            color: InfoChart.colorOf(
                              style,
                              i == largest ? 0 : 1,
                              surface,
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(slot * 0.12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(height: 3, color: track),
                    SizedBox(
                      height: labelHeight - 3,
                      width: slot * 0.96,
                      child: Center(
                        child: FitText(
                          points[i].label,
                          style: style.body(
                            size: style.smallSize,
                            color: muted,
                          ),
                          maxLines: 2,
                          minScale: 0.4,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Los anillos concéntricos: una vuelta por dato, de afuera hacia adentro,
/// cada una con lo suyo de su total; la leyenda al costado (o debajo).
class _Rings extends StatelessWidget {
  const _Rings({
    required this.style,
    required this.points,
    required this.surface,
    required this.text,
    required this.track,
  });

  final InfographicStyle style;
  final List<InfographicChartPoint> points;
  final Color surface;
  final Color text;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final colors = [
      for (var i = 0; i < points.length; i++)
        InfoChart.colorOf(style, i, surface),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final beside = w > h * 1.3;
        final side = beside ? math.min(h, w * 0.46) : math.min(w, h * 0.58);
        final legendSize = beside
            ? Size(w - side - style.gap, h)
            : Size(w, math.max(0, h - side - style.gap * 0.6));
        final rings = SizedBox.square(
          dimension: side,
          child: CustomPaint(
            painter: InfoRingsPainter(
              fractions: [for (final p in points) p.fraction],
              colors: colors,
              track: track,
            ),
          ),
        );
        final legend = _Legend(
          style: style,
          points: points,
          colors: colors,
          text: text,
          size: legendSize,
        );
        return beside
            ? Row(
                children: [
                  rings,
                  SizedBox(width: style.gap),
                  legend,
                ],
              )
            : Column(
                children: [
                  rings,
                  SizedBox(height: style.gap * 0.6),
                  legend,
                ],
              );
      },
    );
  }
}

/// Los anillos concéntricos: el riel de cada vuelta y, encima, su arco desde
/// arriba, con las puntas redondas.
class InfoRingsPainter extends CustomPainter {
  const InfoRingsPainter({
    required this.fractions,
    required this.colors,
    required this.track,
  });

  final List<double> fractions;
  final List<Color> colors;
  final Color track;

  /// El radio de la vuelta [index] de [count], en un lugar de lado [side], y
  /// el grueso de todas: de afuera hacia adentro, con un respiro entre ellas.
  static ({double radius, double stroke}) ring(
    int index,
    int count,
    double side,
  ) {
    final stroke = side / 2 / (count * 1.45 + 0.8);
    return (
      radius: side / 2 - stroke / 2 - index * stroke * 1.45,
      stroke: stroke,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < fractions.length; i++) {
      final (:radius, :stroke) = ring(i, fractions.length, size.shortestSide);
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track,
      );
      final sweep = math.pi * 2 * fractions[i].clamp(0, 1);
      if (sweep <= 0) continue;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = colors[i % colors.length],
      );
    }
  }

  @override
  bool shouldRepaint(InfoRingsPainter oldDelegate) =>
      oldDelegate.fractions != fractions ||
      oldDelegate.colors != colors ||
      oldDelegate.track != track;
}

/// La cuadrícula de cien: diez por diez cuadraditos, pintados en orden con
/// cada parte; con una sola, su cifra y su rótulo al lado.
class _Waffle extends StatelessWidget {
  const _Waffle({
    required this.style,
    required this.points,
    required this.surface,
    required this.text,
    required this.muted,
    required this.track,
  });

  final InfographicStyle style;
  final List<InfographicChartPoint> points;
  final Color surface;
  final Color text;
  final Color muted;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final colors = [
      for (var i = 0; i < points.length; i++)
        InfoChart.colorOf(style, i, surface),
    ];
    final cells = InfoWafflePainter.cellsOf([
      for (final p in points) p.fraction,
    ]);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final beside = w > h * 1.25;
        final side = beside ? math.min(h, w * 0.5) : math.min(w, h * 0.62);
        final grid = SizedBox.square(
          dimension: side,
          child: CustomPaint(
            painter: InfoWafflePainter(
              cells: cells,
              colors: colors,
              track: track,
            ),
          ),
        );
        final restSize = beside
            ? Size(w - side - style.gap, h)
            : Size(w, math.max(0, h - side - style.gap * 0.6));
        final Widget rest;
        if (points.length == 1) {
          final point = points.first;
          rest = SizedBox.fromSize(
            size: restSize,
            child: FitTextGroup(
              crossAxisAlignment: beside
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              items: [
                FitTextItem(
                  text: point.text,
                  style: style.figure(size: style.figureSize, color: text),
                  maxLines: 1,
                  textAlign: beside ? TextAlign.start : TextAlign.center,
                ),
                if (point.label.isNotEmpty)
                  FitTextItem(
                    text: point.label,
                    style: style.small(color: muted, weight: 600),
                    gapBefore: style.gap * 0.3,
                    maxLines: 3,
                    textAlign: beside ? TextAlign.start : TextAlign.center,
                  ),
              ],
            ),
          );
        } else {
          rest = _Legend(
            style: style,
            points: points,
            colors: colors,
            text: text,
            size: restSize,
          );
        }
        return beside
            ? Row(
                children: [
                  grid,
                  SizedBox(width: style.gap),
                  Align(alignment: Alignment.centerLeft, child: rest),
                ],
              )
            : Column(
                children: [
                  grid,
                  SizedBox(height: style.gap * 0.6),
                  rest,
                ],
              );
      },
    );
  }
}

/// Los cien cuadraditos: de a filas, de arriba a la izquierda, los de cada
/// parte de su color y los que sobran en el tono tenue.
class InfoWafflePainter extends CustomPainter {
  const InfoWafflePainter({
    required this.cells,
    required this.colors,
    required this.track,
  });

  /// La parte de cada uno de los cien cuadraditos, o -1 si no es de ninguna.
  final List<int> cells;
  final List<Color> colors;
  final Color track;

  /// Cuántos cuadraditos toca a cada parte: redondeados de modo que la suma
  /// sea la de las fracciones (el método del mayor resto), así «33 %, 33 %,
  /// 34 %» pinta los cien y no noventa y nueve.
  static List<int> cellsOf(List<double> fractions) {
    final exact = [for (final f in fractions) f.clamp(0, 1) * 100];
    final whole = [for (final e in exact) e.floor()];
    final target = math.min(
      100,
      exact.fold<double>(0, (a, e) => a + e).round(),
    );
    var missing = target - whole.fold<int>(0, (a, e) => a + e);
    final byRest = List<int>.generate(exact.length, (i) => i)
      ..sort((a, b) => (exact[b] - whole[b]).compareTo(exact[a] - whole[a]));
    for (final i in byRest) {
      if (missing <= 0) break;
      whole[i]++;
      missing--;
    }
    return [
      for (var part = 0; part < whole.length; part++)
        for (var k = 0; k < whole[part]; k++) part,
      for (var k = whole.fold<int>(0, (a, e) => a + e); k < 100; k++) -1,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / 10;
    final gap = cell * 0.14;
    final left = (size.width - cell * 10) / 2;
    final top = (size.height - cell * 10) / 2;
    for (var i = 0; i < 100; i++) {
      final part = i < cells.length ? cells[i] : -1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left + (i % 10) * cell + gap / 2,
            top + (i ~/ 10) * cell + gap / 2,
            cell - gap,
            cell - gap,
          ),
          Radius.circular(cell * 0.18),
        ),
        Paint()..color = part < 0 ? track : colors[part % colors.length],
      );
    }
  }

  @override
  bool shouldRepaint(InfoWafflePainter oldDelegate) =>
      oldDelegate.cells.length != cells.length ||
      oldDelegate.colors != colors ||
      oldDelegate.track != track ||
      !Iterable<int>.generate(
        cells.length,
      ).every((i) => oldDelegate.cells[i] == cells[i]);
}

/// La escala: una regla del mínimo al máximo, con un degradé de su color,
/// las dos puntas nombradas abajo y una marca por dato, con su rótulo y su
/// cifra arriba, cada una en su renglón para que no se pisen.
class _Scale extends StatelessWidget {
  const _Scale({
    required this.style,
    required this.chart,
    required this.points,
    required this.surface,
    required this.text,
    required this.muted,
  });

  final InfographicStyle style;
  final ChartBlock chart;
  final List<InfographicChartPoint> points;
  final Color surface;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final (low, high) = InfographicChartData.scaleRange(chart) ?? (0.0, 100.0);
    final ends = InfographicChartData.scaleEnds(chart, low, high);
    final from = CreationContrast.ensure(style.tint(1), surface, minimum: 3);
    final to = CreationContrast.ensure(style.tint(0), surface, minimum: 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final n = points.length;
        final barHeight = math.min(style.gap * 1.1, h * 0.14);
        final endsHeight = math.min(style.smallSize * 2.4, h * 0.24);
        final double markRows = math.max(0, h - barHeight - endsHeight);
        final rowHeight = math.min(style.bodySize * 2.4, markRows / n);
        final labelWidth = math.min(w * 0.6, math.max(w / n, w * 0.38));
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < n; i++)
              SizedBox(
                height: rowHeight,
                child: Stack(
                  children: [
                    Positioned(
                      // La etiqueta, centrada en su marca sin salirse.
                      left: (w * points[i].fraction - labelWidth / 2).clamp(
                        0.0,
                        math.max<double>(0, w - labelWidth),
                      ),
                      width: labelWidth,
                      top: 0,
                      bottom: rowHeight * 0.18,
                      child: Center(
                        child: FitText(
                          points[i].label.isEmpty
                              ? points[i].text
                              : '${points[i].label} · ${points[i].text}',
                          style: style.body(
                            size: style.smallSize * 1.05,
                            color: text,
                            weight: 700,
                          ),
                          maxLines: 1,
                          minScale: 0.35,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    // El palito que baja a la regla.
                    Positioned(
                      left: (w * points[i].fraction - 2).clamp(0.0, w - 4),
                      width: 4,
                      bottom: 0,
                      height: rowHeight * 0.2,
                      child: ColoredBox(color: text.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: barHeight,
              child: CustomPaint(
                size: Size.infinite,
                painter: InfoScalePainter(
                  marks: [for (final p in points) p.fraction],
                  from: from,
                  to: to,
                  marker: text,
                  surface: surface,
                ),
              ),
            ),
            SizedBox(
              height: endsHeight,
              child: Row(
                children: [
                  for (final (k, end) in [ends.$1, ends.$2].indexed)
                    Expanded(
                      child: Align(
                        alignment: k == 0
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: FitText(
                          end,
                          style: style.small(color: muted, weight: 600),
                          maxLines: 1,
                          minScale: 0.4,
                          textAlign: k == 0 ? TextAlign.start : TextAlign.end,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// La regla de la escala: la barra redondeada con el degradé de una punta a
/// la otra y, encima, una marca circular por dato, del color del texto con
/// un borde de la superficie.
class InfoScalePainter extends CustomPainter {
  const InfoScalePainter({
    required this.marks,
    required this.from,
    required this.to,
    required this.marker,
    required this.surface,
  });

  final List<double> marks;
  final Color from;
  final Color to;
  final Color marker;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Rect.fromLTWH(
      0,
      size.height * 0.25,
      size.width,
      size.height * 0.5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, Radius.circular(bar.height / 2)),
      Paint()..shader = LinearGradient(colors: [from, to]).createShader(bar),
    );
    final radius = size.height * 0.42;
    for (final mark in marks) {
      final center = Offset(
        (size.width * mark.clamp(0, 1)).clamp(radius, size.width - radius),
        size.height / 2,
      );
      canvas
        ..drawCircle(center, radius, Paint()..color = surface)
        ..drawCircle(center, radius * 0.7, Paint()..color = marker);
    }
  }

  @override
  bool shouldRepaint(InfoScalePainter oldDelegate) =>
      oldDelegate.marks != marks ||
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.marker != marker ||
      oldDelegate.surface != surface;
}
