import 'package:flutter/material.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

/// Alto de un carril: la barra, el rótulo y el aire entre carriles.
const kTimelineLaneHeight = 38.0;

/// Alto de la barra de un evento.
const kTimelineBarHeight = 10.0;

/// Lo menos que ocupa la caja de un evento: la barra y su rótulo.
const kTimelineMinBoxWidth = 28.0;

/// Lo que se ve de un evento a poco zoom: un año a escala de siglos mide menos
/// de un píxel y desaparecería.
const kTimelineMinCorePx = 6.0;

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

  /// Un tramo con principio y fin propios («1914–1918»): el cuerpo tenue de
  /// punta a punta y, en cada extremo, una marca firme que dice dónde
  /// empieza y dónde termina. No es un período —del que solo se sabe que
  /// ocurrió *en algún lugar* del tramo—: acá los dos extremos son datos.
  range,
}

/// Lo que miden de ancho las marcas de los extremos de un tramo.
const kTimelineRangeCapWidth = 3.0;

/// Cuánto sobresalen de la barra, arriba y abajo, las marcas de un tramo.
const kTimelineRangeCapOverhang = 2.0;

extension TimelineEventStyle on TimelineEvent {
  /// Un tramo con fin propio se dibuja como tramo, sea cual sea la precisión de
  /// sus extremos; el «circa» sigue viéndose en los bordes difusos.
  TimelineBarStyle get barStyle => isRange
      ? TimelineBarStyle.range
      : switch ((isPeriod, date.isCirca)) {
          (false, false) => TimelineBarStyle.exact,
          (false, true) => TimelineBarStyle.approximate,
          (true, false) => TimelineBarStyle.period,
          (true, true) => TimelineBarStyle.approximatePeriod,
        };

  /// `true` si los extremos se dibujan difusos.
  bool get hasFuzzyEdges => fuzz > 0;
}

/// Dibuja en [canvas] la barra de un evento en [bar] según su [style].
///
/// [fuzzPx] es el ancho del borde difuso de cada lado, en píxeles, y [corePx]
/// el del tramo mismo, sin los bordes. [paint] es el pincel que se reutiliza de
/// una barra a otra: con cientos de barras por cuadro, uno por barra es
/// basura que el recolector paga.
void paintTimelineBar(
  Canvas canvas,
  Rect bar, {
  required TimelineBarStyle style,
  required Color color,
  required double fuzzPx,
  required double corePx,
  required Paint paint,
}) {
  final height = bar.height;
  final coreWidth = corePx < kTimelineMinCorePx ? kTimelineMinCorePx : corePx;
  final core = Rect.fromLTWH(bar.left + fuzzPx, bar.top, coreWidth, height);

  if (fuzzPx > 0) {
    _paintFade(
      canvas,
      Rect.fromLTWH(bar.left, bar.top, fuzzPx, height),
      color,
      toRight: true,
    );
    _paintFade(
      canvas,
      Rect.fromLTWH(core.right, bar.top, fuzzPx, height),
      color,
      toRight: false,
    );
  }

  final rounded = RRect.fromRectAndRadius(core, Radius.circular(height / 2));
  switch (style) {
    case TimelineBarStyle.exact:
    case TimelineBarStyle.approximate:
      canvas.drawRRect(
        rounded,
        paint
          ..style = PaintingStyle.fill
          ..shader = null
          ..color = color,
      );
    case TimelineBarStyle.period:
    case TimelineBarStyle.approximatePeriod:
      canvas
        ..drawRRect(
          rounded,
          paint
            ..style = PaintingStyle.fill
            ..shader = null
            ..color = color.withValues(alpha: 0.22),
        )
        ..drawRRect(
          rounded.deflate(0.75),
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color,
        );
    case TimelineBarStyle.range:
      // El cuerpo, más tenue que un hecho exacto, para que las dos marcas
      // sean lo que se lee: dónde empieza y dónde termina.
      canvas.drawRRect(
        rounded,
        paint
          ..style = PaintingStyle.fill
          ..shader = null
          ..color = color.withValues(alpha: 0.4),
      );
      paint.color = color;
      for (final left in [core.left, core.right - kTimelineRangeCapWidth]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              left,
              core.top - kTimelineRangeCapOverhang,
              kTimelineRangeCapWidth,
              height + kTimelineRangeCapOverhang * 2,
            ),
            const Radius.circular(kTimelineRangeCapWidth / 2),
          ),
          paint,
        );
      }
  }
}

/// Un degradado de transparente a [color] (o al revés), para el borde de un
/// "circa".
void _paintFade(
  Canvas canvas,
  Rect rect,
  Color color, {
  required bool toRight,
}) {
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

/// Dibuja UNA barra que ocupa todo el lienzo: la muestra de la leyenda, con la
/// misma pintura que las barras del eje.
class TimelineBarSamplePainter extends CustomPainter {
  const TimelineBarSamplePainter({
    required this.style,
    required this.color,
    required this.fuzzPx,
    required this.corePx,
  });

  final TimelineBarStyle style;
  final Color color;
  final double fuzzPx;
  final double corePx;

  @override
  void paint(Canvas canvas, Size size) => paintTimelineBar(
    canvas,
    Offset.zero & size,
    style: style,
    color: color,
    fuzzPx: fuzzPx,
    corePx: corePx,
    paint: Paint(),
  );

  @override
  bool shouldRepaint(TimelineBarSamplePainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.color != color ||
      oldDelegate.fuzzPx != fuzzPx ||
      oldDelegate.corePx != corePx;
}
