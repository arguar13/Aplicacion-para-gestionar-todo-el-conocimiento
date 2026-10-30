import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/design/widgets/topic_dimension_menu.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:sinapsis/features/graph/presentation/widgets/ai_suggest_relations_dialog.dart';
import 'package:sinapsis/features/graph/presentation/widgets/degree_selector.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/link_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';
import 'package:sinapsis/features/map/domain/services/link_strength.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layout_runner.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/arrow_head.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_chrome.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_motion.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_network.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_tree.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_viewport.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_canvas_list.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_minimap.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_root_picker.dart';
import 'package:sinapsis/features/map/presentation/widgets/link_strength_selector.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_export_handle.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_node_size.dart';
import 'package:sinapsis/features/organize/presentation/widgets/add_relation_flow.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Con más zoom que esto, se pasa a la altura de más detalle del nodo del
/// centro.
const kZoomInThreshold = 2.2;

/// Con menos zoom que esto, se vuelve a la altura de menos detalle.
const kZoomOutThreshold = 0.42;

/// Acercarse a este múltiplo del encuadre de la altura pasa a la siguiente
/// aunque no se llegue a [kZoomInThreshold]: una altura grande queda
/// encuadrada tan alejada que ese umbral pediría un zoom enorme.
const kZoomInFromFit = 3.0;

/// El zoom más lejano del visor, y hasta donde llega el encuadre: una altura
/// con cientos de nodos cabe entera en un celular a un zoom muy chico.
const _kMinScale = 0.05;
const _kMaxScale = 4.0;

/// Cuánto tiene que cambiar el zoom en un gesto para que cuente como acercar o
/// alejar. Menos que esto es arrastrar, y arrastrar no cambia de altura.
const _kZoomChange = 1.05;

/// Cuánto puede cambiar el zoom desde que se capturó `_gestureSnapshot` antes
/// de que se vea inaceptablemente borroso: a partir de acá se recaptura una
/// vez a mitad del gesto (F18, 18.2).
const _kMaxSnapshotZoomChange = 2.0;

/// Iteraciones del layout desde cero, y en caliente: con lo ya acomodado
/// alcanzan unas pocas.
const _kColdIterations = 260;
const _kWarmIterations = 60;

const _kCanvasMargin = 120.0;

/// Hasta cuánto se agranda la letra adentro del lienzo: el lienzo se acerca
/// con el zoom, y sus cajas tienen un tamaño fijo para el layout. La letra
/// entera la sigue «Ver como lista».
const _kCanvasMaxTextScale = 1.5;

/// Lo más que ocupan, del alto del lienzo, lo de arriba —las migas y lo que se
/// elige— y las notas de abajo: el resto es del dibujo.
const _kMaxChromeShare = 0.4;
const _kMaxFootnotesShare = 0.2;

/// Lo menos que necesitan las migas al lado de los botones.
const _kMinCrumbsWidth = 140.0;

/// La comunidad —o el conjunto de temas— que se mira a la altura de los
/// temas, como raíz de Radial y Árbol.
const _kFocusId = 'focus';

/// El lienzo único del Mapa (F44, paso 2): lo que eran el Grafo, el Esquema y
/// la vista «Vínculos», en un solo dibujo que se recorre con el zoom.
///
/// - **Tres alturas**: de lejos, las comunidades; al tocar una o acercarse,
///   sus temas **salen de la burbuja**; otro toque o más zoom en un tema
///   despliega sus documentos. Alejarse los recoge de vuelta. Con «sin
///   animaciones», el cambio es directo.
/// - **Las migas** dicen dónde se está y llevan a cualquier altura anterior.
/// - **Red · Radial · Árbol**: la red de fuerzas de siempre, o el despliegue
///   nodo a nodo del Esquema sobre lo que se mira —con las notas mapa como
///   raíz posible y cada vínculo rotulado con su tipo y su flecha—.
/// - **El minimapa** y **⊕ ⊖ ⛶**, exportar a PNG y SVG, y **«Ver como
///   lista»** para el lector de pantalla.
/// - **Los vínculos entre documentos** —tengan o no tema, con su filtro de
///   fuerza, los sueltos y el foco de «Ver en el Mapa»— se prenden con su
///   botón, al lado de la disposición: es el lugar provisorio de lo que en la
///   ola 2 es la capa «Vínculos».
///
/// Nunca dibuja miles de nodos: las comunidades son a lo sumo 60, los temas
/// 300 y los documentos 200. Lo acomoda el layout de fuerzas en otro isolate,
/// en caliente cuando el mapa se recalcula, y durante un gesto pinta una
/// captura del dibujo en vez de recorrerlo (F18).
///
/// Los ganchos de la ola 2: tocar un nodo pasa por `_select` —donde va la
/// ficha—, el resaltado de `_highlight` es el lugar del foco, y la búsqueda y
/// el Resumen llegan por `mapCanvasRequestProvider`.
class MapCanvasView extends ConsumerStatefulWidget {
  const MapCanvasView({
    required this.snapshot,
    required this.dimension,
    required this.filter,
    required this.onOpenTopic,
    required this.onOpenItem,
    this.exportHandle,
    super.key,
  });

  final KnowledgeMapSnapshot snapshot;

  /// Qué se mira: los textos dicen «temas», «etiquetas» o «valores» (F28).
  final TopicDimension dimension;

  /// Los filtros del Mapa, para los vínculos entre documentos.
  final LibraryQuery filter;
  final void Function(String valueId) onOpenTopic;
  final void Function(String itemId) onOpenItem;

  /// Donde el lienzo ofrece su dibujo para exportarlo, si alguien lo quiere.
  final MapExportHandle? exportHandle;

  @override
  ConsumerState<MapCanvasView> createState() => _MapCanvasViewState();
}

class _MapCanvasViewState extends ConsumerState<MapCanvasView>
    with SingleTickerProviderStateMixin {
  // --- Lo que se mira ---

  MapAltitude _altitude = MapAltitude.communities;
  MapArrangement _arrangement = MapArrangement.network;
  bool _asList = false;

  /// Si se miran los documentos vinculados entre sí, tengan o no tema.
  bool _links = false;

  /// Los temas de la comunidad que se mira, por valor; vacío, todos.
  Set<String> _focus = {};
  String? _focusLabel;
  int? _focusGroup;

  /// Hasta cuántos saltos del foco se ven sus temas: el «Grado» —0, 1, 2 o
  /// todos (`null`)—. Arranca en 1, lo que se veía antes.
  int? _degree = 1;

  /// El tema cuyos documentos se miran, por valor.
  String? _topicId;
  String? _topicLabel;

  /// El documento en el que se pidió poner el foco entre los vinculados.
  String? _linksFocusId;
  LinkStrengthFilter _strength = LinkStrengthFilter.all;

  /// El nodo que se pidió mirar —por clave de la escena—: se resalta y se
  /// encuadra con sus vecinos. Es el lugar del foco de la ola 2.
  String? _highlight;

  // --- Lo que se leyó ---

  late CommunityOverview _overview;
  TopicSelection? _selection;
  TopicItemsGraph? _topicItems;
  LinkGraph? _linkGraph;
  bool _linksFailed = false;
  ProviderSubscription<AsyncValue<LinkGraph>>? _linksSubscription;

  // --- La red ---

  GraphScene _scene = const GraphScene.empty();
  Map<String, Offset> _positions = {};
  Size _canvas = Size.zero;

  /// La última posición de cada nodo, para arrancar en caliente.
  final Map<String, Offset> _remembered = {};

  /// Para descartar lo que llega de un cálculo que ya no vale.
  int _generation = 0;
  bool _busy = true;

  // --- Radial, Árbol y la lista ---

  /// Una raíz elegida a mano —un tema o una nota mapa—, en lugar de lo que se
  /// mira.
  MapRootChoice? _rootOverride;
  CanvasTreeRef? _treeRootShown;
  Set<String> _expanded = {};

  /// Lo que la base trajo de cada tema o documento desplegado, por clave.
  final Map<String, List<CanvasTreeLink>> _fetched = {};
  CanvasTree? _tree;
  CanvasTree? _listTree;
  Map<String, Offset> _treePositions = {};
  Size _treeCanvas = Size.zero;

  // --- El visor ---

  final _controller = TransformationController();
  final _boundaryKey = GlobalKey();
  Size _viewport = Size.zero;
  bool _needsFit = true;

  /// El zoom con el que quedó encuadrada la altura de ahora.
  double _fitScale = 1;

  /// El zoom con el que empezó el gesto de ahora: lo que un gesto cambió es lo
  /// que decide si es acercar, alejar o solo arrastrar.
  double _gestureStartScale = 1;

  /// El agrandado de las etiquetas para el zoom de ahora.
  double _labelScale = 1;

  /// Lo ya dibujado, capturado al empezar un arrastre o un zoom (F18, 18.2):
  /// moverlo es mucho más barato que recorrer cientos de nodos en cada cuadro.
  /// `null` fuera de un gesto, o si la captura falló.
  ui.Image? _gestureSnapshot;

  /// El zoom con el que se capturó [_gestureSnapshot].
  double _snapshotScale = 1;

  /// Si hay un gesto en curso: una captura que resuelve con el gesto ya
  /// terminado se descarta sin mostrarla.
  bool _gesturing = false;

  // --- El movimiento entre alturas ---

  late final AnimationController _motionController;
  CanvasMotion? _motion;

  /// Dónde estaba, en la pantalla, lo que se tocó para entrar: de ahí sale lo
  /// nuevo.
  Offset? _emergeFrom;

  /// Si lo que llegue se enciende al aparecer.
  bool _fadeInNext = false;

  /// Lo que se miraba recogiéndose, mientras llega lo de arriba.
  Future<void>? _collapsing;

  TopicGraph get _graph => widget.snapshot.graph;
  KnowledgeMapRepository get _repository =>
      ref.read(knowledgeMapRepositoryProvider);
  String get _topicKind => topicSelectKind(widget.dimension);
  bool get _isTree => _arrangement != MapArrangement.network;

  @override
  void initState() {
    super.initState();
    _overview = aggregateCommunities(_graph, widget.snapshot.detection);
    _controller.addListener(_onZoom);
    _motionController = AnimationController(
      vsync: this,
      duration: kCanvasMotionDuration,
    )..addStatusListener(_onMotionStatus);
    _offerExport(widget.exportHandle);
    // Un pedido que llega con el lienzo abierto se atiende en el acto; uno que
    // llegó con el lienzo cerrado —una fila del Resumen, que lo abre—, en
    // `didChangeDependencies`: atenderlo rotula lo que se mira con los textos
    // del idioma, y en `initState` todavía no se pueden leer.
    ref.listenManual(mapCanvasRequestProvider, (_, request) {
      if (request != null) _apply(request);
    });
  }

  /// Si ya se atendió lo que había al abrirse el lienzo.
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final pending = ref.read(mapCanvasRequestProvider);
    if (pending != null) {
      _apply(pending);
    } else {
      unawaited(_show());
    }
  }

  @override
  void didUpdateWidget(MapCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exportHandle != widget.exportHandle) {
      _withdrawExport(oldWidget.exportHandle);
      _offerExport(widget.exportHandle);
    }
    if (oldWidget.filter != widget.filter && _links) {
      _needsFit = true;
      _listenLinks();
    }
    if (oldWidget.snapshot.sequence == widget.snapshot.sequence) return;
    // El mapa se recalculó: se rehace la altura en la que se está, en
    // caliente. Si lo que se miraba ya no existe, se vuelve a las
    // comunidades.
    _overview = aggregateCommunities(_graph, widget.snapshot.detection);
    final gone =
        _focus.any((id) => _graph.indexOf(id) == null) ||
        (_topicId != null && _graph.indexOf(_topicId!) == null);
    if (gone) {
      _altitude = MapAltitude.communities;
      _focus = {};
      _topicId = null;
      _highlight = null;
      _needsFit = true;
    }
    final override = _rootOverride?.ref;
    if (override != null &&
        override.kind == CanvasTreeKind.topic &&
        _graph.indexOf(override.id) == null) {
      _rootOverride = null;
    }
    _topicItems = null;
    _fetched.clear();
    unawaited(_show(warm: !gone));
  }

  @override
  void dispose() {
    _linksSubscription?.close();
    _withdrawExport(widget.exportHandle);
    _controller
      ..removeListener(_onZoom)
      ..dispose();
    _motionController.dispose();
    _gestureSnapshot?.dispose();
    super.dispose();
  }

  // --- Los pedidos de afuera ---

  /// Atiende [request] y lo da por atendido. Un proveedor no se modifica
  /// mientras se arma el árbol: se vuelve a `null` apenas termina.
  void _apply(MapCanvasRequest request) {
    switch (request) {
      case MapShowLinks(:final focusId):
        _links = true;
        _linksFocusId = focusId;
        _highlight = focusId == null ? null : 'item:$focusId';
        _rootOverride = null;
        _listenLinks();
      case MapShowAltitude(:final altitude):
        _highlight = null;
        switch (altitude) {
          case MapAltitude.communities:
            _resetToCommunities();
          case MapAltitude.topics:
            _stopLinks();
            _altitude = MapAltitude.topics;
            _focus = {};
            _focusLabel = null;
            _focusGroup = null;
            _topicId = null;
          // Sin un tema que abrir, los documentos que se pueden mirar
          // todos juntos son los vinculados.
          case MapAltitude.documents:
            _links = true;
            _linksFocusId = null;
            _listenLinks();
        }
      case MapShowTopic(:final valueId):
        _stopLinks();
        _openCommunityOf(valueId);
        _highlight = 'topic:$valueId';
    }
    _rootOverride = null;
    _needsFit = true;
    unawaited(_show());
    scheduleMicrotask(() {
      if (!mounted) return;
      ref.read(mapCanvasRequestProvider.notifier).state = null;
    });
  }

  /// Los temas de la comunidad donde está [valueId]; todos, si no está en
  /// ninguna que se dibuje.
  void _openCommunityOf(String valueId) {
    final index = _graph.indexOf(valueId);
    _altitude = MapAltitude.topics;
    _topicId = null;
    _focus = {};
    _focusLabel = null;
    _focusGroup = null;
    if (index == null) return;
    for (var i = 0; i < _overview.nodes.length; i++) {
      final node = _overview.nodes[i];
      if (!node.members.contains(index)) continue;
      _focus = {for (final m in node.members) _graph.nodes[m].valueId};
      final scene = sceneOfOverview(_graph, _overview).nodes[i];
      _focusLabel = _labelOf(scene);
      _focusGroup = scene.group;
      return;
    }
  }

  void _resetToCommunities() {
    _stopLinks();
    _altitude = MapAltitude.communities;
    _focus = {};
    _focusLabel = null;
    _focusGroup = null;
    _topicId = null;
    _topicItems = null;
  }

  // --- Los vínculos entre documentos ---

  /// Cada vez que llegan vínculos nuevos, los acomoda. Un oyente y no un
  /// `watch` en `build`: acomodar es asíncrono y no se hace al dibujar.
  void _listenLinks() {
    _linksSubscription?.close();
    _linksFailed = false;
    final request = (
      filter: widget.filter,
      focusId: _linksFocusId,
      strength: _strength,
    );
    _linksSubscription = ref.listenManual(mapLinksProvider(request), (_, next) {
      switch (next) {
        case AsyncData(:final value):
          final first = _linkGraph == null;
          _linkGraph = value;
          _linksFailed = false;
          // Un vínculo nuevo cambia lo que cuelga de cada documento.
          _fetched.removeWhere((key, _) => key.startsWith('item:'));
          if (_links) unawaited(_show(warm: !first));
        case AsyncError():
          if (_linkGraph == null && mounted) {
            setState(() => _linksFailed = true);
          }
        default:
      }
    }, fireImmediately: true);
  }

  void _stopLinks() {
    _links = false;
    _linksSubscription?.close();
    _linksSubscription = null;
    _linkGraph = null;
    _linksFocusId = null;
  }

  void _setLinks(bool on) {
    setState(() {
      _stopLinks();
      _highlight = null;
      _rootOverride = null;
      _needsFit = true;
      _fadeInNext = true;
    });
    if (on) {
      // Lo que se dibuja llega con la suscripción.
      _links = true;
      _listenLinks();
    } else {
      unawaited(_show());
    }
  }

  // --- La exportación ---

  void _offerExport(MapExportHandle? handle) {
    if (handle == null) return;
    if (_asList) {
      _withdrawExport(handle);
      return;
    }
    handle
      ..png = (() => capturePng(_boundaryKey))
      ..svg = _exportSvg
      ..subject = (() => (arrangement: _arrangement.slug, links: _links));
  }

  void _withdrawExport(MapExportHandle? handle) {
    handle
      ?..png = null
      ..svg = null
      ..subject = null;
  }

  /// Lo que se ve, como un documento SVG.
  String _exportSvg() {
    final theme = Theme.of(context);
    final tree = _tree;
    if (_isTree && tree != null) {
      return treeSvg(
        tree: tree,
        positions: _treePositions,
        canvas: _treeCanvas,
        colors: theme.colorScheme,
        brightness: theme.brightness,
        l10n: AppLocalizations.of(context)!,
      );
    }
    return networkSvg(
      scene: _scene,
      positions: _positions,
      canvas: _canvas,
      colors: theme.colorScheme,
      brightness: theme.brightness,
      labelOf: _labelOf,
      highlighted: {?_highlight},
    );
  }

  // --- Armar lo que se mira ---

  /// Cómo se rotula un nodo de la red: una comunidad, con sus dos temas
  /// principales («Cristianismo · Tomás de Aquino», F44, paso 1) —o con su
  /// tema más unido si el motor no lo calculó—; los que juntan varias
  /// comunidades no tienen nombre propio.
  String _labelOf(SceneNode node) {
    final l10n = AppLocalizations.of(context)!;
    return switch (node.kind) {
      SceneKind.overflow => l10n.mapGraphOverflow,
      SceneKind.isolated => l10n.mapBoardIsolatedTitle(_topicKind),
      SceneKind.community => switch (node.group) {
        final group? => _communityName(group) ?? node.label,
        null => node.label,
      },
      _ => node.label,
    };
  }

  String? _communityName(int communityId) {
    final name = widget.snapshot.insights.communities.of(communityId)?.name;
    return name == null || name.isEmpty ? null : name;
  }

  TopicSelection _selectTopics() {
    if (_focus.isEmpty) return selectTopics(_graph);
    final focus = {
      for (final id in _focus)
        if (_graph.indexOf(id) case final index?) index,
    };
    return selectNeighborhood(_graph, focus: focus, degree: _degree);
  }

  /// Arma lo que se mira ahora, lo acomoda y lo muestra.
  Future<void> _show({bool warm = false}) async {
    final generation = ++_generation;
    if (mounted) setState(() => _busy = true);

    final GraphScene scene;
    if (_links) {
      final graph = _linkGraph;
      // Llega con la suscripción, que vuelve a llamar.
      if (graph == null) return;
      scene = sceneOfLinks(graph);
    } else {
      switch (_altitude) {
        case MapAltitude.communities:
          _selection = null;
          scene = sceneOfOverview(_graph, _overview);
        case MapAltitude.topics:
          final selection = _selection = _selectTopics();
          scene = sceneOfTopics(_graph, widget.snapshot.detection, selection);
        case MapAltitude.documents:
          final items =
              _topicItems ??
              await _repository.readTopicItems(
                _topicId!,
                dimensionId: widget.snapshot.request.definitionId,
              );
          if (!mounted || generation != _generation) return;
          _topicItems = items;
          scene = sceneOfItems(items);
      }
    }

    ({Float64List xs, Float64List ys})? placed;
    if (!_isTree) {
      final layout = await _layout(scene, warm: warm);
      if (!mounted || generation != _generation) return;
      placed = (xs: layout.xs, ys: layout.ys);
    }

    // Lo de antes termina de recogerse antes de que aparezca lo nuevo.
    if (_collapsing case final collapsing?) {
      await collapsing;
      if (!mounted || generation != _generation) return;
    }

    setState(() {
      _motion = null;
      _scene = scene;
      if (placed != null) _rememberAndPlace(placed.xs, placed.ys);
      _rebuildTree();
      _busy = false;
    });
    _fitIfNeeded();
    _startArrival();
  }

  Future<({Float64List xs, Float64List ys})> _layout(
    GraphScene scene, {
    required bool warm,
  }) async {
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
      widths: Float64List.fromList([
        for (final node in scene.nodes) mapNodeSize(node).width,
      ]),
      heights: Float64List.fromList([
        for (final node in scene.nodes) mapNodeSize(node).height,
      ]),
    ));
    return (xs: layout.xs, ys: layout.ys);
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

  // --- Radial, Árbol y la lista ---

  /// La raíz del árbol de lo que se mira: lo que eligió la persona, o lo que
  /// se mira —todo, la comunidad, el tema, lo vinculado o el documento en
  /// foco—.
  ({CanvasTreeRef ref, String title, int? group}) _treeRoot() {
    final l10n = AppLocalizations.of(context)!;
    if (_rootOverride case final override?) {
      return (ref: override.ref, title: override.title, group: null);
    }
    if (_links) {
      final focus = _linkGraph?.focusId;
      final title = _linkGraph?.items
          .where((item) => item.id == focus)
          .firstOrNull
          ?.title;
      if (focus != null && title != null) {
        return (ref: CanvasTreeRef.item(focus), title: title, group: null);
      }
      return (
        ref: const CanvasTreeRef.links(),
        title: l10n.f44S2CrumbLinks,
        group: null,
      );
    }
    return switch (_altitude) {
      MapAltitude.communities => (
        ref: const CanvasTreeRef.all(),
        title: l10n.f44S2CrumbAll,
        group: null,
      ),
      MapAltitude.topics => (
        ref: const CanvasTreeRef.community(_kFocusId),
        title: _focusLabel ?? l10n.f44S2CrumbAllTopics(_topicKind),
        group: _focusGroup,
      ),
      MapAltitude.documents => (
        ref: CanvasTreeRef.topic(_topicId!),
        title: _topicLabel ?? _topicId!,
        group: null,
      ),
    };
  }

  /// Lo que el lienzo ya sabe de los nodos que arma él, y de la raíz.
  Map<String, List<CanvasTreeLink>> _treeLinks(CanvasTreeRef root) {
    final links = <String, List<CanvasTreeLink>>{..._fetched};
    List<CanvasTreeLink> topicsOf(Iterable<int> members) => [
      for (final m in rootTopicsAmong(_graph, members))
        CanvasTreeLink(
          target: CanvasTreeRef.topic(_graph.nodes[m].valueId),
          title: _graph.nodes[m].label,
          edge: CanvasTreeEdge.member,
        ),
    ];
    switch (root.kind) {
      case CanvasTreeKind.all:
        final scene = sceneOfOverview(_graph, _overview);
        links[root.key] = [
          for (var i = 0; i < _overview.nodes.length; i++)
            CanvasTreeLink(
              target: CanvasTreeRef.community('$i'),
              title: _labelOf(scene.nodes[i]),
              edge: CanvasTreeEdge.member,
              group: scene.nodes[i].group,
              count: scene.nodes[i].count,
            ),
        ];
        for (var i = 0; i < _overview.nodes.length; i++) {
          links['community:$i'] = topicsOf(_overview.nodes[i].members);
        }
      case CanvasTreeKind.community:
        links[root.key] = topicsOf(_selection?.topics ?? const []);
      case CanvasTreeKind.links:
        links[root.key] = [
          for (final item in _linkGraph?.items ?? const <TopicItemNode>[])
            CanvasTreeLink(
              target: CanvasTreeRef.item(item.id),
              title: item.title,
              edge: CanvasTreeEdge.member,
              isNote: item.isNote,
            ),
        ];
      case CanvasTreeKind.topic:
        // Los documentos del tema que se mira son los mismos de la red.
        if (_altitude == MapAltitude.documents && root.id == _topicId) {
          links[root.key] = [
            ...?_fetched[root.key],
            for (final item in _topicItems?.items ?? const <TopicItemNode>[])
              CanvasTreeLink(
                target: CanvasTreeRef.item(item.id),
                title: item.title,
                edge: CanvasTreeEdge.member,
                isNote: item.isNote,
              ),
          ];
        }
      case CanvasTreeKind.item:
    }
    return links;
  }

  /// Arma el árbol con lo que hay ahora y, si se dibuja, su forma.
  void _rebuildTree() {
    if (!_isTree && !_asList) return;
    final root = _treeRoot();
    if (root.ref != _treeRootShown) {
      _treeRootShown = root.ref;
      _expanded = {root.ref.key};
      _needsFit = true;
      if (root.ref.schemaRef != null && !_fetched.containsKey(root.ref.key)) {
        unawaited(_fetch(root.ref));
      }
    }
    final links = _treeLinks(root.ref);
    CanvasTree build(int maxNodes) => buildCanvasTree(
      root: root.ref,
      rootTitle: root.title,
      rootGroup: root.group,
      graph: _graph,
      expanded: _expanded,
      links: links,
      groupOf: _groupOfTopic,
      maxNodes: maxNodes,
    );
    final tree = _tree = build(kMaxCanvasTreeNodes);
    _listTree = _asList ? build(kMaxCanvasListNodes) : null;
    final placed = placeCanvasTree(tree, _arrangement);
    _treePositions = placed.positions;
    _treeCanvas = placed.canvas;
  }

  int? _groupOfTopic(String valueId) {
    final index = _graph.indexOf(valueId);
    return index == null ? null : widget.snapshot.detection.communityOf[index];
  }

  /// Pide a la base lo que cuelga de [node] —las notas mapa y los documentos
  /// de un tema, o los vínculos de un documento—, y lo suma al árbol si sigue
  /// desplegado cuando llega.
  Future<void> _fetch(CanvasTreeRef node) async {
    final schema = node.schemaRef!;
    final dimensionId = widget.snapshot.request.definitionId;
    final List<CanvasTreeLink> links;
    if (node.kind == CanvasTreeKind.topic) {
      // Los documentos del tema que se mira ya llegaron para la red: no se
      // piden otra vez.
      final known = _altitude == MapAltitude.documents && node.id == _topicId
          ? _topicItems
          : null;
      final (notes, items) = await (
        _repository.schemaLinks(schema, dimensionId: dimensionId),
        known != null
            ? Future.value(known)
            : _repository.readTopicItems(
                node.id,
                dimensionId: dimensionId,
                limit: kSchemaFanOut,
              ),
      ).wait;
      links = [
        ...notes.map(CanvasTreeLink.fromSchema),
        for (final item in items.items)
          CanvasTreeLink(
            target: CanvasTreeRef.item(item.id),
            title: item.title,
            edge: CanvasTreeEdge.member,
            isNote: item.isNote,
          ),
      ];
    } else {
      final fetched = await _repository.schemaLinks(
        schema,
        dimensionId: dimensionId,
      );
      links = [for (final link in fetched) CanvasTreeLink.fromSchema(link)];
    }
    if (!mounted || !_expanded.contains(node.key)) return;
    setState(() {
      _fetched[node.key] = links;
      _rebuildTree();
    });
    _fitIfNeeded();
  }

  /// Despliega o pliega [entry], con él quieto en la pantalla: lo demás se
  /// acomoda alrededor, sin que el dibujo salte.
  void _toggle(CanvasTreeEntry entry) {
    final expanding = !_expanded.contains(entry.key);
    final before = _treePositions[entry.key];
    setState(() {
      _expanded = {..._expanded};
      if (expanding) {
        _expanded.add(entry.key);
      } else {
        _expanded.remove(entry.key);
      }
      _rebuildTree();
    });
    final after = _treePositions[entry.key];
    if (before != null && after != null && !_asList) {
      final delta = (before - after) * _controller.value.getMaxScaleOnAxis();
      _controller.value = Matrix4.identity()
        ..translateByDouble(delta.dx, delta.dy, 0, 1)
        ..multiply(_controller.value);
    }
    final schema = entry.ref.schemaRef;
    if (expanding && schema != null && !_fetched.containsKey(entry.key)) {
      unawaited(_fetch(entry.ref));
    }
  }

  Future<void> _pickRoot() async {
    final chosen = await showMapRootPicker(
      context,
      graph: _graph,
      notes: _repository.readMapNotes(),
      topicKind: _topicKind,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _rootOverride = chosen;
      _rebuildTree();
    });
    _fitIfNeeded();
  }

  void _resetRoot() {
    setState(() {
      _rootOverride = null;
      _rebuildTree();
    });
    _fitIfNeeded();
  }

  /// Cómo se abre —o en qué se entra— desde un nodo del árbol o una fila de la
  /// lista.
  ({VoidCallback onOpen, String tooltip})? _openOf(CanvasTreeEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    final id = entry.ref.id;
    return switch (entry.ref.kind) {
      CanvasTreeKind.all || CanvasTreeKind.links => null,
      CanvasTreeKind.community =>
        id == _kFocusId
            ? null
            : (
                onOpen: () => _enterCommunityAt(int.parse(id)),
                tooltip: l10n.f44S2EnterCommunity(entry.title),
              ),
      CanvasTreeKind.topic => (
        onOpen: () => widget.onOpenTopic(id),
        tooltip: l10n.atlasOpenMaterial,
      ),
      CanvasTreeKind.item => (
        onOpen: () => widget.onOpenItem(id),
        tooltip: l10n.mapSchemaOpen,
      ),
    };
  }

  // --- El encuadre ---

  Map<String, Offset> get _drawnPositions =>
      _isTree ? _treePositions : _positions;

  void _fitIfNeeded() {
    if (!_needsFit || _viewport.isEmpty || _busy) return;
    final positions = _framed();
    if (positions.isEmpty) return;
    _needsFit = false;
    _fitTo(positions);
  }

  void _fitTo(Map<String, Offset> positions) {
    _controller.value = computeFitTransform(
      positions: positions,
      viewportSize: _viewport,
      contentMargin: _isTree ? kTreeNodeSize.width : 90,
      minScale: _kMinScale,
      maxScale: 1.2,
    );
    _fitScale = _gestureStartScale = _controller.value.getMaxScaleOnAxis();
  }

  /// Lo dibujado entero o, con algo resaltado, eso y sus vecinos directos: lo
  /// que se pidió mirar queda en el centro y legible.
  Map<String, Offset> _framed() {
    final positions = _drawnPositions;
    final highlight = _highlight;
    if (_isTree || highlight == null) return positions;
    final index = _scene.indexOf(highlight);
    if (index == null) return positions;
    final keys = {highlight};
    for (final edge in _scene.edges) {
      if (edge.a == index) keys.add(_scene.nodes[edge.b].key);
      if (edge.b == index) keys.add(_scene.nodes[edge.a].key);
    }
    return {
      for (final key in keys)
        if (positions[key] case final at?) key: at,
    };
  }

  void _zoomBy(double factor) {
    if (_viewport.isEmpty) return;
    _controller.value = zoomAround(
      _controller.value,
      factor,
      _viewport.center(Offset.zero),
      minScale: _kMinScale,
      maxScale: _kMaxScale,
    );
  }

  void _fitAll() {
    final positions = _drawnPositions;
    if (positions.isEmpty || _viewport.isEmpty) return;
    _fitTo(positions);
  }

  // --- El movimiento entre alturas ---

  bool get _animate =>
      mounted && !MediaQuery.disableAnimationsOf(context) && !_asList;

  /// Lo que acaba de llegar sale de la burbuja que se tocó, o se enciende.
  void _startArrival() {
    final from = _emergeFrom;
    _emergeFrom = null;
    final fade = _fadeInNext;
    _fadeInNext = false;
    if (!_animate) return;
    final positions = _drawnPositions;
    if (positions.isEmpty) return;
    final CanvasMotion motion;
    if (from != null && !_isTree) {
      final origin = MatrixUtils.transformPoint(
        Matrix4.inverted(_controller.value),
        from,
      );
      motion = CanvasMotion.emerge(origin, positions);
    } else if (fade) {
      motion = CanvasMotion.fadeIn(positions);
    } else {
      return;
    }
    setState(() => _motion = motion);
    _motionController
      ..duration = kCanvasMotionDuration
      ..forward(from: 0);
  }

  /// Recoge lo que se mira hacia su centro, mientras llega lo de arriba.
  void _startCollapse() {
    if (!_animate || _isTree || _positions.isEmpty) return;
    setState(() => _motion = CanvasMotion.collapse(_positions));
    _motionController.duration = kCanvasCollapseDuration;
    final done = _motionController
        .forward(from: 0)
        .orCancel
        .catchError((Object _) {});
    _collapsing = done;
    unawaited(
      done.whenComplete(() {
        if (identical(_collapsing, done)) _collapsing = null;
      }),
    );
  }

  void _onMotionStatus(AnimationStatus status) {
    // Al llegar, el dibujo vuelve a ser el de siempre; lo recogido se queda
    // apagado hasta que aparezca lo nuevo.
    if (status == AnimationStatus.completed &&
        mounted &&
        _motion?.fadeOut == false) {
      setState(() => _motion = null);
    }
  }

  // --- Moverse entre alturas ---

  /// Baja a la altura que ya se dejó puesta; con [from], lo nuevo sale de ese
  /// nodo.
  void _descend({SceneNode? from}) {
    _rootOverride = null;
    _highlight = null;
    _needsFit = true;
    final at = from == null ? null : _positions[from.key];
    if (at != null && !_isTree) {
      _emergeFrom = MatrixUtils.transformPoint(_controller.value, at);
    } else {
      _fadeInNext = true;
    }
    unawaited(_show());
  }

  /// Sube a [altitude]: lo de ahora se recoge, y lo de arriba aparece.
  void _ascend(MapAltitude altitude) {
    _startCollapse();
    if (altitude == MapAltitude.communities) {
      _resetToCommunities();
    } else {
      _stopLinks();
      _altitude = altitude;
      _topicId = null;
      _topicItems = null;
    }
    _rootOverride = null;
    _highlight = null;
    _needsFit = true;
    _fadeInNext = true;
    unawaited(_show());
  }

  void _enterCommunityAt(int index, {SceneNode? from}) {
    final node = _overview.nodes[index];
    final scene = sceneOfOverview(_graph, _overview).nodes[index];
    setState(() {
      _stopLinks();
      _altitude = MapAltitude.topics;
      _focus = {for (final m in node.members) _graph.nodes[m].valueId};
      _focusLabel = _labelOf(scene);
      _focusGroup = scene.group;
      _topicId = null;
      _topicItems = null;
    });
    _descend(from: from);
  }

  void _enterTopic(String valueId, String label, {SceneNode? from}) {
    setState(() {
      _stopLinks();
      _altitude = MapAltitude.documents;
      _topicId = valueId;
      _topicLabel = label;
      _topicItems = null;
    });
    _descend(from: from);
  }

  /// Baja una altura en [node], si hay una más cerca.
  void _drill(SceneNode node) {
    switch (node.kind) {
      case SceneKind.community || SceneKind.overflow || SceneKind.isolated:
        final index = int.tryParse(node.key.substring('overview:'.length));
        if (index != null) _enterCommunityAt(index, from: node);
      case SceneKind.topic:
        _enterTopic(node.ref!, node.label, from: node);
      case SceneKind.note || SceneKind.source:
        return;
    }
  }

  void _goUp() {
    switch (_altitude) {
      case MapAltitude.communities:
        return;
      case MapAltitude.topics:
        _ascend(MapAltitude.communities);
      case MapAltitude.documents:
        _ascend(MapAltitude.topics);
    }
  }

  /// Tocar un nodo de la red. Es el lugar de la ficha de la ola 2: por ahora,
  /// una comunidad o un tema se abren —bajan una altura— y un documento se
  /// abre en Procesado.
  void _select(SceneNode node) {
    switch (node.kind) {
      case SceneKind.note || SceneKind.source:
        widget.onOpenItem(node.ref!);
      case SceneKind.community ||
          SceneKind.overflow ||
          SceneKind.isolated ||
          SceneKind.topic:
        _drill(node);
    }
  }

  // --- Los gestos ---

  /// Solo cuando el zoom cruza un escalón se rehacen las etiquetas.
  void _onZoom() {
    final labelScale = labelScaleFor(_controller.value.getMaxScaleOnAxis());
    if (labelScale != _labelScale) setState(() => _labelScale = labelScale);
  }

  void _onInteractionStart(ScaleStartDetails details) {
    _gestureStartScale = _controller.value.getMaxScaleOnAxis();
    _gesturing = true;
    unawaited(_captureGestureSnapshot());
  }

  /// Mientras dura el gesto: si el zoom ya cambió demasiado desde la última
  /// captura, recaptura una vez para que la imagen no se vea borrosa (F18,
  /// 18.2). Un arrastre puro no cambia el zoom, así que no recaptura nada.
  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (_gestureSnapshot == null) return;
    final change = _controller.value.getMaxScaleOnAxis() / _snapshotScale;
    if (change > _kMaxSnapshotZoomChange ||
        change < 1 / _kMaxSnapshotZoomChange) {
      unawaited(_captureGestureSnapshot());
    }
  }

  /// Captura lo ya dibujado en [_gestureSnapshot] (F18, 18.2). Si algo falla
  /// —sin tamaño todavía, o lo que sea—, no pasa nada: sin captura, el dibujo
  /// sigue siendo el vectorial de siempre.
  Future<void> _captureGestureSnapshot() async {
    ui.Image? image;
    try {
      image = await captureBoundaryImage(
        _boundaryKey,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      // Cualquier falla acá degrada al dibujo vectorial de siempre, no
      // rompe la vista: no hace falta distinguir el tipo de excepción.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return;
    }
    // El gesto ya terminó mientras la captura estaba en camino: esta imagen
    // ya no le corresponde a nada, se descarta sin mostrarla.
    if (image == null || !mounted || !_gesturing) {
      image?.dispose();
      return;
    }
    _snapshotScale = _controller.value.getMaxScaleOnAxis();
    _replaceGestureSnapshot(image);
  }

  void _discardGestureSnapshot() {
    _gesturing = false;
    _replaceGestureSnapshot(null);
  }

  /// Un `ui.Image` vivo a la vez (F18, 18.2): el anterior se libera recién
  /// después de que el cuadro siguiente —que ya no lo usa— se pintó.
  void _replaceGestureSnapshot(ui.Image? next) {
    final previous = _gestureSnapshot;
    if (identical(previous, next)) return;
    setState(() => _gestureSnapshot = next);
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  /// Al soltar un gesto en la red: si cambió el zoom y pasó un umbral, cambia
  /// de altura en el nodo que quedó en el centro.
  ///
  /// Solo cuenta lo que el gesto cambió: con una altura grande el encuadre
  /// queda por debajo de [kZoomOutThreshold], y si bastara estar por debajo,
  /// arrastrar el mapa —que no toca el zoom— lo sacaría de la altura.
  void _onInteractionEnd(ScaleEndDetails details) {
    _discardGestureSnapshot();
    if (_busy || _viewport.isEmpty || _isTree || _links) return;
    final scale = _controller.value.getMaxScaleOnAxis();
    final change = scale / _gestureStartScale;
    if (scale < kZoomOutThreshold && change < 1 / _kZoomChange) {
      _goUp();
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

  // --- Los vínculos a mano y con IA ---

  /// Los documentos a la vista y los vínculos entre ellos, tal cual están
  /// dibujados: de ahí salen los candidatos de la IA.
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

    // Los títulos de cada documento —la escena solo trae el título—: son
    // documentos procesados, como todo lo del Mapa (F41, paso 6).
    final loaded = await ref
        .read(libraryRepositoryProvider)
        .list(LibraryQuery(ids: ids, scope: LibraryScope.processed));
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

  List<MapCrumb> _crumbs(AppLocalizations l10n) => [
    (
      label: l10n.f44S2CrumbAll,
      id: 'overview',
      onTap: () => _ascend(MapAltitude.communities),
    ),
    if (_links)
      (label: l10n.f44S2CrumbLinks, id: 'links', onTap: null)
    else ...[
      if (_altitude != MapAltitude.communities)
        (
          label: _focusLabel ?? l10n.f44S2CrumbAllTopics(_topicKind),
          id: 'topics',
          onTap: () => _ascend(MapAltitude.topics),
        ),
      if (_altitude == MapAltitude.documents)
        (label: _topicLabel ?? '', id: 'documents', onTap: null),
    ],
  ];

  bool get _showsDocuments => _links || _altitude == MapAltitude.documents;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final graph = _linkGraph;
    final noTopics = !_links && _graph.nodes.isEmpty;

    final actions = [
      IconButton(
        key: const ValueKey('map-as-list'),
        tooltip: _asList ? l10n.f44S2AsCanvas : l10n.f44S2AsList,
        isSelected: _asList,
        icon: const Icon(Icons.view_list_outlined),
        selectedIcon: const Icon(Icons.hub_outlined),
        onPressed: () => setState(() {
          _asList = !_asList;
          _offerExport(widget.exportHandle);
          _rebuildTree();
        }),
      ),
      if (!_links && _altitude == MapAltitude.documents)
        IconButton(
          key: const ValueKey('map-open-topic'),
          tooltip: l10n.atlasOpenMaterial,
          icon: const Icon(Icons.folder_open_outlined),
          onPressed: () => widget.onOpenTopic(_topicId!),
        ),
      // Solo con documentos a la vista hay entre qué sugerir.
      if (_showsDocuments && !_busy && _scene.nodes.length > 1)
        IconButton(
          key: const ValueKey('map-ai-suggest'),
          tooltip: l10n.graphAiSuggestTooltip,
          icon: const Icon(Icons.auto_awesome),
          onPressed: () => unawaited(_suggestRelations()),
        ),
      IconButton(
        key: const ValueKey('map-add-link'),
        tooltip: l10n.graphAddRelationTooltip,
        icon: const Icon(Icons.add_link),
        onPressed: () => unawaited(showAddRelationFlow(context, ref)),
      ),
    ];
    final crumbs = MapBreadcrumb(crumbs: _crumbs(l10n));
    // Las migas y los botones en una fila; si no entran con aire para las
    // migas, los botones bajan a la suya.
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxWidth - actions.length * 48;
          if (room >= _kMinCrumbsWidth) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: crumbs,
                  ),
                ),
                ...actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 12),
                child: crumbs,
              ),
              Wrap(alignment: WrapAlignment.end, children: actions),
            ],
          );
        },
      ),
    );

    final Widget body;
    if (noTopics) {
      body = EmptyStateView(
        key: const ValueKey('map-no-topics'),
        icon: Icons.hub_outlined,
        title: l10n.mapEmptyTitle(_topicKind),
        message: l10n.mapEmptyMessage(_topicKind),
        actionLabel: l10n.mapSeeLinksAction,
        onAction: () => _setLinks(true),
      );
    } else if (_links && graph == null) {
      body = _linksFailed
          ? _LinksLoadError(onRetry: _listenLinks)
          : const Center(child: CircularProgressIndicator());
    } else if (_links && graph!.items.isEmpty) {
      body = EmptyStateView(
        key: const ValueKey('map-links-empty'),
        icon: Icons.add_link,
        title: l10n.mapLinksEmptyTitle,
        message: l10n.mapLinksEmptyMessage,
        actionLabel: l10n.graphAddRelationTooltip,
        onAction: () => unawaited(showAddRelationFlow(context, ref)),
      );
    } else if (_asList && _listTree != null) {
      body = MapCanvasList(
        tree: _listTree!,
        topicKind: _topicKind,
        onToggle: _toggle,
        openOf: _openOf,
      );
    } else {
      body = _canvasArea(context, theme, l10n);
    }

    final footnotes = _footnotes(l10n);
    // Lo de arriba y lo de abajo nunca le quitan al lienzo más de lo justo:
    // con la letra al doble en un celular, se desplazan en su lugar.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * _kMaxChromeShare,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [header, ..._contextRows(l10n, theme)],
              ),
            ),
          ),
          SizedBox(
            height: 3,
            child: _busy && !noTopics
                ? const LinearProgressIndicator(key: ValueKey('map-busy'))
                : null,
          ),
          Expanded(child: body),
          if (footnotes.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * _kMaxFootnotesShare,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: footnotes,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Lo que se elige según lo que se mira: el «Grado» en los temas, la fuerza
  /// de los vínculos, de dónde parte el árbol.
  List<Widget> _contextRows(AppLocalizations l10n, ThemeData theme) {
    final graph = _linkGraph;
    return [
      if (!_links && _altitude == MapAltitude.communities && !_isTree)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(l10n.mapGraphHint, style: theme.textTheme.bodySmall),
        ),
      // Con un foco, cuánto de alrededor se ve. En todos los temas no hay
      // desde dónde contar saltos.
      if (!_links && _altitude == MapAltitude.topics && _focus.isNotEmpty)
        DegreeSelector(
          key: const ValueKey('map-degree'),
          degree: _degree,
          onChanged: (degree) {
            if (degree == _degree) return;
            setState(() => _degree = degree);
            unawaited(_show(warm: true));
          },
        ),
      if (_links && graph != null && graph.items.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            l10n.mapLinksSummary(graph.linkedCount),
            key: const ValueKey('map-links-summary'),
            style: theme.textTheme.titleSmall,
          ),
        ),
        LinkStrengthSelector(
          key: const ValueKey('map-links-strength'),
          strength: _strength,
          onChanged: (strength) {
            if (strength == _strength) return;
            setState(() {
              _strength = strength;
              _needsFit = true;
            });
            _listenLinks();
          },
        ),
      ],
      if ((_isTree || _asList) && _tree != null) _rootRow(l10n),
    ];
  }

  Widget _rootRow(AppLocalizations l10n) {
    final root = _tree!.entries[_tree!.root.id];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: l10n.mapSchemaRootTooltip,
              child: OutlinedButton.icon(
                key: const ValueKey('map-tree-root'),
                onPressed: () => unawaited(_pickRoot()),
                icon: Icon(
                  root == null ? Icons.account_tree_outlined : treeIconOf(root),
                ),
                label: Text(
                  root?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (_rootOverride != null)
            IconButton(
              key: const ValueKey('map-tree-root-reset'),
              tooltip: l10n.f44S2RootReset,
              icon: const Icon(Icons.close),
              onPressed: _resetRoot,
            ),
        ],
      ),
    );
  }

  /// Lo que no se dibujó, y por qué.
  List<Widget> _footnotes(AppLocalizations l10n) {
    final graph = _linkGraph;
    final tree = _asList ? _listTree : _tree;
    return [
      if (!_links && _altitude == MapAltitude.topics && _scene.hidden > 0)
        MapFootnote(
          key: const ValueKey('map-cut'),
          text: l10n.mapGraphTopicsCut(
            _scene.nodes.length,
            _scene.nodes.length + _scene.hidden,
          ),
        ),
      if (!_links &&
          !_isTree &&
          !_asList &&
          _altitude == MapAltitude.topics &&
          _scene.hiddenEdges > 0)
        MapFootnote(
          key: const ValueKey('map-edges-cut'),
          text: l10n.mapGraphEdgesCut(
            _scene.edges.length,
            _scene.edges.length + _scene.hiddenEdges,
          ),
        ),
      if (!_links && _altitude == MapAltitude.documents && _scene.hidden > 0)
        MapFootnote(
          key: const ValueKey('map-cut'),
          text: l10n.mapGraphItemsCut(_scene.nodes.length),
        ),
      if ((_isTree || _asList) && tree != null && tree.truncated)
        MapFootnote(
          key: const ValueKey('map-tree-truncated'),
          text: l10n.mapSchemaTruncated(tree.entries.length),
        ),
      if (_links && graph != null) ...[
        if (graph.hidden > 0)
          MapFootnote(
            key: const ValueKey('map-links-cut'),
            text: l10n.mapLinksCut(graph.items.length, graph.linkedCount),
          ),
        if (_strength != LinkStrengthFilter.all)
          MapFootnote(
            key: const ValueKey('map-links-strength-cut'),
            text: l10n.mapLinksStrengthCut(
              graph.shownLinks,
              graph.totalLinks,
              _strength.name,
            ),
          ),
        if (graph.unlinkedCount > 0)
          MapFootnote(
            key: const ValueKey('map-links-unlinked'),
            text: l10n.mapLinksUnlinked(graph.unlinkedCount),
          ),
      ],
    ];
  }

  Widget _canvasArea(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitIfNeeded();
        });
        final canvas = _isTree ? _treeCanvas : _canvas;
        return Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label: l10n.f44S2CanvasSemantics(
                  _isTree ? _treePositions.length : _scene.nodes.length,
                ),
                child: ClipRect(
                  child: InteractiveViewer(
                    key: const ValueKey('map-canvas'),
                    transformationController: _controller,
                    constrained: false,
                    minScale: _kMinScale,
                    maxScale: _kMaxScale,
                    boundaryMargin: const EdgeInsets.all(800),
                    onInteractionStart: _onInteractionStart,
                    onInteractionUpdate: _onInteractionUpdate,
                    onInteractionEnd: _onInteractionEnd,
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      // Con fondo propio: el PNG sale opaco, del color de la
                      // pantalla.
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: SizedBox(
                          width: math.max(canvas.width, 1),
                          height: math.max(canvas.height, 1),
                          // F18, 18.2: mientras dura un gesto, mover una
                          // imagen ya dibujada es mucho más barato que
                          // recorrer cientos de nodos en cada cuadro. Al
                          // soltar vuelve el dibujo vectorial de siempre,
                          // idéntico, porque la imagen es una captura exacta
                          // de esa misma caja.
                          child: switch (_gestureSnapshot) {
                            final snapshot? => RawImage(
                              image: snapshot,
                              fit: BoxFit.fill,
                            ),
                            null => MediaQuery.withClampedTextScaling(
                              maxScaleFactor: _kCanvasMaxTextScale,
                              child: AnimatedBuilder(
                                animation: _motionController,
                                builder: (context, _) =>
                                    _isTree ? _treeLayer(theme) : _network(),
                              ),
                            ),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Abajo, la disposición y los vínculos a un lado y el zoom con el
            // minimapa al otro. En lo muy angosto se achican, no se pisan.
            PositionedDirectional(
              start: 12,
              end: 12,
              bottom: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    flex: 3,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.bottomStart,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MapArrangementSelector(
                            arrangement: _arrangement,
                            showLabels: constraints.maxWidth >= 560,
                            onChanged: _setArrangement,
                          ),
                          const SizedBox(width: 8),
                          _LinksToggle(on: _links, onChanged: _setLinks),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 2,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.bottomEnd,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ValueListenableBuilder<Matrix4>(
                            valueListenable: _controller,
                            builder: (context, transform, _) =>
                                _minimap(transform, theme),
                          ),
                          MapZoomControls(
                            onZoomOut: () => _zoomBy(1 / kCanvasZoomStep),
                            onZoomIn: () => _zoomBy(kCanvasZoomStep),
                            onFit: _fitAll,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _setArrangement(MapArrangement arrangement) {
    if (arrangement == _arrangement) return;
    setState(() {
      _arrangement = arrangement;
      _needsFit = true;
      _fadeInNext = true;
      _offerExport(widget.exportHandle);
    });
    unawaited(_show(warm: true));
  }

  /// El minimapa, solo si hay algo fuera de la vista.
  Widget _minimap(Matrix4 transform, ThemeData theme) {
    final positions = _drawnPositions;
    if (positions.isEmpty || _viewport.isEmpty || _busy) {
      return const SizedBox.shrink();
    }
    final content = contentBounds(positions.values, margin: 40);
    final visible = visibleSceneRect(transform, _viewport);
    if (showsWhole(visible, content)) return const SizedBox.shrink();
    final colors = theme.colorScheme;
    final List<MinimapDot> dots;
    if (_isTree) {
      dots = [
        for (final entry in _tree?.entries.values ?? <CanvasTreeEntry>[])
          if (positions[entry.key] case final at?)
            (at: at, color: treeAccentOf(entry, colors, theme.brightness)),
      ];
    } else {
      dots = [
        for (final node in _scene.nodes)
          if (positions[node.key] case final at?)
            (at: at, color: mapSceneNodeColor(node, colors, theme.brightness)),
      ];
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MapMinimap(
        content: content,
        visible: visible,
        dots: dots,
        onGoTo: (point) =>
            _controller.value = centerOn(_controller.value, point, _viewport),
      ),
    );
  }

  Widget _network() {
    final motion = _motion;
    final t = Curves.easeOutCubic.transform(_motionController.value);
    final positions = motion == null ? _positions : motion.positionsAt(t);
    final highlight = _highlight;
    final layer = Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            // Miles de líneas que no cambian mientras se arrastra: que el
            // motor las guarde dibujadas.
            isComplex: true,
            painter: MapEdgesPainter(
              scene: _scene,
              positions: positions,
              colors: Theme.of(context).colorScheme,
            ),
          ),
        ),
        for (final node in _scene.nodes)
          if (positions[node.key] case final at?)
            _placed(node, at, highlighted: node.key == highlight),
      ],
    );
    return motion == null
        ? layer
        : Opacity(opacity: motion.opacityAt(t), child: layer);
  }

  Widget _placed(SceneNode node, Offset at, {required bool highlighted}) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final size = mapNodeSize(node);
    final label = _labelOf(node);
    final semantics = switch (node.kind) {
      SceneKind.community => l10n.mapGraphCommunitySemantics(
        label,
        l10n.mapTopicCount(_topicKind, node.count),
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
        onTap: () => _select(node),
        child: GestureDetector(
          key: ValueKey('map-node-${node.key}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _select(node),
          child: MapNetworkNode(
            node: node,
            label: label,
            color: mapSceneNodeColor(node, theme.colorScheme, theme.brightness),
            labelScale: _labelScale,
            highlighted: highlighted,
          ),
        ),
      ),
    );
  }

  Widget _treeLayer(ThemeData theme) {
    final tree = _tree;
    if (tree == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final motion = _motion;
    final t = Curves.easeOutCubic.transform(_motionController.value);
    final positions = motion == null ? _treePositions : motion.positionsAt(t);
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
                  final open = _openOf(entry);
                  return MapTreeNodeCard(
                    entry: entry,
                    topicKind: _topicKind,
                    onToggle: () => _toggle(entry),
                    onOpen: open?.onOpen,
                    openTooltip: open?.tooltip,
                    highlighted:
                        entry.ref.kind == CanvasTreeKind.item &&
                        _highlight == 'item:${entry.ref.id}',
                  );
                },
              ),
            ),
      ],
    );
    return motion == null
        ? layer
        : Opacity(opacity: motion.opacityAt(t), child: layer);
  }
}

/// Prende o apaga los documentos vinculados entre sí: el lugar provisorio,
/// hasta la ola 2, de la capa «Vínculos».
class _LinksToggle extends StatelessWidget {
  const _LinksToggle({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: on ? colors.secondaryContainer : colors.surfaceContainerHigh,
      elevation: 2,
      shadowColor: colors.shadow.withValues(alpha: 0.3),
      shape: const CircleBorder(),
      child: IconButton(
        key: const ValueKey('map-links-toggle'),
        isSelected: on,
        tooltip: on ? l10n.f44S2LinksOff : l10n.f44S2LinksOn,
        icon: const Icon(Icons.link),
        color: on ? colors.onSecondaryContainer : null,
        onPressed: () => onChanged(!on),
      ),
    );
  }
}

class _LinksLoadError extends StatelessWidget {
  const _LinksLoadError({required this.onRetry});

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
