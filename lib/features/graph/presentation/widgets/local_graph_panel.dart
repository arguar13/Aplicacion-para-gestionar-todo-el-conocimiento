import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/features/graph/domain/services/graph_layout.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:sinapsis/features/graph/presentation/widgets/compact_graph_node.dart';
import 'package:sinapsis/features/graph/presentation/widgets/graph_edges_painter.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El espacio de trabajo del layout de fuerzas: de sobra para los pocos
/// nodos que entran con `degree: 1` fijo. No es el tamaño real en
/// pantalla —eso lo decide `LayoutBuilder` en el build— sino solo la
/// escala de partida del cálculo, igual de "de mentira" que la de
/// `GraphScreen`.
const _kCanvasSize = Size(360, 240);

/// El alto fijo del panel embebido.
const _kPanelHeight = 200.0;

/// Vista previa del grafo local de CUALQUIER elemento —fuente o nota—
/// dentro de su propio detalle: los vecinos directos (`degree: 1`, fijo),
/// sin selector ni pan/zoom real —eso vive en `LocalGraphScreen`, adonde
/// llevan tanto tocar el panel como su botón—. Es el requisito explícito
/// del punto 1 del encargo de F6 (ver `docs/arquitectura.md`).
class LocalGraphPanel extends ConsumerWidget {
  const LocalGraphPanel({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(libraryItemsProvider(const LibraryQuery()));
    final edges = ref.watch(allRelationEdgesProvider);

    return switch ((items, edges)) {
      (AsyncData(value: final items), AsyncData(value: final edges)) =>
        _LocalGraphPanelBody(item: item, items: items, edges: edges),
      _ => const SizedBox.shrink(),
    };
  }
}

class _LocalGraphPanelBody extends StatelessWidget {
  const _LocalGraphPanelBody({
    required this.item,
    required this.items,
    required this.edges,
  });

  final KnowledgeItem item;
  final List<KnowledgeItem> items;
  final List<RelationEdge> edges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Sin pasar `degree`: el default de `localGraphFrom` ya es 1, el
    // mismo grado fijo que pide este panel.
    final scope = localGraphFrom(
      seedItemId: item.id,
      items: items,
      edges: edges,
    );
    final itemsById = {for (final i in items) i.id: i};
    final nodeIds = scope.nodeIds.where(itemsById.containsKey).toList();

    if (nodeIds.isEmpty) {
      return Row(
        children: [
          Expanded(
            child: Text(
              l10n.graphEmpty,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => context.push(RoutePaths.graphLocal(item.id)),
            child: Text(l10n.localGraphPanelOpenFull),
          ),
        ],
      );
    }

    final positions = computeGraphLayout(
      nodeIds: nodeIds,
      edges: [for (final edge in scope.edges) (edge.fromItemId, edge.toItemId)],
      canvasSize: _kCanvasSize,
      iterations: 150,
    );

    final theme = Theme.of(context);

    return Stack(
      children: [
        InkWell(
          onTap: () => context.push(RoutePaths.graphLocal(item.id)),
          child: SizedBox(
            height: _kPanelHeight,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fitTransform = computeFitTransform(
                  positions: positions,
                  viewportSize: Size(constraints.maxWidth, _kPanelHeight),
                  contentMargin: compactGraphNodeSize.width / 2 + 12,
                );
                return ClipRect(
                  child: Transform(
                    transform: fitTransform,
                    child: SizedBox(
                      width: _kCanvasSize.width,
                      height: _kCanvasSize.height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CustomPaint(
                            size: _kCanvasSize,
                            painter: GraphEdgesPainter(
                              edges: [
                                for (final edge in scope.edges)
                                  (
                                    edge.fromItemId,
                                    edge.toItemId,
                                    edge.kind,
                                    edge.kind.shortLabel(l10n),
                                  ),
                              ],
                              positions: positions,
                              nodeSize: compactGraphNodeSize,
                              colorScheme: theme.colorScheme,
                            ),
                          ),
                          for (final id in nodeIds)
                            Positioned(
                              left:
                                  positions[id]!.dx -
                                  compactGraphNodeSize.width / 2,
                              top:
                                  positions[id]!.dy -
                                  compactGraphNodeSize.height / 2,
                              width: compactGraphNodeSize.width,
                              height: compactGraphNodeSize.height,
                              child: CompactGraphNode(
                                item: itemsById[id]!,
                                isSeed: id == item.id,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            icon: const Icon(Icons.open_in_full),
            tooltip: l10n.localGraphPanelOpenFull,
            onPressed: () => context.push(RoutePaths.graphLocal(item.id)),
          ),
        ),
      ],
    );
  }
}
