import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Una unión que atrae: entre los nodos en las posiciones [a] y [b], con un
/// [weight] que dice cuánto.
class MapLayoutLink {
  const MapLayoutLink(this.a, this.b, this.weight);

  final int a;
  final int b;
  final double weight;
}

/// Dónde va cada nodo: dos arreglos de coordenadas, por posición de nodo.
class MapLayout {
  const MapLayout(this.xs, this.ys);

  final Float64List xs;
  final Float64List ys;

  int get count => xs.length;

  Offset positionOf(int node) => Offset(xs[node], ys[node]);
}

/// Dónde va cada nodo del mapa, con un Fruchterman-Reingold como el del grafo
/// de relaciones, más tres cosas que el mapa necesita (F14):
///
/// - **Uniones con peso**: una unión atrae con la raíz cuadrada de su peso
///   relativo al mayor. Lo que más une, queda más cerca; la raíz evita que un
///   par muy pesado aplaste a todos los demás contra un rincón.
/// - **Grupos**: con [groups] —la comunidad de cada nodo—, cada nodo se siente
///   además atraído por el centro de su grupo, con la fuerza [groupPull]. Sin
///   eso, dos comunidades con unos pocos vínculos entre ellas se mezclan.
/// - **Arranque en caliente**: con [startX] y [startY] —`NaN` donde no hay
///   posición previa— los nodos que ya estaban parten de su lugar y casi no se
///   mueven: un layout ya calculado no está en equilibrio, solo quedó congelado
///   por el enfriamiento, y dejarlo moverse libremente lo desplaza cientos de
///   píxeles. Los nuevos nacen junto a sus vecinos y sí se acomodan. Así el
///   mapa no da un salto cada vez que se recalcula.
///
/// Determinista, como el del grafo de relaciones: sin azar, con las posiciones
/// iniciales en un círculo ordenado por grupo y por posición. Las posiciones
/// finales no están acotadas a [extent]: solo lo usa para saber cuánto espacio
/// hay y qué tan separados quedan los nodos en promedio.
///
/// Sin ninguna unión y sin posiciones previas, no hay nada que atraiga: la
/// repulsión sola los desparramaría por miles de píxeles. Se acomodan en una
/// espiral compacta, ordenados por grupo, con lugar para una etiqueta cada uno.
///
/// Cuesta O(nodos²) por iteración, así que se usa con unos pocos cientos de
/// nodos —el mapa dibuja como máximo 300 a la vez—.
MapLayout layoutForces({
  required int count,
  required List<MapLayoutLink> links,
  Int32List? groups,
  double groupPull = 0.25,
  Float64List? startX,
  Float64List? startY,
  double extent = 900,
  int iterations = 300,
}) {
  if (count == 0) return MapLayout(Float64List(0), Float64List(0));
  if (count == 1) {
    return MapLayout(
      Float64List.fromList([extent / 2]),
      Float64List.fromList([extent / 2]),
    );
  }

  final k = math.sqrt(extent * extent / count);
  final kSquared = k * k;

  if (links.isEmpty && startX == null) {
    return _spiral(count, groups, extent);
  }

  var maxWeight = 0.0;
  for (final link in links) {
    if (link.weight > maxWeight) maxWeight = link.weight;
  }
  final strength = Float64List(links.length);
  for (var i = 0; i < links.length; i++) {
    strength[i] = maxWeight > 0 ? math.sqrt(links[i].weight / maxWeight) : 0;
  }

  final xs = Float64List(count);
  final ys = Float64List(count);
  final placed = Uint8List(count);
  final known = _place(
    count,
    links,
    strength,
    groups,
    startX,
    startY,
    extent,
    xs,
    ys,
    placed,
  );
  // En caliente si la mayoría ya tenía lugar: con unos pocos conocidos entre
  // muchos nuevos, es como empezar de cero.
  final warm = known * 2 >= count;

  // Los grupos, con índices densos: las identidades de comunidad pueden ser
  // grandes y salteadas.
  final groupOf = Int32List(count);
  var groupCount = 0;
  if (groups != null && groupPull > 0) {
    final dense = <int, int>{};
    for (var i = 0; i < count; i++) {
      groupOf[i] = dense.putIfAbsent(groups[i], () => groupCount++);
    }
  }
  final groupSize = Int32List(groupCount);
  for (var i = 0; i < count && groupCount > 0; i++) {
    groupSize[groupOf[i]]++;
  }
  final groupX = Float64List(groupCount);
  final groupY = Float64List(groupCount);

  final moveX = Float64List(count);
  final moveY = Float64List(count);
  // La temperatura limita cuánto puede moverse un nodo por vuelta. En caliente,
  // los que ya tenían lugar casi no se mueven (y se enfrían rápido: en total,
  // una fracción de `k`) y los nuevos tienen margen para acomodarse.
  var hot = warm ? 0.05 * k : extent / 10;
  var settled = warm ? 0.004 * k : hot;
  final coolHot = warm ? 0.9 : 0.97;
  final coolSettled = warm ? 0.94 : 0.97;

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
        moveX[i] += pushX;
        moveY[i] += pushY;
        moveX[j] -= pushX;
        moveY[j] -= pushY;
      }
    }

    // Atracción: las uniones acercan a sus dos extremos, más cuanto más pesan.
    for (var l = 0; l < links.length; l++) {
      final a = links[l].a;
      final b = links[l].b;
      final dx = xs[a] - xs[b];
      final dy = ys[a] - ys[b];
      final distance = math.max(math.sqrt(dx * dx + dy * dy), 0.01);
      final force = strength[l] * distance * distance / k;
      final pullX = dx / distance * force;
      final pullY = dy / distance * force;
      moveX[a] -= pullX;
      moveY[a] -= pullY;
      moveX[b] += pullX;
      moveY[b] += pullY;
    }

    // Cohesión: cada nodo hacia el centro de su grupo.
    if (groupCount > 0) {
      groupX.fillRange(0, groupCount, 0);
      groupY.fillRange(0, groupCount, 0);
      for (var i = 0; i < count; i++) {
        groupX[groupOf[i]] += xs[i];
        groupY[groupOf[i]] += ys[i];
      }
      for (var i = 0; i < count; i++) {
        final g = groupOf[i];
        if (groupSize[g] < 2) continue;
        moveX[i] += (groupX[g] / groupSize[g] - xs[i]) * groupPull * k;
        moveY[i] += (groupY[g] / groupSize[g] - ys[i]) * groupPull * k;
      }
    }

    // El desplazamiento se acota por la temperatura, que baja en cada vuelta:
    // al principio los nodos se mueven mucho para encontrar su lugar, y al
    // final apenas ajustan.
    for (var i = 0; i < count; i++) {
      final distance = math.max(
        math.sqrt(moveX[i] * moveX[i] + moveY[i] * moveY[i]),
        0.01,
      );
      final limit = math.min(distance, placed[i] == 1 ? settled : hot);
      xs[i] += moveX[i] / distance * limit;
      ys[i] += moveY[i] / distance * limit;
    }
    hot *= coolHot;
    settled *= coolSettled;
  }

  return MapLayout(xs, ys);
}

/// Dónde va cada nodo para que el mapa **se lea**: [layoutForces] por
/// componente, sin cajas encimadas y con los componentes juntos.
///
/// Sobre el grafo entero, [layoutForces] deja dos cosas que en la pantalla de
/// un teléfono no se leen:
///
/// - **Componentes perdidos en la distancia.** Entre dos componentes —grupos
///   de elementos que no se tocan— solo hay repulsión: se alejan sin límite, y
///   encuadrarlos a todos achica el mapa hasta que nada se lee.
/// - **Cajas encimadas.** El motor ve puntos, pero cada nodo es una caja de
///   [boxSize] con su título; con la cohesión de grupo, un componente entero
///   termina apilado en un rincón.
///
/// Así que:
///
/// 1. Cada componente se acomoda **por separado**, con una distancia ideal
///    entre nodos unidos fija —[edgeLength]— en vez de una que dependa de
///    cuántos nodos hay en el mapa entero.
/// 2. Dentro de cada uno se separan las cajas que se pisan, con su tamaño de
///    verdad —[widths] y [heights] por nodo, o [boxSize] para todos— y [gap]
///    de aire, moviendo lo mínimo.
/// 3. Los componentes se ubican **en filas**, del más grande al más chico, con
///    [componentGap] entre ellos, y el ancho de la fila se elige para que el
///    conjunto tenga la proporción [aspect] (ancho sobre alto) de la pantalla.
///
/// Los grupos de [groups] se respetan dentro de cada componente; un grupo que
/// es el componente entero —como en la vista de vínculos— no agrega nada y no
/// se usa. Con [startX]/[startY] cada componente arranca en caliente desde lo
/// que ya tenía, como en [layoutForces], y como el orden de las filas sale del
/// tamaño de cada componente, recalcular no los cambia de lugar mientras el
/// grafo no cambie. Determinista: sin azar.
MapLayout layoutReadable({
  required int count,
  required List<MapLayoutLink> links,
  Int32List? groups,
  Float64List? startX,
  Float64List? startY,
  int iterations = 300,
  Float64List? widths,
  Float64List? heights,
  Size boxSize = const Size(150, 34),
  Size gap = const Size(24, 22),
  double edgeLength = 120,
  double componentGap = 90,
  double aspect = 0.75,
  double gravity = 0.01,
}) {
  final xs = Float64List(count);
  final ys = Float64List(count);
  if (count == 0) return MapLayout(xs, ys);

  final width =
      widths ?? (Float64List(count)..fillRange(0, count, boxSize.width));
  final height =
      heights ?? (Float64List(count)..fillRange(0, count, boxSize.height));
  final components = _components(count, links);
  final placed = <_PlacedComponent>[];
  for (final members in components) {
    placed.add(
      _layoutComponent(
        members,
        links: links,
        groups: groups,
        startX: startX,
        startY: startY,
        iterations: iterations,
        widths: width,
        heights: height,
        gap: gap,
        edgeLength: edgeLength,
        gravity: gravity,
      ),
    );
  }

  _packInRows(placed, componentGap: componentGap, aspect: aspect);
  for (final component in placed) {
    for (var m = 0; m < component.members.length; m++) {
      xs[component.members[m]] = component.xs[m] + component.left;
      ys[component.members[m]] = component.ys[m] + component.top;
    }
  }
  return MapLayout(xs, ys);
}

/// Los componentes del grafo —los nodos que se alcanzan por las uniones—, del
/// más grande al más chico y, a igual tamaño, por su primer nodo: un orden
/// estable, que no cambia si el grafo no cambia. Cada uno, con sus nodos en
/// orden.
List<List<int>> _components(int count, List<MapLayoutLink> links) {
  final parent = Int32List.fromList(List<int>.generate(count, (i) => i));
  int root(int i) {
    var node = i;
    while (parent[node] != node) {
      parent[node] = parent[parent[node]];
      node = parent[node];
    }
    return node;
  }

  for (final link in links) {
    final a = root(link.a);
    final b = root(link.b);
    if (a != b) parent[math.max(a, b)] = math.min(a, b);
  }
  final byRoot = <int, List<int>>{};
  for (var i = 0; i < count; i++) {
    byRoot.putIfAbsent(root(i), () => []).add(i);
  }
  return byRoot.values.toList()..sort((a, b) {
    final bySize = b.length.compareTo(a.length);
    return bySize != 0 ? bySize : a.first.compareTo(b.first);
  });
}

/// Un componente ya acomodado: sus nodos, sus posiciones con la esquina de
/// arriba a la izquierda de su caja contenedora en el origen, y su tamaño.
/// [left] y [top] los pone [_packInRows].
class _PlacedComponent {
  _PlacedComponent(this.members, this.xs, this.ys, this.width, this.height);

  final List<int> members;
  final Float64List xs;
  final Float64List ys;
  final double width;
  final double height;
  double left = 0;
  double top = 0;
}

_PlacedComponent _layoutComponent(
  List<int> members, {
  required List<MapLayoutLink> links,
  required Int32List? groups,
  required Float64List? startX,
  required Float64List? startY,
  required int iterations,
  required Float64List widths,
  required Float64List heights,
  required Size gap,
  required double edgeLength,
  required double gravity,
}) {
  final size = members.length;
  final local = <int, int>{for (var m = 0; m < size; m++) members[m]: m};
  final localLinks = <MapLayoutLink>[
    for (final link in links)
      if (local.containsKey(link.a) && local.containsKey(link.b))
        MapLayoutLink(local[link.a]!, local[link.b]!, link.weight),
  ];

  // Un grupo que es el componente entero no separa nada: solo apretaría.
  Int32List? localGroups;
  if (groups != null) {
    final candidate = Int32List(size);
    var several = false;
    for (var m = 0; m < size; m++) {
      candidate[m] = groups[members[m]];
      if (candidate[m] != candidate[0]) several = true;
    }
    if (several) localGroups = candidate;
  }

  Float64List? localStartX;
  Float64List? localStartY;
  if (startX != null && startY != null) {
    localStartX = Float64List(size);
    localStartY = Float64List(size);
    for (var m = 0; m < size; m++) {
      localStartX[m] = startX[members[m]];
      localStartY[m] = startY[members[m]];
    }
  }

  // `layoutForces` toma como distancia ideal la raíz de extent² / nodos: con
  // este extent, la distancia ideal es `edgeLength` cualquiera sea el tamaño
  // del componente.
  final forces = layoutForces(
    count: size,
    links: localLinks,
    groups: localGroups ?? Int32List(size),
    groupPull: localGroups == null ? gravity : 0.25,
    startX: localStartX,
    startY: localStartY,
    extent: edgeLength * math.sqrt(size),
    iterations: iterations,
  );
  final xs = Float64List.fromList(forces.xs);
  final ys = Float64List.fromList(forces.ys);
  final halfW = Float64List(size);
  final halfH = Float64List(size);
  for (var m = 0; m < size; m++) {
    halfW[m] = (widths[members[m]] + gap.width) / 2;
    halfH[m] = (heights[members[m]] + gap.height) / 2;
  }
  _separateBoxes(xs, ys, halfW, halfH);

  // Las posiciones son centros: la caja contenedora va de borde a borde de las
  // cajas, sin el aire de `gap`.
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (var m = 0; m < size; m++) {
    final w = widths[members[m]] / 2;
    final h = heights[members[m]] / 2;
    left = math.min(left, xs[m] - w);
    top = math.min(top, ys[m] - h);
    right = math.max(right, xs[m] + w);
    bottom = math.max(bottom, ys[m] + h);
  }
  for (var m = 0; m < size; m++) {
    xs[m] -= left;
    ys[m] -= top;
  }
  return _PlacedComponent(members, xs, ys, right - left, bottom - top);
}

/// Separa las cajas centradas en cada posición —de medio ancho [halfW] y
/// medio alto [halfH], aire incluido— hasta que ninguna pise a otra: cada par
/// encimado se aparta por el eje en el que menos se pisa, la mitad cada uno,
/// que es moverlo lo mínimo y conservar la forma que dejaron las fuerzas. Dos
/// cajas exactamente en el mismo punto se apartan en horizontal, la de menor
/// posición a la izquierda: sin azar.
void _separateBoxes(
  Float64List xs,
  Float64List ys,
  Float64List halfW,
  Float64List halfH,
) {
  final count = xs.length;
  // Cada vuelta resuelve todos los choques que ve; los que crea al empujar se
  // resuelven en las siguientes. El tope solo protege de un caso imposible:
  // con las fuerzas ya repartidas, termina en unas pocas decenas.
  for (var round = 0; round < 500; round++) {
    var moved = false;
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        final dx = xs[j] - xs[i];
        final dy = ys[j] - ys[i];
        final spanX = halfW[i] + halfW[j];
        final spanY = halfH[i] + halfH[j];
        final overlapX = spanX - dx.abs();
        final overlapY = spanY - dy.abs();
        if (overlapX <= 0 || overlapY <= 0) continue;
        moved = true;
        // Se aparta por el eje que menos cuesta, relativo al tamaño de las
        // cajas: dos cajas anchas y bajas se separan antes en vertical.
        if (overlapX / spanX < overlapY / spanY) {
          final push = overlapX / 2 + 0.01;
          final direction = dx > 0 || (dx == 0 && j > i) ? 1.0 : -1.0;
          xs[i] -= push * direction;
          xs[j] += push * direction;
        } else {
          final push = overlapY / 2 + 0.01;
          final direction = dy >= 0 ? 1.0 : -1.0;
          ys[i] -= push * direction;
          ys[j] += push * direction;
        }
      }
    }
    if (!moved) return;
  }
}

/// Ubica los componentes en filas, en el orden en que vienen: cada fila se
/// llena hasta un ancho que da al conjunto la proporción [aspect], y cada
/// componente se centra en el alto de su fila.
void _packInRows(
  List<_PlacedComponent> components, {
  required double componentGap,
  required double aspect,
}) {
  if (components.isEmpty) return;
  var area = 0.0;
  var widest = 0.0;
  for (final component in components) {
    area +=
        (component.width + componentGap) * (component.height + componentGap);
    widest = math.max(widest, component.width);
  }
  // El ancho para que filas de ese ancho den la proporción pedida: con el área
  // total A y ancho W, el alto es A / W, y W / (A / W) = aspect.
  final rowWidth = math.max(widest, math.sqrt(area * aspect));

  var x = 0.0;
  var y = 0.0;
  var rowStart = 0;
  var rowHeight = 0.0;
  void closeRow(int end) {
    for (var c = rowStart; c < end; c++) {
      components[c].top += (rowHeight - components[c].height) / 2;
    }
  }

  for (var c = 0; c < components.length; c++) {
    final component = components[c];
    if (x > 0 && x + component.width > rowWidth) {
      closeRow(c);
      y += rowHeight + componentGap;
      x = 0;
      rowHeight = 0;
      rowStart = c;
    }
    component
      ..left = x
      ..top = y;
    x += component.width + componentGap;
    rowHeight = math.max(rowHeight, component.height);
  }
  closeRow(components.length);
}

/// Las posiciones de partida: las que se dieron, y para el resto un lugar en
/// el círculo —ordenado por grupo, para que los de un grupo queden juntos— o,
/// si el nodo tiene vecinos con lugar, junto a ellos. Marca en [known] las que
/// se dieron y devuelve cuántas son.
int _place(
  int count,
  List<MapLayoutLink> links,
  Float64List strength,
  Int32List? groups,
  Float64List? startX,
  Float64List? startY,
  double extent,
  Float64List xs,
  Float64List ys,
  Uint8List known,
) {
  final order = List<int>.generate(count, (i) => i)
    ..sort((x, y) {
      final byGroup = (groups?[x] ?? 0).compareTo(groups?[y] ?? 0);
      return byGroup != 0 ? byGroup : x.compareTo(y);
    });
  final onCircle = Int32List(count);
  for (var rank = 0; rank < count; rank++) {
    onCircle[order[rank]] = rank;
  }
  final center = extent / 2;
  final radius = extent / 3;
  double circleX(int i) =>
      center + radius * math.cos(2 * math.pi * onCircle[i] / count);
  double circleY(int i) =>
      center + radius * math.sin(2 * math.pi * onCircle[i] / count);

  var knownCount = 0;
  if (startX != null && startY != null) {
    for (var i = 0; i < count; i++) {
      if (!startX[i].isNaN && !startY[i].isNaN) {
        xs[i] = startX[i];
        ys[i] = startY[i];
        known[i] = 1;
        knownCount++;
      }
    }
  }

  // Los nuevos, junto a sus vecinos con lugar: el promedio de esos vecinos,
  // ponderado por la fuerza de la unión, con un desvío según la posición para
  // que dos nuevos no nazcan en el mismo punto.
  final sumX = Float64List(count);
  final sumY = Float64List(count);
  final sumWeight = Float64List(count);
  for (var l = 0; l < links.length; l++) {
    final a = links[l].a;
    final b = links[l].b;
    if (known[a] == 1 && known[b] == 0) {
      sumX[b] += xs[a] * strength[l];
      sumY[b] += ys[a] * strength[l];
      sumWeight[b] += strength[l];
    }
    if (known[b] == 1 && known[a] == 0) {
      sumX[a] += xs[b] * strength[l];
      sumY[a] += ys[b] * strength[l];
      sumWeight[a] += strength[l];
    }
  }
  final spread = extent / math.max(count, 1) / 2;
  for (var i = 0; i < count; i++) {
    if (known[i] == 1) continue;
    if (sumWeight[i] > 0) {
      xs[i] = sumX[i] / sumWeight[i] + spread * math.cos(i.toDouble());
      ys[i] = sumY[i] / sumWeight[i] + spread * math.sin(i.toDouble());
    } else {
      xs[i] = circleX(i);
      ys[i] = circleY(i);
    }
  }
  return knownCount;
}

/// Los nodos en una espiral de girasol —cada uno a la misma distancia de sus
/// vecinos, sin huecos—, de a uno por posición en el orden por grupo.
MapLayout _spiral(int count, Int32List? groups, double extent) {
  final order = List<int>.generate(count, (i) => i)
    ..sort((x, y) {
      final byGroup = (groups?[x] ?? 0).compareTo(groups?[y] ?? 0);
      return byGroup != 0 ? byGroup : x.compareTo(y);
    });
  // La separación entre nodos: la distancia ideal, con aire para una etiqueta.
  final gap = (1.8 * math.sqrt(extent * extent / count)).clamp(60.0, 110.0);
  const goldenAngle = 2.399963229728653;
  final xs = Float64List(count);
  final ys = Float64List(count);
  for (var rank = 0; rank < count; rank++) {
    final node = order[rank];
    final radius = gap * math.sqrt(rank + 0.5);
    xs[node] = extent / 2 + radius * math.cos(rank * goldenAngle);
    ys[node] = extent / 2 + radius * math.sin(rank * goldenAngle);
  }
  return MapLayout(xs, ys);
}
