import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_density.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_viewport.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que ocupa el mini mapa, a lo alto.
const kTimelineMinimapHeight = 40.0;

/// El mini mapa de la línea de tiempo (F40): una franja sobre el eje con la
/// densidad de hechos de TODO el rango de los datos y, marcado, el tramo que se
/// ve ahora. Tocarlo o arrastrarlo salta a esa época sin cambiar el zoom.
///
/// Dibuja las barras que ya calculó [TimelineDensity] —una vez por lista de
/// hechos—: arrastrar el eje solo mueve la ventana, que es un rectángulo.
class TimelineMinimap extends StatelessWidget {
  const TimelineMinimap({
    required this.density,
    required this.viewport,
    required this.onJumpTo,
    required this.onDragTo,
    super.key,
  });

  final TimelineDensity density;
  final TimelineViewport viewport;

  /// Se llama con el año tocado: la vista se centra ahí, con un movimiento
  /// animado.
  final ValueChanged<double> onJumpTo;

  /// Se llama con el año bajo el dedo mientras se arrastra: sigue al dedo, sin
  /// animar.
  final ValueChanged<double> onDragTo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: l10n.timelineMinimapLabel,
      container: true,
      child: SizedBox(
        height: kTimelineMinimapHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            double yearAt(double dx) =>
                density.yearAt((dx / width).clamp(0.0, 1.0));

            return GestureDetector(
              key: const ValueKey('timeline-minimap'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => onJumpTo(yearAt(details.localPosition.dx)),
              onHorizontalDragStart: (details) =>
                  onDragTo(yearAt(details.localPosition.dx)),
              onHorizontalDragUpdate: (details) =>
                  onDragTo(yearAt(details.localPosition.dx)),
              child: CustomPaint(
                size: Size(width, kTimelineMinimapHeight),
                painter: TimelineMinimapPainter(
                  density: density,
                  windowFrom: density.fractionOf(viewport.from),
                  windowTo: density.fractionOf(viewport.to),
                  barColor: scheme.primary.withValues(alpha: 0.55),
                  windowColor: scheme.primary,
                  trackColor: scheme.surfaceContainerLow,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Dibuja las barras de densidad y la ventana marcada.
class TimelineMinimapPainter extends CustomPainter {
  const TimelineMinimapPainter({
    required this.density,
    required this.windowFrom,
    required this.windowTo,
    required this.barColor,
    required this.windowColor,
    required this.trackColor,
  });

  final TimelineDensity density;

  /// Dónde empieza y termina la ventana, como fracción del ancho. Puede
  /// salirse de 0 a 1: la vista del eje puede mirar más allá de los datos.
  final double windowFrom;
  final double windowTo;

  final Color barColor;
  final Color windowColor;
  final Color trackColor;

  /// Lo mínimo que se ve de la ventana, para que un zoom muy cerrado no la
  /// vuelva una raya imposible de agarrar.
  static const minWindowWidth = 6.0;

  /// Lo mínimo que se ve de una barra con algún hecho: una con uno solo entre
  /// cien no se pierde.
  static const _minBarHeight = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas
      ..drawRRect(track, Paint()..color = trackColor)
      ..save()
      ..clipRRect(track);

    final barWidth = size.width / density.length;
    final paint = Paint()..color = barColor;
    for (var i = 0; i < density.length; i++) {
      final level = density.levels[i];
      if (level <= 0) continue;
      final height = math.max(_minBarHeight, level * (size.height - 6));
      canvas.drawRect(
        Rect.fromLTWH(i * barWidth, size.height - height, barWidth, height),
        paint,
      );
    }

    final window = visibleWindow(size.width);
    canvas
      ..drawRect(window, Paint()..color = windowColor.withValues(alpha: 0.16))
      ..drawRect(
        window.deflate(0.75),
        Paint()
          ..color = windowColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      )
      ..restore();
  }

  /// El rectángulo de la ventana en un lienzo de [width] píxeles: recortado al
  /// ancho y nunca más angosto que [minWindowWidth].
  Rect visibleWindow(double width) {
    final left = (windowFrom * width).clamp(0.0, width);
    final right = (windowTo * width).clamp(0.0, width);
    final span = math.max(minWindowWidth, right - left);
    final start = math.min(left, width - span);
    return Rect.fromLTWH(math.max(0, start), 0, span, kTimelineMinimapHeight);
  }

  @override
  bool shouldRepaint(TimelineMinimapPainter oldDelegate) =>
      !identical(oldDelegate.density, density) ||
      oldDelegate.windowFrom != windowFrom ||
      oldDelegate.windowTo != windowTo ||
      oldDelegate.barColor != barColor ||
      oldDelegate.windowColor != windowColor ||
      oldDelegate.trackColor != trackColor;
}
