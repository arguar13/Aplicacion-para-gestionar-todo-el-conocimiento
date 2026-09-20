import 'dart:math' as math;
import 'dart:ui';

import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/lane_layout.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';

/// Un evento ya ubicado sobre el lienzo, en píxeles.
class TimelineBox {
  const TimelineBox({
    required this.event,
    required this.rect,
    required this.labelOffset,
    required this.fuzzPx,
    required this.corePx,
  });

  final TimelineEvent event;

  /// La caja entera del evento —la barra y, debajo, el rótulo—, en las
  /// coordenadas del lienzo. Lo que ocupa y lo que se toca.
  final Rect rect;

  /// Cuánto se corre el rótulo hacia la derecha: cuando el evento empieza antes
  /// del borde izquierdo de la pantalla, el título sigue a la vista.
  final double labelOffset;

  /// El ancho del borde difuso de cada lado, en píxeles; 0 si no hay.
  final double fuzzPx;

  /// El ancho del tramo mismo, sin los bordes.
  final double corePx;

  /// La barra del evento: la franja de arriba de la caja.
  Rect get bar =>
      Rect.fromLTWH(rect.left, rect.top, rect.width, kTimelineBarHeight);
}

/// Lo que el lienzo dibuja y deja tocar en un cuadro: los eventos de la
/// ventana actual con su posición en píxeles.
///
/// Es un modelo y no widgets a propósito. Un subárbol por evento —una barra, un
/// rótulo, un toque, una ayuda, su semántica— costaba, con 157 barras a la
/// vista, 22 a 28 ms por cuadro en armarse y 45 a 62 en pintarse en una PC en
/// modo profile, y perdía 233 de 299 cuadros arrastrando: un teléfono no
/// llega. Ahora la ventana se reparte en carriles, se ubica en píxeles acá y un
/// solo pintor la dibuja; tocar y la semántica salen del mismo modelo, así que
/// lo que se ve, lo que se toca y lo que lee un lector de pantalla no pueden
/// discrepar.
class TimelineFrame {
  const TimelineFrame(this.boxes);

  /// Ubica [placed] —lo que repartió `layoutLanes`— para una vista que empieza
  /// en el año [from] y muestra [pxPerYear] píxeles por año.
  ///
  /// [labelYears] dice cuánto eje necesita el rótulo de un evento, en años: el
  /// mismo cálculo con el que se repartieron los carriles, para que la caja de
  /// un evento no pise la del vecino.
  factory TimelineFrame.place(
    List<PlacedEvent> placed, {
    required double from,
    required double pxPerYear,
    required double top,
    required double Function(TimelineEvent event) labelYears,
  }) {
    return TimelineFrame([
      for (final (:event, :lane) in placed)
        () {
          final left = (event.reachFrom - from) * pxPerYear;
          final reachPx = (event.reachTo - event.reachFrom) * pxPerYear;
          final width = math.max(
            math.max(reachPx, labelYears(event) * pxPerYear),
            kTimelineMinBoxWidth,
          );
          // Un evento que empieza antes de la pantalla deja el rótulo a la
          // vista.
          final shift = left < 0 ? math.min(-left, width - 28) : 0.0;
          return TimelineBox(
            event: event,
            rect: Rect.fromLTWH(
              left,
              top + lane * kTimelineLaneHeight,
              width,
              kTimelineLaneHeight,
            ),
            labelOffset: math.max(0, shift),
            fuzzPx: event.fuzz * pxPerYear,
            corePx: (event.to - event.from) * pxPerYear,
          );
        }(),
    ]);
  }

  /// Los eventos ubicados, en el orden del eje.
  final List<TimelineBox> boxes;

  /// El evento que está bajo [position], o `null`. Si dos cajas se solapan gana
  /// la que se dibuja encima, la última.
  TimelineBox? hitTest(Offset position) {
    for (var i = boxes.length - 1; i >= 0; i--) {
      if (boxes[i].rect.contains(position)) return boxes[i];
    }
    return null;
  }
}
