import 'package:flutter/material.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_network.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_tree.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_node_size.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se abre la ficha de un nodo del árbol o de una fila de la lista (F44,
/// paso 4), y con qué nombre; `null` si no tiene —todo, lo vinculado—.
typedef CanvasTreeSheet = ({VoidCallback onOpen, String tooltip});

/// La red del lienzo (F44, paso 2): las uniones en una capa compleja y estable
/// y cada nodo en su lugar, con su nombre y lo que oye el lector de pantalla.
///
/// No sabe de alturas ni de movimientos: [positions] es dónde está cada nodo
/// ahora —su lugar o, durante un cambio de altura, el de ese instante— y
/// [opacity], cuánto se ve todo junto mientras aparece o se recoge.
///
/// Tocar un nodo abre su ficha ([onSelect]); tocarlo dos veces baja una altura
/// ([onEnter]), si la tiene. Con un foco (F44, paso 4), lo que queda fuera de
/// su vecindario [lit] se dibuja apagado, en una sola capa.
class MapNetworkLayer extends StatelessWidget {
  const MapNetworkLayer({
    required this.scene,
    required this.positions,
    required this.labelOf,
    required this.topicKind,
    required this.labelScale,
    required this.onSelect,
    this.onEnter,
    this.highlighted = const {},
    this.lit,
    this.opacity,
    super.key,
  });

  final GraphScene scene;
  final Map<String, Offset> positions;

  /// Cómo se rotula cada nodo: ver `MapCanvasView`.
  final String Function(SceneNode node) labelOf;

  /// Qué es un tema acá: ver `topicSelectKind`.
  final String topicKind;

  /// El agrandado de las etiquetas: ver [labelScaleFor].
  final double labelScale;

  /// Tocar un nodo.
  final ValueChanged<SceneNode> onSelect;

  /// Tocar dos veces un nodo que junta algo —una comunidad, un tema—.
  final ValueChanged<SceneNode>? onEnter;

  /// Las claves de lo que se pidió mirar, lo que tiene la ficha abierta y lo
  /// que está en el centro del foco: llevan un anillo.
  final Set<String> highlighted;

  /// Las posiciones en `scene.nodes` que quedan encendidas con el foco;
  /// `null`, sin foco.
  final Set<int>? lit;

  /// Cuánto se ve, de 0 a 1, en medio de un movimiento; `null` fuera de uno.
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final layer = Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            // Miles de líneas que no cambian mientras se arrastra: que el
            // motor las guarde dibujadas.
            isComplex: true,
            painter: MapEdgesPainter(
              scene: scene,
              positions: positions,
              colors: Theme.of(context).colorScheme,
              lit: lit,
            ),
          ),
        ),
        // Lo apagado, todo junto en una capa: una sola mezcla, no una por nodo.
        if (lit != null)
          Positioned.fill(
            child: Opacity(
              opacity: kMapDimmedOpacity,
              child: Stack(children: _nodes(context, lit: false)),
            ),
          ),
        ..._nodes(context, lit: true),
      ],
    );
    return switch (opacity) {
      final opacity? => Opacity(opacity: opacity, child: layer),
      null => layer,
    };
  }

  /// Los nodos encendidos —todos, sin foco— o, con [lit] en `false`, los
  /// apagados.
  List<Widget> _nodes(BuildContext context, {required bool lit}) {
    final shown = this.lit;
    return [
      for (var i = 0; i < scene.nodes.length; i++)
        if (shown == null ? lit : shown.contains(i) == lit)
          if (positions[scene.nodes[i].key] case final at?)
            _placed(
              context,
              scene.nodes[i],
              at,
              highlighted: highlighted.contains(scene.nodes[i].key),
            ),
    ];
  }

  Widget _placed(
    BuildContext context,
    SceneNode node,
    Offset at, {
    required bool highlighted,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final size = mapNodeSize(node);
    final label = labelOf(node);
    final semantics = switch (node.kind) {
      SceneKind.community => l10n.mapGraphCommunitySemantics(
        label,
        l10n.mapTopicCount(topicKind, node.count),
      ),
      SceneKind.overflow || SceneKind.isolated => '$label: ${node.count}',
      SceneKind.topic => '$label: ${l10n.mapItemCount(node.size)}',
      SceneKind.note || SceneKind.source => label,
    };

    return Positioned(
      left: at.dx - size.width / 2,
      top: at.dy - size.height / 2,
      width: size.width,
      height: size.height,
      child: Semantics(
        label: semantics,
        button: true,
        selected: highlighted,
        excludeSemantics: true,
        onTap: () => onSelect(node),
        child: GestureDetector(
          key: ValueKey('map-node-${node.key}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(node),
          // Un documento no tiene adónde bajar: sin doble toque, su ficha se
          // abre en el acto.
          onDoubleTap: onEnter == null || !_canEnter(node)
              ? null
              : () => onEnter!(node),
          child: MapNetworkNode(
            node: node,
            label: label,
            color: mapSceneNodeColor(node, theme.colorScheme, theme.brightness),
            labelScale: labelScale,
            highlighted: highlighted,
          ),
        ),
      ),
    );
  }
}

/// Si [node] tiene una altura más cerca a la que bajar.
bool _canEnter(SceneNode node) => switch (node.kind) {
  SceneKind.community ||
  SceneKind.overflow ||
  SceneKind.isolated ||
  SceneKind.topic => true,
  SceneKind.note || SceneKind.source => false,
};

/// Radial y Árbol en el lienzo (F44, paso 2): las uniones de cada nodo con su
/// padre —con el tipo de vínculo y su flecha— y la tarjeta de cada nodo, que
/// se despliega con [onToggle] y abre su ficha con [sheetOf].
///
/// Como [MapNetworkLayer], recibe ya puesto lo que se mueve: [positions] y
/// [opacity].
class MapTreeLayer extends StatelessWidget {
  const MapTreeLayer({
    required this.tree,
    required this.positions,
    required this.topicKind,
    required this.onToggle,
    required this.sheetOf,
    required this.isHighlighted,
    this.opacity,
    super.key,
  });

  final CanvasTree tree;
  final Map<String, Offset> positions;

  /// Qué es un tema acá: ver `topicSelectKind`.
  final String topicKind;
  final ValueChanged<CanvasTreeEntry> onToggle;
  final CanvasTreeSheet? Function(CanvasTreeEntry entry) sheetOf;

  /// Si la tarjeta lleva el borde de lo que se pidió mirar o tiene la ficha
  /// abierta.
  final bool Function(CanvasTreeEntry entry) isHighlighted;

  /// Cuánto se ve, de 0 a 1, en medio de un movimiento; `null` fuera de uno.
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final layer = Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: MapTreeEdgesPainter(
              entries: tree.entries.values.toList(),
              positions: positions,
              colors: theme.colorScheme,
              labelOf: (entry) => treeEdgeLabel(l10n, entry),
              textColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final entry in tree.entries.values)
          if (positions[entry.key] case final at?)
            Positioned(
              left: at.dx - kTreeNodeSize.width / 2,
              top: at.dy - kTreeNodeSize.height / 2,
              width: kTreeNodeSize.width,
              height: kTreeNodeSize.height,
              child: Builder(
                builder: (context) {
                  final sheet = sheetOf(entry);
                  return MapTreeNodeCard(
                    entry: entry,
                    topicKind: topicKind,
                    onToggle: () => onToggle(entry),
                    onSheet: sheet?.onOpen,
                    sheetTooltip: sheet?.tooltip,
                    highlighted: isHighlighted(entry),
                  );
                },
              ),
            ),
      ],
    );
    return switch (opacity) {
      final opacity? => Opacity(opacity: opacity, child: layer),
      null => layer,
    };
  }
}
