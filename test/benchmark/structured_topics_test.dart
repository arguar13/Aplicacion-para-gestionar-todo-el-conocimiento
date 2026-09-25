import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/community_detector.dart';
import 'package:sinapsis/features/map/domain/services/topic_graph_builder.dart';

import 'structured_topics.dart';

/// Los temas con estructura que usa el benchmark del mapa: que de verdad la
/// tengan, y que sean siempre los mismos.
void main() {
  /// Un árbol de 400 temas: 12 áreas de primer nivel y el resto colgando de
  /// otros ya puestos, con las ramas ricas haciéndose más ricas, como en la
  /// bóveda sintética.
  TopicGraphInput vault() {
    final random = Random(3);
    final rows = <AtlasValueRow>[];
    for (var i = 0; i < 400; i++) {
      final parent = i < 12
          ? null
          : rows[(pow(random.nextDouble(), 2) * rows.length).floor()].id;
      rows.add(AtlasValueRow(id: 't$i', label: 'Tema $i', parentId: parent));
    }
    return TopicGraphInput(
      definitionId: 'tema',
      definitionName: 'Tema',
      values: rows,
      items: const [],
      relations: const [],
    );
  }

  TopicGraphInput structured({int seed = 14}) =>
      structuredTopicInput(vault(), items: 3000, relations: 7500, seed: seed);

  test('conserva el árbol de temas y rehace lo que se les asigna', () {
    final input = structured();

    expect(input.values.length, 400);
    expect(input.items.length, 3000);
    expect(input.relations.length, 7500);
    final known = {for (final v in input.values) v.id};
    for (final item in input.items) {
      expect(item.valueIds, isNotEmpty);
      expect(known.containsAll(item.valueIds), isTrue);
    }
  });

  test('es determinista: la misma semilla da lo mismo, otra da otra cosa', () {
    List<String> shape(TopicGraphInput input) => [
      for (final item in input.items.take(50)) item.valueIds.join(','),
      for (final r in input.relations.take(50)) '${r.fromItemId}>${r.toItemId}',
    ];

    expect(shape(structured()), shape(structured()));
    expect(shape(structured(seed: 15)), isNot(shape(structured())));
  });

  test('el detector encuentra varias comunidades, no una maraña', () {
    final graph = buildTopicGraph(structured());
    final detection = detectCommunities(graph);

    // Doce áreas unidas por unos pocos puentes: varias comunidades, y ninguna
    // se lo lleva todo.
    final sizes = [for (final c in detection.communities) c.members.length]
      ..sort();
    expect(detection.communities.length, greaterThan(3));
    expect(sizes.last, lessThan(graph.nodes.length * 0.8));
    expect(detection.converged, isTrue);
  });

  test('la mayoría de los vínculos son del mismo área, y hay puentes', () {
    final input = structured();
    final rows = {for (final v in input.values) v.id: v.parentId};
    String rootOf(String id) {
      var current = id;
      while (rows[current] != null) {
        current = rows[current]!;
      }
      return current;
    }

    // El área de un elemento: la del primero de sus temas.
    final areaOfItem = {
      for (final item in input.items) item.id: rootOf(item.valueIds.first),
    };
    final sameArea = input.relations
        .where((r) => areaOfItem[r.fromItemId] == areaOfItem[r.toItemId])
        .length;
    expect(sameArea / input.relations.length, greaterThan(0.7));

    final bridges = input.items
        .where((item) => {...item.valueIds.map(rootOf)}.length > 1)
        .length;
    expect(bridges, greaterThan(0));
    expect(bridges / input.items.length, lessThan(0.2));
  });

  group('areaDepth (F18, 18.1)', () {
    /// El ancestro de [id] a la profundidad [depth], mismo criterio que
    /// `areaOf` adentro de la función: se prueba desde afuera, sin acceso a
    /// lo privado.
    String areaAt(Map<String, String?> parentOf, String id, int depth) {
      final chain = [id];
      var current = id;
      while (parentOf[current] != null) {
        current = parentOf[current]!;
        chain.add(current);
      }
      final index = (chain.length - 1) - depth;
      return chain[index < 0 ? 0 : index];
    }

    test('por defecto (0) sigue agrupando por rama de primer nivel entera', () {
      final input = structuredTopicInput(vault());
      final parentOf = {for (final v in input.values) v.id: v.parentId};

      // Sin el puente, los temas elegidos de un elemento comparten la MISMA
      // raíz: es la garantía que ya probaba «mayoría del mismo área» para
      // las relaciones, ahora sobre los propios temas de cada elemento.
      for (final item in input.items.take(200)) {
        final primary = item.valueIds.length > 1
            ? item.valueIds.sublist(0, item.valueIds.length - 1)
            : item.valueIds;
        final roots = {for (final id in primary) areaAt(parentOf, id, 0)};
        expect(roots, hasLength(1));
      }
    });

    test('con areaDepth > 0, el área es una sub-rama, más angosta que la '
        'raíz entera', () {
      const depth = 2;
      final flat = structuredTopicInput(vault(), seed: 5);
      final narrow = structuredTopicInput(vault(), seed: 5, areaDepth: depth);
      final parentOf = {for (final v in narrow.values) v.id: v.parentId};

      // Misma semilla, mismo árbol: las dos corridas eligen los mismos
      // ELEMENTOS por área (mismo orden de sorteo), pero la sub-rama agrupa
      // más fino —hay al menos tantas áreas distintas como con la raíz
      // entera, y en la práctica más, porque el árbol tiene ramas de sobra
      // profundidad—.
      final rootAreas = {
        for (final item in flat.items) areaAt(parentOf, item.valueIds.first, 0),
      };
      final subAreas = {
        for (final item in narrow.items)
          areaAt(parentOf, item.valueIds.first, depth),
      };
      expect(subAreas.length, greaterThan(rootAreas.length));

      // Sin el puente, los temas elegidos comparten el ancestro a esa
      // profundidad —no solo la raíz—.
      for (final item in narrow.items.take(200)) {
        final primary = item.valueIds.length > 1
            ? item.valueIds.sublist(0, item.valueIds.length - 1)
            : item.valueIds;
        final areas = {for (final id in primary) areaAt(parentOf, id, depth)};
        expect(areas, hasLength(1));
      }
    });

    test('un valor más superficial que areaDepth usa el ancestro más '
        'profundo que tenga, nunca más abajo de sí mismo', () {
      // Árbol chico y de poca profundidad: dos raíces con un solo hijo cada
      // una, nada llega a profundidad 2.
      const shallow = TopicGraphInput(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: [
          AtlasValueRow(id: 'r0', label: 'r0'),
          AtlasValueRow(id: 'r0a', label: 'r0a', parentId: 'r0'),
          AtlasValueRow(id: 'r1', label: 'r1'),
          AtlasValueRow(id: 'r1a', label: 'r1a', parentId: 'r1'),
        ],
        items: [],
        relations: [],
      );

      final input = structuredTopicInput(
        shallow,
        items: 200,
        relations: 100,
        areaDepth: 5,
      );

      expect(input.items, isNotEmpty);
      for (final item in input.items) {
        for (final id in item.valueIds) {
          expect({'r0', 'r0a', 'r1', 'r1a'}, contains(id));
        }
      }
    });
  });

  test('hay contradicciones, pocas, y algunas ya revisadas', () {
    final input = structured();
    final contradictions = input.relations
        .where((r) => r.kind == RelationKind.contradicts)
        .toList();

    expect(contradictions, isNotEmpty);
    expect(contradictions.length / input.relations.length, lessThan(0.1));
    expect(contradictions.any((r) => r.reviewed), isTrue);
    expect(contradictions.any((r) => !r.reviewed), isTrue);
  });
}
