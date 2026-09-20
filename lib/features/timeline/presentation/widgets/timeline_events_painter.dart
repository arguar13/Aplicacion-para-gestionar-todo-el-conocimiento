import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_frame.dart';

/// Los rótulos ya medidos, para no volver a medirlos en cada cuadro.
///
/// Medir un texto —partirlo en líneas, acortarlo con puntos suspensivos— es lo
/// más caro de dibujarlo, y arrastrar el eje repinta los mismos rótulos, con
/// el mismo ancho, decenas de veces por segundo. Se guarda uno por título y
/// ancho; al acercar el zoom los anchos cambian y se miden los nuevos.
class TimelineLabelCache {
  TimelineLabelCache();

  /// Cuántos rótulos se guardan como máximo. Una ventana tiene cientos, y con
  /// el zoom cambian: pasado esto se empieza de cero en vez de crecer sin
  /// límite.
  static const _limit = 1200;

  final _painters = <(String, int), TextPainter>{};
  TextStyle? _style;

  /// El rótulo de [title] en [maxWidth] píxeles, medido, listo para pintar.
  TextPainter labelFor(String title, double maxWidth, TextStyle style) {
    if (_style != style) {
      clear();
      _style = style;
    }
    final key = (title, maxWidth.round());
    final cached = _painters[key];
    if (cached != null) return cached;

    if (_painters.length >= _limit) clear();
    return _painters[key] = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth < 0 ? 0 : maxWidth);
  }

  /// Cuántos rótulos guardados hay.
  int get length => _painters.length;

  void clear() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}

/// Dibuja todos los eventos de un [TimelineFrame] en un solo lienzo: cada
/// barra según la precisión de su fecha y, debajo, su rótulo.
///
/// Un solo pintor en vez de un widget por evento: ver [TimelineFrame] por qué.
/// También arma la semántica —un nodo por evento, con su título y su fecha, que
/// se puede activar— a partir del mismo modelo, así que un lector de pantalla
/// ve lo que se ve.
class TimelineEventsPainter extends CustomPainter {
  TimelineEventsPainter({
    required this.frame,
    required this.scheme,
    required this.labelStyle,
    required this.labels,
    required this.onOpen,
  });

  final TimelineFrame frame;
  final ColorScheme scheme;
  final TextStyle labelStyle;
  final TimelineLabelCache labels;

  /// Se llama con el elemento de un evento activado por accesibilidad.
  final ValueChanged<String> onOpen;

  final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in frame.boxes) {
      if (box.rect.right < 0 || box.rect.left > size.width) continue;
      final event = box.event;

      // Una fuente y una nota no se ven igual: ver `EntityRole`.
      paintTimelineBar(
        canvas,
        box.bar,
        style: event.barStyle,
        color: event.sourceKind.role.accent(scheme),
        fuzzPx: box.fuzzPx,
        corePx: box.corePx,
        paint: _paint,
      );
      labels
          .labelFor(event.title, box.rect.width - box.labelOffset, labelStyle)
          .paint(
            canvas,
            Offset(
              box.rect.left + box.labelOffset,
              box.rect.top + kTimelineBarHeight + 3,
            ),
          );
    }
  }

  @override
  bool shouldRepaint(TimelineEventsPainter oldDelegate) =>
      !identical(oldDelegate.frame, frame) ||
      oldDelegate.scheme != scheme ||
      oldDelegate.labelStyle != labelStyle;

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final box in frame.boxes)
          CustomPainterSemantics(
            key: ValueKey('${box.event.itemId}-${box.event.date.label}'),
            rect: box.rect,
            properties: SemanticsProperties(
              button: true,
              label: '${box.event.title}, ${box.event.date.label}',
              textDirection: TextDirection.ltr,
              onTap: () => onOpen(box.event.itemId),
            ),
          ),
      ];

  @override
  bool shouldRebuildSemantics(TimelineEventsPainter oldDelegate) =>
      !identical(oldDelegate.frame, frame);
}
