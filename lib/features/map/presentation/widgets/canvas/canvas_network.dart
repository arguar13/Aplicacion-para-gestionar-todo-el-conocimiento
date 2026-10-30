import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/svg_writer.dart';
import 'package:sinapsis/features/map/presentation/widgets/arrow_head.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_item_box.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_node_size.dart';

/// Cuánto se agranda la letra de las etiquetas en el lienzo para que, con el
/// zoom que haya, se siga leyendo en pantalla: a menos zoom, más letra. Va por
/// escalones, no de a poco, para que un gesto de zoom no reconstruya cada nodo
/// en cada cuadro.
double labelScaleFor(double zoom) {
  if (zoom >= 0.9) return 1;
  if (zoom >= 0.65) return 1.5;
  if (zoom >= 0.45) return 2.2;
  if (zoom >= 0.3) return 3.3;
  return 4.5;
}

/// El color de una comunidad: no cambia mientras la comunidad exista, porque
/// sale de su identidad. Los tonos se reparten con el ángulo áureo: identidades
/// seguidas quedan lejos en la rueda de colores. Sin comunidad, uno neutro.
Color mapCommunityColor(int? group, ColorScheme colors, Brightness brightness) {
  if (group == null) return colors.outline;
  final hue = (group * 137.508) % 360;
  return HSLColor.fromAHSL(
    1,
    hue,
    0.55,
    brightness == Brightness.dark ? 0.62 : 0.46,
  ).toColor();
}

/// El color de un nodo de la red: el de su comunidad; un documento, el de su
/// rol (fuente o nota).
Color mapSceneNodeColor(
  SceneNode node,
  ColorScheme colors,
  Brightness brightness,
) => switch (node.kind) {
  SceneKind.note => EntityRole.note.accent(colors),
  SceneKind.source => EntityRole.source.accent(colors),
  SceneKind.overflow || SceneKind.isolated => colors.outline,
  SceneKind.community ||
  SceneKind.topic => mapCommunityColor(node.group, colors, brightness),
};

/// Si el nodo junta temas: una comunidad, el desborde o los aislados.
bool isCommunityLike(SceneNode node) =>
    node.kind == SceneKind.community ||
    node.kind == SceneKind.overflow ||
    node.kind == SceneKind.isolated;

/// Un nodo de la red: un círculo con su nombre debajo —con la cuenta adentro
/// si junta temas— o, si es un documento, su caja.
class MapNetworkNode extends StatelessWidget {
  const MapNetworkNode({
    required this.node,
    required this.label,
    required this.color,
    required this.labelScale,
    this.highlighted = false,
    super.key,
  });

  final SceneNode node;
  final String label;
  final Color color;

  /// El agrandado de la etiqueta: ver [labelScaleFor].
  final double labelScale;

  /// Si es lo que se pidió mirar: lleva un anillo.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (node.kind == SceneKind.note || node.kind == SceneKind.source) {
      return MapItemBox(
        isNote: node.kind == SceneKind.note,
        label: label,
        highlighted: highlighted,
      );
    }

    final disc = mapNodeDisc(node);
    final isCommunity = isCommunityLike(node);
    // Blanco o negro, el que mejor se lea sobre el color de la comunidad: con
    // los tonos claros del modo oscuro, blanco no alcanza.
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final baseSize = theme.textTheme.labelSmall?.fontSize ?? 11;

    // Cuando la etiqueta crece con el alejamiento se sale de la caja del nodo:
    // que se salga, sin aviso de desborde.
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: 0,
      maxWidth: double.infinity,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: disc,
            height: disc,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: isCommunity ? 0.85 : 0.9),
              border: Border.all(
                color: highlighted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surface,
                width: highlighted ? 4 : 2,
              ),
            ),
            child: isCommunity
                ? Text(
                    '${node.count}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: onColor,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          // Con mucho alejamiento, la etiqueta de un tema chico se calla: las
          // de los grandes se leen y no se pisan.
          if (labelScale < 2.2 || isCommunity || disc >= 26)
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: baseSize * labelScale,
                fontWeight: highlighted ? FontWeight.w700 : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// La red de ahora como un documento SVG: los mismos nodos, colores y uniones
/// que en pantalla, con todas las etiquetas y a su tamaño natural. Con un foco,
/// lo que queda fuera de su vecindario [lit] va apagado, como se ve.
String networkSvg({
  required GraphScene scene,
  required Map<String, Offset> positions,
  required Size canvas,
  required ColorScheme colors,
  required Brightness brightness,
  required String Function(SceneNode node) labelOf,
  Set<String> highlighted = const {},
  Set<int>? lit,
}) {
  final svg = SvgWriter(
    width: math.max(canvas.width, 1),
    height: math.max(canvas.height, 1),
    background: colors.surface,
  );

  for (final edge in scene.edges) {
    final a = positions[scene.nodes[edge.a].key];
    final b = positions[scene.nodes[edge.b].key];
    if (a == null || b == null) continue;
    final base = mapEdgeColor(edge, colors);
    final color = mapEdgeLit(lit, edge.a, edge.b) ? base : mapDimmed(base);
    svg.line(a, b, color: color, strokeWidth: mapEdgeWidth(edge.weight));
    if (edge.relation != null && (b - a).distance > 40) {
      final head = arrowHead(a, b, back: 22, length: 8, half: 4);
      if (head != null) {
        svg.triangle(head.tip, head.left, head.right, fill: color);
      }
    }
  }

  for (var i = 0; i < scene.nodes.length; i++) {
    final node = scene.nodes[i];
    final at = positions[node.key];
    if (at == null) continue;
    final label = labelOf(node);
    final dimmed = lit != null && !lit.contains(i);
    Color shown(Color color) => dimmed ? mapDimmed(color) : color;
    if (node.kind == SceneKind.note || node.kind == SceneKind.source) {
      writeMapItemBoxSvg(
        svg,
        isNote: node.kind == SceneKind.note,
        label: label,
        at: at,
        colors: colors,
        highlighted: highlighted.contains(node.key),
        dimmed: dimmed,
      );
      continue;
    }
    final color = mapSceneNodeColor(node, colors, brightness);
    final disc = mapNodeDisc(node);
    final isCommunity = isCommunityLike(node);
    svg.circle(
      at,
      disc / 2,
      fill: shown(color.withValues(alpha: isCommunity ? 0.85 : 0.9)),
      stroke: shown(
        highlighted.contains(node.key) ? colors.primary : colors.surface,
      ),
      strokeWidth: highlighted.contains(node.key) ? 4 : 2,
    );
    if (isCommunity) {
      svg.text(
        '${node.count}',
        at + const Offset(0, 5),
        color: shown(
          ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? const Color(0xFFFFFFFF)
              : const Color(0xDD000000),
        ),
        size: 14,
        bold: true,
      );
    }
    svg.text(
      SvgWriter.ellipsize(label, 26),
      at + Offset(0, disc / 2 + 14),
      color: shown(colors.onSurface),
      size: 11,
    );
  }
  return svg.build();
}
