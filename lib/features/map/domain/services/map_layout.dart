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
