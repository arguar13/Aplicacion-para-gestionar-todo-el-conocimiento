import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

/// Alto de un carril: la barra, el rótulo y el aire entre carriles.
const kTimelineLaneHeight = 38.0;

/// Alto de la barra de un evento.
const kTimelineBarHeight = 10.0;

/// Cómo se dibuja un evento según lo que se sabe de su fecha.
///
/// Que la fecha sea imprecisa se ve, no se lee: una fecha exacta y un siglo
/// entero no pueden parecer lo mismo, porque no lo son.
enum TimelineBarStyle {
  /// Día, mes o año conocidos: una barra llena.
  exact,

  /// Fecha aproximada ("circa"): la barra llena con los bordes que se
  /// desvanecen.
  approximate,

  /// Década o siglo: se sabe el tramo, no el momento. Un contorno con el
  /// relleno tenue —el hecho ocurrió *en algún lugar* de ahí—.
  period,

  /// Un período aproximado: el contorno tenue y los bordes que se desvanecen.
  approximatePeriod,
}

extension TimelineEventStyle on TimelineEvent {
  TimelineBarStyle get barStyle => switch ((isPeriod, date.isCirca)) {
    (false, false) => TimelineBarStyle.exact,
    (false, true) => TimelineBarStyle.approximate,
    (true, false) => TimelineBarStyle.period,
    (true, true) => TimelineBarStyle.approximatePeriod,
  };

  /// `true` si los extremos se dibujan difusos.
  bool get hasFuzzyEdges => fuzz > 0;
}

/// Un evento sobre el eje: su barra y, debajo, su título.
///
/// Es una caja de [width] píxeles —lo que ocupa el evento contando su rótulo—
/// y adentro la barra se dibuja según el zoom: [pxPerYear] traduce el tramo y
/// el borde difuso a píxeles. Tocarlo abre el elemento.
class TimelineEventBar extends StatelessWidget {
  const TimelineEventBar({
    required this.event,
    required this.width,
    required this.pxPerYear,
    required this.labelOffset,
    required this.onTap,
    super.key,
  });

  final TimelineEvent event;
  final double width;
  final double pxPerYear;

  /// Cuánto se corre el rótulo hacia la derecha: cuando el evento empieza
  /// antes del borde izquierdo de la pantalla, el título sigue a la vista.
  final double labelOffset;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Una nota y una fuente no se pintan igual: la nota es lo tuyo, la fuente
    // lo que trajiste de afuera.
    final color = event.sourceKind == SourceKind.manualNote
        ? scheme.tertiary
        : scheme.primary;

    return Semantics(
      button: true,
      label: '${event.title}, ${event.date.label}',
      excludeSemantics: true,
      child: Tooltip(
        message: '${event.title}\n${event.date.label}',
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: kTimelineLaneHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: width,
                  height: kTimelineBarHeight,
                  child: CustomPaint(
                    painter: TimelineBarPainter(
                      style: event.barStyle,
                      color: color,
                      fuzzPx: event.fuzz * pxPerYear,
                      corePx: (event.to - event.from) * pxPerYear,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: EdgeInsets.only(left: labelOffset),
                  child: Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dibuja la barra de un evento según su [style].
class TimelineBarPainter extends CustomPainter {
  const TimelineBarPainter({
    required this.style,
    required this.color,
    required this.fuzzPx,
    required this.corePx,
  });

  final TimelineBarStyle style;
  final Color color;

  /// El ancho del borde difuso de cada lado, en píxeles; 0 si no hay.
  final double fuzzPx;

  /// El ancho del tramo mismo, sin los bordes.
  final double corePx;

  /// Lo que se ve de un evento a poco zoom: un año a escala de siglos mide
  /// menos de un píxel y desaparecería.
  static const _minCorePx = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final height = size.height;

    final coreWidth = corePx < _minCorePx ? _minCorePx : corePx;
    final core = Rect.fromLTWH(fuzzPx, 0, coreWidth, height);

    if (fuzzPx > 0) {
      _paintFade(canvas, Rect.fromLTWH(0, 0, fuzzPx, height), toRight: true);
      _paintFade(
        canvas,
        Rect.fromLTWH(core.right, 0, fuzzPx, height),
        toRight: false,
      );
    }

    final rounded = RRect.fromRectAndRadius(core, Radius.circular(height / 2));
    switch (style) {
      case TimelineBarStyle.exact:
      case TimelineBarStyle.approximate:
        canvas.drawRRect(rounded, Paint()..color = color);
      case TimelineBarStyle.period:
      case TimelineBarStyle.approximatePeriod:
        canvas
          ..drawRRect(rounded, Paint()..color = color.withValues(alpha: 0.22))
          ..drawRRect(
            rounded.deflate(0.75),
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
    }
  }

  /// Un degradado de transparente a [color] (o al revés), para el borde de un
  /// "circa".
  void _paintFade(Canvas canvas, Rect rect, {required bool toRight}) {
    final strong = color.withValues(alpha: 0.55);
    final clear = color.withValues(alpha: 0);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: toRight ? [clear, strong] : [strong, clear],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(TimelineBarPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.color != color ||
      oldDelegate.fuzzPx != fuzzPx ||
      oldDelegate.corePx != corePx;
}
