import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';

/// Una arista tal cual la necesita el pintor: de dónde a dónde, con qué tipo
/// de vínculo —el tipo es lo que decide de qué color sale la línea— y con
/// qué etiqueta mostrar sobre la línea. La etiqueta se recibe ya resuelta
/// —`kind.shortLabel(l10n)`— en vez de que el pintor conozca `RelationKind`
/// y `AppLocalizations` los dos: un `CustomPainter` no tiene `BuildContext`
/// del que sacar el idioma actual.
typedef GraphEdge = (String from, String to, RelationKind kind, String label);

/// Dibuja las aristas del grafo: una línea por vínculo, coloreada según su
/// tipo, con una punta de flecha chica que marca el sentido —de dónde
/// viene, hacia dónde va— y su nombre en una etiqueta a mitad de camino, al
/// estilo de la relación con nombre de un diagrama entidad-relación.
///
/// Cada nodo se dibuja como una tarjeta rectangular, al estilo de una
/// entidad en un diagrama entidad-relación (ver `_GraphNode` en
/// `graph_screen.dart`) — no como un círculo. La línea tiene que terminar
/// justo en el borde de esa tarjeta, en el lado que mira hacia la otra, y
/// no a una distancia fija del centro como alcanzaba con un círculo: un
/// nodo ancho y bajo tiene un borde mucho más cerca del centro por arriba
/// que por los costados. [clipToRectBorder] es ese cálculo.
class GraphEdgesPainter extends CustomPainter {
  const GraphEdgesPainter({
    required this.edges,
    required this.positions,
    required this.nodeSize,
    required this.colorScheme,
    this.dimmedNodeIds,
  });

  final List<GraphEdge> edges;
  final Map<String, Offset> positions;

  /// El tamaño de la tarjeta de cada nodo — todas del mismo tamaño, ver
  /// `_GraphNode`.
  final Size nodeSize;
  final ColorScheme colorScheme;

  /// Los nodos que deben pintarse tenues, en modo foco: una arista donde
  /// cualquiera de las dos puntas está acá se dibuja apagada, para que la
  /// red alrededor del nodo elegido resalte por contraste en vez de por
  /// tamaño o grosor. `null` —fuera de modo foco— pinta todo a la misma
  /// intensidad.
  final Set<String>? dimmedNodeIds;

  @override
  void paint(Canvas canvas, Size size) {
    final halfWidth = nodeSize.width / 2;
    final halfHeight = nodeSize.height / 2;

    for (final (from, to, kind, label) in edges) {
      final start = positions[from];
      final end = positions[to];
      if (start == null || end == null) continue;

      final dimmed =
          dimmedNodeIds != null &&
          (dimmedNodeIds!.contains(from) || dimmedNodeIds!.contains(to));
      final baseColor = kind.color(colorScheme);
      final color = dimmed ? baseColor.withValues(alpha: 0.18) : baseColor;

      final linePaint = Paint()
        ..color = color
        ..strokeWidth = dimmed ? 1.2 : 1.8
        ..style = PaintingStyle.stroke;
      final arrowPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final direction = end - start;
      final distance = direction.distance;
      // Dos tarjetas superpuestas o casi —dos nodos con la misma posición
      // fijada a mano— no tienen ningún borde real entre las dos hacia el
      // que trazar una línea con sentido.
      if (distance <= 1) continue;
      final unit = direction / distance;

      // La línea arranca en el borde de la tarjeta de origen —no en su
      // centro, que quedaría debajo de su contenido— y termina en el borde
      // de la de destino, con la punta de flecha pegada ahí.
      final lineStart = clipToRectBorder(start, unit, halfWidth, halfHeight);
      final lineEnd = clipToRectBorder(end, -unit, halfWidth, halfHeight);
      canvas.drawLine(lineStart, lineEnd, linePaint);

      const arrowLength = 9.0;
      const arrowAngle = 0.5;
      final angle = math.atan2(unit.dy, unit.dx);
      final arrowP1 =
          lineEnd -
          Offset(
            arrowLength * math.cos(angle - arrowAngle),
            arrowLength * math.sin(angle - arrowAngle),
          );
      final arrowP2 =
          lineEnd -
          Offset(
            arrowLength * math.cos(angle + arrowAngle),
            arrowLength * math.sin(angle + arrowAngle),
          );

      canvas.drawPath(
        Path()
          ..moveTo(lineEnd.dx, lineEnd.dy)
          ..lineTo(arrowP1.dx, arrowP1.dy)
          ..lineTo(arrowP2.dx, arrowP2.dy)
          ..close(),
        arrowPaint,
      );

      _paintLabel(
        canvas,
        label: label,
        at: Offset.lerp(lineStart, lineEnd, 0.5)!,
        color: color,
        dimmed: dimmed,
      );
    }
  }

  /// El nombre del vínculo, a mitad de camino de la línea, dentro de una
  /// píldora que "rompe" la línea en vez de taparla —el mismo recurso que
  /// usa Graphviz y cualquier diagramador de entidad-relación para que la
  /// etiqueta se lea aunque varias líneas se crucen en el mismo punto—.
  void _paintLabel(
    Canvas canvas, {
    required String label,
    required Offset at,
    required Color color,
    required bool dimmed,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: dimmed ? color : colorScheme.onSurface,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    const paddingH = 6.0;
    const paddingV = 2.5;
    final pillSize = Size(
      textPainter.width + paddingH * 2,
      textPainter.height + paddingV * 2,
    );
    final pillRect = Rect.fromCenter(
      center: at,
      width: pillSize.width,
      height: pillSize.height,
    );
    final pillRRect = RRect.fromRectAndRadius(
      pillRect,
      Radius.circular(pillSize.height / 2),
    );

    canvas
      ..drawRRect(
        pillRRect,
        Paint()
          ..color = colorScheme.surface.withValues(alpha: dimmed ? 0.55 : 0.96),
      )
      ..drawRRect(
        pillRRect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    textPainter.paint(
      canvas,
      at - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(GraphEdgesPainter oldDelegate) =>
      oldDelegate.edges != edges ||
      oldDelegate.positions != positions ||
      oldDelegate.nodeSize != nodeSize ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.dimmedNodeIds != dimmedNodeIds;
}

/// Dónde cruza el borde de una tarjeta rectangular centrada en [center] el
/// rayo que sale de su centro en la dirección [unit] —un vector unitario—.
///
/// Es la versión rectangular de "el punto a `radius` de distancia del
/// centro, hacia el otro nodo" que alcanzaba con un círculo: acá la
/// distancia al borde no es constante, depende de qué tan inclinado sea el
/// ángulo. Se calcula por cuánto hay que escalar [unit] para tocar la pared
/// vertical (`halfWidth / |unit.dx|`) o la horizontal (`halfHeight /
/// |unit.dy|`) primero, y se usa el que se toca antes — el mismo principio
/// que un recorte de rayo contra una caja ("slab method"), simplificado
/// porque acá el rayo siempre arranca en el centro de la caja.
Offset clipToRectBorder(
  Offset center,
  Offset unit,
  double halfWidth,
  double halfHeight,
) {
  final tx = unit.dx == 0 ? double.infinity : halfWidth / unit.dx.abs();
  final ty = unit.dy == 0 ? double.infinity : halfHeight / unit.dy.abs();
  final t = math.min(tx, ty);
  return center + unit * t;
}
