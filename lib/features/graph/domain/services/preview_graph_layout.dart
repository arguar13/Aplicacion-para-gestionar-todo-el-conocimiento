import 'dart:math' as math;
import 'dart:ui';

/// Cuántos vecinos dibuja, como mucho, la vista previa del mapa del detalle.
/// Con más, la vista deja de ser una vista previa: los demás se resumen en un
/// «+N» que invita a abrir el mapa completo.
const kLocalGraphPreviewMaxNeighbors = 10;

/// Los vecinos que la vista previa dibuja y cuántos quedan sin dibujar.
typedef PreviewNeighbors = ({List<String> shown, int hidden});

/// Cuáles de los vecinos de [seedId] entran en la vista previa.
///
/// [neighborIds] viene del más reciente al más viejo (el orden en que el
/// repositorio los eligió) y son vecinos DIRECTOS, así que todos están a un
/// salto: lo que los distingue es qué tan atado está cada uno. Primero entran
/// los que tienen más vínculos con el elemento (dos vínculos de distinto tipo
/// pesan más que uno), después los que más se vinculan con los otros vecinos
/// (los que están en el centro de un grupo), y a igualdad, el más reciente.
/// El orden es estable: los mismos datos dan siempre la misma elección.
///
/// [omitted] son los que el repositorio ya dejó afuera por su propio tope: se
/// suman a `hidden` para que el «+N» cuente todos los que
/// faltan, no solo los que esta vista recortó.
PreviewNeighbors pickPreviewNeighbors({
  required String seedId,
  required List<String> neighborIds,
  required List<(String from, String to)> edges,
  int omitted = 0,
  int max = kLocalGraphPreviewMaxNeighbors,
}) {
  final withSeed = <String, int>{};
  final withOthers = <String, int>{};
  for (final (from, to) in edges) {
    if (from == to) continue;
    if (from == seedId) {
      withSeed.update(to, (n) => n + 1, ifAbsent: () => 1);
    } else if (to == seedId) {
      withSeed.update(from, (n) => n + 1, ifAbsent: () => 1);
    } else {
      withOthers
        ..update(from, (n) => n + 1, ifAbsent: () => 1)
        ..update(to, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  final order =
      [for (var i = 0; i < neighborIds.length; i++) (i, neighborIds[i])]
        ..sort((a, b) {
          final bySeed = (withSeed[b.$2] ?? 0).compareTo(withSeed[a.$2] ?? 0);
          if (bySeed != 0) return bySeed;
          final byOthers = (withOthers[b.$2] ?? 0).compareTo(
            withOthers[a.$2] ?? 0,
          );
          if (byOthers != 0) return byOthers;
          return a.$1.compareTo(b.$1);
        });

  final shown = [for (final (_, id) in order.take(math.max(max, 0))) id];
  return (shown: shown, hidden: neighborIds.length - shown.length + omitted);
}

/// Los tamaños de los nodos de la vista previa para un lienzo de [width] de
/// ancho: caben tres a lo ancho (un vecino, el elemento y otro vecino), con
/// aire entre ellos, y nunca más anchos de lo que se lee bien ni más angostos
/// de lo que un título aguanta.
({Size node, Size center}) previewNodeSizes(double width) {
  final available = math.max<double>(width - 16, 40);
  final nodeWidth = math.min(
    ((available - 20) / 3.2).clamp(76.0, 124.0),
    available,
  );
  return (
    node: Size(nodeWidth, 38),
    center: Size(math.min(nodeWidth * 1.15, available), 46),
  );
}

/// Dónde va cada cosa en la vista previa del mapa de un elemento.
class PreviewLayout {
  const PreviewLayout({
    required this.size,
    required this.center,
    required this.neighbors,
  });

  /// El lienzo entero: el ancho que se pidió y el alto que hizo falta.
  final Size size;

  /// El rectángulo del elemento, en el medio.
  final Rect center;

  /// El rectángulo de cada vecino, en el mismo orden en que se pidieron.
  final List<Rect> neighbors;
}

/// La disposición de la vista previa del mapa: el elemento en el medio y sus
/// [count] vecinos alrededor, en tres columnas que usan todo el [width]
/// disponible —los vecinos de los costados contra los bordes, uno o dos
/// arriba y abajo del elemento—, como un anillo que se adapta a tarjetas
/// anchas y bajas.
///
/// Es geometría cerrada, sin simulación física: se prueba cada alto posible,
/// del más bajo al más alto, y se queda con el primero que CUMPLE todo
/// —ningún nodo toca a otro (hay al menos [gap] de aire entre cualquier par)
/// y ningún vínculo (la recta del elemento a un vecino) atraviesa a otro
/// nodo—; que ninguno se sale del lienzo lo da la construcción: las columnas
/// arrancan a [margin] del borde. Eso se cumple desde unos 280 de ancho (la
/// tarjeta de un teléfono chico); en un lienzo más angosto cae a una grilla en
/// filas, que por construcción nunca encima nada aunque ya no sea un anillo.
/// Determinista: los mismos datos dan siempre la misma disposición.
PreviewLayout layoutLocalPreview({
  required int count,
  required double width,
  required Size nodeSize,
  required Size centerSize,
  double gap = 10,
  double margin = 8,
}) {
  Rect centered(double height) => Rect.fromCenter(
    center: Offset(width / 2, height / 2),
    width: centerSize.width,
    height: centerSize.height,
  );

  // Con pocos vecinos el lienzo no se aplasta: un mínimo para que respire.
  final minHeight = math.max<double>(centerSize.height + 2 * margin, 124);
  if (count <= 0) {
    final height = minHeight;
    return PreviewLayout(
      size: Size(width, height),
      center: centered(height),
      neighbors: const [],
    );
  }

  // Un solo vecino: el par, junto y centrado en el lienzo, con un tramo de
  // vínculo entre uno y otro, en vez de pegado a un costado. Si no entran en
  // el ancho, sigue la búsqueda de siempre (y su grilla de último recurso).
  const link = 32.0;
  final start = (width - centerSize.width - link - nodeSize.width) / 2;
  if (count == 1 && start >= margin) {
    return PreviewLayout(
      size: Size(width, minHeight),
      center: Rect.fromLTWH(
        start,
        (minHeight - centerSize.height) / 2,
        centerSize.width,
        centerSize.height,
      ),
      neighbors: [
        Rect.fromLTWH(
          start + centerSize.width + link,
          (minHeight - nodeSize.height) / 2,
          nodeSize.width,
          nodeSize.height,
        ),
      ],
    );
  }

  for (var height = minHeight; height <= 400; height += 4) {
    final neighbors = _placeInColumns(
      count: count,
      width: width,
      height: height,
      nodeSize: nodeSize,
      margin: margin,
    );
    final center = centered(height);
    if (_isClean(center: center, neighbors: neighbors, gap: gap)) {
      return PreviewLayout(
        size: Size(width, height),
        center: center,
        neighbors: neighbors,
      );
    }
  }

  return _gridFallback(
    count: count,
    width: width,
    nodeSize: nodeSize,
    centerSize: centerSize,
    gap: gap,
    margin: margin,
  );
}

/// Cuántos vecinos van arriba y abajo del elemento (en la columna del medio)
/// y cuántos en cada costado, para [count] vecinos. Con uno solo, va a la
/// derecha; con dos, uno a cada lado; con tres, uno arriba y uno a cada lado;
/// de ahí en más, los de la columna del medio son uno (si [count] es impar) o
/// dos (si es par) y el resto se reparte parejo entre los dos costados.
({int middle, int left, int right}) previewColumns(int count) {
  if (count <= 1) return (middle: 0, left: 0, right: count);
  if (count == 2 || count == 4) {
    return (middle: 0, left: count ~/ 2, right: count ~/ 2);
  }
  final middle = count.isOdd ? 1 : 2;
  final side = (count - middle) ~/ 2;
  return (middle: middle, left: side, right: side);
}

List<Rect> _placeInColumns({
  required int count,
  required double width,
  required double height,
  required Size nodeSize,
  required double margin,
}) {
  final columns = previewColumns(count);
  final radiusX = width / 2 - margin - nodeSize.width / 2;
  final radiusY = height / 2 - margin - nodeSize.height / 2;
  Rect at(double x, double y) => Rect.fromCenter(
    center: Offset(width / 2 + x, height / 2 + y),
    width: nodeSize.width,
    height: nodeSize.height,
  );

  /// Los nodos de una columna de los costados, de arriba abajo, repartidos
  /// parejo entre el borde de arriba y el de abajo del lienzo.
  List<Rect> side(int nodes, double x) => [
    for (var i = 0; i < nodes; i++)
      at(x, nodes == 1 ? 0 : -radiusY + 2 * radiusY * i / (nodes - 1)),
  ];

  return [
    // Primero el de arriba y después, en el sentido de las agujas del reloj,
    // el resto: el orden en que se piden es el de importancia, y los más
    // importantes quedan donde primero se mira.
    if (columns.middle >= 1) at(0, -radiusY),
    ...side(columns.right, radiusX),
    if (columns.middle == 2) at(0, radiusY),
    ...side(columns.left, -radiusX).reversed,
  ];
}

bool _isClean({
  required Rect center,
  required List<Rect> neighbors,
  required double gap,
}) {
  final all = [center, ...neighbors];
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      if (all[i].inflate(gap / 2).overlaps(all[j].inflate(gap / 2))) {
        return false;
      }
    }
  }
  // Un vínculo no puede pasar por detrás de otro vecino.
  for (var i = 0; i < neighbors.length; i++) {
    for (var j = 0; j < neighbors.length; j++) {
      if (i != j &&
          segmentHitsRect(center.center, neighbors[i].center, neighbors[j])) {
        return false;
      }
    }
  }
  return true;
}

/// Si el segmento de [a] a [b] pasa por dentro de [rect] (Liang-Barsky).
bool segmentHitsRect(Offset a, Offset b, Rect rect) {
  var t0 = 0.0;
  var t1 = 1.0;
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  bool clip(double p, double q) {
    if (p == 0) return q >= 0;
    final r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
    return true;
  }

  return clip(-dx, a.dx - rect.left) &&
      clip(dx, rect.right - a.dx) &&
      clip(-dy, a.dy - rect.top) &&
      clip(dy, rect.bottom - a.dy) &&
      t0 <= t1;
}

/// La disposición de último recurso: el elemento arriba y los vecinos en
/// filas debajo. Menos lucida que el anillo, pero nunca encima nada.
PreviewLayout _gridFallback({
  required int count,
  required double width,
  required Size nodeSize,
  required Size centerSize,
  required double gap,
  required double margin,
}) {
  final columns = math.max(
    1,
    ((width - 2 * margin + gap) / (nodeSize.width + gap)).floor(),
  );
  final top = margin;
  final center = Rect.fromLTWH(
    (width - centerSize.width) / 2,
    top,
    centerSize.width,
    centerSize.height,
  );
  final rows = (count / columns).ceil();
  final rowsTop = center.bottom + gap * 2;
  final neighbors = <Rect>[];
  for (var i = 0; i < count; i++) {
    final row = i ~/ columns;
    final inRow = math.min(columns, count - row * columns);
    final rowWidth = inRow * nodeSize.width + (inRow - 1) * gap;
    neighbors.add(
      Rect.fromLTWH(
        (width - rowWidth) / 2 + (i % columns) * (nodeSize.width + gap),
        rowsTop + row * (nodeSize.height + gap),
        nodeSize.width,
        nodeSize.height,
      ),
    );
  }
  final height = rowsTop + rows * (nodeSize.height + gap) - gap + margin;
  return PreviewLayout(
    size: Size(width, height),
    center: center,
    neighbors: neighbors,
  );
}
