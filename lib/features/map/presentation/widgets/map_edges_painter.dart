import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/presentation/widgets/arrow_head.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_layer_marks.dart';

/// Cuánto se ve lo que queda fuera del vecindario en el modo foco del lienzo
/// (F44, paso 4, «Centrar aquí»): apagado, no borrado.
const kMapDimmedOpacity = 0.18;

/// [color] apagado como lo que queda fuera del foco.
Color mapDimmed(Color color) =>
    color.withValues(alpha: color.a * kMapDimmedOpacity);

/// Si la unión de [a] con [b] queda encendida con el vecindario [lit] —las
/// posiciones en la escena que se ven—: con los dos extremos adentro. Sin
/// foco ([lit] `null`), todas.
bool mapEdgeLit(Set<int>? lit, int a, int b) =>
    lit == null || (lit.contains(a) && lit.contains(b));

/// El grosor de una unión según su peso: crece despacio, entre 1 y 5.
double mapEdgeWidth(double weight) =>
    (1 + 0.7 * math.log(1 + weight)).clamp(1.0, 5.0);

/// El color de una unión: rojo si es una contradicción o junta alguna, el del
/// tipo de vínculo entre elementos, y un gris tenue entre temas. Una unión
/// sale marcada en tensión solo con la capa «Contradicciones» (`layeredScene`,
/// F44, paso 5).
Color mapEdgeColor(SceneEdge edge, ColorScheme colors) {
  if (edge.tension) return colors.error.withValues(alpha: 0.8);
  final relation = edge.relation;
  if (relation != null) return relation.color(colors);
  return colors.outline.withValues(alpha: 0.4);
}

/// Las uniones que se dibujan igual —mismo color, mismo grosor— y los extremos
/// de cada una, uno tras otro: `x1, y1, x2, y2, x1, y1, …`.
class MapEdgeBatch {
  const MapEdgeBatch({
    required this.color,
    required this.width,
    required this.points,
  });

  final Color color;

  /// El grosor, en medios píxeles: las uniones no se distinguen por menos.
  final double width;

  final Float32List points;

  int get count => points.length ~/ 4;
}

/// Agrupa las uniones de [scene] por cómo se dibujan; con un foco, las que
/// salen de su vecindario [lit] van apagadas.
///
/// Con miles de uniones, dibujar cada una con su propia llamada hace que el
/// dibujo de cada cuadro cueste decenas de milisegundos aunque nada cambie:
/// agrupadas, son un puñado de llamadas —una por color y grosor— y el motor las
/// resuelve de una vez. El grosor se redondea a medio píxel para que los grupos
/// sean pocos; a ese tamaño no se nota.
List<MapEdgeBatch> batchEdges(
  GraphScene scene,
  Map<String, Offset> positions,
  ColorScheme colors, {
  Set<int>? lit,
}) {
  final grouped = <(Color, double), List<double>>{};
  for (final edge in scene.edges) {
    final a = positions[scene.nodes[edge.a].key];
    final b = positions[scene.nodes[edge.b].key];
    if (a == null || b == null) continue;
    final width = (mapEdgeWidth(edge.weight) * 2).round() / 2;
    final color = mapEdgeColor(edge, colors);
    final shown = mapEdgeLit(lit, edge.a, edge.b) ? color : mapDimmed(color);
    (grouped[(shown, width)] ??= []).addAll([a.dx, a.dy, b.dx, b.dy]);
  }
  return [
    for (final entry in grouped.entries)
      MapEdgeBatch(
        color: entry.key.$1,
        width: entry.key.$2,
        points: Float32List.fromList(entry.value),
      ),
  ];
}

/// Las uniones del grafo: una línea por vínculo, y entre elementos una punta
/// hacia el destino.
///
/// Lo que dibuja no cambia mientras se arrastra o se acerca —lo mueve la
/// transformación del visor, no este dibujo—, y tiene miles de líneas: quien
/// lo usa le pasa a su `CustomPaint` las pistas `isComplex` y `willChange` para
/// que el motor lo guarde ya dibujado en vez de recorrerlo en cada cuadro.
class MapEdgesPainter extends CustomPainter {
  const MapEdgesPainter({
    required this.scene,
    required this.positions,
    required this.colors,
    this.lit,
  });

  final GraphScene scene;
  final Map<String, Offset> positions;
  final ColorScheme colors;

  /// El vecindario del modo foco: lo que queda afuera va apagado. `null`, sin
  /// foco.
  final Set<int>? lit;

  @override
  void paint(Canvas canvas, Size size) {
    for (final batch in batchEdges(scene, positions, colors, lit: lit)) {
      canvas.drawRawPoints(
        PointMode.lines,
        batch.points,
        Paint()
          ..color = batch.color
          ..strokeWidth = batch.width
          ..style = PaintingStyle.stroke,
      );
    }

    // Entre elementos el vínculo tiene sentido: una punta hacia el destino.
    // Todas las del mismo color, en un solo trazo.
    final heads = <Color, Path>{};
    for (final edge in scene.edges) {
      final relation = edge.relation;
      if (relation == null) continue;
      final a = positions[scene.nodes[edge.a].key];
      final b = positions[scene.nodes[edge.b].key];
      if (a == null || b == null || (b - a).distance <= 40) continue;
      final head = arrowHead(a, b, back: 22, length: 8, half: 4);
      if (head == null) continue;
      final color = mapEdgeColor(edge, colors);
      final shown = mapEdgeLit(lit, edge.a, edge.b) ? color : mapDimmed(color);
      (heads[shown] ??= Path()).addPath(arrowPath(head), Offset.zero);
    }
    for (final MapEntry(:key, :value) in heads.entries) {
      canvas.drawPath(value, Paint()..color = key);
    }

    // Con la capa «Contradicciones» (F44, paso 5), cada unión en tensión
    // lleva su rayo: se distingue también sin el rojo.
    paintTensionMarks(
      canvas,
      scene,
      positions,
      colors,
      colorOf: (edge) {
        final color = mapEdgeColor(edge, colors);
        return mapEdgeLit(lit, edge.a, edge.b) ? color : mapDimmed(color);
      },
    );
  }

  @override
  bool shouldRepaint(MapEdgesPainter old) =>
      old.scene != scene ||
      old.positions != positions ||
      old.colors != colors ||
      old.lit != lit;
}
