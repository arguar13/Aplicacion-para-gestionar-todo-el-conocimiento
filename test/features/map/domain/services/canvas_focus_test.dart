import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/services/canvas_focus.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';

/// El vecindario del modo foco (F44, paso 4, «Centrar aquí»): lo que queda
/// encendido alrededor del nodo del centro según el «Grado».
void main() {
  SceneNode node(int i) =>
      SceneNode(key: 'topic:t$i', kind: SceneKind.topic, label: 'T$i', size: 1);

  /// Una cadena 0 — 1 — 2 — 3, el 5 colgado del 0, el 4 suelto y un lazo del
  /// 2 consigo mismo.
  final scene = GraphScene(
    nodes: [for (var i = 0; i < 6; i++) node(i)],
    edges: const [
      SceneEdge(a: 0, b: 1, weight: 1),
      SceneEdge(a: 1, b: 2, weight: 1),
      SceneEdge(a: 2, b: 3, weight: 1),
      SceneEdge(a: 0, b: 5, weight: 1),
      SceneEdge(a: 2, b: 2, weight: 1),
    ],
  );

  test('grado 0: solo el del centro', () {
    expect(focusNeighborhood(scene, 1, degree: 0), {1});
  });

  test('grado 1: también los unidos directamente, en los dos sentidos', () {
    expect(focusNeighborhood(scene, 1), {0, 1, 2});
    expect(focusNeighborhood(scene, 3), {2, 3});
  });

  test('grado 2: también los unidos a esos', () {
    expect(focusNeighborhood(scene, 1, degree: 2), {0, 1, 2, 3, 5});
    expect(focusNeighborhood(scene, 5, degree: 2), {0, 1, 5});
  });

  test('todos: lo que se alcanza, y nada de lo que no está unido', () {
    expect(focusNeighborhood(scene, 3, degree: null), {0, 1, 2, 3, 5});
    expect(focusNeighborhood(scene, 4, degree: null), {4});
  });

  test('un lazo no cuenta como vecino', () {
    expect(focusNeighborhood(scene, 2, degree: 0), {2});
    expect(focusNeighborhood(scene, 2), {1, 2, 3});
  });

  test('un nodo que no está en la escena no tiene vecindario', () {
    expect(focusNeighborhood(scene, 6), isEmpty);
    expect(focusNeighborhood(scene, -1), isEmpty);
    expect(focusNeighborhood(const GraphScene.empty(), 0), isEmpty);
  });
}
