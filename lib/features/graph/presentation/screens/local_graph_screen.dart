import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/features/graph/domain/services/graph_layout.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:sinapsis/features/graph/presentation/widgets/compact_graph_node.dart';
import 'package:sinapsis/features/graph/presentation/widgets/degree_selector.dart';
import 'package:sinapsis/features/graph/presentation/widgets/graph_edges_painter.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuánto se aleja cada nodo del borde del lienzo y del visor al encuadrar:
/// la mitad de la diagonal de [compactGraphNodeSize], con el mismo margen
/// de sobra que `_kNodeMargin` en `GraphScreen`.
final _kNodeMargin =
    math.sqrt(
      compactGraphNodeSize.width * compactGraphNodeSize.width / 4 +
          compactGraphNodeSize.height * compactGraphNodeSize.height / 4,
    ) +
    16;

/// El grafo local de un elemento puntual: sus vecinos hasta cierta
/// cantidad de saltos, con pan y zoom real — el destino al que lleva tocar
/// una nota mapa desde cualquier vista de grafo (decisión D4 de F6, ver
/// `docs/arquitectura.md`).
///
/// Sin selector de espacio ni de componente conexo, a diferencia de
/// `GraphScreen`: acá todo lo que se ve ya está conectado por construcción
/// a la semilla, así que ninguno de los dos aplicaría.
class LocalGraphScreen extends ConsumerStatefulWidget {
  const LocalGraphScreen({required this.itemId, super.key});

  final String itemId;

  @override
  ConsumerState<LocalGraphScreen> createState() => _LocalGraphScreenState();
}

class _LocalGraphScreenState extends ConsumerState<LocalGraphScreen> {
  /// A diferencia de `GraphScreen`, que arranca sin techo, acá arranca en
  /// 1: un panel embebido ya mostró los vecinos directos, así que abrir la
  /// pantalla completa con lo mismo es el punto de partida menos
  /// sorprendente.
  ///
  /// Vive acá y no en el cuerpo porque el grado decide QUÉ se le pide a la
  /// base: el grafo local trae solo el vecindario, no la bóveda entera.
  int? _degree = 1;

  @override
  Widget build(BuildContext context) {
    final itemId = widget.itemId;
    final hood = ref.watch(
      neighborhoodProvider((
        itemId: itemId,
        degree: _degree,
        maxNodes: kLocalGraphScreenMaxNodes,
      )),
    );
    final nodeIds = hood.valueOrNull?.nodeIds;
    final items = nodeIds == null
        ? const AsyncLoading<List<KnowledgeItem>>()
        : nodeIds.isEmpty
        ? const AsyncData<List<KnowledgeItem>>([])
        : ref.watch(libraryItemsProvider(LibraryQuery(ids: nodeIds)));
    final seedTitle =
        ref.watch(libraryItemProvider(itemId)).valueOrNull?.title ?? '';

    return switch ((hood, items)) {
      (AsyncData(value: final hood), AsyncData(value: final items)) =>
        _LocalGraphBody(
          itemId: itemId,
          seedTitle: seedTitle,
          items: items,
          edges: hood.edges,
          omitted: hood.omitted,
          degree: _degree,
          onDegreeChanged: (degree) => setState(() => _degree = degree),
        ),
      (AsyncError(:final error), _) ||
      (_, AsyncError(:final error)) => Scaffold(
        appBar: AppBar(title: Text(seedTitle)),
        body: Center(child: Text('$error')),
      ),
      _ => Scaffold(
        appBar: AppBar(title: Text(seedTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _LocalGraphBody extends ConsumerStatefulWidget {
  const _LocalGraphBody({
    required this.itemId,
    required this.seedTitle,
    required this.items,
    required this.edges,
    required this.omitted,
    required this.degree,
    required this.onDegreeChanged,
  });

  final String itemId;
  final String seedTitle;
  final List<KnowledgeItem> items;
  final List<RelationEdge> edges;

  /// Cuántos vecinos no se dibujan por el tope de nodos.
  final int omitted;

  final int? degree;
  final ValueChanged<int?> onDegreeChanged;

  @override
  ConsumerState<_LocalGraphBody> createState() => _LocalGraphBodyState();
}

class _LocalGraphBodyState extends ConsumerState<_LocalGraphBody> {
  final _transformController = TransformationController();

  Set<String> _lastNodeIds = const {};
  Set<String> _lastEdgeIds = const {};
  Size _lastCanvasSize = Size.zero;
  Map<String, Offset> _layoutPositions = const {};
  bool _pendingFit = false;
  Size _lastViewportSize = Size.zero;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _ensureLayout({
    required List<String> nodeIds,
    required List<RelationEdge> edges,
    required Size canvasSize,
  }) {
    final nodeSet = nodeIds.toSet();
    final edgeIdSet = edges.map((e) => e.id).toSet();
    final sameNodes =
        nodeSet.length == _lastNodeIds.length &&
        _lastNodeIds.every(nodeSet.contains);
    final sameEdges =
        edgeIdSet.length == _lastEdgeIds.length &&
        _lastEdgeIds.every(edgeIdSet.contains);

    if (sameNodes &&
        sameEdges &&
        canvasSize == _lastCanvasSize &&
        _layoutPositions.isNotEmpty) {
      return;
    }

    _layoutPositions = computeGraphLayout(
      nodeIds: nodeIds,
      edges: [for (final edge in edges) (edge.fromItemId, edge.toItemId)],
      canvasSize: canvasSize,
    );
    _lastNodeIds = nodeSet;
    _lastEdgeIds = edgeIdSet;
    _lastCanvasSize = canvasSize;
    _pendingFit = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final scope = localGraphFrom(
      seedItemId: widget.itemId,
      items: widget.items,
      edges: widget.edges,
      degree: widget.degree,
    );
    final itemsById = {for (final item in widget.items) item.id: item};

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.localGraphTitle(widget.seedTitle),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: DegreeSelector(
            degree: widget.degree,
            onChanged: widget.onDegreeChanged,
          ),
        ),
      ),
      body: scope.nodeIds.isEmpty
          ? _EmptyMessage(text: l10n.graphEmpty)
          : LayoutBuilder(
              builder: (context, constraints) {
                _lastViewportSize = constraints.biggest;
                return Stack(
                  children: [
                    _buildCanvas(
                      context,
                      scope,
                      itemsById,
                      constraints.biggest,
                    ),
                    if (widget.omitted > 0)
                      Positioned(
                        right: 16,
                        bottom: 24,
                        child: Text(
                          l10n.localGraphOmitted(widget.omitted),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: _ZoomControls(
                        onZoomIn: () => _zoomBy(1.4),
                        onZoomOut: () => _zoomBy(1 / 1.4),
                        onFit: _fitToView,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildCanvas(
    BuildContext context,
    ({List<String> nodeIds, List<RelationEdge> edges}) scope,
    Map<String, KnowledgeItem> itemsById,
    Size viewportSize,
  ) {
    final nodeIds = scope.nodeIds.where(itemsById.containsKey).toList();

    final canvasSize = Size(
      math.max(600, nodeIds.length * 160.0),
      math.max(600, nodeIds.length * 160.0),
    );

    _ensureLayout(nodeIds: nodeIds, edges: scope.edges, canvasSize: canvasSize);

    final positions = {
      for (final id in nodeIds) id: _layoutPositions[id] ?? Offset.zero,
    };
    final bounds = _canvasBounds(positions);
    final renderPositions = _shiftPositions(positions, bounds.origin);

    if (_pendingFit) {
      _pendingFit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _transformController.value = computeFitTransform(
          positions: renderPositions,
          viewportSize: viewportSize,
          contentMargin: _kNodeMargin,
        );
      });
    }

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return InteractiveViewer(
      transformationController: _transformController,
      constrained: false,
      // Sin tope, mismo criterio que `GraphScreen`: un layout de fuerzas
      // sin límite necesita un paneo que tampoco lo tenga.
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.1,
      maxScale: 3,
      child: SizedBox(
        width: bounds.size.width,
        height: bounds.size.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: bounds.size,
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
                positions: renderPositions,
                nodeSize: compactGraphNodeSize,
                colorScheme: theme.colorScheme,
              ),
            ),
            for (final id in nodeIds)
              Positioned(
                left: renderPositions[id]!.dx - compactGraphNodeSize.width / 2,
                top: renderPositions[id]!.dy - compactGraphNodeSize.height / 2,
                width: compactGraphNodeSize.width,
                height: compactGraphNodeSize.height,
                child: CompactGraphNode(
                  item: itemsById[id]!,
                  isSeed: id == widget.itemId,
                ),
              ),
          ],
        ),
      ),
    );
  }

  ({Offset origin, Size size}) _canvasBounds(Map<String, Offset> positions) {
    if (positions.isEmpty) {
      return (origin: Offset.zero, size: const Size(600, 600));
    }

    final xs = positions.values.map((p) => p.dx);
    final ys = positions.values.map((p) => p.dy);
    final minX = xs.reduce(math.min) - _kNodeMargin;
    final maxX = xs.reduce(math.max) + _kNodeMargin;
    final minY = ys.reduce(math.min) - _kNodeMargin;
    final maxY = ys.reduce(math.max) + _kNodeMargin;

    return (origin: Offset(minX, minY), size: Size(maxX - minX, maxY - minY));
  }

  Map<String, Offset> _shiftPositions(
    Map<String, Offset> positions,
    Offset origin,
  ) {
    return {
      for (final entry in positions.entries) entry.key: entry.value - origin,
    };
  }

  void _zoomBy(double factor) {
    final viewport = _lastViewportSize;
    if (viewport.isEmpty) return;

    final current = _transformController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.1, 3.0);
    final effectiveFactor = targetScale / currentScale;
    if (effectiveFactor == 1) return;

    final focal = Offset(viewport.width / 2, viewport.height / 2);
    final zoom = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(effectiveFactor, effectiveFactor, effectiveFactor, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);

    setState(() {
      _transformController.value = zoom.multiplied(current);
    });
  }

  void _fitToView() {
    final viewport = _lastViewportSize;
    if (viewport.isEmpty || _layoutPositions.isEmpty) return;

    final positions = {
      for (final id in _lastNodeIds) id: _layoutPositions[id] ?? Offset.zero,
    };
    final bounds = _canvasBounds(positions);
    final renderPositions = _shiftPositions(positions, bounds.origin);

    setState(() {
      _transformController.value = computeFitTransform(
        positions: renderPositions,
        viewportSize: viewport,
        contentMargin: _kNodeMargin,
      );
    });
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      elevation: 2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.graphZoomOutTooltip,
            icon: const Icon(Icons.remove),
            onPressed: onZoomOut,
          ),
          IconButton(
            tooltip: l10n.graphFitViewTooltip,
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: onFit,
          ),
          IconButton(
            tooltip: l10n.graphZoomInTooltip,
            icon: const Icon(Icons.add),
            onPressed: onZoomIn,
          ),
        ],
      ),
    );
  }
}
