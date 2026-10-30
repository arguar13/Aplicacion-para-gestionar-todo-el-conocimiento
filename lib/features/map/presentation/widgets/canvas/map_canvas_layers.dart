import 'package:flutter/material.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_network.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_tree.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_node_size.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se abre —o en qué se entra— desde un nodo del árbol o una fila de la
/// lista, y con qué nombre; `null` si no hay adónde.
typedef CanvasTreeOpen = ({VoidCallback onOpen, String tooltip});

/// La red del lienzo (F44, paso 2): las uniones en una capa compleja y estable
/// y cada nodo en su lugar, con su nombre y lo que oye el lector de pantalla.
///
/// No sabe de alturas ni de movimientos: [positions] es dónde está cada nodo
/// ahora —su lugar o, durante un cambio de altura, el de ese instante— y
/// [opacity], cuánto se ve todo junto mientras aparece o se recoge.
class MapNetworkLayer extends StatelessWidget {
  const MapNetworkLayer({
    required this.scene,
    required this.positions,
    required this.labelOf,
    required this.topicKind,
    required this.labelScale,
    required this.onSelect,
    this.highlight,
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

  /// La clave del nodo que se pidió mirar: lleva un anillo.
  final String? highlight;

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
            ),
          ),
        ),
        for (final node in scene.nodes)
          if (positions[node.key] case final at?)
            _placed(context, node, at, highlighted: node.key == highlight),
      ],
    );
    return switch (opacity) {
      final opacity? => Opacity(opacity: opacity, child: layer),
      null => layer,
    };
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

/// Radial y Árbol en el lienzo (F44, paso 2): las uniones de cada nodo con su
/// padre —con el tipo de vínculo y su flecha— y la tarjeta de cada nodo, que
/// se despliega con [onToggle] y se abre con [openOf].
///
/// Como [MapNetworkLayer], recibe ya puesto lo que se mueve: [positions] y
/// [opacity].
class MapTreeLayer extends StatelessWidget {
  const MapTreeLayer({
    required this.tree,
    required this.positions,
    required this.topicKind,
    required this.onToggle,
    required this.openOf,
    this.highlight,
    this.opacity,
    super.key,
  });

  final CanvasTree tree;
  final Map<String, Offset> positions;

  /// Qué es un tema acá: ver `topicSelectKind`.
  final String topicKind;
  final ValueChanged<CanvasTreeEntry> onToggle;
  final CanvasTreeOpen? Function(CanvasTreeEntry entry) openOf;

  /// La clave, en la escena, del documento que se pidió mirar.
  final String? highlight;

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
                  final open = openOf(entry);
                  return MapTreeNodeCard(
                    entry: entry,
                    topicKind: topicKind,
                    onToggle: () => onToggle(entry),
                    onOpen: open?.onOpen,
                    openTooltip: open?.tooltip,
                    highlighted:
                        entry.ref.kind == CanvasTreeKind.item &&
                        highlight == 'item:${entry.ref.id}',
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
