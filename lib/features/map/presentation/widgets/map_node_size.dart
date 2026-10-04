import 'dart:math' as math;
import 'dart:ui';

import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_item_box.dart';

/// El tamaño de la caja de un nodo, con su etiqueta.
Size mapNodeSize(SceneNode node) => switch (node.kind) {
  SceneKind.community || SceneKind.overflow || SceneKind.isolated => Size(
    math.max(mapNodeDisc(node), 120),
    mapNodeDisc(node) + 22,
  ),
  SceneKind.topic => Size(
    math.max(mapNodeDisc(node), 96),
    mapNodeDisc(node) + 18,
  ),
  SceneKind.note || SceneKind.source => kMapItemBoxSize,
};

/// El diámetro del círculo de un nodo, que crece con su peso.
double mapNodeDisc(SceneNode node) => switch (node.kind) {
  SceneKind.community ||
  SceneKind.overflow ||
  SceneKind.isolated => (30 + 7 * math.sqrt(node.size)).clamp(30, 110),
  SceneKind.topic => (16 + 5 * math.sqrt(node.size)).clamp(16, 60),
  _ => 0,
};
