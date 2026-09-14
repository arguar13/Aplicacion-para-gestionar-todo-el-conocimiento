import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/features/graph/domain/services/graph_layout.dart';
import 'package:sinapsis/features/graph/presentation/widgets/graph_edges_painter.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La bóveda como una red: un nodo por cada elemento que tiene al menos un
/// vínculo, y una línea por cada vínculo, con pan y zoom para recorrerla.
///
/// Solo entran los elementos vinculados a propósito: la mayoría de una
/// biblioteca no tiene ningún vínculo puesto (decisión 5 de
/// docs/arquitectura.md dice que sugerirlos automáticamente quedó afuera),
/// y dibujar cientos de puntos sueltos sin una sola línea sería ruido, no
/// un mapa.
class GraphScreen extends ConsumerWidget {
  const GraphScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(libraryItemsProvider(const LibraryQuery()));
    final edges = ref.watch(allRelationEdgesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.graphTitle)),
      body: switch ((items, edges)) {
        (AsyncData(value: final items), AsyncData(value: final edges)) =>
          _Graph(items: items, edges: edges),
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Graph extends StatelessWidget {
  const _Graph({required this.items, required this.edges});

  final List<KnowledgeItem> items;
  final List<RelationEdge> edges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (edges.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.graphEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final itemsById = {for (final item in items) item.id: item};

    // Solo los elementos que de verdad participan de un vínculo: el otro
    // extremo de una arista puede apuntar a un elemento que se borró entre
    // que se armó la lista de aristas y esta de items —las dos vienen de
    // streams separados, que no se actualizan en el mismo instante—, y ese
    // caso se descarta en vez de dibujar un nodo sin nada que mostrar.
    final nodeIds = <String>{
      for (final edge in edges) ...[edge.fromItemId, edge.toItemId],
    }.where(itemsById.containsKey).toList();

    final canvasSize = Size(
      math.max(900, nodeIds.length * 110.0),
      math.max(900, nodeIds.length * 110.0),
    );
    final positions = computeGraphLayout(
      nodeIds: nodeIds,
      edges: [for (final edge in edges) (edge.fromItemId, edge.toItemId)],
      canvasSize: canvasSize,
    );

    const nodeRadius = 24.0;
    final theme = Theme.of(context);

    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(200),
      minScale: 0.1,
      maxScale: 3,
      child: SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: Stack(
          children: [
            CustomPaint(
              size: canvasSize,
              painter: GraphEdgesPainter(
                edges: [
                  for (final edge in edges) (edge.fromItemId, edge.toItemId),
                ],
                positions: positions,
                nodeRadius: nodeRadius,
                color: theme.colorScheme.outline,
              ),
            ),
            for (final id in nodeIds)
              _GraphNode(
                item: itemsById[id]!,
                center: positions[id]!,
                radius: nodeRadius,
              ),
          ],
        ),
      ),
    );
  }
}

class _GraphNode extends StatelessWidget {
  const _GraphNode({
    required this.item,
    required this.center,
    required this.radius,
  });

  final KnowledgeItem item;
  final Offset center;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const labelWidth = 96.0;

    return Positioned(
      left: center.dx - labelWidth / 2,
      top: center.dy - radius,
      width: labelWidth,
      child: GestureDetector(
        onTap: () => context.push(RoutePaths.itemDetail(item.id)),
        child: Column(
          children: [
            Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              alignment: Alignment.center,
              child: Icon(
                item.source.kind.icon,
                size: radius,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
