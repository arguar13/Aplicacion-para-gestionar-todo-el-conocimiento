import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:sinapsis/features/graph/presentation/widgets/ai_suggest_relations_dialog.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';
import 'package:sinapsis/features/map/domain/services/svg_writer.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layout_runner.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/arrow_head.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_export_handle.dart';
import 'package:sinapsis/features/organize/presentation/widgets/add_relation_flow.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Con más zoom que esto, se pasa al nivel de más detalle del nodo del centro.
const kZoomInThreshold = 2.2;

/// Con menos zoom que esto, se vuelve al nivel de menos detalle.
const kZoomOutThreshold = 0.42;

/// Acercarse a este múltiplo del encuadre del nivel pasa al siguiente aunque no
/// se llegue a [kZoomInThreshold]: un nivel grande queda encuadrado tan
/// alejado que ese umbral pediría un zoom enorme.
const kZoomInFromFit = 3.0;

/// El zoom más lejano del visor, y hasta donde llega el encuadre: un nivel
/// con cientos de nodos cabe entero en un celular a un zoom muy chico.
const _kMinScale = 0.05;

/// Cuánto tiene que cambiar el zoom en un gesto para que cuente como acercar o
/// alejar. Menos que esto es arrastrar, y arrastrar no cambia de nivel.
const _kZoomChange = 1.05;

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

/// Iteraciones del layout desde cero, y en caliente: con lo ya acomodado
/// alcanzan unas pocas.
const _kColdIterations = 260;
const _kWarmIterations = 60;

const _kCanvasMargin = 120.0;

/// Los tres niveles de detalle del grafo (F14, D5).
enum GraphLevel {
  /// Las comunidades de temas, coloreadas.
  overview,

  /// Los temas de una comunidad o de un vecindario, coloreados por comunidad.
  topics,

  /// Los elementos de un tema y los vínculos entre ellos.
  items,
}

/// El grafo de conocimiento (F14): la bóveda como una red de temas con tres
/// niveles de detalle —comunidades, temas, elementos— que se recorren tocando
/// o acercándose.
///
/// Nunca dibuja miles de nodos: el panorama tiene a lo sumo 60, el nivel de
/// temas 300 y el de elementos 200. Lo acomoda el layout de fuerzas con las
/// uniones ponderadas y las comunidades agrupadas, en otro isolate, y en
/// caliente cuando el mapa se recalcula, para que no dé un salto.
class MapGraphView extends ConsumerStatefulWidget {
  const MapGraphView({
    required this.snapshot,
    required this.onOpenTopic,
    required this.onOpenItem,
    this.exportHandle,
    super.key,
  });

  final KnowledgeMapSnapshot snapshot;
  final void Function(String valueId) onOpenTopic;
  final void Function(String itemId) onOpenItem;

  /// Donde la vista ofrece su dibujo para exportarlo, si alguien lo quiere.
  final MapExportHandle? exportHandle;

  @override
  ConsumerState<MapGraphView> createState() => _MapGraphViewState();
}

class _MapGraphViewState extends ConsumerState<MapGraphView> {
  GraphLevel _level = GraphLevel.overview;

  /// Los temas en foco en el nivel de temas, por valor.
  Set<String> _focus = {};
  String? _focusLabel;

  /// El tema del nivel de elementos, por valor.
  String? _topicId;
  String? _topicLabel;

  GraphScene _scene = const GraphScene.empty();
  Map<String, Offset> _positions = {};
  Size _canvas = Size.zero;

  /// La última posición de cada nodo, para arrancar en caliente.
  final Map<String, Offset> _remembered = {};

  /// Para descartar lo que llega de un cálculo que ya no vale.
  int _generation = 0;
  bool _busy = true;

  final _controller = TransformationController();
  final _boundaryKey = GlobalKey();
  Size _viewport = Size.zero;
  bool _needsFit = true;

  /// El zoom con el que quedó encuadrado el nivel de ahora.
  double _fitScale = 1;

  /// El zoom con el que empezó el gesto de ahora: lo que un gesto cambió es lo
  /// que decide si es acercar, alejar o solo arrastrar.
  double _gestureStartScale = 1;

  /// El agrandado de las etiquetas para el zoom de ahora: ver [labelScaleFor].
  double _labelScale = 1;

  TopicGraph get _graph => widget.snapshot.graph;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onZoom);
    _offerExport(widget.exportHandle);
    unawaited(_show(warm: false));
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

  @override
  void didUpdateWidget(MapGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exportHandle != widget.exportHandle) {
      _withdrawExport(oldWidget.exportHandle);
      _offerExport(widget.exportHandle);
    }
    if (oldWidget.snapshot.sequence == widget.snapshot.sequence) return;
    // El mapa se recalculó: se rehace el nivel en el que se está, en caliente.
    // Si lo que se miraba ya no existe, se vuelve al panorama.
    final gone =
        _focus.any((id) => _graph.indexOf(id) == null) ||
        (_topicId != null && _graph.indexOf(_topicId!) == null);
    if (gone) {
      _level = GraphLevel.overview;
      _focus = {};
      _topicId = null;
      _needsFit = true;
    }
    unawaited(_show(warm: !gone));
  }

  @override
  void dispose() {
    _withdrawExport(widget.exportHandle);
    _controller
      ..removeListener(_onZoom)
      ..dispose();
    super.dispose();
  }

  /// El nivel de ahora como un documento SVG: los mismos nodos, colores y
  /// uniones que en pantalla, con todas las etiquetas y a su tamaño natural.
  String _exportSvg() {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;
    final svg = SvgWriter(
      width: math.max(_canvas.width, 1),
      height: math.max(_canvas.height, 1),
      background: scheme.surface,
    );

    for (final edge in _scene.edges) {
      final a = _positions[_scene.nodes[edge.a].key];
      final b = _positions[_scene.nodes[edge.b].key];
      if (a == null || b == null) continue;
      final relation = edge.relation;
      final color = mapEdgeColor(edge, scheme);
      svg.line(a, b, color: color, strokeWidth: mapEdgeWidth(edge.weight));
      if (relation != null && (b - a).distance > 40) {
        final head = arrowHead(a, b, back: 22, length: 8, half: 4);
        if (head != null) {
          svg.triangle(head.tip, head.left, head.right, fill: color);
        }
      }
    }

    for (final node in _scene.nodes) {
      final at = _positions[node.key];
      if (at == null) continue;
      final color = _colorOf(node, scheme, brightness);
      final label = switch (node.kind) {
        SceneKind.overflow => l10n.mapGraphOverflow,
        SceneKind.isolated => l10n.mapBoardIsolatedTitle,
        _ => node.label,
      };
      if (node.kind == SceneKind.note || node.kind == SceneKind.source) {
        final role = node.kind == SceneKind.note
            ? EntityRole.note
            : EntityRole.source;
        svg
          ..rect(
            Rect.fromCenter(center: at, width: 150, height: 34),
            fill: role.surface(scheme),
            stroke: role.outline(scheme),
            radius: role.radius,
          )
          ..text(
            SvgWriter.ellipsize(label, 22),
            Offset(at.dx - 75 + 10, at.dy + 4),
            color: scheme.onSurface,
            size: 11,
            anchor: 'start',
          );
        continue;
      }
      final disc = _disc(node);
      final isCommunity =
          node.kind == SceneKind.community ||
          node.kind == SceneKind.overflow ||
          node.kind == SceneKind.isolated;
      svg.circle(
        at,
        disc / 2,
        fill: color.withValues(alpha: isCommunity ? 0.85 : 0.9),
        stroke: scheme.surface,
        strokeWidth: 2,
      );
      if (isCommunity) {
        svg.text(
          '${node.count}',
          at + const Offset(0, 5),
          color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? const Color(0xFFFFFFFF)
              : const Color(0xDD000000),
          size: 14,
          bold: true,
        );
      }
      svg.text(
        SvgWriter.ellipsize(label, 26),
        at + Offset(0, disc / 2 + 14),
        color: scheme.onSurface,
        size: 11,
      );
    }
    return svg.build();
  }

  /// Solo cuando el zoom cruza un escalón se rehacen las etiquetas.
  void _onZoom() {
    final labelScale = labelScaleFor(_controller.value.getMaxScaleOnAxis());
    if (labelScale != _labelScale) setState(() => _labelScale = labelScale);
  }

  /// Arma la escena del nivel actual, la acomoda y la muestra.
  Future<void> _show({required bool warm}) async {
    final generation = ++_generation;
    if (mounted) setState(() => _busy = true);

    final GraphScene scene;
    switch (_level) {
      case GraphLevel.overview:
        scene = sceneOfOverview(
          _graph,
          aggregateCommunities(_graph, widget.snapshot.detection),
        );
      case GraphLevel.topics:
        final focus = {
          for (final id in _focus)
            if (_graph.indexOf(id) case final index?) index,
        };
        scene = sceneOfTopics(
          _graph,
          widget.snapshot.detection,
          selectNeighborhood(_graph, focus: focus),
        );
      case GraphLevel.items:
        final items = await ref
            .read(knowledgeMapRepositoryProvider)
            .readTopicItems(_topicId!);
        scene = sceneOfItems(items);
    }
    if (!mounted || generation != _generation) return;

    // Los que ya tenían lugar parten de él; los nuevos, `NaN`.
    final startX = Float64List(scene.nodes.length);
    final startY = Float64List(scene.nodes.length);
    var known = 0;
    for (var i = 0; i < scene.nodes.length; i++) {
      final at = warm ? _remembered[scene.nodes[i].key] : null;
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
      _scene = scene;
      _rememberAndPlace(layout.xs, layout.ys);
      _busy = false;
    });
  }

  /// Guarda las posiciones y las pone dentro del lienzo, con margen.
  void _rememberAndPlace(Float64List xs, Float64List ys) {
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

  void _fitIfNeeded() {
    if (!_needsFit || _viewport.isEmpty || _positions.isEmpty || _busy) return;
    _needsFit = false;
    _controller.value = computeFitTransform(
      positions: _positions,
      viewportSize: _viewport,
      contentMargin: 90,
      minScale: _kMinScale,
      maxScale: 1.2,
    );
    _fitScale = _gestureStartScale = _controller.value.getMaxScaleOnAxis();
  }

  // --- Navegación entre niveles ---

  void _goTo(GraphLevel level) {
    _level = level;
    _needsFit = true;
    unawaited(_show(warm: false));
  }

  /// Pasa a los temas de la comunidad [node].
  void _openCommunity(SceneNode node, {int? overviewIndex}) {
    final index = overviewIndex ?? _scene.indexOf(node.key)!;
    final overview = aggregateCommunities(_graph, widget.snapshot.detection);
    final members = overview.nodes[index].members;
    _focus = {for (final m in members) _graph.nodes[m].valueId};
    _focusLabel = node.label.isEmpty ? null : node.label;
    _goTo(GraphLevel.topics);
  }

  void _openItems(SceneNode topic) {
    _topicId = topic.ref;
    _topicLabel = topic.label;
    _goTo(GraphLevel.items);
  }

  void _goUp() {
    switch (_level) {
      case GraphLevel.overview:
        return;
      case GraphLevel.topics:
        _focus = {};
        _goTo(GraphLevel.overview);
      case GraphLevel.items:
        _topicId = null;
        _goTo(_focus.isEmpty ? GraphLevel.overview : GraphLevel.topics);
    }
  }

  void _onInteractionStart(ScaleStartDetails details) {
    _gestureStartScale = _controller.value.getMaxScaleOnAxis();
  }

  /// Al soltar un gesto: si cambió el zoom y pasó un umbral, cambia de nivel en
  /// el nodo que quedó en el centro.
  ///
  /// Solo cuenta lo que el gesto cambió: con un nivel grande el encuadre queda
  /// por debajo de [kZoomOutThreshold], y si bastara estar por debajo,
  /// arrastrar el mapa —que no toca el zoom— lo sacaría del nivel.
  void _onInteractionEnd(ScaleEndDetails details) {
    if (_busy || _viewport.isEmpty) return;
    final scale = _controller.value.getMaxScaleOnAxis();
    final change = scale / _gestureStartScale;
    if (scale < kZoomOutThreshold && change < 1 / _kZoomChange) {
      setState(_goUp);
      return;
    }
    final drillAt = math.min(kZoomInThreshold, _fitScale * kZoomInFromFit);
    if (scale <= drillAt || change < _kZoomChange) return;

    final center = _controller.toScene(
      Offset(_viewport.width / 2, _viewport.height / 2),
    );
    SceneNode? nearest;
    var best = double.infinity;
    for (final node in _scene.nodes) {
      final at = _positions[node.key];
      if (at == null) continue;
      final distance = (at - center).distanceSquared;
      if (distance < best) {
        best = distance;
        nearest = node;
      }
    }
    if (nearest != null) _drill(nearest);
  }

  /// Baja un nivel en [node], si hay un nivel más cerca.
  void _drill(SceneNode node) {
    switch (node.kind) {
      case SceneKind.community || SceneKind.overflow || SceneKind.isolated:
        setState(() => _openCommunity(node));
      case SceneKind.topic:
        setState(() => _openItems(node));
      case SceneKind.note || SceneKind.source:
        return;
    }
  }

  Future<void> _onTap(SceneNode node) async {
    switch (node.kind) {
      case SceneKind.community || SceneKind.overflow || SceneKind.isolated:
        setState(() => _openCommunity(node));
      case SceneKind.topic:
        final l10n = AppLocalizations.of(context)!;
        final action = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(node.label),
                  subtitle: Text(l10n.mapItemCount(node.size)),
                ),
                ListTile(
                  key: const ValueKey('map-graph-action-items'),
                  leading: const Icon(Icons.hub_outlined),
                  title: Text(l10n.mapGraphActionItems),
                  onTap: () => Navigator.of(context).pop('items'),
                ),
                ListTile(
                  key: const ValueKey('map-graph-action-material'),
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(l10n.atlasOpenMaterial),
                  onTap: () => Navigator.of(context).pop('material'),
                ),
              ],
            ),
          ),
        );
        if (!mounted) return;
        if (action == 'items') setState(() => _openItems(node));
        if (action == 'material') widget.onOpenTopic(node.ref!);
      case SceneKind.note || SceneKind.source:
        widget.onOpenItem(node.ref!);
    }
  }

  // --- Vínculos ---

  /// Los elementos del tema que se mira y los vínculos entre ellos, tal cual
  /// están dibujados: de ahí salen los candidatos de la IA.
  Future<void> _suggestRelations() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final ids = {
      for (final node in _scene.nodes)
        if (node.ref case final id?) id,
    };
    final links = [
      for (final edge in _scene.edges)
        if (_scene.nodes[edge.a].ref case final from?)
          if (_scene.nodes[edge.b].ref case final to?) (from: from, to: to),
    ];

    // Los títulos y el texto de cada elemento: la escena solo trae el título.
    final loaded = await ref
        .read(libraryRepositoryProvider)
        .list(LibraryQuery(ids: ids));
    if (!mounted) return;

    final failure = loaded.getLeft().toNullable();
    if (failure != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
      return;
    }
    await showAiSuggestRelationsDialog(
      context,
      ref,
      items: loaded.getRight().toNullable() ?? const [],
      links: links,
    );
  }

  // --- Dibujo ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Breadcrumb(
                level: _level,
                focusLabel: _focusLabel,
                topicLabel: _topicLabel,
                onOverview: () => setState(() {
                  _focus = {};
                  _goTo(GraphLevel.overview);
                }),
                onTopics: () => setState(() => _goTo(GraphLevel.topics)),
              ),
            ),
            // Solo con elementos a la vista hay entre qué sugerir.
            if (_level == GraphLevel.items && !_busy && _scene.nodes.length > 1)
              IconButton(
                key: const ValueKey('map-graph-ai-suggest'),
                tooltip: l10n.graphAiSuggestTooltip,
                icon: const Icon(Icons.auto_awesome),
                onPressed: () => unawaited(_suggestRelations()),
              ),
            IconButton(
              key: const ValueKey('map-graph-add-relation'),
              tooltip: l10n.graphAddRelationTooltip,
              icon: const Icon(Icons.add_link),
              onPressed: () => unawaited(showAddRelationFlow(context, ref)),
            ),
          ],
        ),
        if (_level == GraphLevel.overview && !_busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(l10n.mapGraphHint, style: theme.textTheme.bodySmall),
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
                  key: const ValueKey('map-graph-canvas'),
                  transformationController: _controller,
                  constrained: false,
                  minScale: _kMinScale,
                  maxScale: 4,
                  boundaryMargin: const EdgeInsets.all(800),
                  onInteractionStart: _onInteractionStart,
                  onInteractionEnd: _onInteractionEnd,
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
                                // Miles de líneas que no cambian mientras se
                                // arrastra: que el motor las guarde dibujadas.
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
                                _placed(context, node, at),
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
        if (_scene.hidden > 0 && _level == GraphLevel.topics)
          _Footnote(
            key: const ValueKey('map-graph-cut'),
            text: l10n.mapGraphTopicsCut(
              _scene.nodes.length,
              _scene.nodes.length + _scene.hidden,
            ),
          ),
        if (_scene.hiddenEdges > 0 && _level == GraphLevel.topics)
          _Footnote(
            key: const ValueKey('map-graph-edges-cut'),
            text: l10n.mapGraphEdgesCut(
              _scene.edges.length,
              _scene.edges.length + _scene.hiddenEdges,
            ),
          ),
        if (_scene.hidden > 0 && _level == GraphLevel.items)
          _Footnote(
            key: const ValueKey('map-graph-cut'),
            text: l10n.mapGraphItemsCut(_scene.nodes.length),
          ),
      ],
    );
  }

  Widget _placed(BuildContext context, SceneNode node, Offset at) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final size = _sizeOf(node);
    final color = _colorOf(node, colors, brightness);
    final label = switch (node.kind) {
      SceneKind.overflow => l10n.mapGraphOverflow,
      SceneKind.isolated => l10n.mapBoardIsolatedTitle,
      _ => node.label,
    };
    final semantics = switch (node.kind) {
      SceneKind.community => l10n.mapGraphCommunitySemantics(
        node.label,
        node.count,
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
        excludeSemantics: true,
        onTap: () => unawaited(_onTap(node)),
        child: GestureDetector(
          key: ValueKey('map-graph-node-${node.key}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_onTap(node)),
          child: _NodeBody(
            node: node,
            label: label,
            color: color,
            labelScale: _labelScale,
          ),
        ),
      ),
    );
  }
}

/// El tamaño de la caja de un nodo, con su etiqueta.
Size _sizeOf(SceneNode node) => switch (node.kind) {
  SceneKind.community ||
  SceneKind.overflow ||
  SceneKind.isolated => Size(math.max(_disc(node), 120), _disc(node) + 22),
  SceneKind.topic => Size(math.max(_disc(node), 96), _disc(node) + 18),
  SceneKind.note || SceneKind.source => const Size(150, 34),
};

/// El diámetro del círculo de un nodo, que crece con su peso.
double _disc(SceneNode node) => switch (node.kind) {
  SceneKind.community ||
  SceneKind.overflow ||
  SceneKind.isolated => (30 + 7 * math.sqrt(node.size)).clamp(30, 110),
  SceneKind.topic => (16 + 5 * math.sqrt(node.size)).clamp(16, 60),
  _ => 0,
};

/// El color de un nodo: el de su comunidad, que no cambia mientras la
/// comunidad exista; sin comunidad, uno neutro.
Color _colorOf(SceneNode node, ColorScheme colors, Brightness brightness) {
  switch (node.kind) {
    case SceneKind.note:
      return EntityRole.note.accent(colors);
    case SceneKind.source:
      return EntityRole.source.accent(colors);
    case SceneKind.overflow || SceneKind.isolated:
      return colors.outline;
    case SceneKind.community || SceneKind.topic:
      final group = node.group;
      if (group == null) return colors.outline;
      // Los tonos se reparten con el ángulo áureo: identidades seguidas quedan
      // lejos en la rueda de colores.
      final hue = (group * 137.508) % 360;
      return HSLColor.fromAHSL(
        1,
        hue,
        0.55,
        brightness == Brightness.dark ? 0.62 : 0.46,
      ).toColor();
  }
}

class _NodeBody extends StatelessWidget {
  const _NodeBody({
    required this.node,
    required this.label,
    required this.color,
    required this.labelScale,
  });

  final SceneNode node;
  final String label;
  final Color color;

  /// El agrandado de la etiqueta: ver [labelScaleFor].
  final double labelScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (node.kind == SceneKind.note || node.kind == SceneKind.source) {
      final role = node.kind == SceneKind.note
          ? EntityRole.note
          : EntityRole.source;
      final colors = theme.colorScheme;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: role.surface(colors),
          border: Border.all(color: role.outline(colors)),
          borderRadius: BorderRadius.circular(role.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(
                node.kind == SceneKind.note
                    ? Icons.sticky_note_2_outlined
                    : Icons.article_outlined,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final disc = _disc(node);
    final isCommunity =
        node.kind == SceneKind.community ||
        node.kind == SceneKind.overflow ||
        node.kind == SceneKind.isolated;
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
              border: Border.all(color: theme.colorScheme.surface, width: 2),
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
              ),
            ),
        ],
      ),
    );
  }
}

/// El camino: comunidades › lo que se está mirando › tema.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.level,
    required this.focusLabel,
    required this.topicLabel,
    required this.onOverview,
    required this.onTopics,
  });

  final GraphLevel level;
  final String? focusLabel;
  final String? topicLabel;
  final VoidCallback onOverview;
  final VoidCallback onTopics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final crumbs = <(String, GraphLevel, VoidCallback?)>[
      (l10n.mapGraphCrumbOverview, GraphLevel.overview, onOverview),
      if (level != GraphLevel.overview && focusLabel != null)
        (focusLabel!, GraphLevel.topics, onTopics),
      if (level == GraphLevel.items && topicLabel != null)
        (topicLabel!, GraphLevel.items, null),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0) const Icon(Icons.chevron_right, size: 16),
            ActionChip(
              key: ValueKey('map-graph-crumb-${crumbs[i].$2.name}'),
              label: Text(crumbs[i].$1),
              onPressed: i == crumbs.length - 1 ? null : crumbs[i].$3,
              visualDensity: VisualDensity.compact,
            ),
          ],
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
      padding: const EdgeInsets.all(8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
