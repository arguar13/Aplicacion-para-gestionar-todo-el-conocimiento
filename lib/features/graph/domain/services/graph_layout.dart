import 'dart:math' as math;
import 'dart:ui';

/// Dónde va cada nodo del grafo de relaciones, calculado con un
/// Fruchterman-Reingold simplificado: los nodos se repelen entre sí como
/// cargas iguales, y los que tienen un vínculo se atraen como si estuvieran
/// unidos por un resorte. El resultado es el que se espera de un grafo de
/// verdad —los grupos conectados quedan juntos, lo demás se separa— sin
/// necesitar layout manual ni una biblioteca externa para algo que son
/// unas pocas decenas de líneas.
///
/// Determinístico a propósito: dos corridas con los mismos nodos y las
/// mismas aristas producen exactamente el mismo resultado. Un layout con
/// azar de verdad haría que el grafo "saltara" cada vez que se abre la
/// pantalla, que es peor que una disposición imperfecta pero estable.
Map<String, Offset> computeGraphLayout({
  required List<String> nodeIds,
  required List<(String from, String to)> edges,
  Size canvasSize = const Size(900, 900),
  int iterations = 300,
}) {
  if (nodeIds.isEmpty) return {};
  if (nodeIds.length == 1) {
    return {nodeIds.single: canvasSize.center(Offset.zero)};
  }

  final area = canvasSize.width * canvasSize.height;
  // La distancia "ideal" entre dos nodos si se repartiera el área del
  // lienzo en partes iguales — la constante de Fruchterman-Reingold.
  final k = math.sqrt(area / nodeIds.length);

  // Posiciones iniciales en un círculo, por índice: nada de `Random()`, para
  // que el resultado no dependa de una semilla que alguien podría olvidarse
  // de fijar.
  final positions = <String, Offset>{
    for (var i = 0; i < nodeIds.length; i++)
      nodeIds[i]:
          canvasSize.center(Offset.zero) +
          Offset.fromDirection(
            2 * math.pi * i / nodeIds.length,
            math.min(canvasSize.width, canvasSize.height) / 3,
          ),
  };

  var temperature = canvasSize.width / 10;

  for (var iteration = 0; iteration < iterations; iteration++) {
    final displacement = {for (final id in nodeIds) id: Offset.zero};

    // Repulsión: todos los pares de nodos se empujan entre sí.
    for (var i = 0; i < nodeIds.length; i++) {
      for (var j = i + 1; j < nodeIds.length; j++) {
        final a = nodeIds[i];
        final b = nodeIds[j];
        final delta = positions[a]! - positions[b]!;
        final distance = math.max(delta.distance, 0.01);
        final force = (k * k) / distance;
        final direction = delta / distance;

        displacement[a] = displacement[a]! + direction * force;
        displacement[b] = displacement[b]! - direction * force;
      }
    }

    // Atracción: los nodos unidos por un vínculo se acercan.
    for (final (from, to) in edges) {
      if (!positions.containsKey(from) || !positions.containsKey(to)) {
        continue;
      }
      final delta = positions[from]! - positions[to]!;
      final distance = math.max(delta.distance, 0.01);
      final force = (distance * distance) / k;
      final direction = delta / distance;

      displacement[from] = displacement[from]! - direction * force;
      displacement[to] = displacement[to]! + direction * force;
    }

    // Se aplica el desplazamiento acotado por la "temperatura", que baja
    // con cada vuelta: al principio los nodos se mueven mucho para
    // encontrar su lugar, y al final apenas ajustan, para que el layout
    // converja en vez de oscilar para siempre.
    for (final id in nodeIds) {
      final disp = displacement[id]!;
      final distance = math.max(disp.distance, 0.01);
      final capped = disp / distance * math.min(distance, temperature);

      final next = positions[id]! + capped;
      positions[id] = Offset(
        next.dx.clamp(0, canvasSize.width),
        next.dy.clamp(0, canvasSize.height),
      );
    }

    temperature *= 0.97;
  }

  return positions;
}
