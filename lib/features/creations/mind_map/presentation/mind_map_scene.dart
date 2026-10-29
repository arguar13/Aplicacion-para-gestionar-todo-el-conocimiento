import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_layout.dart';

/// Los colores del mapa mental en un tema (F43): el del tipo —el rosa del
/// mapa— en las uniones y en la raíz, y cada nivel un poco menos teñido que
/// el de arriba, sobre las superficies del tema. Se calculan una vez y se le
/// pasan al dibujo, que no mira el tema: así el mismo dibujo sirve para la
/// pantalla y para la imagen que se exporta.
@immutable
class MindMapPalette {
  const MindMapPalette({
    required this.background,
    required this.edge,
    required this.rootFill,
    required this.rootText,
    required this.fills,
    required this.borders,
    required this.text,
    required this.toggleFill,
    required this.toggleIcon,
  });

  factory MindMapPalette.of(ThemeData theme, Color accent) {
    final scheme = theme.colorScheme;
    final base = scheme.surfaceContainerHigh;
    final fills = [
      for (final alpha in _tints)
        Color.alphaBlend(accent.withValues(alpha: alpha), base),
    ];
    return MindMapPalette(
      background: scheme.surface,
      edge: CreationContrast.ensure(
        accent.withValues(alpha: 1),
        scheme.surface,
        minimum: 3,
      ).withValues(alpha: 0.75),
      rootFill: accent,
      rootText: CreationContrast.readableOn(accent),
      fills: fills,
      borders: [for (final alpha in _borders) accent.withValues(alpha: alpha)],
      text: CreationContrast.ensureOnAll(scheme.onSurface, fills),
      toggleFill: scheme.surface,
      toggleIcon: CreationContrast.ensure(accent, scheme.surface, minimum: 3),
    );
  }

  /// Lo teñido de cada nivel debajo de la raíz: el primero, el que más.
  static const _tints = [0.30, 0.20, 0.12, 0.07];
  static const _borders = [0.60, 0.46, 0.34, 0.26];

  final Color background;
  final Color edge;
  final Color rootFill;
  final Color rootText;
  final List<Color> fills;
  final List<Color> borders;
  final Color text;
  final Color toggleFill;
  final Color toggleIcon;

  /// El relleno de un nodo de nivel [depth] (la raíz es 0).
  Color fillAt(int depth) =>
      depth == 0 ? rootFill : fills[math.min(depth, fills.length) - 1];

  /// Su borde; la raíz no lleva.
  Color borderAt(int depth) =>
      depth == 0 ? rootFill : borders[math.min(depth, borders.length) - 1];

  /// Su letra.
  Color textAt(int depth) => depth == 0 ? rootText : text;

  @override
  bool operator ==(Object other) =>
      other is MindMapPalette &&
      other.background == background &&
      other.edge == edge &&
      other.rootFill == rootFill &&
      other.text == text;

  @override
  int get hashCode => Object.hash(background, edge, rootFill, text);
}

/// Las medidas de los nodos: la letra, cuánto se ensancha un nodo antes de
/// pasar de renglón y el lugar del «›». Con ellas se mide cada nodo antes de
/// acomodarlo —con el mismo tamaño de letra con que se dibuja—, así lo
/// medido y lo dibujado coinciden.
@immutable
class MindMapMetrics {
  const MindMapMetrics({
    required this.rootStyle,
    required this.nodeStyle,
    required this.textScaler,
    required this.textDirection,
    this.interactive = true,
  });

  /// Las de [context]: la letra del tema y el tamaño de letra de la persona.
  ///
  /// Con [textScaler], ese en vez del de la persona: la imagen exportada va
  /// con la letra de siempre.
  factory MindMapMetrics.of(
    BuildContext context, {
    bool interactive = true,
    TextScaler? textScaler,
  }) {
    final text = Theme.of(context).textTheme;
    return MindMapMetrics(
      rootStyle: text.titleMedium!.copyWith(fontWeight: FontWeight.w700),
      nodeStyle: text.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
      textScaler: textScaler ?? MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      interactive: interactive,
    );
  }

  final TextStyle rootStyle;
  final TextStyle nodeStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;

  /// Si los nodos llevan su «›» para abrir y cerrar. La imagen exportada va
  /// con todo abierto y sin ellos.
  final bool interactive;

  /// Renglones de un nodo: lo que no entra va con «…» y se lee entero al
  /// tocarlo.
  static const maxLines = 3;
  static const double horizontalPadding = 16;
  static const double verticalPadding = 10;
  static const double minHeight = 44;

  /// El círculo del «›» y lo que lo separa del texto y del borde.
  static const double toggleSize = 28;
  static const double toggleGap = 8;

  /// Lo más ancho del texto de un nodo antes de pasar de renglón; con la
  /// letra agrandada, un poco más, para no cortar tanto.
  double maxTextWidth(int depth) {
    final grow = math.min(textScaler.scale(14) / 14, 1.6);
    return (depth == 0 ? 240 : 200) * grow;
  }

  TextStyle styleAt(int depth) => depth == 0 ? rootStyle : nodeStyle;

  /// El lugar que se le deja al «›» si [node] tiene ramas.
  double toggleSpace(MindMapNode node) => interactive && node.hasChildren
      ? toggleGap + toggleSize + toggleGap
      : horizontalPadding;

  /// El tamaño de [node] en el nivel [depth].
  Size sizeOf(MindMapNode node, int depth) {
    final painter = TextPainter(
      text: TextSpan(text: node.label, style: styleAt(depth)),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
      ellipsis: '…',
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxTextWidth(depth));
    final width =
        horizontalPadding + painter.width.ceilToDouble() + toggleSpace(node);
    final height = math.max(
      minHeight,
      painter.height.ceilToDouble() + verticalPadding * 2,
    );
    painter.dispose();
    return Size(width, height);
  }

  @override
  bool operator ==(Object other) =>
      other is MindMapMetrics &&
      other.rootStyle == rootStyle &&
      other.nodeStyle == nodeStyle &&
      other.textScaler == textScaler &&
      other.textDirection == textDirection &&
      other.interactive == interactive;

  @override
  int get hashCode =>
      Object.hash(rootStyle, nodeStyle, textScaler, textDirection, interactive);
}

/// Lo que se ve del mapa con las ramas abiertas de ahora: cada nodo visible
/// con su nivel y su lugar.
@immutable
class MindMapScene {
  const MindMapScene._(this.layout, this.nodes, this.depths);

  /// [map] con las ramas de [expanded] abiertas —las demás, cerradas—, medido
  /// con [metrics] y acomodado con `layoutMindMapTree`.
  factory MindMapScene.build(
    MindMap map,
    Set<String> expanded,
    MindMapMetrics metrics,
  ) {
    final nodes = <String, MindMapNode>{};
    final depths = <String, int>{};
    TreeLayoutNode visit(MindMapNode node, int depth) {
      nodes[node.id] = node;
      depths[node.id] = depth;
      final open = expanded.contains(node.id);
      return TreeLayoutNode(
        node.id,
        metrics.sizeOf(node, depth),
        children: [
          if (open)
            for (final child in node.children) visit(child, depth + 1),
        ],
      );
    }

    final layout = layoutMindMapTree(visit(map.root, 0));
    return MindMapScene._(layout, nodes, depths);
  }

  final TreeLayout layout;

  /// Los nodos que se ven, por id.
  final Map<String, MindMapNode> nodes;

  /// El nivel de cada uno (la raíz es 0).
  final Map<String, int> depths;

  Size get size => layout.size;
}

/// Todos los nodos de [map] que tienen ramas: lo que abre «Ampliar todo».
Set<String> mindMapBranchIds(MindMap map) => {
  for (final node in map.root.descendants)
    if (node.hasChildren) node.id,
};

/// Cómo mirar un mapa de [content] en un visor de [viewport] para verlo
/// entero y centrado: a la escala que lo encuadra —con un poco de aire—,
/// nunca más de [maxScale] (un mapa chico no se agiganta) ni menos de
/// [minScale].
Matrix4 mindMapFitTransform(
  Size content,
  Size viewport, {
  required double minScale,
  double maxScale = 1,
}) {
  if (content.isEmpty || viewport.isEmpty) return Matrix4.identity();
  final scale =
      (math.min(
                viewport.width / content.width,
                viewport.height / content.height,
              ) *
              0.94)
          .clamp(minScale, maxScale);
  final dx = (viewport.width - content.width * scale) / 2;
  final dy = (viewport.height - content.height * scale) / 2;
  // La escala va en los tres ejes: el visor la lee con
  // `getMaxScaleOnAxis`, que con el eje z en 1 diría «1» al alejarse.
  return Matrix4.identity()
    ..translateByDouble(dx, dy, 0, 1)
    ..scaleByDouble(scale, scale, scale, 1);
}

/// [current] acercado o alejado [factor] veces alrededor de [focal] —un
/// punto del visor—, sin pasarse de [minScale] y [maxScale].
Matrix4 mindMapZoomTransform(
  Matrix4 current,
  double factor,
  Offset focal, {
  required double minScale,
  required double maxScale,
}) {
  final scale = current.getMaxScaleOnAxis();
  final target = (scale * factor).clamp(minScale, maxScale);
  final step = target / scale;
  return Matrix4.identity()
    ..translateByDouble(focal.dx, focal.dy, 0, 1)
    ..scaleByDouble(step, step, step, 1)
    ..translateByDouble(-focal.dx, -focal.dy, 0, 1)
    ..multiply(current);
}
