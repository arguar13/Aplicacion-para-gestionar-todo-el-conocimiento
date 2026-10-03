import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/domain/entities/link_graph.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/svg_writer.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layout_runner.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/arrow_head.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_export_handle.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_item_box.dart';
import 'package:sinapsis/features/organize/presentation/widgets/add_relation_flow.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Iteraciones del layout desde cero, y en caliente: con lo ya acomodado
/// alcanzan unas pocas. Las mismas del grafo.
const _kColdIterations = 260;
const _kWarmIterations = 60;

const _kCanvasMargin = 120.0;

/// La vista «Vínculos» del Mapa (F28): los elementos y sus vínculos, tengan o
/// no temas o etiquetas. Es lo que muestra en el acto lo que se vincula:
/// el grafo de temas solo une elementos que tienen alguno.
///
/// Dibuja con el mismo lenguaje que el nivel de elementos del grafo —las
/// mismas cajas, los mismos colores por tipo de vínculo, las puntas hacia el
/// destino— y escala igual: a lo sumo `kMaxGraphItems` elementos, los
/// elegidos por `selectLinkGraph`, con un aviso de cuántos quedaron afuera.
/// Los filtros del Mapa la acotan como a las demás vistas.
///
/// [focusId] es el elemento en el que poner el foco —lo que abre «Ver en el
/// Mapa» al vincular—: entra con su vecindario, se resalta y se encuadra.
class MapLinksView extends ConsumerStatefulWidget {
  const MapLinksView({
    required this.filter,
    required this.onOpenItem,
    this.focusId,
    this.exportHandle,
    super.key,
  });

  final LibraryQuery filter;
  final String? focusId;
  final void Function(String itemId) onOpenItem;

  /// Donde la vista ofrece su dibujo para exportarlo, si alguien lo quiere.
  final MapExportHandle? exportHandle;

  @override
  ConsumerState<MapLinksView> createState() => _MapLinksViewState();
}

class _MapLinksViewState extends ConsumerState<MapLinksView> {
  LinkGraph? _graph;
  GraphScene _scene = const GraphScene.empty();
  Map<String, Offset> _positions = {};
  Size _canvas = Size.zero;

  /// La última posición de cada elemento, para arrancar en caliente: un
  /// vínculo nuevo acomoda lo que mueve y deja el resto donde estaba.
  final Map<String, Offset> _remembered = {};

  /// Para descartar lo que llega de un acomodo que ya no vale.
  int _generation = 0;
  bool _busy = true;

  final _controller = TransformationController();
  final _boundaryKey = GlobalKey();
  Size _viewport = Size.zero;
  bool _needsFit = true;

  ProviderSubscription<AsyncValue<LinkGraph>>? _subscription;

  MapLinksRequest get _request =>
      (filter: widget.filter, focusId: widget.focusId);

  @override
  void initState() {
    super.initState();
    _offerExport(widget.exportHandle);
    _listen();
  }

  /// Cada vez que llegan vínculos nuevos, los acomoda. Un oyente y no un
  /// `watch` en `build`: acomodar es asíncrono y no se hace al dibujar.
  void _listen() {
    _subscription?.close();
    _subscription = ref.listenManual(mapLinksProvider(_request), (_, next) {
      if (next case AsyncData(:final value)) unawaited(_show(value));
    }, fireImmediately: true);
  }

  @override
  void didUpdateWidget(MapLinksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exportHandle != widget.exportHandle) {
      _withdrawExport(oldWidget.exportHandle);
      _offerExport(widget.exportHandle);
    }
    if (oldWidget.filter != widget.filter ||
        oldWidget.focusId != widget.focusId) {
      _needsFit = true;
      _listen();
    }
  }

  @override
  void dispose() {
    _subscription?.close();
    _withdrawExport(widget.exportHandle);
    _controller.dispose();
    super.dispose();
  }

  void _offerExport(MapExportHandle? handle) {
    handle
      ?..png = (() => capturePng(_boundaryKey))
      ..svg = _exportSvg;
  }

  void _withdrawExport(MapExportHandle? handle) {
    handle
      ?..png = null
      ..svg = null;
  }

  /// Arma la escena de [graph], la acomoda y la muestra.
  Future<void> _show(LinkGraph graph) async {
    final generation = ++_generation;
    if (mounted) setState(() => _busy = true);

    final scene = sceneOfLinks(graph);
    final startX = Float64List(scene.nodes.length);
    final startY = Float64List(scene.nodes.length);
    var known = 0;
    for (var i = 0; i < scene.nodes.length; i++) {
      final at = _remembered[scene.nodes[i].key];
      startX[i] = at?.dx ?? double.nan;
      startY[i] = at?.dy ?? double.nan;
      if (at != null) known++;
    }
    final groups = Int32List(scene.nodes.length);
    for (var i = 0; i < groups.length; i++) {
      groups[i] = scene.nodes[i].group ?? -1 - i;
    }
    final layout = await ref.read(mapLayoutRunnerProvider)((
      count: scene.nodes.length,
      links: scene.links,
      groups: groups,
      startX: known == 0 ? null : startX,
      startY: known == 0 ? null : startY,
      iterations: known == 0 ? _kColdIterations : _kWarmIterations,
    ));
    if (!mounted || generation != _generation) return;

    setState(() {
      _graph = graph;
      _scene = scene;
      _place(layout.xs, layout.ys);
      _busy = false;
    });
  }

  /// Guarda las posiciones y las pone dentro del lienzo, con margen.
  void _place(Float64List xs, Float64List ys) {
    _remembered.clear();
    if (xs.isEmpty) {
      _positions = {};
      _canvas = Size.zero;
      return;
    }
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (var i = 0; i < xs.length; i++) {
      left = math.min(left, xs[i]);
      top = math.min(top, ys[i]);
      right = math.max(right, xs[i]);
      bottom = math.max(bottom, ys[i]);
      _remembered[_scene.nodes[i].key] = Offset(xs[i], ys[i]);
    }
    final shift = Offset(_kCanvasMargin - left, _kCanvasMargin - top);
    _positions = {
      for (var i = 0; i < xs.length; i++)
        _scene.nodes[i].key: Offset(xs[i], ys[i]) + shift,
    };
    _canvas = Size(
      right - left + 2 * _kCanvasMargin,
      bottom - top + 2 * _kCanvasMargin,
    );
  }

  /// Encuadra todo o, con un foco, el foco y sus vecinos directos: lo que se
  /// acaba de vincular queda en el centro y legible.
  void _fitIfNeeded() {
    if (!_needsFit || _viewport.isEmpty || _positions.isEmpty || _busy) return;
    _needsFit = false;
    _controller.value = computeFitTransform(
      positions: _framed(),
      viewportSize: _viewport,
      contentMargin: 90,
      minScale: 0.05,
      maxScale: 1.2,
    );
  }

  Map<String, Offset> _framed() {
    final focus = _graph?.focusId;
    if (focus == null) return _positions;
    final focusIndex = _scene.indexOf('item:$focus');
    if (focusIndex == null) return _positions;
    final keys = {_scene.nodes[focusIndex].key};
    for (final edge in _scene.edges) {
      if (edge.a == focusIndex) keys.add(_scene.nodes[edge.b].key);
      if (edge.b == focusIndex) keys.add(_scene.nodes[edge.a].key);
    }
    return {
      for (final key in keys)
        if (_positions[key] case final at?) key: at,
    };
  }

  /// Lo dibujado como un documento SVG: las mismas cajas y uniones que en
  /// pantalla, a su tamaño natural.
  String _exportSvg() {
    final colors = Theme.of(context).colorScheme;
    final svg = SvgWriter(
      width: math.max(_canvas.width, 1),
      height: math.max(_canvas.height, 1),
      background: colors.surface,
    );
    for (final edge in _scene.edges) {
      final a = _positions[_scene.nodes[edge.a].key];
      final b = _positions[_scene.nodes[edge.b].key];
      if (a == null || b == null) continue;
      final color = mapEdgeColor(edge, colors);
      svg.line(a, b, color: color, strokeWidth: mapEdgeWidth(edge.weight));
      if ((b - a).distance > 40) {
        final head = arrowHead(a, b, back: 22, length: 8, half: 4);
        if (head != null) {
          svg.triangle(head.tip, head.left, head.right, fill: color);
        }
      }
    }
    for (final node in _scene.nodes) {
      final at = _positions[node.key];
      if (at == null) continue;
      writeMapItemBoxSvg(
        svg,
        isNote: node.kind == SceneKind.note,
        label: node.label,
        at: at,
        colors: colors,
        highlighted: node.ref == _graph?.focusId,
      );
    }
    return svg.build();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = ref.watch(mapLinksProvider(_request));
    final graph = _graph;

    if (graph == null) {
      return state.hasError
          ? _LoadError(
              onRetry: () => ref.invalidate(mapLinksProvider(_request)),
            )
          : const Center(child: CircularProgressIndicator());
    }

    final addLink = IconButton(
      key: const ValueKey('map-links-add'),
      tooltip: l10n.graphAddRelationTooltip,
      icon: const Icon(Icons.add_link),
      onPressed: () => unawaited(showAddRelationFlow(context, ref)),
    );

    if (graph.items.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: EmptyStateView(
              key: const ValueKey('map-links-empty'),
              icon: Icons.add_link,
              title: l10n.mapLinksEmptyTitle,
              message: l10n.mapLinksEmptyMessage,
              actionLabel: l10n.graphAddRelationTooltip,
              onAction: () => unawaited(showAddRelationFlow(context, ref)),
            ),
          ),
          if (graph.unlinkedCount > 0)
            _Footnote(text: l10n.mapLinksUnlinked(graph.unlinkedCount)),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.mapLinksSummary(graph.linkedCount),
                  key: const ValueKey('map-links-summary'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              addLink,
            ],
          ),
        ),
        SizedBox(
          height: 3,
          child: _busy ? const LinearProgressIndicator() : null,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewport = constraints.biggest;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fitIfNeeded();
              });
              return ClipRect(
                child: InteractiveViewer(
                  key: const ValueKey('map-links-canvas'),
                  transformationController: _controller,
                  constrained: false,
                  minScale: 0.05,
                  maxScale: 4,
                  boundaryMargin: const EdgeInsets.all(800),
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    // Con fondo propio: el PNG sale opaco, del color de la
                    // pantalla.
                    child: ColoredBox(
                      color: theme.colorScheme.surface,
                      child: SizedBox(
                        width: math.max(_canvas.width, 1),
                        height: math.max(_canvas.height, 1),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                isComplex: true,
                                painter: MapEdgesPainter(
                                  scene: _scene,
                                  positions: _positions,
                                  colors: theme.colorScheme,
                                ),
                              ),
                            ),
                            for (final node in _scene.nodes)
                              if (_positions[node.key] case final at?)
                                _placed(node, at, graph.focusId),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (graph.hidden > 0)
          _Footnote(
            key: const ValueKey('map-links-cut'),
            text: l10n.mapLinksCut(graph.items.length, graph.linkedCount),
          ),
        if (graph.unlinkedCount > 0)
          _Footnote(
            key: const ValueKey('map-links-unlinked'),
            text: l10n.mapLinksUnlinked(graph.unlinkedCount),
          ),
      ],
    );
  }

  Widget _placed(SceneNode node, Offset at, String? focusId) {
    return Positioned(
      left: at.dx - kMapItemBoxSize.width / 2,
      top: at.dy - kMapItemBoxSize.height / 2,
      width: kMapItemBoxSize.width,
      height: kMapItemBoxSize.height,
      child: Semantics(
        label: node.label,
        button: true,
        excludeSemantics: true,
        onTap: () => widget.onOpenItem(node.ref!),
        child: GestureDetector(
          key: ValueKey('map-links-node-${node.ref}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpenItem(node.ref!),
          child: MapItemBox(
            isNote: node.kind == SceneKind.note,
            label: node.label,
            highlighted: node.ref == focusId,
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.mapLinksLoadError),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: Text(l10n.mapRetry)),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
