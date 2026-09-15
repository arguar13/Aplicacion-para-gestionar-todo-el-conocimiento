import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';

/// Una arista tal cual la necesita el pintor: de dónde a dónde, y con qué
/// tipo de vínculo — el tipo es lo que decide de qué color sale la línea.
typedef GraphEdge = (String from, String to, RelationKind kind);

/// Dibuja las aristas del grafo: una línea por vínculo, coloreada según su
/// tipo, con una punta de flecha chica que marca el sentido —de dónde
/// viene, hacia dónde va—.
class GraphEdgesPainter extends CustomPainter {
  const GraphEdgesPainter({
    required this.edges,
    required this.positions,
    required this.nodeRadius,
    required this.colorScheme,
    this.dimmedNodeIds,
  });

  final List<GraphEdge> edges;
  final Map<String, Offset> positions;
  final double nodeRadius;
  final ColorScheme colorScheme;

  /// Los nodos que deben pintarse tenues, en modo foco: una arista donde
  /// cualquiera de las dos puntas está acá se dibuja apagada, para que la
  /// red alrededor del nodo elegido resalte por contraste en vez de por
  /// tamaño o grosor. `null` —fuera de modo foco— pinta todo a la misma
  /// intensidad.
  final Set<String>? dimmedNodeIds;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (from, to, kind) in edges) {
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
      if (distance <= nodeRadius * 2) continue;
      final unit = direction / distance;

      // La línea se corta antes de llegar al centro del nodo destino, para
      // que la punta de flecha quede pegada al borde del círculo y no
      // enterrada debajo de su ícono.
      final lineEnd = end - unit * nodeRadius;
      canvas.drawLine(start + unit * nodeRadius, lineEnd, linePaint);

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
    }
  }

  @override
  bool shouldRepaint(GraphEdgesPainter oldDelegate) =>
      oldDelegate.edges != edges ||
      oldDelegate.positions != positions ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.dimmedNodeIds != dimmedNodeIds;
}
