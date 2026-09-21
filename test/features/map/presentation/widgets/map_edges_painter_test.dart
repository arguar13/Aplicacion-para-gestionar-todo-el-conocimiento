import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';

/// Las uniones del grafo (F14): agrupadas por cómo se dibujan, para que miles
/// de ellas cuesten un puñado de llamadas y no una por vínculo.
void main() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

  SceneNode node(String key) =>
      SceneNode(key: key, kind: SceneKind.topic, label: key, size: 1);

  final nodes = [
    for (final key in ['a', 'b', 'c', 'd']) node(key),
  ];
  const positions = {
    'a': Offset.zero,
    'b': Offset(100, 0),
    'c': Offset(0, 100),
    'd': Offset(100, 100),
  };

  test('agrupa las uniones por color y grosor, con sus extremos en orden', () {
    final scene = GraphScene(
      nodes: nodes,
      edges: const [
        SceneEdge(a: 0, b: 1, weight: 1),
        SceneEdge(a: 2, b: 3, weight: 1),
        SceneEdge(a: 0, b: 3, weight: 1, tension: true),
        SceneEdge(a: 1, b: 2, weight: 40),
      ],
    );

    final batches = batchEdges(scene, positions, scheme);

    // Dos iguales entre sí, una tensión y una mucho más pesada: tres grupos.
    expect(batches, hasLength(3));
    expect(batches.fold<int>(0, (sum, b) => sum + b.count), 4);
    final plain = batches.firstWhere((b) => b.count == 2);
    expect(plain.color, scheme.outline.withValues(alpha: 0.4));
    expect(plain.points, [0, 0, 100, 0, 0, 100, 100, 100]);
    final tension = batches.singleWhere((b) => b.color.a > 0.7);
    expect(tension.color, scheme.error.withValues(alpha: 0.8));
    expect(tension.points, [0, 0, 100, 100]);
  });

  test('el grosor crece con el peso, de medio en medio píxel, entre 1 y 5', () {
    final scene = GraphScene(
      nodes: nodes,
      edges: [
        for (var weight = 0.0; weight < 40; weight++)
          SceneEdge(a: 0, b: 1, weight: weight),
        const SceneEdge(a: 0, b: 1, weight: 100000),
      ],
    );

    final widths = [
      for (final batch in batchEdges(scene, positions, scheme)) batch.width,
    ]..sort();

    expect(widths.first, 1);
    expect(widths.last, 5);
    for (final width in widths) {
      expect((width * 2) % 1, 0, reason: '$width no es de medio en medio');
    }
    // Cuarenta y un pesos distintos, y menos de diez grosores: agrupar sirve.
    expect(widths.length, lessThan(10));
  });

  test('el color de un vínculo entre elementos es el de su tipo', () {
    final scene = GraphScene(
      nodes: nodes,
      edges: const [
        SceneEdge(a: 0, b: 1, weight: 2, relation: RelationKind.cites),
        SceneEdge(a: 2, b: 3, weight: 2, relation: RelationKind.continues),
      ],
    );

    final batches = batchEdges(scene, positions, scheme);

    expect(batches, hasLength(2));
    expect(
      {for (final b in batches) b.color},
      {RelationKind.cites.color(scheme), RelationKind.continues.color(scheme)},
    );
  });

  test('una unión cuyo extremo no tiene lugar no se dibuja', () {
    final scene = GraphScene(
      nodes: nodes,
      edges: const [
        SceneEdge(a: 0, b: 1, weight: 1),
        SceneEdge(a: 0, b: 3, weight: 1),
      ],
    );

    final batches = batchEdges(scene, {
      'a': positions['a']!,
      'b': positions['b']!,
    }, scheme);

    expect(batches, hasLength(1));
    expect(batches.single.count, 1);
  });

  test('miles de uniones son un puñado de grupos', () {
    final many = [
      for (var i = 0; i < 4000; i++)
        SceneEdge(a: i % 4, b: (i + 1) % 4, weight: 1.0 + i % 7),
    ];
    final scene = GraphScene(nodes: nodes, edges: many);

    final batches = batchEdges(scene, positions, scheme);

    expect(batches.fold<int>(0, (sum, b) => sum + b.count), 4000);
    expect(batches.length, lessThan(12));
  });

  test('vuelve a dibujar solo si cambia la escena, un lugar o un color', () {
    final scene = GraphScene(
      nodes: nodes,
      edges: const [SceneEdge(a: 0, b: 1, weight: 1)],
    );
    MapEdgesPainter painter({GraphScene? s, Map<String, Offset>? p}) =>
        MapEdgesPainter(
          scene: s ?? scene,
          positions: p ?? positions,
          colors: scheme,
        );

    expect(painter().shouldRepaint(painter()), isFalse);
    expect(
      painter().shouldRepaint(painter(s: const GraphScene.empty())),
      isTrue,
    );
    expect(painter().shouldRepaint(painter(p: {...positions})), isTrue);
  });

  testWidgets('dibuja sin fallar, con uniones entre temas y entre elementos', (
    tester,
  ) async {
    final scene = GraphScene(
      nodes: nodes,
      edges: const [
        SceneEdge(a: 0, b: 1, weight: 1),
        SceneEdge(a: 0, b: 3, weight: 1, tension: true),
        SceneEdge(a: 1, b: 2, weight: 5, relation: RelationKind.cites),
      ],
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          size: const Size(200, 200),
          painter: MapEdgesPainter(
            scene: scene,
            positions: positions,
            colors: scheme,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
