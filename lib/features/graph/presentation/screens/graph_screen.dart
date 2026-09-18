import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/domain/services/item_thumbnail.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/graph/domain/services/graph_layout.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:sinapsis/features/graph/presentation/providers/graph_providers.dart';
import 'package:sinapsis/features/graph/presentation/widgets/ai_suggest_relations_dialog.dart';
import 'package:sinapsis/features/graph/presentation/widgets/degree_selector.dart';
import 'package:sinapsis/features/graph/presentation/widgets/graph_edges_painter.dart';
import 'package:sinapsis/features/graph/presentation/widgets/space_color.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_item_dialog.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_relation_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El tamaño de la tarjeta de cada nodo —todas del mismo tamaño, al estilo
/// de una entidad en un diagrama entidad-relación—. Compartida entre el
/// cálculo del margen del lienzo, el pintor de aristas y el widget que
/// dibuja el nodo: si se desincronizan, vuelve el recorte en el borde que
/// arregló esta constante.
///
/// Cuatro filas, como una tabla en miniatura con su vista previa arriba:
/// portada, encabezado, tipo de fuente y una línea de pie con la fecha — ver
/// `_GraphNode`.
///
/// La portada —`_NodeThumbnail`— es la fila más alta de las cuatro a
/// propósito: una miniatura chica no deja apreciar la foto, el fotograma
/// del video o la primera página de un documento, y termina pareciendo un
/// detalle decorativo en vez de la vista previa real que es.
const _kNodeSize = Size(220, 208);

/// Cuánto se aleja cada nodo del borde del lienzo y del visor al encuadrar:
/// la mitad de la diagonal de la tarjeta, con margen de sobra para que la
/// sombra del nodo enfocado tampoco quede cortada.
final _kNodeMargin =
    math.sqrt(
      _kNodeSize.width * _kNodeSize.width / 4 +
          _kNodeSize.height * _kNodeSize.height / 4,
    ) +
    16;

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

  /// El nodo que se está arrastrando a mano, o `null` fuera de un arrastre.
  ///
  /// Mientras haya uno, se apaga el paneo de `InteractiveViewer` —ver
  /// `_buildCanvas`—: sin esto, el reconocedor de gestos del lienzo entero y
  /// el del nodo compiten por el mismo arrastre, y el nodo se mueve a los
  /// tirones en vez de seguir al dedo o al mouse de punta a punta.
  String? _draggingNodeId;

  /// La posición del nodo que se está arrastrando, mientras dura el
  /// arrastre.
  ///
  /// Aparte de `_pinnedPositions` y no una entrada más ahí: escribir en
  /// `_pinnedPositions` en cada píxel de arrastre —como se hacía antes—
  /// obliga a un `setState` en todo `_GraphBodyState`, que reconstruye cada
  /// tarjeta del lienzo entero y repinta todas las aristas en cada frame.
  /// Con el grafo cargado, eso es justo el tirón que describían como "está
  /// duro". Este notifier en cambio solo lo escuchan la tarjeta que se está
  /// moviendo —envuelta en un `ValueListenableBuilder`— y el pintor de
  /// aristas —vía `CustomPaint.repaint`—, así que un arrastre no toca el
  /// resto del árbol para nada. Recién al soltar (`onDragEnd`) se vuelca a
  /// `_pinnedPositions` con un `setState` de verdad.
  final ValueNotifier<Offset?> _liveDragPosition = ValueNotifier(null);

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
    _liveDragPosition.dispose();
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
            icon: const Icon(Icons.compare_arrows),
            tooltip: l10n.graphTensionTooltip,
            onPressed: () => context.push(RoutePaths.graphTension),
          ),
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
                      DegreeSelector(
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

    // Ya no es un límite —ver el comentario de `computeGraphLayout`—, solo
    // la escala de partida del cálculo de fuerzas: crece con la cantidad de
    // nodos para que la separación inicial entre ellos tenga sentido, pero
    // el resultado final puede terminar siendo más grande que esto. El
    // tamaño real del `Stack` de más abajo NO es este —ver `_canvasBounds`—:
    // usarlo tal cual dejaría nodos fuera de alcance del toque aunque se
    // sigan viendo, que es justo el bug que corrigió este cálculo aparte.
    final canvasSize = Size(
      math.max(900, nodeIds.length * 230.0),
      math.max(900, nodeIds.length * 230.0),
    );

    _ensureLayout(nodeIds: nodeIds, edges: scope.edges, canvasSize: canvasSize);

    final positions = {
      for (final id in nodeIds)
        id: _pinnedPositions[id] ?? _layoutPositions[id] ?? Offset.zero,
    };

    // El `Stack` de más abajo solo se dimensiona con `canvasSize` como
    // semilla; acá se recalcula su tamaño real a partir de dónde terminaron
    // los nodos de verdad —ver el comentario de `_canvasBounds` sobre por
    // qué hace falta—. `renderPositions` es la misma `positions` pero
    // corrida para que el punto más arriba-izquierda caiga en (0,0) del
    // `Stack`: todo lo que se dibuja o se mide de acá en más usa esta
    // versión, nunca `positions` directamente.
    final bounds = _canvasBounds(positions);
    final renderPositions = _shiftPositions(positions, bounds.origin);

    if (_pendingFit) {
      _pendingFit = false;
      // Recién en el próximo frame, no acá: el visor ya tiene su tamaño
      // final —`viewportSize` es el de ESTE build—, pero tocar
      // `_transformController` en medio de construir el árbol de widgets
      // dispararía un repintado de `InteractiveViewer` a mitad de camino.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _transformController.value = computeFitTransform(
          positions: renderPositions,
          viewportSize: viewportSize,
          contentMargin: _kNodeMargin,
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
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: () {
        if (_focusedNodeId != null) setState(() => _focusedNodeId = null);
      },
      child: InteractiveViewer(
        transformationController: _transformController,
        constrained: false,
        // Sin tope: con un margen fijo, un grafo que ya llenó el
        // rectángulo de partida —o un nodo arrastrado bien afuera de
        // él— se queda sin adónde desplazarse para seguir viéndolo. Un
        // lienzo "sin límites" de verdad necesita que el paneo tampoco
        // los tenga.
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.1,
        maxScale: 3,
        // Se apaga mientras se arrastra un nodo a mano — ver
        // `_draggingNodeId` — para que ese gesto no compita con el paneo del
        // lienzo entero y el nodo siga al dedo sin tirones.
        panEnabled: _draggingNodeId == null,
        child: SizedBox(
          width: bounds.size.width,
          height: bounds.size.height,
          child: Stack(
            // Sin recorte: por más que el `Stack` ya se dimensiona para
            // contener a todos los nodos —ver `_canvasBounds`—, un arrastre
            // en curso puede sacar a uno de ese rectángulo por un instante,
            // antes de que el próximo build lo vuelva a ajustar.
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
                  nodeSize: _kNodeSize,
                  colorScheme: theme.colorScheme,
                  dimmedNodeIds: dimmedNodeIds,
                  draggingNodeId: _draggingNodeId,
                  liveDragPosition: _liveDragPosition,
                ),
              ),
              for (final id in nodeIds)
                _GraphNode(
                  key: ValueKey(id),
                  item: itemsById[id]!,
                  center: renderPositions[id]!,
                  dimmed: dimmedNodeIds?.contains(id) ?? false,
                  focused: focused == id,
                  dragging: _draggingNodeId == id,
                  liveDragPosition: _liveDragPosition,
                  onTap: () => context.push(RoutePaths.itemDetail(id)),
                  onLongPress: () => setState(() {
                    _focusedNodeId = _focusedNodeId == id ? null : id;
                  }),
                  onDragStart: () => setState(() {
                    _draggingNodeId = id;
                    _liveDragPosition.value = renderPositions[id];
                  }),
                  onDragEnd: () => setState(() {
                    if (_draggingNodeId == id) {
                      // De vuelta a coordenadas absolutas —sin el corrimiento
                      // de este build— antes de guardarlo: `_pinnedPositions`
                      // tiene que sobrevivir al próximo build, donde
                      // `bounds.origin` puede haber cambiado.
                      final liveRender =
                          _liveDragPosition.value ?? renderPositions[id]!;
                      _pinnedPositions[id] = liveRender + bounds.origin;
                      _draggingNodeId = null;
                    }
                    _liveDragPosition.value = null;
                  }),
                  onDragUpdate: (delta) {
                    if (_draggingNodeId != id) return;
                    final scale = _transformController.value
                        .getMaxScaleOnAxis();
                    final current =
                        _liveDragPosition.value ?? renderPositions[id]!;
                    _liveDragPosition.value = current + delta / scale;
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// El rectángulo que necesita el `Stack` del lienzo para contener TODAS
  /// las posiciones actuales, con el mismo margen que ya usa el encuadre
  /// automático.
  ///
  /// Hace falta porque un `Stack` con `Clip.none` deja de pintar recortado
  /// lo que cae afuera de su propio tamaño, pero Flutter igual rechaza de
  /// entrada cualquier toque fuera de ese rectángulo —antes de preguntarle
  /// a los hijos— sin importar qué tan afuera esté un `Positioned`. Con el
  /// layout de fuerzas ya sin límite (ver `computeGraphLayout`), un nodo
  /// lejos del centro podía terminar afuera de la semilla de siempre y
  /// quedar visible pero "fijado": se veía, pero ningún toque le llegaba.
  /// Medir el `Stack` según dónde terminaron los nodos de verdad, en cada
  /// build, es lo que evita que vuelva a pasar sin importar cuán separado
  /// termine el grafo.
  ({Offset origin, Size size}) _canvasBounds(Map<String, Offset> positions) {
    if (positions.isEmpty) {
      return (origin: Offset.zero, size: const Size(900, 900));
    }

    final xs = positions.values.map((p) => p.dx);
    final ys = positions.values.map((p) => p.dy);
    final minX = xs.reduce(math.min) - _kNodeMargin;
    final maxX = xs.reduce(math.max) + _kNodeMargin;
    final minY = ys.reduce(math.min) - _kNodeMargin;
    final maxY = ys.reduce(math.max) + _kNodeMargin;

    return (origin: Offset(minX, minY), size: Size(maxX - minX, maxY - minY));
  }

  /// [positions] corrida para que quede en el sistema de coordenadas local
  /// del `Stack` —donde (0,0) es la esquina superior izquierda de
  /// [origin]—, que es lo que de verdad esperan `Positioned` y
  /// `CustomPaint`.
  Map<String, Offset> _shiftPositions(
    Map<String, Offset> positions,
    Offset origin,
  ) {
    return {
      for (final entry in positions.entries) entry.key: entry.value - origin,
    };
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
    // Mismo corrimiento que aplica `_buildCanvas` al armar el `Stack`: el
    // encuadre tiene que apuntar al mismo sistema de coordenadas que se
    // está dibujando de verdad ahora mismo, no al de `positions` sin
    // corregir.
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

/// Los chips de tema del grafo —uno por componente conexo, más "Todos
/// juntos"— con el mismo estilo horizontal desplazable que [DegreeSelector].
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

/// Un elemento del grafo, dibujado como una tarjeta rectangular —una
/// "entidad", al estilo de una tabla en un diagrama entidad-relación de
/// base de datos— en vez de un círculo con una etiqueta suelta debajo.
///
/// Cuatro filas, como una tabla en miniatura con su portada arriba: una
/// vista previa del contenido —la foto, la primera página del PDF, la
/// miniatura del video—, un encabezado con el color del espacio —el mismo
/// rol que cumple el nombre de la tabla— con el título del elemento, una
/// fila de "columna" con su tipo de fuente, y un pie con cuándo se actualizó
/// por última vez. Es más información al mismo golpe de vista que un ícono
/// solo, y la forma rectangular distingue de entrada un nodo de una arista,
/// que ya usa líneas y puntas de flecha rectas —el mismo lenguaje visual que
/// cualquier diagrama entidad-relación—.
class _GraphNode extends StatelessWidget {
  const _GraphNode({
    required this.item,
    required this.center,
    required this.dimmed,
    required this.focused,
    required this.dragging,
    required this.liveDragPosition,
    required this.onTap,
    required this.onLongPress,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    super.key,
  });

  final KnowledgeItem item;
  final Offset center;
  final bool dimmed;
  final bool focused;

  /// Si este nodo es el que se está arrastrando ahora mismo — ver
  /// `_draggingNodeId` en `_GraphBodyState`. Mientras dure, la tarjeta se
  /// levanta un poco con sombra y escala, como si se la tomara de la mesa.
  final bool dragging;

  /// La posición en vivo del nodo que se está arrastrando —el mismo
  /// notifier para los tres, ver `_liveDragPosition` en `_GraphBodyState`—.
  ///
  /// Se escucha siempre, no solo cuando [dragging] es cierto: envolver el
  /// `Positioned` en un `ValueListenableBuilder` incondicional —en vez de
  /// agregarlo solo para el nodo que se arrastra— mantiene la forma del
  /// árbol de widgets igual en cualquier momento del gesto. Si en cambio
  /// el nodo dejara de estar envuelto de golpe al empezar a arrastrarlo,
  /// Flutter desmontaría y volvería a montar su `GestureDetector` a mitad
  /// de camino, y el arrastre se cortaría en el primer píxel.
  final ValueListenable<Offset?> liveDragPosition;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final fill = spaceNodeColor(item.spaceId, theme.colorScheme);
    final foreground = spaceNodeForeground(item.spaceId, theme.colorScheme);
    final elevated = focused || dragging;
    final borderColor = focused
        ? theme.colorScheme.primary
        : dragging
        ? theme.colorScheme.primary.withValues(alpha: 0.6)
        : theme.colorScheme.outlineVariant;
    final stateLabel = item.processingState.label(l10n);
    final stateColor = item.processingState.color(theme.colorScheme);

    // El `Positioned` con la posición de verdad se arma más abajo, en el
    // `ValueListenableBuilder` — ver el comentario de [liveDragPosition].
    // Esto de acá es todo lo que NO depende de esa posición: separarlo
    // como `child` fijo es lo que deja que un arrastre repinte solo el
    // `Positioned`, sin reconstruir el resto de la tarjeta en cada frame.
    final content = AnimatedOpacity(
      opacity: dimmed ? 0.25 : 1,
      duration: const Duration(milliseconds: 200),
      child: MouseRegion(
        cursor: dragging
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (details) => onDragUpdate(details.delta),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: AnimatedScale(
            scale: dragging ? 1.045 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: focused ? 2 : 1),
                boxShadow: [
                  BoxShadow(
                    color: elevated
                        ? (focused
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.shadow)
                              .withValues(alpha: focused ? 0.35 : 0.28)
                        : theme.colorScheme.shadow.withValues(alpha: 0.12),
                    blurRadius: elevated ? (dragging ? 20 : 16) : 6,
                    spreadRadius: elevated ? 1 : 0,
                    offset: Offset(0, dragging ? 6 : 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                // Antes la tarjeta tenía una altura fija y esta columna la
                // llenaba entera; ahora que el título puede pasar a varias
                // líneas, la tarjeta crece con su contenido en vez de al
                // revés — sin este `min`, `Column` intentaría estirarse
                // hasta el alto (enorme) del lienzo del grafo.
                mainAxisSize: MainAxisSize.min,
                children: [
                  // La "portada": una vista previa real cuando se puede
                  // conseguir barata, o el ícono del tipo de fuente sobre
                  // un fondo tenue cuando no — ver `_NodeThumbnail`.
                  SizedBox(
                    height: 130,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _NodeThumbnail(item: item, tint: fill),
                        if (stateColor != null)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Tooltip(
                              message: stateLabel ?? '',
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: stateColor,
                                  border: Border.all(
                                    color: theme.colorScheme.surface,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // El "nombre de la tabla": el color del espacio
                  // identifica de qué carpeta es sin tener que leer nada,
                  // igual que ya hacía el relleno del círculo anterior.
                  Container(
                    color: fill,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            item.source.kind.icon,
                            size: 14,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Sin `maxLines`/`overflow` a propósito: el título
                        // se ve completo aunque ocupe varias filas, en vez
                        // de cortado con puntos suspensivos.
                        Expanded(
                          child: Text(
                            item.title,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // La única "columna" visible de la tabla: de qué tipo
                  // de fuente es, la misma etiqueta que ya usa la
                  // biblioteca.
                  Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      item.source.kind.label(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // El pie: cuándo se actualizó por última vez, y cuántas
                  // etiquetas tiene si tiene alguna — una segunda señal
                  // aparte del color del espacio, sin agregar otra fila
                  // de texto largo que no entraría en 184px de ancho.
                  Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            DateFormat.MMMd(locale).format(item.updatedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (item.tags.isNotEmpty) ...[
                          Icon(
                            Icons.label_outline,
                            size: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${item.tags.length}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return ValueListenableBuilder<Offset?>(
      valueListenable: liveDragPosition,
      builder: (context, liveOffset, child) {
        final effectiveCenter = dragging ? (liveOffset ?? center) : center;
        return Positioned(
          left: effectiveCenter.dx - _kNodeSize.width / 2,
          // Sin `height` fijo a propósito: un título largo pasa a varias
          // líneas —ver el `Text` del encabezado, más arriba— y la tarjeta
          // crece hacia abajo para mostrarlo entero, en vez de cortarlo con
          // puntos suspensivos. `top` se sigue calculando con la altura de
          // siempre como referencia, así que el punto que calculó el
          // layout de fuerzas queda arriba de la tarjeta y no en un centro
          // que ya no es fijo.
          top: effectiveCenter.dy - _kNodeSize.height / 2,
          width: _kNodeSize.width,
          child: child!,
        );
      },
      child: content,
    );
  }
}

/// La vista previa de la portada de un nodo: una imagen real cuando se
/// puede conseguir barata —ver `ItemThumbnailResolver`— o el ícono del
/// tipo de fuente sobre un degradé con el color del espacio mientras tanto
/// o si no hay ninguna.
///
/// El ícono de respaldo solo se dibuja cuando no hay imagen —a diferencia
/// de antes, que lo dejaba siempre detrás—: con `BoxFit.contain` la imagen
/// no llena todo el recuadro, y el ícono se vería asomado por los costados
/// de una foto o un video que sí se pudo conseguir. El degradé de fondo,
/// en cambio, se ve siempre: es lo que reemplaza el hueco gris liso de
/// antes, y de paso hace de marco parejo alrededor de una imagen que no
/// llena el recuadro.
///
/// `BoxFit.contain` y no `BoxFit.cover`: la portada de un video o una foto
/// se ve completa, encuadrada entera, en vez de recortada para llenar el
/// espacio.
class _NodeThumbnail extends ConsumerWidget {
  const _NodeThumbnail({required this.item, required this.tint});

  final KnowledgeItem item;
  final Color tint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final thumbnail = ref.watch(graphNodeThumbnailProvider(item)).valueOrNull;
    final hasImage =
        thumbnail is ItemThumbnailBytes || thumbnail is ItemThumbnailUrl;

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            tint.withValues(alpha: 0.3),
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!hasImage)
            Center(
              child: Icon(
                item.source.kind.icon,
                size: 30,
                color: tint.withValues(alpha: 0.75),
              ),
            ),
          switch (thumbnail) {
            ItemThumbnailBytes(:final bytes) => TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
            ItemThumbnailUrl(:final url) => Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
            ),
            ItemThumbnailNone() || null => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}
