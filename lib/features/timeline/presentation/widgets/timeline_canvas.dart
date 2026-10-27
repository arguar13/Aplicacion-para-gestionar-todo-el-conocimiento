import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/axis_scale.dart';
import 'package:sinapsis/features/timeline/domain/services/lane_layout.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_density.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_viewport.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/axis_labels.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_events_painter.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_frame.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_minimap.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que ocupa el eje con sus marcas, abajo.
const _axisHeight = 30.0;

/// Espacio sobre el primer carril.
const _topPadding = 8.0;

/// Lo más ancho que se deja crecer el rótulo de un evento.
const _maxLabelWidth = 180.0;

/// Cuánto acerca o aleja un paso: el botón «+», la tecla y el doble toque.
const _zoomStep = 1.5;

/// Lo que dura un encuadre animado (mostrar todo, cambiar el filtro, saltar
/// desde el mini mapa, doble toque).
const _motionDuration = Duration(milliseconds: 350);

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
/// cambia [frameKey] y la vista se mueve, animada, hasta encuadrar los hechos
/// nuevos.
///
/// Arriba del eje va el mini mapa (F40): la densidad de hechos de todo el
/// rango, con la ventana que se ve marcada.
class TimelineCanvas extends StatefulWidget {
  const TimelineCanvas({
    required this.events,
    required this.onOpen,
    this.frameKey,
    this.colorOf,
    super.key,
  });

  final List<TimelineEvent> events;

  /// Se llama con el evento tocado. Con el evento entero y no solo su
  /// elemento: lo que abre depende de qué hecho es.
  final ValueChanged<TimelineEvent> onOpen;

  /// Qué encuadra a [events]: mientras sea igual, los datos que cambian no
  /// mueven la vista; cuando cambia, la vista se encuadra de nuevo —animada—
  /// sobre los hechos que llegaron con ella.
  final Object? frameKey;

  /// De qué color se dibuja un evento; sin él, el de su rol. Es por donde
  /// entran los colores por documento.
  final Color Function(TimelineEvent event)? colorOf;

  @override
  State<TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends State<TimelineCanvas>
    with SingleTickerProviderStateMixin {
  late TimelineIndex _index;
  late ViewportLimits _limits;
  late TimelineViewport _viewport;

  /// La densidad de todo el rango, para el mini mapa: se arma con la lista de
  /// hechos, no en cada cuadro.
  late TimelineDensity _density;

  // El encuadre animado en curso: de dónde a dónde, y el reloj que lo mueve.
  // Cualquier gesto del usuario lo corta: la vista obedece a quien la toca.
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: _motionDuration,
  )..addListener(_onMotionTick);
  TimelineViewport? _motionFrom;
  TimelineViewport? _motionTo;

  // El doble toque se arma a mano y no con `onDoubleTap`: ese retrasa el toque
  // simple hasta que vence el tiempo del segundo, y abrir un hecho tardaría
  // 300 ms en cada toque.
  Timer? _doubleTapTimer;
  Offset? _lastTap;

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

  // La ayuda de un evento —su título, su fecha completa y, si lo tiene, su
  // cita—: con el mouse, un momento después de apoyarse; con el dedo, al
  // mantener apretado. Es una sola para todo el lienzo, no una por evento.
  static const _tipDelay = Duration(milliseconds: 500);
  static const _touchTipDuration = Duration(seconds: 6);

  /// Lo que se reserva de alto para la ayuda al decidir si entra debajo de un
  /// evento: el título, la fecha, cuatro renglones de cita y el documento.
  static const _tipRoom = 150.0;
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
    _doubleTapTimer?.cancel();
    _motion.dispose();
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
    final hovered = _hovered;
    if (box == null
        ? hovered == null
        : hovered != null &&
              timelineEventKey(box.event) == timelineEventKey(hovered.event)) {
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
    final eventsChanged = !identical(oldWidget.events, widget.events);
    if (eventsChanged) _rebuildIndex();
    if (widget.frameKey != oldWidget.frameKey) {
      // Otro filtro: se encuadran los hechos nuevos, moviéndose desde donde se
      // estaba.
      _fit();
    } else if (eventsChanged) {
      _viewport = _viewport.clamped(_limits);
    }
  }

  void _rebuildIndex() {
    _index = TimelineIndex(widget.events);
    final extent = _index.extent ?? (from: 0.0, to: 1.0);
    _limits = ViewportLimits.forExtent(extent);
    _density = TimelineDensity.of(
      widget.events,
      from: extent.from,
      to: extent.to,
    );
  }

  /// Pone la vista de golpe: lo que sigue al dedo, a la rueda y al teclado.
  /// Corta un encuadre animado que esté en curso.
  void _setViewport(TimelineViewport viewport) {
    _motion.stop();
    if (viewport == _viewport) return;
    _tipTimer?.cancel();
    setState(() {
      _viewport = viewport;
      _hovered = null;
      _tip = null;
    });
  }

  /// Lleva la vista hasta [target] con un movimiento, respetando los límites.
  /// Sin animaciones (accesibilidad), de golpe.
  void _animateTo(TimelineViewport target) {
    final end = target.clamped(_limits);
    if (end == _viewport) {
      _motion.stop();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _setViewport(end);
      return;
    }
    _tipTimer?.cancel();
    _motionFrom = _viewport;
    _motionTo = end;
    _hovered = null;
    _tip = null;
    _motion.forward(from: 0);
  }

  void _onMotionTick() {
    final from = _motionFrom;
    final to = _motionTo;
    if (from == null || to == null) return;
    setState(() {
      _viewport = TimelineViewport.lerp(
        from,
        to,
        Curves.easeInOutCubic.transform(_motion.value),
        _limits,
      );
    });
  }

  void _fit() => _animateTo(TimelineViewport.fit(_limits));

  void _zoom(double scale) => _setViewport(_viewport.zoomed(scale, _limits));

  /// Un toque en el fondo (sin hecho): el segundo, cerca del primero y a
  /// tiempo, acerca ahí con el mismo paso que el «+».
  void _onBackgroundTap(Offset position, double width) {
    final previous = _lastTap;
    if (previous != null && (position - previous).distance <= kDoubleTapSlop) {
      _forgetTap();
      final fraction = position.dx / width;
      _animateTo(
        TimelineViewport.anchored(
          focusYear: _viewport.yearAt(fraction),
          fraction: fraction,
          span: _viewport.span / _zoomStep,
          limits: _limits,
        ),
      );
      return;
    }
    _lastTap = position;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(kDoubleTapTimeout, _forgetTap);
  }

  void _forgetTap() {
    _doubleTapTimer?.cancel();
    _doubleTapTimer = null;
    _lastTap = null;
  }

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

    final surface = LayoutBuilder(
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
            const SingleActivator(LogicalKeyboardKey.equal): () =>
                _zoom(_zoomStep),
            const SingleActivator(LogicalKeyboardKey.equal, shift: true): () =>
                _zoom(_zoomStep),
            const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
                _zoom(_zoomStep),
            const SingleActivator(LogicalKeyboardKey.minus): () =>
                _zoom(1 / _zoomStep),
            const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
                _zoom(1 / _zoomStep),
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
                    if (box == null) {
                      _onBackgroundTap(details.localPosition, width);
                      return;
                    }
                    _forgetTap();
                    widget.onOpen(box.event);
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
                              colorOf: widget.colorOf,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: _axisHeight + 8,
                          child: _Controls(
                            onZoomIn: () => _zoom(_zoomStep),
                            onZoomOut: () => _zoom(1 / _zoomStep),
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
                        if (_tip case final tip?) _tipFor(tip, width, height),
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TimelineMinimap(
            density: _density,
            viewport: _viewport,
            onJumpTo: (year) => _animateTo(_viewport.centeredOn(year, _limits)),
            onDragTo: (year) =>
                _setViewport(_viewport.centeredOn(year, _limits)),
          ),
        ),
        Expanded(child: surface),
      ],
    );
  }

  /// La ayuda de un evento, debajo de su caja: el título y la fecha, la cita
  /// del texto de donde sale —si tiene— y el documento. Mantener apretado un
  /// hecho la muestra sin abrir su ficha. Si debajo no entra, va arriba.
  Widget _tipFor(TimelineBox box, double canvasWidth, double canvasHeight) {
    final theme = Theme.of(context);
    final event = box.event;
    final quote = event.excerpt?.replaceAll(RegExp(r'\s+'), ' ').trim();
    const maxWidth = 280.0;
    final left = box.rect.left
        .clamp(8, math.max(8, canvasWidth - maxWidth - 8))
        .toDouble();
    final onTip = theme.colorScheme.onInverseSurface;
    final base = theme.textTheme.bodySmall?.copyWith(color: onTip);
    final below = box.rect.bottom + 4 + _tipRoom <= canvasHeight;

    return Positioned(
      key: const ValueKey('timeline-tip'),
      left: left,
      top: below ? box.rect.bottom + 4 : null,
      bottom: below ? null : canvasHeight - box.rect.top + 4,
      child: IgnorePointer(
        child: Material(
          elevation: 3,
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${event.title}\n${event.dateLabel}', style: base),
                  if (quote != null && quote.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '«$quote»',
                      key: const ValueKey('timeline-tip-quote'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: base?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                  if (event.isDatedEvent) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.documentTitle,
                      key: const ValueKey('timeline-tip-document'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: base?.copyWith(
                        color: onTip.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
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
