import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/axis_scale.dart';
import 'package:sinapsis/features/timeline/domain/services/lane_layout.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_viewport.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/axis_labels.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_events_painter.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_frame.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que ocupa el eje con sus marcas, abajo.
const _axisHeight = 30.0;

/// Espacio sobre el primer carril.
const _topPadding = 8.0;

/// Lo más ancho que se deja crecer el rótulo de un evento.
const _maxLabelWidth = 180.0;

/// El eje con los hechos: los dibuja, y se mueve y se acerca con los dedos, la
/// rueda, el teclado y los botones.
///
/// Solo se calcula lo que se ve. El índice devuelve los eventos de la
/// ventana actual y el reparto en carriles trabaja sobre esos, así que mover
/// la vista cuesta lo que hay en pantalla y no lo que hay guardado. Y lo que se
/// ve se dibuja en UN solo lienzo, no en un widget por evento: ver
/// [TimelineFrame].
///
/// La vista se conserva mientras los datos cambian —un hecho que se fecha no
/// la mueve—; quien quiera encuadrar de nuevo, como al cambiar los filtros,
/// crea un lienzo nuevo con otra `key`.
class TimelineCanvas extends StatefulWidget {
  const TimelineCanvas({required this.events, required this.onOpen, super.key});

  final List<TimelineEvent> events;

  /// Se llama con el elemento de un evento tocado.
  final ValueChanged<String> onOpen;

  @override
  State<TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends State<TimelineCanvas> {
  late TimelineIndex _index;
  late ViewportLimits _limits;
  late TimelineViewport _viewport;

  // El estado de un gesto en curso: la vista y el año que estaban bajo los
  // dedos al empezar. Todo el gesto se calcula contra eso, no contra el
  // cuadro anterior: sin acumular errores de redondeo.
  TimelineViewport? _gestureStart;
  double _gestureFocusYear = 0;

  // El foco del teclado se pide al tocar el lienzo y no al abrirlo: un lienzo
  // nuevo aparece cada vez que cambian los filtros, y quedarse con el foco
  // mientras alguien escribe en la búsqueda se lo sacaría en cada tecla.
  final _focusNode = FocusNode();

  /// Los rótulos ya medidos: arrastrar repinta los mismos con el mismo ancho.
  final _labels = TimelineLabelCache();

  // La ayuda de un evento —su título y su fecha completa—: con el mouse, un
  // momento después de apoyarse; con el dedo, al mantener apretado. Es una sola
  // para todo el lienzo, no una por evento.
  static const _tipDelay = Duration(milliseconds: 500);
  static const _touchTipDuration = Duration(seconds: 3);
  TimelineBox? _hovered;
  TimelineBox? _tip;
  Timer? _tipTimer;

  @override
  void initState() {
    super.initState();
    _rebuildIndex();
    _viewport = TimelineViewport.fit(_limits);
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _labels.clear();
    _focusNode.dispose();
    super.dispose();
  }

  void _hideTip() {
    _tipTimer?.cancel();
    if (_tip != null || _hovered != null) {
      setState(() {
        _tip = null;
        _hovered = null;
      });
    }
  }

  /// Con el mouse encima de un evento, su ayuda aparece a los [_tipDelay].
  void _onHover(TimelineBox? box) {
    if (box?.event.itemId == _hovered?.event.itemId &&
        box?.event.date.label == _hovered?.event.date.label) {
      return;
    }
    _tipTimer?.cancel();
    setState(() {
      _hovered = box;
      _tip = null;
    });
    if (box == null) return;
    _tipTimer = Timer(_tipDelay, () {
      if (mounted) setState(() => _tip = box);
    });
  }

  /// Con el dedo, mantener apretado un evento muestra su ayuda un rato.
  void _onLongPress(TimelineBox? box) {
    if (box == null) return;
    _tipTimer?.cancel();
    setState(() {
      _hovered = box;
      _tip = box;
    });
    _tipTimer = Timer(_touchTipDuration, () {
      if (mounted) _hideTip();
    });
  }

  @override
  void didUpdateWidget(TimelineCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.events, widget.events)) {
      _rebuildIndex();
      _viewport = _viewport.clamped(_limits);
    }
  }

  void _rebuildIndex() {
    _index = TimelineIndex(widget.events);
    _limits = ViewportLimits.forExtent(_index.extent ?? (from: 0, to: 1));
  }

  void _setViewport(TimelineViewport viewport) {
    if (viewport == _viewport) return;
    _tipTimer?.cancel();
    setState(() {
      _viewport = viewport;
      _hovered = null;
      _tip = null;
    });
  }

  void _fit() => _setViewport(TimelineViewport.fit(_limits));

  void _zoom(double scale) => _setViewport(_viewport.zoomed(scale, _limits));

  void _pan(double fractionOfSpan) =>
      _setViewport(_viewport.panned(fractionOfSpan, _limits));

  void _onScaleStart(ScaleStartDetails details, double width) {
    _gestureStart = _viewport;
    _gestureFocusYear = _viewport.yearAt(details.localFocalPoint.dx / width);
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double width) {
    final start = _gestureStart;
    if (start == null) return;
    _setViewport(
      TimelineViewport.anchored(
        focusYear: _gestureFocusYear,
        fraction: details.localFocalPoint.dx / width,
        span: start.span / details.scale,
        limits: _limits,
      ),
    );
  }

  /// La rueda acerca y aleja alrededor del cursor; el desplazamiento
  /// horizontal (un trackpad) mueve la vista.
  void _onPointerSignal(PointerSignalEvent event, double width) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      final horizontal = scroll.scrollDelta.dx;
      final vertical = scroll.scrollDelta.dy;
      if (horizontal.abs() > vertical.abs()) {
        _pan(horizontal / width);
        return;
      }
      final fraction = scroll.localPosition.dx / width;
      _setViewport(
        TimelineViewport.anchored(
          focusYear: _viewport.yearAt(fraction),
          fraction: fraction,
          span: _viewport.span / math.exp(-vertical / 400),
          limits: _limits,
        ),
      );
    });
  }

  /// Cuánto eje necesita el rótulo de un evento, en años: estimado por la
  /// cantidad de letras, sin medir el texto —son cientos por cuadro—.
  double _labelYears(TimelineEvent event, double pxPerYear) {
    final labelPx = math.min(_maxLabelWidth, 12 + event.title.length * 6.2);
    return math.max(28, labelPx) / pxPerYear;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final pxPerYear = width / _viewport.span;

        final lanesHeight = height - _axisHeight - _topPadding;
        final maxLanes = math.max(
          1,
          (lanesHeight / kTimelineLaneHeight).floor(),
        );

        final window = _index.window(_viewport.from, _viewport.to);
        final layout = layoutLanes(
          window.events,
          maxLanes: maxLanes,
          footprint: (event) => _labelYears(event, pxPerYear),
        );

        final frame = TimelineFrame.place(
          layout.placed,
          from: _viewport.from,
          pxPerYear: pxPerYear,
          top: _topPadding,
          labelYears: (event) => _labelYears(event, pxPerYear),
        );

        final scale = axisScale(
          from: _viewport.from,
          to: _viewport.to,
          targetCount: math.max(2, (width / 90).floor()),
        );

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _pan(-0.1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _pan(0.1),
            // "+" es mayúscula-"=" en casi todos los teclados.
            const SingleActivator(LogicalKeyboardKey.equal): () => _zoom(1.5),
            const SingleActivator(LogicalKeyboardKey.equal, shift: true): () =>
                _zoom(1.5),
            const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
                _zoom(1.5),
            const SingleActivator(LogicalKeyboardKey.minus): () =>
                _zoom(1 / 1.5),
            const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
                _zoom(1 / 1.5),
            const SingleActivator(LogicalKeyboardKey.digit0): _fit,
          },
          child: Focus(
            focusNode: _focusNode,
            child: Listener(
              onPointerSignal: (event) => _onPointerSignal(event, width),
              child: MouseRegion(
                cursor: _hovered == null
                    ? MouseCursor.defer
                    : SystemMouseCursors.click,
                onHover: (event) =>
                    _onHover(frame.hitTest(event.localPosition)),
                onExit: (_) => _hideTip(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _focusNode.requestFocus(),
                  onTapUp: (details) {
                    final box = frame.hitTest(details.localPosition);
                    if (box != null) widget.onOpen(box.event.itemId);
                  },
                  onLongPressStart: (details) =>
                      _onLongPress(frame.hitTest(details.localPosition)),
                  onScaleStart: (details) => _onScaleStart(details, width),
                  onScaleUpdate: (details) => _onScaleUpdate(details, width),
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _AxisPainter(
                              ticks: [
                                for (final tick in scale.ticks)
                                  (
                                    x:
                                        (tick.position - _viewport.from) *
                                        pxPerYear,
                                    label: axisTickLabel(
                                      l10n,
                                      locale,
                                      scale.unit,
                                      tick,
                                    ),
                                  ),
                              ],
                              axisHeight: _axisHeight,
                              lineColor: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                              textStyle: Theme.of(context).textTheme.labelSmall!
                                  .copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            key: const ValueKey('timeline-events'),
                            painter: TimelineEventsPainter(
                              frame: frame,
                              scheme: Theme.of(context).colorScheme,
                              labelStyle: Theme.of(
                                context,
                              ).textTheme.labelSmall!,
                              labels: _labels,
                              onOpen: widget.onOpen,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: _axisHeight + 8,
                          child: _Controls(
                            onZoomIn: () => _zoom(1.5),
                            onZoomOut: () => _zoom(1 / 1.5),
                            onFit: _fit,
                          ),
                        ),
                        if (layout.hidden > 0)
                          Positioned(
                            left: 8,
                            bottom: _axisHeight + 8,
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(l10n.timelineHidden(layout.hidden)),
                            ),
                          ),
                        if (_tip case final tip?) _tipFor(tip, width),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// La ayuda de un evento: su título y su fecha completa, debajo de su caja.
  Widget _tipFor(TimelineBox box, double canvasWidth) {
    final theme = Theme.of(context);
    final event = box.event;
    const maxWidth = 260.0;
    final left = box.rect.left
        .clamp(8, math.max(8, canvasWidth - maxWidth - 8))
        .toDouble();

    return Positioned(
      key: const ValueKey('timeline-tip'),
      left: left,
      top: box.rect.bottom + 4,
      child: IgnorePointer(
        child: Material(
          elevation: 3,
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '${event.title}\n${event.date.label}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Los botones para acercar, alejar y encuadrar todo, para quien no tiene rueda
/// ni pellizco.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.timelineZoomIn,
            onPressed: onZoomIn,
          ),
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: l10n.timelineZoomOut,
            onPressed: onZoomOut,
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen_outlined),
            tooltip: l10n.timelineFit,
            onPressed: onFit,
          ),
        ],
      ),
    );
  }
}

/// Las marcas del eje: una línea tenue que cruza el lienzo y el rótulo abajo.
class _AxisPainter extends CustomPainter {
  const _AxisPainter({
    required this.ticks,
    required this.axisHeight,
    required this.lineColor,
    required this.textStyle,
  });

  final List<({double x, String label})> ticks;
  final double axisHeight;
  final Color lineColor;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final axisY = size.height - axisHeight;
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, axisY), Offset(size.width, axisY), paint);

    for (final tick in ticks) {
      canvas.drawLine(
        Offset(tick.x, 0),
        Offset(tick.x, axisY + 6),
        paint..color = lineColor.withValues(alpha: 0.5),
      );

      TextPainter(
          text: TextSpan(text: tick.label, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )
        ..layout()
        ..paint(canvas, Offset(tick.x + 4, axisY + 8))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(_AxisPainter oldDelegate) =>
      !listEquals(oldDelegate.ticks, ticks) ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.textStyle != textStyle;
}
