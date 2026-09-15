import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/graph/domain/services/graph_layout.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:sinapsis/features/graph/presentation/widgets/ai_suggest_relations_dialog.dart';
import 'package:sinapsis/features/graph/presentation/widgets/graph_edges_painter.dart';
import 'package:sinapsis/features/graph/presentation/widgets/space_color.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_item_dialog.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_relation_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Ancho de la etiqueta bajo cada nodo. Compartida entre el cálculo del
/// margen del lienzo y el widget que dibuja el nodo: si se desincronizan,
/// vuelve el recorte en el borde que arregló esta constante.
const _kNodeLabelWidth = 96.0;

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
    final spaces = ref.watch(allSpacesProvider);

    return switch ((items, edges, spaces)) {
      (
        AsyncData(value: final items),
        AsyncData(value: final edges),
        AsyncData(value: final spaces),
      ) =>
        _GraphBody(items: items, edges: edges, spaces: spaces),
      (AsyncError(:final error), _, _) ||
      (_, AsyncError(:final error), _) ||
      (_, _, AsyncError(:final error)) => Scaffold(
        appBar: AppBar(title: Text(l10n.graphTitle)),
        body: Center(child: Text('$error')),
      ),
      _ => Scaffold(
        appBar: AppBar(title: Text(l10n.graphTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _GraphBody extends ConsumerStatefulWidget {
  const _GraphBody({
    required this.items,
    required this.edges,
    required this.spaces,
  });

  final List<KnowledgeItem> items;
  final List<RelationEdge> edges;
  final List<Space> spaces;

  @override
  ConsumerState<_GraphBody> createState() => _GraphBodyState();
}

class _GraphBodyState extends ConsumerState<_GraphBody> {
  String? _selectedSpaceId;
  int? _degree;
  String? _focusedNodeId;

  /// Qué componente conexo se está mirando —ver `computeConnectedComponents`—,
  /// como índice dentro de la lista que devuelve esa función para el
  /// recorte actual. `null` es "todos juntos": la vista de siempre, sin
  /// separar por tema.
  int? _selectedComponentIndex;

  /// El recorte de nodos —antes de elegir un componente— para el que se
  /// calculó por última vez `_selectedComponentIndex`. Cuando cambia el
  /// espacio o el grado, cambia el conjunto de temas disponibles, y ahí es
  /// cuando conviene volver a elegir automáticamente el tema más grande —no
  /// en cada repintado, que dejaría a quien esté mirando un tema puntual
  /// sin poder quedarse en él mientras el resto de la pantalla se
  /// actualiza por otro motivo.
  Set<String> _lastScopeNodeIds = const {};

  /// Posiciones que alguien arrastró a mano, por encima de lo que calcula
  /// `computeGraphLayout`. Vive en el estado y no se recalcula con el
  /// layout de fondo: mover un nodo es una decisión de quien mira el
  /// grafo, no algo que el algoritmo deba deshacer en el próximo repintado.
  final _pinnedPositions = <String, Offset>{};

  /// Para convertir el arrastre de un nodo —en píxeles de pantalla— a
  /// desplazamiento dentro del lienzo, que está escalado por el zoom
  /// actual de `InteractiveViewer`. También es lo que leen y escriben los
  /// controles de zoom y el encuadre automático.
  final _transformController = TransformationController();

  Set<String> _lastNodeIds = const {};
  Set<String> _lastEdgeIds = const {};
  Size _lastCanvasSize = Size.zero;
  Map<String, Offset> _layoutPositions = const {};

  /// Si el layout que se acaba de calcular todavía no se encuadró en el
  /// visor. Se consume una sola vez, en el primer frame después de
  /// calcularlo — ver `_buildCanvas`.
  bool _pendingFit = false;

  /// El tamaño del visor tal como lo vio el último `build()`, para que los
  /// botones de zoom —que se tocan fuera de un `build`— sepan alrededor de
  /// qué punto de pantalla centrar el acercamiento.
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
    required double edgeMargin,
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
      edgeMargin: edgeMargin,
    );
    _lastNodeIds = nodeSet;
    _lastEdgeIds = edgeIdSet;
    _lastCanvasSize = canvasSize;
    // Las posiciones fijadas a mano de nodos que ya no están en este
    // recorte del grafo se descartan; las de los que siguen se mantienen.
    _pinnedPositions.removeWhere((id, _) => !nodeSet.contains(id));
    // Un layout nuevo todavía no se encuadró: `_buildCanvas` lo hace en el
    // próximo frame, una vez que el visor tiene un tamaño de verdad.
    _pendingFit = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final scope = scopeGraph(
      items: widget.items,
      edges: widget.edges,
      spaceId: _selectedSpaceId,
      degree: _degree,
    );

    // Uno por cada grupo de elementos que se puede alcanzar de uno a otro
    // siguiendo vínculos, sin tocar nada de fuera del grupo: es "un grafo
    // por tema" automático, sin pedirle a nadie que clasifique nada — ver
    // el comentario de `computeConnectedComponents`.
    final components = computeConnectedComponents(
      nodeIds: scope.nodeIds,
      edges: scope.edges,
    );

    // El espacio o el grado cambiaron: los temas disponibles ya no son los
    // mismos, así que conviene volver a elegir el más grande de una — la
    // elección anterior puede ni existir más en este recorte nuevo. No se
    // toca si lo único que cambió fue el tema elegido dentro del MISMO
    // recorte: eso lo maneja `_ComponentSelector` con su propio `onSelected`.
    final scopeNodeIdSet = scope.nodeIds.toSet();
    final sameScope =
        scopeNodeIdSet.length == _lastScopeNodeIds.length &&
        _lastScopeNodeIds.every(scopeNodeIdSet.contains);
    if (!sameScope) {
      _lastScopeNodeIds = scopeNodeIdSet;
      _selectedComponentIndex = components.length > 1 ? 0 : null;
    }

    final selectedComponent = _selectedComponentIndex;
    final activeNodeIds =
        selectedComponent != null && selectedComponent < components.length
        ? components[selectedComponent]
        : null;

    // El recorte de verdad que se dibuja: todo el `scope`, o solo el
    // componente elegido si hay uno. Los nodos y las aristas se filtran
    // igual, por la misma razón que `scopeGraph` ya filtra aristas
    // colgantes: un componente nunca deja una arista con un solo extremo
    // adentro, porque las aristas son justamente lo que define el grupo.
    final effectiveNodeIds = activeNodeIds == null
        ? scope.nodeIds
        : scope.nodeIds.where(activeNodeIds.contains).toList();
    final effectiveEdges = activeNodeIds == null
        ? scope.edges
        : scope.edges
              .where((edge) => activeNodeIds.contains(edge.fromItemId))
              .toList();

    final itemsById = {for (final item in widget.items) item.id: item};

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.graphTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: l10n.graphLegendTooltip,
            onPressed: () => _showLegend(context, l10n),
          ),
          _SpaceFilterButton(
            spaces: widget.spaces,
            selectedSpaceId: _selectedSpaceId,
            onSelected: (id) => setState(() {
              _selectedSpaceId = id;
              _focusedNodeId = null;
            }),
          ),
          const SizedBox(width: 4),
        ],
        bottom: _selectedSpaceId == null && components.length <= 1
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(
                  (_selectedSpaceId != null ? 48 : 0) +
                      (components.length > 1 ? 56 : 0),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedSpaceId != null)
                      _DegreeSelector(
                        degree: _degree,
                        onChanged: (degree) => setState(() => _degree = degree),
                      ),
                    if (components.length > 1)
                      _ComponentSelector(
                        components: components,
                        selectedIndex: _selectedComponentIndex,
                        itemsById: itemsById,
                        edges: scope.edges,
                        onSelected: (int? index) => setState(() {
                          _selectedComponentIndex = index;
                          _focusedNodeId = null;
                        }),
                      ),
                  ],
                ),
              ),
      ),
      body: widget.edges.isEmpty
          ? _EmptyMessage(text: l10n.graphEmpty)
          : effectiveNodeIds.isEmpty
          ? _EmptyMessage(text: l10n.graphScopeEmpty)
          : LayoutBuilder(
              builder: (context, constraints) {
                _lastViewportSize = constraints.biggest;
                return Stack(
                  children: [
                    _buildCanvas(context, (
                      nodeIds: effectiveNodeIds,
                      edges: effectiveEdges,
                    ), constraints.biggest),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'graph-ai-suggest',
            tooltip: l10n.graphAiSuggestTooltip,
            onPressed: () => showAiSuggestRelationsDialog(
              context,
              ref,
              items: widget.items,
              edges: widget.edges,
            ),
            child: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'graph-add-relation',
            tooltip: l10n.graphAddRelationTooltip,
            onPressed: () => _addRelation(context),
            child: const Icon(Icons.add_link),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(
    BuildContext context,
    ({List<String> nodeIds, List<RelationEdge> edges}) scope,
    Size viewportSize,
  ) {
    final itemsById = {for (final item in widget.items) item.id: item};
    final nodeIds = scope.nodeIds.where(itemsById.containsKey).toList();

    final canvasSize = Size(
      math.max(900, nodeIds.length * 110.0),
      math.max(900, nodeIds.length * 110.0),
    );
    const nodeRadius = 24.0;
    // El nodo se dibuja centrado en su posición, con la etiqueta debajo:
    // el margen tiene que cubrir lo que sobresale del centro en cada
    // dirección para que ningún nodo quede a medias fuera del lienzo.
    const edgeMargin = _kNodeLabelWidth / 2 + 8;

    _ensureLayout(
      nodeIds: nodeIds,
      edges: scope.edges,
      canvasSize: canvasSize,
      edgeMargin: edgeMargin,
    );

    final positions = {
      for (final id in nodeIds)
        id: _pinnedPositions[id] ?? _layoutPositions[id] ?? Offset.zero,
    };

    if (_pendingFit) {
      _pendingFit = false;
      // Recién en el próximo frame, no acá: el visor ya tiene su tamaño
      // final —`viewportSize` es el de ESTE build—, pero tocar
      // `_transformController` en medio de construir el árbol de widgets
      // dispararía un repintado de `InteractiveViewer` a mitad de camino.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _transformController.value = computeFitTransform(
          positions: positions,
          viewportSize: viewportSize,
        );
      });
    }

    final focused = _focusedNodeId;
    Set<String>? dimmedNodeIds;
    if (focused != null && nodeIds.contains(focused)) {
      final connected = <String>{focused};
      for (final edge in scope.edges) {
        if (edge.fromItemId == focused) connected.add(edge.toItemId);
        if (edge.toItemId == focused) connected.add(edge.fromItemId);
      }
      dimmedNodeIds = nodeIds.where((id) => !connected.contains(id)).toSet();
    }

    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        if (_focusedNodeId != null) setState(() => _focusedNodeId = null);
      },
      child: InteractiveViewer(
        transformationController: _transformController,
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
                    for (final edge in scope.edges)
                      (edge.fromItemId, edge.toItemId, edge.kind),
                  ],
                  positions: positions,
                  nodeRadius: nodeRadius,
                  colorScheme: theme.colorScheme,
                  dimmedNodeIds: dimmedNodeIds,
                ),
              ),
              for (final id in nodeIds)
                _GraphNode(
                  key: ValueKey(id),
                  item: itemsById[id]!,
                  center: positions[id]!,
                  radius: nodeRadius,
                  dimmed: dimmedNodeIds?.contains(id) ?? false,
                  focused: focused == id,
                  onTap: () => context.push(RoutePaths.itemDetail(id)),
                  onLongPress: () => setState(() {
                    _focusedNodeId = _focusedNodeId == id ? null : id;
                  }),
                  onDragUpdate: (delta) {
                    final scale = _transformController.value
                        .getMaxScaleOnAxis();
                    final current = positions[id]!;
                    setState(() {
                      _pinnedPositions[id] = current + delta / scale;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Acerca o aleja el zoom por [factor] —mayor que 1 acerca, menor aleja—
  /// alrededor del centro del visor, sin perder el paneo actual.
  void _zoomBy(double factor) {
    final viewport = _lastViewportSize;
    if (viewport.isEmpty) return;

    final current = _transformController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.1, 3.0);
    // El factor que hace falta para llegar de la escala actual a la
    // buscada, no `factor` tal cual: cerca de los topes (0.1 o 3), pedir
    // "acercar" de nuevo no debería seguir intentando multiplicar más allá
    // del límite.
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

  /// Vuelve a centrar y escalar la vista para que quepan todos los nodos
  /// que se están mostrando ahora — el mismo cálculo que corre solo la
  /// primera vez que aparece un layout nuevo, pero a pedido.
  void _fitToView() {
    final viewport = _lastViewportSize;
    if (viewport.isEmpty || _layoutPositions.isEmpty) return;

    final positions = {
      for (final id in _lastNodeIds)
        id: _pinnedPositions[id] ?? _layoutPositions[id] ?? Offset.zero,
    };

    setState(() {
      _transformController.value = computeFitTransform(
        positions: positions,
        viewportSize: viewport,
      );
    });
  }

  Future<void> _addRelation(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final fromId = await showDialog<String>(
      context: context,
      builder: (context) => PickItemDialog(title: l10n.graphPickFirstItemTitle),
    );
    if (fromId == null || !context.mounted) return;

    final toId = await showDialog<String>(
      context: context,
      builder: (context) => PickItemDialog(
        excludeItemId: fromId,
        title: l10n.graphPickSecondItemTitle,
      ),
    );
    if (toId == null || !context.mounted) return;

    final picked = await showDialog<({RelationKind kind, String? note})>(
      context: context,
      builder: (context) => const PickRelationDialog(),
    );
    if (picked == null || !context.mounted) return;

    final result = await ref
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: fromId,
          toItemId: toId,
          kind: picked.kind,
          note: picked.note,
        );

    if (!context.mounted) return;
    result.match((failure) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    }, (_) {});
  }

  Future<void> _showLegend(BuildContext context, AppLocalizations l10n) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.graphLegendSpacesTitle,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    for (final space in widget.spaces)
                      _LegendChip(
                        color: spaceNodeColor(space.id, theme.colorScheme),
                        label: space.name,
                      ),
                    _LegendChip(
                      color: spaceNodeColor(null, theme.colorScheme),
                      label: l10n.graphSpaceFilterNone,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.graphLegendRelationsTitle,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    for (final kind in RelationKind.values)
                      _LegendChip(
                        color: kind.color(theme.colorScheme),
                        icon: kind.icon,
                        label: kind.shortLabel(l10n),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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

class _SpaceFilterButton extends StatelessWidget {
  const _SpaceFilterButton({
    required this.spaces,
    required this.selectedSpaceId,
    required this.onSelected,
  });

  final List<Space> spaces;
  final String? selectedSpaceId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final selectedId = selectedSpaceId;
    final selectedLabel = selectedId == null
        ? l10n.graphSpaceFilterAll
        : spaces
                  .where((s) => s.id == selectedId)
                  .map((s) => s.name)
                  .firstOrNull ??
              l10n.graphSpaceFilterAll;

    return PopupMenuButton<String?>(
      tooltip: l10n.graphSpaceFilterTooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(child: Text(l10n.graphSpaceFilterAll)),
        for (final space in spaces)
          PopupMenuItem(
            value: space.id,
            child: Row(
              children: [
                _SpaceSwatch(spaceId: space.id),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(space.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedId != null) ...[
              _SpaceSwatch(spaceId: selectedId),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                selectedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _SpaceSwatch extends StatelessWidget {
  const _SpaceSwatch({required this.spaceId});

  final String? spaceId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: spaceNodeColor(spaceId, Theme.of(context).colorScheme),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _DegreeSelector extends StatelessWidget {
  const _DegreeSelector({required this.degree, required this.onChanged});

  final int? degree;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                l10n.graphDegreeLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final option in const [0, 1, 2, null])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(option == null ? l10n.graphDegreeAll : '$option'),
                  selected: degree == option,
                  onSelected: (_) => onChanged(option),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Los chips de tema del grafo —uno por componente conexo, más "Todos
/// juntos"— con el mismo estilo horizontal desplazable que `_DegreeSelector`.
class _ComponentSelector extends StatelessWidget {
  const _ComponentSelector({
    required this.components,
    required this.selectedIndex,
    required this.itemsById,
    required this.edges,
    required this.onSelected,
  });

  final List<Set<String>> components;
  final int? selectedIndex;
  final Map<String, KnowledgeItem> itemsById;
  final List<RelationEdge> edges;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Tooltip(
              message: l10n.graphComponentsHint,
              child: Icon(
                Icons.info_outline,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            for (var i = 0; i < components.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(
                    _componentLabel(l10n, components[i], itemsById, edges),
                  ),
                  selected: selectedIndex == i,
                  onSelected: (_) => onSelected(i),
                ),
              ),
            ChoiceChip(
              label: Text(l10n.graphComponentAllLabel),
              selected: selectedIndex == null,
              onSelected: (_) => onSelected(null),
            ),
          ],
        ),
      ),
    );
  }
}

/// El texto de un chip de tema: la etiqueta que más se repite entre sus
/// elementos, si comparten alguna, o si no el título del elemento con más
/// vínculos adentro del grupo — el más probable "centro" del tema.
///
/// Aparte del widget para poder probarla con datos concretos, sin montar
/// ninguna pantalla: es la única parte de `_ComponentSelector` con lógica
/// real, el resto es puro armado de chips.
String _componentLabel(
  AppLocalizations l10n,
  Set<String> nodeIds,
  Map<String, KnowledgeItem> itemsById,
  List<RelationEdge> edges,
) {
  final tagCounts = <String, int>{};
  for (final id in nodeIds) {
    for (final tag in itemsById[id]?.tags ?? const <Tag>[]) {
      tagCounts[tag.name] = (tagCounts[tag.name] ?? 0) + 1;
    }
  }

  if (tagCounts.isNotEmpty) {
    final topTag = tagCounts.entries.reduce(
      (a, b) => b.value > a.value ? b : a,
    );
    return l10n.graphComponentTagLabel(topTag.key, nodeIds.length);
  }

  // Sin ninguna etiqueta en común: el elemento con más vínculos DENTRO de
  // este mismo grupo es la mejor pista disponible de qué tiene que ver el
  // tema — el resto ya cuelga de él, directa o indirectamente.
  final degree = <String, int>{for (final id in nodeIds) id: 0};
  for (final edge in edges) {
    if (!nodeIds.contains(edge.fromItemId) ||
        !nodeIds.contains(edge.toItemId)) {
      continue;
    }
    degree[edge.fromItemId] = (degree[edge.fromItemId] ?? 0) + 1;
    degree[edge.toItemId] = (degree[edge.toItemId] ?? 0) + 1;
  }

  var hubTitle = itemsById[nodeIds.first]?.title ?? '';
  var hubDegree = -1;
  for (final id in nodeIds) {
    final d = degree[id] ?? 0;
    if (d > hubDegree) {
      hubDegree = d;
      hubTitle = itemsById[id]?.title ?? hubTitle;
    }
  }

  return l10n.graphComponentFallbackLabel(hubTitle, nodeIds.length);
}

/// Los controles de zoom del grafo: acercar, alejar y volver a encuadrar el
/// contenido entero. Aparte del pellizco con los dedos que ya ofrece
/// `InteractiveViewer` —discreto y fácil de no encontrar— para que zoom y
/// encuadre sean acciones visibles, no solo un gesto que hay que conocer de
/// antes.
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

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label, this.icon});

  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon == null)
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          )
        else
          Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _GraphNode extends StatelessWidget {
  const _GraphNode({
    required this.item,
    required this.center,
    required this.radius,
    required this.dimmed,
    required this.focused,
    required this.onTap,
    required this.onLongPress,
    required this.onDragUpdate,
    super.key,
  });

  final KnowledgeItem item;
  final Offset center;
  final double radius;
  final bool dimmed;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<Offset> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const labelWidth = _kNodeLabelWidth;
    final fill = spaceNodeColor(item.spaceId, theme.colorScheme);
    final foreground = spaceNodeForeground(item.spaceId, theme.colorScheme);

    return Positioned(
      left: center.dx - labelWidth / 2,
      top: center.dy - radius,
      width: labelWidth,
      child: AnimatedOpacity(
        opacity: dimmed ? 0.25 : 1,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          onPanUpdate: (details) => onDragUpdate(details.delta),
          child: Column(
            children: [
              Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: focused
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surface,
                    width: focused ? 3 : 2,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(
                  item.source.kind.icon,
                  size: radius,
                  color: foreground,
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
      ),
    );
  }
}
