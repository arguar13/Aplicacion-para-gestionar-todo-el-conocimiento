import 'dart:math' as math;
import 'dart:typed_data';
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
///
/// [canvasSize] no es un límite: las posiciones finales pueden terminar
/// afuera de ese rectángulo sin que nada las recorte —quien llama a esta
/// función ya no clampa nada—. Solo sirve para dos cosas al arrancar: dónde
/// pone el círculo inicial de nodos y qué tan separados "deberían" quedar en
/// promedio (la constante `k`, más abajo). Antes sí clampaba cada posición a
/// ese rectángulo en cada iteración; eso hacía que un grafo con muchos nodos
/// —o con componentes sueltos que se repelen sin nada que los atraiga de
/// vuelta— chocara contra un borde artificial en vez de separarse lo que la
/// física del layout pedía. Quien lo dibuja es quien decide, con `Clip.none`
/// y un `boundaryMargin` sin tope, que ese resultado —por más grande que
/// termine siendo— siempre se vea entero.
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
  final kSquared = k * k;

  final count = nodeIds.length;

  // El cálculo entero va sobre arreglos de números indexados por posición y no
  // sobre un mapa de id a `Offset`: el bucle de repulsión recorre todos los
  // pares de nodos, y con un mapa cada par costaba cuatro búsquedas por texto
  // y cuatro objetos nuevos. Con 200 nodos eran más de medio segundo; con
  // arreglos, una fracción. Las operaciones son las mismas y en el mismo
  // orden, así que el resultado es idéntico al de siempre, dígito por dígito.
  final indexOf = {for (var i = 0; i < count; i++) nodeIds[i]: i};
  final links = <(int, int)>[
    for (final (from, to) in edges)
      if (indexOf[from] case final f? when indexOf[to] != null)
        (f, indexOf[to]!),
  ];

  // Posiciones iniciales en un círculo, por índice: nada de `Random()`, para
  // que el resultado no dependa de una semilla que alguien podría olvidarse
  // de fijar.
  final center = canvasSize.center(Offset.zero);
  final radius = math.min(canvasSize.width, canvasSize.height) / 3;
  final xs = Float64List(count);
  final ys = Float64List(count);
  for (var i = 0; i < count; i++) {
    final start = Offset.fromDirection(2 * math.pi * i / count, radius);
    xs[i] = center.dx + start.dx;
    ys[i] = center.dy + start.dy;
  }

  final moveX = Float64List(count);
  final moveY = Float64List(count);
  var temperature = canvasSize.width / 10;

  for (var iteration = 0; iteration < iterations; iteration++) {
    moveX.fillRange(0, count, 0);
    moveY.fillRange(0, count, 0);

    // Repulsión: todos los pares de nodos se empujan entre sí.
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        final dx = xs[i] - xs[j];
        final dy = ys[i] - ys[j];
        final distance = math.max(math.sqrt(dx * dx + dy * dy), 0.01);
        final force = kSquared / distance;
        final pushX = dx / distance * force;
        final pushY = dy / distance * force;

        moveX[i] = moveX[i] + pushX;
        moveY[i] = moveY[i] + pushY;
        moveX[j] = moveX[j] - pushX;
        moveY[j] = moveY[j] - pushY;
      }
    }

    // Atracción: los nodos unidos por un vínculo se acercan.
    for (final (from, to) in links) {
      final dx = xs[from] - xs[to];
      final dy = ys[from] - ys[to];
      final distance = math.max(math.sqrt(dx * dx + dy * dy), 0.01);
      final force = (distance * distance) / k;
      final pullX = dx / distance * force;
      final pullY = dy / distance * force;

      moveX[from] = moveX[from] - pullX;
      moveY[from] = moveY[from] - pullY;
      moveX[to] = moveX[to] + pullX;
      moveY[to] = moveY[to] + pullY;
    }

    // Se aplica el desplazamiento acotado por la "temperatura", que baja
    // con cada vuelta: al principio los nodos se mueven mucho para
    // encontrar su lugar, y al final apenas ajustan, para que el layout
    // converja en vez de oscilar para siempre.
    for (var i = 0; i < count; i++) {
      final distance = math.max(
        math.sqrt(moveX[i] * moveX[i] + moveY[i] * moveY[i]),
        0.01,
      );
      final limit = math.min(distance, temperature);
      xs[i] = xs[i] + moveX[i] / distance * limit;
      ys[i] = ys[i] + moveY[i] / distance * limit;
    }

    temperature *= 0.97;
  }

  return {for (var i = 0; i < count; i++) nodeIds[i]: Offset(xs[i], ys[i])};
}
