import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_charts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las piezas de los gráficos de Estadísticas e Historial (F43, M16 y M17),
/// dibujadas por la app sin librería, con la base de los gráficos de la
/// infografía (`InfoRingPainter`, `CreationContrast`).
///
/// Cada gráfico va en una [StatsSection]: su título, una línea de qué muestra
/// y «Ver los números». Tocar una barra dice su número exacto, y el lector de
/// pantalla lee los valores. Sin animaciones: se dibuja entero de una vez.

/// Una sección: el título, la línea de qué muestra, los tramos a elegir, el
/// gráfico y, plegada, la tabla con los números.
class StatsSection extends StatelessWidget {
  const StatsSection({
    required this.title,
    required this.subtitle,
    required this.child,
    this.controls,
    this.table,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;

  /// Los tramos a elegir, arriba del gráfico.
  final Widget? controls;

  /// Los números del gráfico, renglón por renglón: el rótulo y la cifra.
  final List<(String, String)>? table;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final rows = table;
    // Un Material y no una caja pintada: la tabla plegable y las filas que se
    // tocan dibujan su tinta sobre él.
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (controls != null) ...[const SizedBox(height: 12), controls!],
            const SizedBox(height: 12),
            child,
            if (rows != null && rows.isNotEmpty)
              Theme(
                // Sin las líneas que ExpansionTile pone arriba y abajo.
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    l10n.cardStatsForecastTable,
                    style: theme.textTheme.labelLarge,
                  ),
                  children: [
                    for (final (label, value) in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text(label)),
                            const SizedBox(width: 12),
                            Text(
                              value,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Los tramos a elegir de un gráfico («7 días · 30 días · 3 meses»), como
/// chips que bajan de renglón si no entran: con letra grande, nada se corta.
class StatsRangeChips<T> extends StatelessWidget {
  const StatsRangeChips({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.keyPrefix,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  /// Para las pruebas: cada chip lleva `Key('$keyPrefix-$value')`.
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            key: keyPrefix == null
                ? null
                : Key('$keyPrefix-${value is Enum ? value.name : value}'),
            label: Text(labelOf(value)),
            selected: value == selected,
            showCheckmark: false,
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}

/// Una barra de un [StatsBarChart]: lo apilado, de abajo hacia arriba, y lo
/// que se dice al tocarla.
@immutable
class StatsBar {
  const StatsBar({required this.values, required this.description});

  /// Cada capa de la barra, en el orden de los colores del gráfico.
  final List<double> values;

  /// El número exacto, en palabras: lo que aparece al tocarla y lo que lee el
  /// lector de pantalla («lun 12 oct: 34 repasos»).
  final String description;

  double get total => values.fold(0, (sum, v) => sum + v);
}

/// Un gráfico de columnas, apiladas o no, con su eje: las marcas del eje de
/// la izquierda, los rótulos de abajo, la cifra encima de cada columna si
/// entra, y una línea de referencia si hace falta (el 90 % de la retención).
///
/// Tocar o arrastrar sobre el gráfico elige una columna: queda resaltada y se
/// dice su número exacto en el renglón de arriba. Para el lector de pantalla
/// el gráfico es un solo nodo que lee el resumen y los valores.
class StatsBarChart extends StatefulWidget {
  const StatsBarChart({
    required this.bars,
    required this.colors,
    required this.semanticsLabel,
    this.xLabels = const {},
    this.maxValue,
    this.tickText,
    this.valueText,
    this.reference,
    this.referenceLabel,
    this.height = 168,
    super.key,
  });

  final List<StatsBar> bars;

  /// Un color por capa.
  final List<Color> colors;

  /// El resumen del gráfico; el lector de pantalla le suma los valores.
  final String semanticsLabel;

  /// Los rótulos de abajo, por posición de la columna. Uno que se pisaría con
  /// el anterior no se dibuja.
  final Map<int, String> xLabels;

  /// El tope del eje (100 para un porcentaje); si no, el redondeo del mayor.
  final double? maxValue;

  /// Cómo se escribe una marca del eje («50 %»); si no, el número.
  final String Function(double value)? tickText;

  /// La cifra encima de cada columna, si entra en su ancho; `null` = sin
  /// cifras (solo al tocar).
  final String Function(StatsBar bar)? valueText;

  /// Una línea tenue de referencia, en unidades del eje.
  final double? reference;
  final String? referenceLabel;

  final double height;

  @override
  State<StatsBarChart> createState() => _StatsBarChartState();
}

class _StatsBarChartState extends State<StatsBarChart> {
  int? _selected;

  @override
  void didUpdateWidget(StatsBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected != null && _selected! >= widget.bars.length) _selected = null;
  }

  /// Cuántos valores se leen uno por uno: con más, el resumen y «Ver los
  /// números».
  static const _spokenBars = 31;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Los rótulos del eje crecen con la letra, hasta un punto: más grandes no
    // entran entre las columnas. Los números exactos están en el renglón de
    // arriba y en la tabla, con la letra entera.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
    final axisStyle = (theme.textTheme.labelSmall ?? const TextStyle())
        .copyWith(color: scheme.onSurfaceVariant);
    final valueStyle = (theme.textTheme.labelSmall ?? const TextStyle())
        .copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600);
    final selected = _selected;
    final spoken = widget.bars.length <= _spokenBars
        ? [for (final bar in widget.bars) bar.description].join('; ')
        : l10n.f43S20ChartSeeNumbers;

    return Semantics(
      container: true,
      label: '${widget.semanticsLabel}. $spoken',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Siempre ocupa su renglón: elegir una columna no mueve el gráfico.
          Text(
            selected == null
                ? l10n.f43S20ChartTapHint
                : widget.bars[selected].description,
            key: const Key('stats-chart-callout'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: selected == null
                ? theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )
                : theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final painter = StatsBarPainter(
                  bars: widget.bars,
                  colors: widget.colors,
                  xLabels: widget.xLabels,
                  maxValue: widget.maxValue,
                  tickText: widget.tickText,
                  valueText: widget.valueText,
                  reference: widget.reference,
                  referenceLabel: widget.referenceLabel,
                  selected: selected,
                  axisStyle: axisStyle,
                  valueStyle: valueStyle,
                  scaler: scaler,
                  grid: scheme.outlineVariant,
                  baseline: scheme.outline,
                  surface: scheme.surfaceContainerLow,
                  textDirection: Directionality.of(context),
                );
                void pick(Offset at) {
                  final index = painter.indexAt(at, constraints.biggest);
                  if (index != null && index != _selected) {
                    setState(() => _selected = index);
                  }
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => pick(details.localPosition),
                  onHorizontalDragUpdate: (details) =>
                      pick(details.localPosition),
                  child: CustomPaint(size: Size.infinite, painter: painter),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que pinta [StatsBarChart]. Público para que la prueba mida dónde cae
/// cada columna.
class StatsBarPainter extends CustomPainter {
  StatsBarPainter({
    required this.bars,
    required this.colors,
    required this.xLabels,
    required this.maxValue,
    required this.tickText,
    required this.valueText,
    required this.reference,
    required this.referenceLabel,
    required this.selected,
    required this.axisStyle,
    required this.valueStyle,
    required this.scaler,
    required this.grid,
    required this.baseline,
    required this.surface,
    required this.textDirection,
  });

  final List<StatsBar> bars;
  final List<Color> colors;
  final Map<int, String> xLabels;
  final double? maxValue;
  final String Function(double value)? tickText;
  final String Function(StatsBar bar)? valueText;
  final double? reference;
  final String? referenceLabel;
  final int? selected;
  final TextStyle axisStyle;
  final TextStyle valueStyle;
  final TextScaler scaler;
  final Color grid;
  final Color baseline;
  final Color surface;
  final TextDirection textDirection;

  /// El tope del eje: [maxValue], o el mayor redondeado hacia arriba con
  /// [niceCeil].
  double get top {
    final fixed = maxValue;
    if (fixed != null) return fixed;
    final peak = bars.fold<double>(0, (m, b) => math.max(m, b.total));
    return niceCeil(peak);
  }

  /// El redondeo de [value] hacia arriba a un tope que se lee sin hacer
  /// cuentas y que no desperdicia el alto: hasta 10, el par siguiente; desde
  /// ahí, 10, 12, 14, 16, 20, 24, 30, 40, 50, 60 u 80 por una potencia de diez.
  /// La mitad —la marca del medio del eje— es siempre un entero.
  static double niceCeil(double value) {
    if (value <= 2) return 2;
    if (value <= 10) return (value / 2).ceil() * 2.0;
    final magnitude = math
        .pow(10, (math.log(value) / math.ln10).floor())
        .toDouble();
    for (final step in const [1, 1.2, 1.4, 1.6, 2, 2.4, 3, 4, 5, 6, 8]) {
      // Redondeado, para que 1,2 × 10 no quede en 12,000000000000002.
      final candidate = (step * magnitude).roundToDouble();
      if (candidate >= value) return candidate;
    }
    return 10 * magnitude;
  }

  String _tick(double value) =>
      tickText?.call(value) ??
      (value == value.roundToDouble()
          ? '${value.round()}'
          : value.toStringAsFixed(1));

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: scaler,
    maxLines: 1,
  )..layout();

  /// El rectángulo donde van las columnas, dentro de [size]: deja lugar para
  /// las marcas del eje a la izquierda, los rótulos abajo y las cifras arriba.
  Rect plotRect(Size size) {
    final ticks = [
      for (final t in [0.0, top / 2, top]) _text(_tick(t), axisStyle),
    ];
    final left = ticks.fold<double>(0, (m, t) => math.max(m, t.width)) + 6;
    for (final t in ticks) {
      t.dispose();
    }
    final probe = _text('0', axisStyle);
    final lineHeight = probe.height;
    probe.dispose();
    final topGap = valueText == null ? lineHeight / 2 : lineHeight + 4;
    final bottom = xLabels.isEmpty ? lineHeight / 2 : lineHeight + 6;
    return Rect.fromLTRB(
      left,
      topGap,
      size.width,
      math.max(topGap + 1, size.height - bottom),
    );
  }

  /// Qué columna cae en [at], o `null` si ninguna.
  int? indexAt(Offset at, Size size) {
    if (bars.isEmpty) return null;
    final plot = plotRect(size);
    if (at.dx < plot.left - 4 || at.dx > plot.right + 4) return null;
    final slot = plot.width / bars.length;
    return ((at.dx - plot.left) / slot).floor().clamp(0, bars.length - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final plot = plotRect(size);
    final scale = plot.height / top;
    double yOf(double value) => plot.bottom - value.clamp(0, top) * scale;

    // La grilla, casi invisible, y sus marcas.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (final t in [top / 2, top]) {
      final y = yOf(t);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    for (final t in [0.0, top / 2, top]) {
      final label = _text(_tick(t), axisStyle);
      label
        ..paint(
          canvas,
          Offset(
            plot.left - 6 - label.width,
            (yOf(t) - label.height / 2).clamp(0, size.height - label.height),
          ),
        )
        ..dispose();
    }

    if (bars.isNotEmpty) {
      final slot = plot.width / bars.length;
      // Entre columna y columna, 2 px de aire (1 si no entra).
      final gap = slot >= 8
          ? math.min<double>(slot * 0.3, 10)
          : (slot >= 3 ? 1 : 0).toDouble();
      final width = math.max(1, slot - gap).toDouble();

      // Las cifras de arriba, solo si entran todas en su ancho.
      final values = valueText;
      final labels = <TextPainter?>[
        if (values != null)
          for (final bar in bars)
            if (bar.total <= 0) null else _text(values(bar), valueStyle),
      ];
      final labelsFit = labels.every((l) => l == null || l.width <= slot - 1);

      for (var i = 0; i < bars.length; i++) {
        final bar = bars[i];
        final left = plot.left + slot * i + (slot - width) / 2;
        final dim = selected != null && selected != i;
        var bottom = plot.bottom;
        final radius = Radius.circular(math.min(4, width / 2));
        final layers = [
          for (var k = 0; k < bar.values.length; k++)
            if (bar.values[k] > 0) k,
        ];
        for (final (n, k) in layers.indexed) {
          final h = bar.values[k] * scale;
          final isTop = n == layers.length - 1;
          // Un respiro de 2 px del color de la superficie entre capas.
          final separator = isTop || h <= 3 ? 0.0 : 1.5;
          final rect = Rect.fromLTRB(
            left,
            math.max(plot.top, bottom - h) + 0,
            left + width,
            bottom - separator,
          );
          final color = colors[k % colors.length];
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              rect,
              topLeft: isTop ? radius : Radius.zero,
              topRight: isTop ? radius : Radius.zero,
            ),
            Paint()..color = dim ? color.withValues(alpha: 0.35) : color,
          );
          bottom -= h;
        }
        final label = i < labels.length ? labels[i] : null;
        if (label != null && (labelsFit || selected == i)) {
          label.paint(
            canvas,
            Offset(
              (left + width / 2 - label.width / 2).clamp(
                0,
                size.width - label.width,
              ),
              math.max(0, yOf(bar.total) - label.height - 2),
            ),
          );
        }
      }
      for (final label in labels) {
        label?.dispose();
      }

      // Los rótulos de abajo, sin pisarse: primero los de las puntas —dicen
      // de dónde a dónde va el eje— y después los del medio que entren.
      final keys = xLabels.keys.where((k) => k >= 0 && k < bars.length).toList()
        ..sort();
      final ordered = [
        if (keys.isNotEmpty) keys.first,
        if (keys.length > 1) keys.last,
        ...keys.skip(1).take(math.max(0, keys.length - 2)),
      ];
      final taken = <(double, double)>[];
      for (final key in ordered) {
        final label = _text(xLabels[key]!, axisStyle);
        final center = plot.left + slot * key + slot / 2;
        final x = (center - label.width / 2)
            .clamp(plot.left, math.max(plot.left, size.width - label.width))
            .toDouble();
        final free = taken.every(
          (t) => x + label.width + 4 <= t.$1 || x >= t.$2 + 4,
        );
        if (free) {
          label.paint(canvas, Offset(x, plot.bottom + 4));
          taken.add((x, x + label.width));
        }
        label.dispose();
      }
    }

    // La referencia, punteada y tenue, encima de las columnas: no la tapan.
    // Su rótulo lleva el color de la superficie detrás, para leerse aunque
    // caiga sobre una columna.
    final ref = reference;
    if (ref != null && ref > 0 && ref <= top) {
      final y = yOf(ref);
      final dash = Paint()
        ..color = baseline.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var x = plot.left; x < plot.right; x += 7) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, plot.right), y),
          dash,
        );
      }
      final text = referenceLabel;
      if (text != null) {
        final label = _text(text, axisStyle);
        final at = Offset(
          plot.right - label.width - 2,
          math.max(0, y - label.height - 2),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            (at & label.size).inflate(2),
            const Radius.circular(4),
          ),
          Paint()..color = surface.withValues(alpha: 0.85),
        );
        label
          ..paint(canvas, at)
          ..dispose();
      }
    }

    // La línea de base, al final: queda por encima de las columnas.
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(StatsBarPainter oldDelegate) =>
      oldDelegate.bars != bars ||
      oldDelegate.colors != colors ||
      oldDelegate.selected != selected ||
      oldDelegate.xLabels != xLabels ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.reference != reference ||
      oldDelegate.axisStyle != axisStyle ||
      oldDelegate.grid != grid ||
      oldDelegate.surface != surface ||
      oldDelegate.scaler != scaler;
}

/// Una muestra de color con su rótulo: la leyenda de un gráfico de varias
/// capas. El color nunca es lo único que dice qué es cada una.
class StatsLegend extends StatelessWidget {
  const StatsLegend({required this.entries, super.key});

  final List<(Color, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final (color, label) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: theme.textTheme.bodySmall)),
            ],
          ),
      ],
    );
  }
}

/// Un anillo con las partes de un todo y el total en el centro, con el mismo
/// pintor de los anillos de la infografía.
class StatsDonut extends StatelessWidget {
  const StatsDonut({
    required this.values,
    required this.colors,
    required this.center,
    required this.centerCaption,
    this.size = 148,
    super.key,
  });

  final List<int> values;
  final List<Color> colors;

  /// La cifra del centro y lo que es («120» · «tarjetas»).
  final String center;
  final String centerCaption;

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = values.fold(0, (sum, v) => sum + v);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: InfoRingPainter(
          fractions: [
            for (final v in values)
              if (total == 0) 0 else v / total,
          ],
          colors: colors,
          track: theme.colorScheme.surfaceContainerHighest,
          single: false,
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.2),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    centerCaption,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un color legible para una marca sobre [surface]: el de la serie, llevado
/// hasta 3:1 si hace falta (la base de contraste de las creaciones).
Color statsMarkColor(Color color, Color surface) =>
    CreationContrast.ensure(color, surface, minimum: 3);
