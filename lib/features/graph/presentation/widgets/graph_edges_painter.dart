import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dibuja las aristas del grafo: una línea por vínculo, con una punta de
/// flecha chica que marca el sentido —de dónde viene, hacia dónde va—.
class GraphEdgesPainter extends CustomPainter {
  const GraphEdgesPainter({
    required this.edges,
    required this.positions,
    required this.nodeRadius,
    required this.color,
  });

  final List<(String from, String to)> edges;
  final Map<String, Offset> positions;
  final double nodeRadius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final (from, to) in edges) {
      final start = positions[from];
      final end = positions[to];
      if (start == null || end == null) continue;

      final direction = end - start;
      final distance = direction.distance;
      if (distance <= nodeRadius * 2) continue;
      final unit = direction / distance;

      // La línea se corta antes de llegar al centro del nodo destino, para
      // que la punta de flecha quede pegada al borde del círculo y no
      // enterrada debajo de su ícono.
      final lineEnd = end - unit * nodeRadius;
      canvas.drawLine(start + unit * nodeRadius, lineEnd, linePaint);

      const arrowLength = 8.0;
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
    }
  }

  @override
  bool shouldRepaint(GraphEdgesPainter oldDelegate) =>
      oldDelegate.edges != edges ||
      oldDelegate.positions != positions ||
      oldDelegate.color != color;
}
