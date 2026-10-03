import 'dart:async';
import 'dart:isolate';

import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/map/domain/services/community_detector.dart';
import 'package:sinapsis/features/map/domain/services/topic_graph_builder.dart';

/// Lo que produce el cálculo del mapa, con lo que tardó cada parte.
class MapComputation {
  const MapComputation({
    required this.graph,
    required this.detection,
    required this.build,
    required this.communities,
  });

  final TopicGraph graph;
  final CommunityDetection detection;
  final Duration build;
  final Duration communities;
}

/// Cómo se calcula el mapa a partir de lo que entregó la base. Se inyecta para
/// que las pruebas controlen el cálculo; en la app es [computeMapInIsolate].
typedef MapComputer =
    Future<MapComputation> Function(
      TopicGraphInput input,
      CommunityMemory memory,
    );

/// El cálculo del mapa, en el isolate de quien lo llama: arma el grafo y lo
/// agrupa en comunidades, partiendo de [memory].
MapComputation computeMap(TopicGraphInput input, CommunityMemory memory) {
  final buildWatch = Stopwatch()..start();
  final graph = buildTopicGraph(input);
  buildWatch.stop();

  final communitiesWatch = Stopwatch()..start();
  final detection = detectCommunities(graph, previous: memory);
  communitiesWatch.stop();

  return MapComputation(
    graph: graph,
    detection: detection,
    build: buildWatch.elapsed,
    communities: communitiesWatch.elapsed,
  );
}

/// [computeMap] en un isolate aparte: con miles de temas el cálculo son
/// decenas de milisegundos, y en el isolate de la interfaz serían cuadros
/// perdidos.
Future<MapComputation> computeMapInIsolate(
  TopicGraphInput input,
  CommunityMemory memory,
) => Isolate.run(() => computeMap(input, memory));

/// El motor del mapa de conocimiento (F14): lo mantiene al día sin bloquear la
/// interfaz y sin recalcular de más.
///
/// - **Por lotes**: un cambio en la base no dispara un cálculo, dispara una
///   espera ([debounce]); otro cambio la reinicia. Una importación de mil
///   elementos da un cálculo, no mil. Para que un aluvión largo no deje el
///   mapa congelado, pasado [maxWait] desde el primer cambio se calcula igual.
/// - **Acotado**: solo escuchan las tablas que el mapa lee (ver
///   [KnowledgeMapRepository.changes]); repasar una tarjeta no lo mueve.
/// - **En caliente**: cada cálculo parte de las comunidades del anterior, así
///   que las identidades —y los colores— se conservan y solo se mueve lo que el
///   cambio movió. Los recuerdos son por categoría, no por filtro: filtrar no
///   recolorea.
/// - **En otro isolate**: armar el grafo y agruparlo corre fuera de la
///   interfaz; en el isolate principal solo se lee de la base y se entrega.
/// - **Fallo aislado**: si algo falla, el mapa lo cuenta como un estado
///   ([MapFailed], con el último mapa bueno) y lo registra; ningún error sale
///   de acá hacia el resto de la aplicación, y el próximo cambio reintenta.
/// - **En caché**: un mapa se conserva mientras nada de lo que lee haya
///   cambiado, así que volver a abrirlo no recalcula. Los que tienen un filtro
///   se descartan al dejar de mirarlos: sin oyente no se sabría si lo que el
///   filtro mira cambió.
class KnowledgeMapEngine {
  KnowledgeMapEngine({
    required KnowledgeMapRepository repository,
    required TelemetryService telemetry,
    MapComputer compute = computeMapInIsolate,
    this.debounce = const Duration(milliseconds: 400),
    this.maxWait = const Duration(seconds: 3),
    this.maxCachedRequests = 4,
  }) : _repository = repository,
       _telemetry = telemetry,
       _compute = compute {
    // Suscripta desde el nacimiento, ANTES que cualquier pedido: drift avisa a
    // sus oyentes en el orden en que se suscribieron, así que cuando un pedido
    // se entera de una escritura y calcula, la caché ya sabe que no vale.
    _writes = _repository.changes().listen((_) => _generation++);
  }

  final KnowledgeMapRepository _repository;
  final TelemetryService _telemetry;
  final MapComputer _compute;

  /// Cuánto se espera, sin cambios nuevos, antes de recalcular.
  final Duration debounce;

  /// Lo máximo que un aluvión de cambios puede demorar un cálculo.
  final Duration maxWait;

  /// Cuántos mapas sin filtro se guardan.
  final int maxCachedRequests;

  late final StreamSubscription<void> _writes;
  final _clock = Stopwatch()..start();
  final _entries = <MapRequest, _Entry>{};
  final _memories = <String, CommunityMemory>{};

  /// Cuántos cambios de lo que el mapa lee hubo desde que nació el motor: un
  /// mapa sirve si se calculó con la misma cuenta que hay ahora.
  int _generation = 0;
  int _sequence = 0;
  var _disposed = false;

  /// Cuántos cálculos se hicieron de verdad, sin contar los que salieron de la
  /// caché: para que las pruebas y las mediciones puedan decir «no se
  /// recalculó».
  int computations = 0;

  /// El mapa de [request], que se actualiza solo. Lo primero que sale es el
  /// estado que haya —el mapa en caché, o [MapLoading]—; si no está al día, se
  /// recalcula y sale el nuevo.
  Stream<KnowledgeMapState> watch(MapRequest request) {
    final entry = _entryFor(request);
    late final StreamController<KnowledgeMapState> controller;
    controller = StreamController<KnowledgeMapState>(
      onListen: () {
        entry.listeners.add(controller);
        _attach(entry);
        controller.add(entry.state);
        unawaited(_refreshIfStale(entry));
      },
      onCancel: () {
        entry.listeners.remove(controller);
        if (entry.listeners.isEmpty) _detach(entry);
      },
    );
    return controller.stream;
  }

  /// Deja de escuchar la base y de calcular. Lo llama quien creó el motor al
  /// terminar.
  Future<void> dispose() async {
    _disposed = true;
    await _writes.cancel();
    for (final entry in _entries.values.toList()) {
      await _close(entry);
    }
    _entries.clear();
  }

  _Entry _entryFor(MapRequest request) {
    final existing = _entries.remove(request);
    if (existing != null) {
      // Al final: el más recientemente pedido es el último en salir.
      return _entries[request] = existing;
    }
    final created = _entries[request] = _Entry(request);
    _evictOverflow();
    return created;
  }

  /// Se descartan los mapas sin filtro ni oyentes más viejos cuando pasan del
  /// tope.
  void _evictOverflow() {
    final idle = [
      for (final entry in _entries.values)
        if (entry.listeners.isEmpty && !entry.request.filter.isFiltered) entry,
    ];
    while (idle.length > maxCachedRequests) {
      final oldest = idle.removeAt(0);
      _entries.remove(oldest.request);
      unawaited(_close(oldest));
    }
  }

  /// Empieza a escuchar los cambios que pueden mover este mapa.
  void _attach(_Entry entry) {
    entry.changes ??= _repository
        .changes(filter: entry.request.filter)
        .listen((_) => _schedule(entry));
  }

  /// Deja de escuchar cuando nadie mira. Un mapa con filtro se descarta, y uno
  /// sin filtro queda en caché, validado por la cuenta de cambios.
  void _detach(_Entry entry) {
    unawaited(entry.stopListening());
    if (entry.request.filter.isFiltered) {
      _entries.remove(entry.request);
      unawaited(_close(entry));
    } else {
      _evictOverflow();
    }
  }

  Future<void> _close(_Entry entry) async {
    entry.closed = true;
    await entry.stopListening();
    for (final controller in entry.listeners.toList()) {
      await controller.close();
    }
    entry.listeners.clear();
  }

  /// Recalcula ahora si el mapa no existe o no está al día.
  Future<void> _refreshIfStale(_Entry entry) async {
    // El aviso de una escritura llega un instante DESPUÉS de que la escritura
    // termina: quien pide el mapa en seguida de escribir vería la cuenta sin
    // reflejar su propio cambio. Un turno del bucle de eventos deja entregar
    // los avisos en camino.
    await Future<void>.delayed(Duration.zero);
    if (entry.closed || _disposed) return;
    // Un mapa que falló no está al día aunque nada haya cambiado: volver a
    // mirarlo es pedir que se reintente.
    final fresh =
        entry.snapshot != null &&
        entry.generation == _generation &&
        entry.state is! MapFailed;
    // Con un cálculo en curso o esperando su turno, el mapa nuevo les llega a
    // todos los que miran cuando termine: no se pide otro.
    if (fresh || entry.timer != null || entry.running) return;
    await _drain(entry);
  }

  /// Un cambio llegó: se recalcula cuando se calme la ráfaga, o pasado
  /// [maxWait] desde el primero.
  void _schedule(_Entry entry) {
    if (entry.closed || _disposed) return;
    final now = _clock.elapsed;
    final since = entry.dirtySince ??= now;
    final remaining = maxWait - (now - since);
    final wait = remaining <= Duration.zero
        ? Duration.zero
        : (debounce < remaining ? debounce : remaining);
    entry.timer?.cancel();
    entry.timer = Timer(wait, () {
      entry
        ..timer = null
        ..dirtySince = null;
      unawaited(_drain(entry));
    });
  }

  /// Calcula el mapa de [entry]; si se pide otro mientras tanto, lo hace
  /// después de terminar, nunca en paralelo.
  Future<void> _drain(_Entry entry) async {
    if (entry.running) {
      entry.rerun = true;
      return;
    }
    entry.running = true;
    try {
      do {
        entry.rerun = false;
        await _run(entry);
      } while (entry.rerun && !entry.closed && !_disposed);
    } finally {
      entry.running = false;
    }
  }

  Future<void> _run(_Entry entry) async {
    final request = entry.request;
    final total = Stopwatch()..start();
    // La cuenta de ANTES de leer: si algo cambia mientras se calcula, el mapa
    // queda viejo de nacimiento y el próximo pedido lo recalcula.
    final generation = _generation;
    computations++;
    try {
      final input = await _repository.readTopicInput(
        request.definitionId,
        filter: request.filter,
      );
      final read = total.elapsed;
      final memory =
          _memories[request.definitionId] ?? const CommunityMemory.none();
      final computed = await _compute(input, memory);
      if (entry.closed || _disposed) return;

      _memories[request.definitionId] = computed.detection.memory;
      final snapshot = KnowledgeMapSnapshot(
        request: request,
        graph: computed.graph,
        detection: computed.detection,
        timings: MapTimings(
          read: read,
          build: computed.build,
          communities: computed.communities,
          total: total.elapsed,
        ),
        sequence: ++_sequence,
        unassignedItemIds: input.unassignedItemIds,
      );
      entry
        ..snapshot = snapshot
        ..generation = generation;
      _emit(entry, MapReady(snapshot));
      // Catch-all deliberado: el fallo del mapa es un estado del mapa, no una
      // excepción sin dueño que llegue a otra pantalla. Un `TypeError` o un
      // error de un isolate son tan válidos de reportar como una `Exception`.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stackTrace) {
      _telemetry.recordError(error, stackTrace, hint: 'KnowledgeMapEngine');
      if (entry.closed || _disposed) return;
      _emit(entry, MapFailed(error, lastGood: entry.snapshot));
    }
  }

  void _emit(_Entry entry, KnowledgeMapState state) {
    entry.state = state;
    for (final controller in entry.listeners.toList()) {
      if (!controller.isClosed) controller.add(state);
    }
  }
}

/// Lo que el motor sabe de un pedido.
class _Entry {
  _Entry(this.request);

  final MapRequest request;
  final listeners = <StreamController<KnowledgeMapState>>{};

  KnowledgeMapState state = const MapLoading();

  /// El último mapa bueno.
  KnowledgeMapSnapshot? snapshot;

  /// La cuenta de cambios con la que se leyó [snapshot].
  int generation = -1;

  /// Los cambios que le importan a este pedido; solo mientras hay oyentes.
  StreamSubscription<void>? changes;

  /// La espera que precede a un cálculo, y cuándo llegó el primer cambio de la
  /// ráfaga que la originó.
  Timer? timer;
  Duration? dirtySince;

  bool running = false;
  bool rerun = false;
  bool closed = false;

  /// Deja de escuchar la base y de esperar un cálculo.
  Future<void> stopListening() async {
    timer?.cancel();
    timer = null;
    dirtySince = null;
    final cancelling = changes?.cancel();
    changes = null;
    await cancelling;
  }
}
