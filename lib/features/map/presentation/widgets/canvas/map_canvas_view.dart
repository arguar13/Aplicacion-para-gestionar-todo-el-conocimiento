import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/design/widgets/topic_dimension_menu.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:sinapsis/features/graph/presentation/widgets/degree_selector.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/link_graph.dart';
import 'package:sinapsis/features/map/domain/entities/map_node_facts.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/map/domain/services/canvas_focus.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';
import 'package:sinapsis/features/map/domain/services/link_strength.dart';
import 'package:sinapsis/features/map/domain/services/map_node_facts_builder.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layout_runner.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/arrow_head.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_chrome.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_gesture_cache.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_motion.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_network.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_placement.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_tree.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_viewport.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_canvas_layers.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_canvas_list.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_minimap.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_node_sheet.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_root_picker.dart';
import 'package:sinapsis/features/map/presentation/widgets/link_strength_selector.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_export_handle.dart';
import 'package:sinapsis/features/map/presentation/widgets/suggest_links.dart';
import 'package:sinapsis/features/organize/presentation/widgets/add_relation_flow.dart';
import 'package:sinapsis/features/organize/presentation/widgets/relations_section.dart';
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

/// Hasta cuánto se agranda la letra adentro del lienzo: el lienzo se acerca
/// con el zoom, y sus cajas tienen un tamaño fijo para el layout. La letra
/// entera la sigue «Ver como lista».
const _kCanvasMaxTextScale = 1.5;

/// Lo más que ocupan, del alto del lienzo, lo de arriba —las migas y lo que se
/// elige— y las notas de abajo: el resto es del dibujo.
const _kMaxChromeShare = 0.4;
const _kMaxFootnotesShare = 0.2;

/// Lo más que ocupa la ficha de un nodo, del alto del lienzo: abajo y sin
/// taparlo. Con ella abierta, las notas de abajo se callan y lo de arriba
/// cede lugar, para que siempre quede dibujo a la vista.
const _kMaxSheetShare = 0.4;
const _kMaxChromeShareWithSheet = 0.3;

/// La comunidad —o el conjunto de temas— que se mira a la altura de los
/// temas, como raíz de Radial y Árbol.
const _kFocusId = 'focus';

/// El lienzo único del Mapa (F44, paso 2): lo que eran el Grafo, el Esquema y
/// la vista «Vínculos», en un solo dibujo que se recorre con el zoom.
///
/// - **Tres alturas**: de lejos, las comunidades; al entrar en una —tocarla
///   dos veces, «Entrar» en su ficha o acercarse—, sus temas **salen de la
///   burbuja**; lo mismo en un tema despliega sus documentos. Alejarse los
///   recoge de vuelta. Con «sin animaciones», el cambio es directo.
/// - **La ficha** (F44, paso 4): tocar cualquier nodo —en la red, en Radial y
///   Árbol o en la lista— abre abajo lo que es, con qué se une y lo que se
///   puede hacer con él: Entrar, Centrar aquí, Abrir, Preguntar al chat,
///   Estudiar y, en un documento, Vincular y Ver sus vínculos. Sale de lo que
///   el lienzo ya tiene (`mapNodeFacts`): abrirla no recalcula nada.
/// - **El foco** («Centrar aquí»): el nodo al centro, su vecindario según el
///   «Grado» y el resto apagado; en Radial y Árbol, el nodo es la raíz. «Salir
///   del foco» o la miga lo devuelven.
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
/// Lo que piden de afuera —el Resumen, «Ver en el Mapa» y, en el paso 5, la
/// búsqueda— llega por `mapCanvasRequestProvider`, y va por el mismo camino
/// que lo que se toca en la ficha (`_goTo`).
///
/// Acá vive lo que se mira y cómo se pasa de una cosa a otra; lo demás tiene
/// su pieza: el dibujo de la red y del árbol (`map_canvas_layers.dart`), lo de
/// alrededor —migas, botones, notas de abajo— (`canvas_chrome.dart`), la ficha
/// (`map_node_sheet.dart`), dónde va cada nodo (`canvas_placement.dart`), el
/// caché del gesto (`canvas_gesture_cache.dart`) y lo que el árbol ya sabe de
/// cada nodo (`knownCanvasTreeLinks`).
class MapCanvasView extends ConsumerStatefulWidget {
  const MapCanvasView({
    required this.snapshot,
    required this.dimension,
    required this.filter,
    required this.onOpenTopic,
    required this.onOpenItem,
    required this.onAsk,
    required this.onStudy,
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

  /// «✨ Preguntar al chat» desde una ficha: la pregunta, ya escrita, para
  /// mandarla en una conversación nueva sobre lo procesado.
  final ValueChanged<String> onAsk;

  /// «🎓 Estudiar» desde una ficha: Repasar con este recorte en el selector.
  final ValueChanged<CreationScope> onStudy;

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
  /// encuadra con sus vecinos.
  String? _highlight;

  /// El nodo cuya ficha está abierta.
  MapNodeRef? _selected;

  /// El nodo de «Centrar aquí» y su vecindario según el «Grado»: las
  /// posiciones en `_scene.nodes` que quedan encendidas. Sin foco, `null`.
  MapNodeRef? _centered;
  Set<int>? _lit;

  /// Lo que dice la ficha de cada nodo, para lo que se dibuja ahora.
  final _facts = MapNodeFactsMemo();

  // --- Lo que se leyó ---

  late CommunityOverview _overview;
  TopicSelection? _selection;
  TopicItemsGraph? _topicItems;
  LinkGraph? _linkGraph;
  bool _linksFailed = false;
  ProviderSubscription<AsyncValue<LinkGraph>>? _linksSubscription;

  // --- La red ---

  GraphScene _scene = const GraphScene.empty();
  final _placement = CanvasNetworkPlacement();
  Map<String, Offset> get _positions => _placement.positions;
  Size get _canvas => _placement.canvas;

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

  /// El tamaño del visor con el que se encuadró solo, mientras la persona no
  /// movió el mapa desde entonces. Si el visor cambia —se abre o se cierra la
  /// ficha, aparece una fila arriba—, se vuelve a encuadrar con el nuevo: lo
  /// que se pidió mirar sigue entero y en el medio, sin taparse.
  Size? _autoFitViewport;

  /// El zoom con el que quedó encuadrada la altura de ahora.
  double _fitScale = 1;

  /// El zoom con el que empezó el gesto de ahora: lo que un gesto cambió es lo
  /// que decide si es acercar, alejar o solo arrastrar.
  double _gestureStartScale = 1;

  /// El agrandado de las etiquetas para el zoom de ahora.
  double _labelScale = 1;

  /// Lo ya dibujado, capturado al empezar un arrastre o un zoom (F18, 18.2):
  /// mientras dura el gesto se pinta eso en vez del dibujo.
  late final _gestureCache = CanvasGestureCache(
    boundaryKey: _boundaryKey,
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

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
      _leaveNode();
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
    _gestureCache.dispose();
    super.dispose();
  }

  // --- Los pedidos de afuera ---

  /// Atiende [request] y lo da por atendido. Un proveedor no se modifica
  /// mientras se arma el árbol: se vuelve a `null` apenas termina.
  void _apply(MapCanvasRequest request) {
    _goTo(request);
    scheduleMicrotask(() {
      if (!mounted) return;
      ref.read(mapCanvasRequestProvider.notifier).state = null;
    });
  }

  /// Lleva el lienzo adonde dice [request] —lo que piden de afuera y lo que se
  /// toca en una ficha— y abre la ficha de lo que se pidió: un documento, un
  /// tema o [select]. Con [center], además, lo centra.
  void _goTo(
    MapCanvasRequest request, {
    MapNodeRef? select,
    bool center = false,
  }) {
    _leaveNode();
    MapNodeRef? node;
    switch (request) {
      case MapShowLinks(:final focusId):
        _showLinksFocused(focusId);
        node = focusId == null ? null : MapDocumentRef(focusId);
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
        node = MapTopicRef(valueId);
      case MapShowDocument(:final itemId):
        node = MapDocumentRef(itemId);
        final place = widget.snapshot.insights.search
            .document(itemId)
            ?.topicValueId;
        final at = place == null ? null : _graph.indexOf(place);
        if (at == null) {
          // Sin tema, su lugar es la burbuja «Sin tema» (paso 5); hasta
          // entonces, lo vinculado con él en foco.
          _showLinksFocused(itemId);
        } else {
          _stopLinks();
          _openCommunityOf(place!);
          _altitude = MapAltitude.documents;
          _topicId = place;
          _topicLabel = _graph.nodes[at].label;
          _topicItems = null;
          _highlight = 'item:$itemId';
        }
    }
    _selected = select ?? node;
    if (center) _centered = _selected;
    _rootOverride = null;
    _needsFit = true;
    unawaited(_show());
  }

  /// Lo vinculado, con [focusId] —si viene— resaltado.
  void _showLinksFocused(String? focusId) {
    _links = true;
    _linksFocusId = focusId;
    _highlight = focusId == null ? null : 'item:$focusId';
    _listenLinks();
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
      _leaveNode();
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
      highlighted: _highlighted,
      lit: _lit,
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
      final layout = await ref.read(mapLayoutRunnerProvider)(
        _placement.jobFor(scene, warm: warm),
      );
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
      if (placed != null) _placement.place(scene, placed.xs, placed.ys);
      // Solo se centra lo que se dibuja.
      _lit = _litNow();
      if (_lit == null) _centered = null;
      _rebuildTree();
      _busy = false;
    });
    _fitIfNeeded();
    _startArrival();
  }

  // --- Radial, Árbol y la lista ---

  /// La raíz del árbol de lo que se mira: lo que eligió la persona, lo que
  /// se centró o lo que se mira —todo, la comunidad, el tema, lo vinculado o
  /// el documento en foco—.
  ({CanvasTreeRef ref, String title, int? group}) _treeRoot() {
    final l10n = AppLocalizations.of(context)!;
    if (_rootOverride case final override?) {
      return (ref: override.ref, title: override.title, group: null);
    }
    if (_centered case final node?) {
      final facts = _factsOf(node);
      if (facts != null) {
        return (
          ref: switch (node) {
            MapCommunityRef(:final index) => CanvasTreeRef.community('$index'),
            MapTopicRef(:final valueId) => CanvasTreeRef.topic(valueId),
            MapDocumentRef(:final itemId) => CanvasTreeRef.item(itemId),
          },
          title: _titleOf(facts),
          group: node is MapCommunityRef ? facts.group : null,
        );
      }
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
  Map<String, List<CanvasTreeLink>> _treeLinks(CanvasTreeRef root) =>
      knownCanvasTreeLinks(
        root: root,
        graph: _graph,
        overview: _overview,
        labelOf: _labelOf,
        fetched: _fetched,
        focusTopics: _selection?.topics ?? const [],
        linked: _linkGraph?.items ?? const [],
        // Los documentos del tema que se mira son los mismos de la red.
        shownTopic: _altitude == MapAltitude.documents && _topicId != null
            ? (valueId: _topicId!, items: _topicItems?.items ?? const [])
            : null,
      );

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

  /// Lo que es [entry] en el lienzo, para su ficha: todo y lo vinculado no
  /// tienen; la comunidad que se mira es la del panorama que tiene sus temas.
  MapNodeRef? _refOfEntry(CanvasTreeEntry entry) {
    final id = entry.ref.id;
    return switch (entry.ref.kind) {
      // Lo que junta el lienzo sin ser un nodo del mapa no tiene ficha.
      CanvasTreeKind.all ||
      CanvasTreeKind.links ||
      CanvasTreeKind.unthemed => null,
      CanvasTreeKind.community => switch (id == _kFocusId
          ? _overview.nodes.indexWhere(
              (node) =>
                  node.members.isNotEmpty &&
                  _focus.contains(_graph.nodes[node.members.first].valueId),
            )
          : int.parse(id)) {
        -1 => null,
        final index => MapCommunityRef(index),
      },
      CanvasTreeKind.topic => MapTopicRef(id),
      CanvasTreeKind.item => MapDocumentRef(id),
    };
  }

  /// Cómo se abre la ficha de un nodo del árbol o de una fila de la lista.
  CanvasTreeSheet? _sheetOf(CanvasTreeEntry entry) {
    final node = _refOfEntry(entry);
    if (node == null) return null;
    return (
      onOpen: () => _openSheet(node),
      tooltip: AppLocalizations.of(context)!.f44S4SheetShow(entry.title),
    );
  }

  /// Si la tarjeta de [entry] lleva el borde: el documento que se pidió
  /// mirar, o lo que tiene la ficha abierta.
  bool _isTreeHighlighted(CanvasTreeEntry entry) {
    if (entry.ref.kind == CanvasTreeKind.item &&
        _highlight == 'item:${entry.ref.id}') {
      return true;
    }
    final selected = _selected;
    return selected != null && _refOfEntry(entry) == selected;
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
    _autoFitViewport = _viewport;
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

  /// Lo dibujado entero; con un foco, su vecindario con el nodo en el medio;
  /// con algo resaltado, eso y sus vecinos directos: lo que se pidió mirar
  /// queda en el centro y legible.
  Map<String, Offset> _framed() {
    final positions = _drawnPositions;
    if (_isTree) return positions;
    final lit = _lit;
    final center = _centered == null ? null : positions[_centered!.sceneKey];
    if (lit != null && center != null) {
      return mirroredAround(center, {
        for (final i in lit)
          if (positions[_scene.nodes[i].key] case final at?)
            _scene.nodes[i].key: at,
      });
    }
    final highlight = _highlight;
    if (highlight == null) return positions;
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
    _autoFitViewport = null;
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
    _autoFitViewport = null;
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
    _leaveNode();
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
    _leaveNode();
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
      // La burbuja «Sin tema» todavía no se dibuja.
      case SceneKind.unthemed || SceneKind.note || SceneKind.source:
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

  // --- La ficha y el foco ---

  /// Tocar un nodo de la red abre su ficha. Bajar una altura es tocarlo dos
  /// veces, acercarse o «Entrar» en la ficha.
  void _select(SceneNode node) {
    final ref = MapNodeRef.ofSceneKey(node.key);
    if (ref != null) _openSheet(ref);
  }

  /// Abre la ficha de [node]: solo eso. No se recalcula el grafo ni se
  /// acomoda nada; lo que dice sale de lo que ya se tiene.
  void _openSheet(MapNodeRef node) => setState(() => _selected = node);

  void _closeSheet() => setState(() => _selected = null);

  /// Lo de un nodo —su ficha, el foco— no sigue cuando cambia lo que se mira.
  void _leaveNode() {
    _selected = null;
    _centered = null;
    _lit = null;
  }

  /// Lo que dice la ficha de [node], o `null` si ya no está en el mapa.
  MapNodeFacts? _factsOf(MapNodeRef node) => _facts.of(
    node,
    graph: _graph,
    detection: widget.snapshot.detection,
    overview: _overview,
    insights: widget.snapshot.insights,
    scene: _scene,
    tree: _listTree ?? (_isTree ? _tree : null),
  );

  /// El nombre de una ficha: el de un grupo es su clase.
  String _titleOf(MapNodeFacts facts) {
    final l10n = AppLocalizations.of(context)!;
    if (facts.kind != MapNodeKind.group) return facts.title;
    final index = (facts.ref as MapCommunityRef).index;
    return _overview.nodes[index].kind == OverviewKind.isolated
        ? l10n.mapBoardIsolatedTitle(_topicKind)
        : l10n.mapGraphOverflow;
  }

  /// Lo que lleva un anillo: lo que se pidió mirar, la ficha abierta y el
  /// centro del foco.
  Set<String> get _highlighted => {
    ?_highlight,
    ?_selected?.sceneKey,
    ?_centered?.sceneKey,
  };

  /// «Entrar» en la ficha: la cierra y, ya con el lienzo entero, baja una
  /// altura en [node]. Así lo que sale de la burbuja se acomoda en el visor
  /// que va a quedar, y no en el que tenía la ficha abierta.
  void _enterFromSheet(MapNodeRef node) {
    setState(() => _selected = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enter(node);
    });
  }

  /// Baja una altura en [node].
  void _enter(MapNodeRef node) {
    final at = _scene.indexOf(node.sceneKey);
    final drawn = at == null ? null : _scene.nodes[at];
    switch (node) {
      case MapCommunityRef(:final index):
        _enterCommunityAt(index, from: drawn);
      case MapTopicRef(:final valueId):
        final topic = _graph.indexOf(valueId);
        if (topic != null) {
          _enterTopic(valueId, _graph.nodes[topic].label, from: drawn);
        }
      case MapDocumentRef():
        return;
    }
  }

  /// El vecindario del foco en lo que se dibuja ahora, según el «Grado».
  Set<int>? _litNow() {
    final node = _centered;
    if (node == null) return null;
    final at = _scene.indexOf(node.sceneKey);
    return at == null ? null : focusNeighborhood(_scene, at, degree: _degree);
  }

  /// «Centrar aquí»: [node] al centro, su vecindario alrededor y el resto
  /// apagado. Lo que no se dibuja ahora —un tema desde el árbol, lo más
  /// reciente de una comunidad— se trae primero.
  void _centerOn(MapNodeRef node) {
    if (_scene.indexOf(node.sceneKey) == null) {
      _bring(node, center: true);
      return;
    }
    setState(() {
      _centered = node;
      _selected = node;
      _rootOverride = null;
      _lit = _litNow();
      // Se encuadra al terminar de dibujar (`_canvasArea`): la fila del foco
      // y la ficha cambian el alto del lienzo, y el nodo tiene que quedar en
      // el medio del que queda.
      _needsFit = true;
      _rebuildTree();
    });
  }

  /// «Salir del foco» o la miga: vuelve a lo que se miraba, entero.
  void _exitFocus() {
    setState(() {
      _centered = null;
      _lit = null;
      _needsFit = true;
      _rebuildTree();
    });
  }

  /// El «Grado»: en los temas de una comunidad, cuánto de alrededor se trae;
  /// con un foco, cuánto de su vecindario queda encendido.
  void _setDegree(int? degree) {
    if (degree == _degree) return;
    final reselect =
        !_links && _altitude == MapAltitude.topics && _focus.isNotEmpty;
    setState(() {
      _degree = degree;
      if (_centered != null) {
        _needsFit = true;
        if (!reselect) _lit = _litNow();
      }
    });
    if (reselect) unawaited(_show(warm: true));
  }

  /// Un vecino, lo más reciente o el tema de un documento, tocado en la
  /// ficha: si se dibuja, se abre su ficha y se encuadra ahí mismo; si no, el
  /// lienzo vuela hasta él.
  void _visit(MapNodeRef node) {
    if (_scene.indexOf(node.sceneKey) == null) {
      _bring(node);
      return;
    }
    setState(() {
      _selected = node;
      _highlight = node.sceneKey;
      _needsFit = true;
    });
  }

  /// Va adonde está [node] y abre su ficha: una comunidad, de lejos; un tema,
  /// entre los de su comunidad; un documento, en su tema.
  void _bring(MapNodeRef node, {bool center = false}) => _goTo(
    switch (node) {
      MapCommunityRef() => const MapShowAltitude(MapAltitude.communities),
      MapTopicRef(:final valueId) => MapShowTopic(valueId),
      MapDocumentRef(:final itemId) => MapShowDocument(itemId),
    },
    select: node,
    center: center,
  );

  /// Lo que se puede hacer con el nodo de [facts], con lo que cada acción hace
  /// acá.
  List<MapNodeAction> _actionsOf(MapNodeFacts facts, AppLocalizations l10n) {
    final node = facts.ref;
    return mapNodeActions(
      l10n,
      facts,
      title: _titleOf(facts),
      centered: _centered == node,
      showingItsLinks:
          node is MapDocumentRef && _links && _linksFocusId == node.itemId,
      spaces: widget.dimension.isSpaces,
      on: (
        enter: _enterFromSheet,
        center: _centerOn,
        exitFocus: _exitFocus,
        openTopic: widget.onOpenTopic,
        openItem: widget.onOpenItem,
        ask: widget.onAsk,
        study: widget.onStudy,
        link: (itemId) =>
            unawaited(addRelationFlow(context, ref, fromItemId: itemId)),
        seeLinks: (itemId) => _goTo(MapShowLinks(focusId: itemId)),
      ),
    );
  }

  // --- Los gestos ---

  /// Solo cuando el zoom cruza un escalón se rehacen las etiquetas.
  void _onZoom() {
    final labelScale = labelScaleFor(_controller.value.getMaxScaleOnAxis());
    if (labelScale != _labelScale) setState(() => _labelScale = labelScale);
  }

  void _onInteractionStart(ScaleStartDetails details) {
    _gestureStartScale = _controller.value.getMaxScaleOnAxis();
    // La persona mueve el mapa: desde acá, el encuadre es suyo.
    _autoFitViewport = null;
    _gestureCache.start(
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      scale: _controller.value.getMaxScaleOnAxis,
    );
  }

  /// Mientras dura el gesto, el caché recaptura si el zoom ya cambió
  /// demasiado (F18, 18.2).
  void _onInteractionUpdate(ScaleUpdateDetails details) => _gestureCache.update(
    pixelRatio: MediaQuery.devicePixelRatioOf(context),
    scale: _controller.value.getMaxScaleOnAxis,
  );

  /// Al soltar un gesto en la red: si cambió el zoom y pasó un umbral, cambia
  /// de altura en el nodo que quedó en el centro.
  ///
  /// Solo cuenta lo que el gesto cambió: con una altura grande el encuadre
  /// queda por debajo de [kZoomOutThreshold], y si bastara estar por debajo,
  /// arrastrar el mapa —que no toca el zoom— lo sacaría de la altura.
  void _onInteractionEnd(ScaleEndDetails details) {
    _gestureCache.end();
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
  Future<void> _suggestRelations() => suggestLinksAmong(
    context,
    ref,
    ids: {
      for (final node in _scene.nodes)
        if (node.ref case final id?) id,
    },
    links: [
      for (final edge in _scene.edges)
        if (_scene.nodes[edge.a].ref case final from?)
          if (_scene.nodes[edge.b].ref case final to?) (from: from, to: to),
    ],
  );

  // --- Dibujo ---

  /// Dónde se está; con un foco, la miga de la altura sale de él y la última
  /// es el nodo del centro.
  List<MapCrumb> _crumbs(AppLocalizations l10n) {
    final crumbs = _altitudeCrumbs(l10n);
    final centered = _centered;
    final facts = centered == null ? null : _factsOf(centered);
    if (facts == null) return crumbs;
    final here = crumbs.removeLast();
    return [
      ...crumbs,
      (label: here.label, id: here.id, onTap: _exitFocus),
      (label: _titleOf(facts), id: 'focus', onTap: null),
    ];
  }

  List<MapCrumb> _altitudeCrumbs(AppLocalizations l10n) => [
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
    final header = MapCanvasHeader(crumbs: _crumbs(l10n), actions: actions);

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
          ? MapLinksLoadError(onRetry: _listenLinks)
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
        sheetOf: _sheetOf,
      );
    } else {
      body = _canvasArea(context, theme, l10n);
    }

    final selected = _selected;
    final facts = selected == null || noTopics ? null : _factsOf(selected);
    final footnotes = facts == null ? _footnotes(l10n) : const <Widget>[];
    // Lo de arriba y lo de abajo nunca le quitan al lienzo más de lo justo:
    // con la letra al doble en un celular, se desplazan en su lugar.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  constraints.maxHeight *
                  (facts == null
                      ? _kMaxChromeShare
                      : _kMaxChromeShareWithSheet),
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
          if (facts != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * _kMaxSheetShare,
              ),
              child: MapNodeSheet(
                key: ValueKey('map-sheet-${facts.ref.sceneKey}'),
                facts: facts,
                title: _titleOf(facts),
                topicKind: _topicKind,
                actions: _actionsOf(facts, l10n),
                onGoTo: _visit,
                onClose: _closeSheet,
              ),
            ),
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
          child: Text(l10n.f44S4CanvasHint, style: theme.textTheme.bodySmall),
        ),
      // En una comunidad, cuánto de alrededor se ve; con un foco en la red,
      // cuánto de su vecindario queda encendido. En todos los temas, sin
      // foco, no hay desde dónde contar saltos.
      if ((!_links && _altitude == MapAltitude.topics && _focus.isNotEmpty) ||
          (_centered != null && !_isTree))
        DegreeSelector(
          key: const ValueKey('map-degree'),
          degree: _degree,
          onChanged: _setDegree,
        ),
      if (_centered case final centered?)
        if (_factsOf(centered) case final facts?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: InputChip(
                key: const ValueKey('map-focus'),
                avatar: const Icon(Icons.center_focus_strong, size: 18),
                label: Text(
                  l10n.f44S4Centered(_titleOf(facts)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => _openSheet(centered),
                onDeleted: _exitFocus,
                deleteButtonTooltipMessage: l10n.f44S4ExitFocus,
              ),
            ),
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
      if ((_isTree || _asList) && _tree != null)
        MapTreeRootRow(
          root: _tree!.entries[_tree!.root.id],
          chosen: _rootOverride != null,
          onPick: () => unawaited(_pickRoot()),
          onReset: _resetRoot,
        ),
    ];
  }

  /// Lo que no se dibujó, y por qué.
  List<Widget> _footnotes(AppLocalizations l10n) => mapCanvasFootnotes(
    l10n,
    links: _links,
    altitude: _altitude,
    scene: _scene,
    isTree: _isTree,
    asList: _asList,
    tree: _asList ? _listTree : _tree,
    linkGraph: _linkGraph,
    strength: _strength,
  );

  Widget _canvasArea(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        final fitted = _autoFitViewport;
        if (fitted != null && fitted != _viewport) _needsFit = true;
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
                          child: switch (_gestureCache.image) {
                            final snapshot? => RawImage(
                              image: snapshot,
                              fit: BoxFit.fill,
                            ),
                            null => MediaQuery.withClampedTextScaling(
                              maxScaleFactor: _kCanvasMaxTextScale,
                              child: AnimatedBuilder(
                                animation: _motionController,
                                builder: (context, _) =>
                                    _isTree ? _treeLayer() : _network(),
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
            PositionedDirectional(
              start: 12,
              end: 12,
              bottom: 12,
              child: MapCanvasControls(
                arrangement: _arrangement,
                showLabels: constraints.maxWidth >= 560,
                onArrangement: _setArrangement,
                links: _links,
                onLinks: _setLinks,
                minimap: ValueListenableBuilder<Matrix4>(
                  valueListenable: _controller,
                  builder: (context, transform, _) =>
                      _minimap(transform, theme),
                ),
                onZoomOut: () => _zoomBy(1 / kCanvasZoomStep),
                onZoomIn: () => _zoomBy(kCanvasZoomStep),
                onFit: _fitAll,
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
        onGoTo: (point) {
          _autoFitViewport = null;
          _controller.value = centerOn(_controller.value, point, _viewport);
        },
      ),
    );
  }

  /// La red, con lo que se mueve entre alturas a la altura de ahora.
  Widget _network() {
    final motion = _motion;
    final t = Curves.easeOutCubic.transform(_motionController.value);
    return MapNetworkLayer(
      scene: _scene,
      positions: motion == null ? _positions : motion.positionsAt(t),
      opacity: motion?.opacityAt(t),
      labelOf: _labelOf,
      topicKind: _topicKind,
      labelScale: _labelScale,
      highlighted: _highlighted,
      lit: _lit,
      onSelect: _select,
      onEnter: _drill,
    );
  }

  /// Radial o Árbol, con lo que se mueve a la altura de ahora.
  Widget _treeLayer() {
    final tree = _tree;
    if (tree == null) return const SizedBox.shrink();
    final motion = _motion;
    final t = Curves.easeOutCubic.transform(_motionController.value);
    return MapTreeLayer(
      tree: tree,
      positions: motion == null ? _treePositions : motion.positionsAt(t),
      opacity: motion?.opacityAt(t),
      topicKind: _topicKind,
      onToggle: _toggle,
      sheetOf: _sheetOf,
      isHighlighted: _isTreeHighlighted,
    );
  }
}
