import 'dart:async';
import 'dart:isolate';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_repository_impl.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/domain/services/topic_graph_builder.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Un repositorio a mano: entrega lo que se le pone, puede fallar o demorarse
/// y avisa de un cambio cuando se le dice.
class FakeMapRepository implements KnowledgeMapRepository {
  FakeMapRepository(this.input);

  TopicGraphInput input;
  Error? failure;
  Completer<void>? gate;
  int reads = 0;
  final changed = StreamController<void>.broadcast();

  @override
  Future<TopicGraphInput> readTopicInput(
    String definitionId, {
    LibraryQuery filter = const LibraryQuery(),
  }) async {
    reads++;
    await gate?.future;
    final failure = this.failure;
    if (failure != null) throw failure;
    return input;
  }

  @override
  Future<MapDashboard> readDashboard({
    LibraryQuery filter = const LibraryQuery(),
  }) async => const MapDashboard.empty();

  @override
  Future<List<SchemaLink>> schemaLinks(
    SchemaRef node, {
    int limit = kSchemaFanOut,
  }) async => const [];

  @override
  Future<List<SchemaLink>> readMapNotes({int limit = kMaxMapNotes}) async =>
      const [];

  @override
  Future<TopicItemsGraph> readTopicItems(
    String valueId, {
    int limit = kMaxGraphItems,
  }) async => TopicItemsGraph.empty(valueId);

  @override
  Stream<void> changes({LibraryQuery filter = const LibraryQuery()}) =>
      changed.stream;

  void notify() => changed.add(null);

  /// Cambia lo que se entrega y avisa.
  void update(TopicGraphInput next) {
    input = next;
    notify();
  }

  /// Hace que la lectura falle, y avisa.
  void fail(Error error) {
    failure = error;
    notify();
  }

  /// Deja de fallar, y avisa.
  void recover() {
    failure = null;
    notify();
  }

  /// Hace que la lectura espere a que se libere [gate], y avisa.
  void hold() {
    gate = Completer<void>();
    notify();
  }
}

/// El motor del mapa (F14): por lotes, en caliente, con la caché acotada y con
/// el fallo aislado.
void main() {
  const request = MapRequest('tema');
  const debounce = Duration(milliseconds: 30);
  const maxWait = Duration(milliseconds: 150);

  late MockTelemetryService telemetry;
  late FakeMapRepository repository;
  late KnowledgeMapEngine engine;
  late int running;
  late int maxRunning;

  /// a, b / c, d: dos parejas de temas con seis elementos cada una y un
  /// vínculo entre las dos, que pesa menos que lo que une a cada pareja.
  TopicGraphInput inputOf({
    List<TopicItem>? extraItems,
    String definitionId = 'tema',
  }) => TopicGraphInput(
    definitionId: definitionId,
    definitionName: 'Tema',
    values: [
      for (final id in ['a', 'b', 'c', 'd']) AtlasValueRow(id: id, label: id),
    ],
    items: [
      for (var i = 1; i <= 6; i++) ...[
        TopicItem(id: 'p$i', valueIds: const ['a', 'b']),
        TopicItem(id: 'q$i', valueIds: const ['c', 'd']),
      ],
      ...?extraItems,
    ],
    relations: const [
      TopicRelation(
        fromItemId: 'p1',
        toItemId: 'q1',
        kind: RelationKind.relatedTo,
      ),
    ],
  );

  KnowledgeMapEngine newEngine({
    Duration debounce = debounce,
    Duration maxWait = maxWait,
    int maxCachedRequests = 4,
    MapComputer? compute,
  }) => KnowledgeMapEngine(
    repository: repository,
    telemetry: telemetry,
    debounce: debounce,
    maxWait: maxWait,
    maxCachedRequests: maxCachedRequests,
    compute:
        compute ??
        (input, memory) async {
          running++;
          if (running > maxRunning) maxRunning = running;
          // Un turno del bucle de eventos: es donde una segunda ejecución
          // paralela se metería.
          await Future<void>.delayed(const Duration(milliseconds: 10));
          running--;
          return computeMap(input, memory);
        },
  );

  setUp(() {
    telemetry = MockTelemetryService();
    repository = FakeMapRepository(inputOf());
    running = 0;
    maxRunning = 0;
    engine = newEngine();
  });

  tearDown(() async {
    await engine.dispose();
    await repository.changed.close();
  });

  Future<void> until(bool Function() condition, {String reason = ''}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('No ocurrió: $reason');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Escucha [stream] y junta lo que sale.
  ({
    List<KnowledgeMapState> states,
    List<Object> errors,
    StreamSubscription<void> subscription,
  })
  listenTo(Stream<KnowledgeMapState> stream) {
    final states = <KnowledgeMapState>[];
    final errors = <Object>[];
    // Lo cancela quien llama, al final de cada prueba.
    // ignore: cancel_subscriptions
    final subscription = stream.listen(states.add, onError: errors.add);
    return (states: states, errors: errors, subscription: subscription);
  }

  List<KnowledgeMapSnapshot> readyOf(List<KnowledgeMapState> states) => [
    for (final state in states)
      if (state is MapReady) state.snapshot,
  ];

  test('lo primero que sale es «cargando», y después el mapa', () async {
    final seen = listenTo(engine.watch(request));

    await until(() => readyOf(seen.states).isNotEmpty, reason: 'primer mapa');

    expect(seen.states.first, isA<MapLoading>());
    final snapshot = readyOf(seen.states).single;
    expect(snapshot.graph.nodes, hasLength(4));
    expect(snapshot.detection.communities, hasLength(2));
    expect(snapshot.request, request);
    expect(engine.computations, 1);
    await seen.subscription.cancel();
  });

  test('vuelve a abrirse sin recalcular mientras nada haya cambiado', () async {
    final first = listenTo(engine.watch(request));
    await until(() => readyOf(first.states).isNotEmpty);
    await first.subscription.cancel();

    final second = listenTo(engine.watch(request));
    await Future<void>.delayed(debounce * 4);

    // El mapa en caché sale primero, sin pasar por «cargando».
    expect(second.states.first, isA<MapReady>());
    expect(
      readyOf(second.states).single.sequence,
      readyOf(first.states).single.sequence,
    );
    expect(engine.computations, 1);
    expect(repository.reads, 1);
    await second.subscription.cancel();
  });

  test('dos que miran lo mismo comparten un solo cálculo', () async {
    final one = listenTo(engine.watch(request));
    final other = listenTo(engine.watch(request));

    await until(
      () => readyOf(one.states).isNotEmpty && readyOf(other.states).isNotEmpty,
    );

    expect(engine.computations, 1);
    expect(readyOf(one.states).single, same(readyOf(other.states).single));
    await one.subscription.cancel();
    await other.subscription.cancel();
  });

  group('por lotes', () {
    test('un cambio recalcula, y el mapa nuevo sale solo', () async {
      final seen = listenTo(engine.watch(request));
      await until(() => readyOf(seen.states).isNotEmpty);

      repository.update(
        inputOf(
          extraItems: const [
            TopicItem(id: 'i5', valueIds: ['a', 'c']),
          ],
        ),
      );
      await until(() => readyOf(seen.states).length == 2, reason: 'recálculo');

      final [before, after] = readyOf(seen.states);
      expect(after.sequence, greaterThan(before.sequence));
      expect(after.graph.nodes[after.graph.indexOf('a')!].itemCount, 7);
      await seen.subscription.cancel();
    });

    test('una ráfaga de cambios da un solo cálculo', () async {
      final seen = listenTo(engine.watch(request));
      await until(() => readyOf(seen.states).isNotEmpty);

      // Una ráfaga de verdad: cada cambio le devuelve el turno al bucle de
      // eventos, pero sin esperas cronometradas. Con 3 ms reales entre uno y
      // otro, una máquina cargada estiraba alguno más allá de la espera del
      // motor, la ráfaga se partía en dos y daba tres cálculos.
      for (var i = 0; i < 10; i++) {
        repository.notify();
        await Future<void>.delayed(Duration.zero);
      }
      await until(() => readyOf(seen.states).length == 2, reason: 'ráfaga');
      await Future<void>.delayed(debounce * 4);

      expect(engine.computations, 2);
      expect(readyOf(seen.states), hasLength(2));
      await seen.subscription.cancel();
    });

    test('un aluvión largo no congela el mapa: pasado el máximo, calcula '
        'igual', () async {
      final seen = listenTo(engine.watch(request));
      await until(() => readyOf(seen.states).isNotEmpty);

      // Un cambio cada 15 ms durante medio segundo: nunca hay una pausa de
      // 30 ms que cierre la ráfaga.
      var during = 0;
      for (var i = 0; i < 34; i++) {
        repository.notify();
        await Future<void>.delayed(const Duration(milliseconds: 15));
        during = readyOf(seen.states).length;
      }

      expect(
        during,
        greaterThanOrEqualTo(2),
        reason: 'calculó a mitad del aluvión',
      );
      expect(engine.computations, lessThan(34));
      await seen.subscription.cancel();
    });

    test('un cambio durante un cálculo no se pierde, y nunca corren dos a la '
        'vez', () async {
      final seen = listenTo(engine.watch(request));
      await until(() => readyOf(seen.states).isNotEmpty);

      repository.hold();
      await until(() => repository.reads == 2, reason: 'lectura en curso');
      // Con la lectura en curso llegan otros dos cambios.
      repository.update(
        inputOf(
          extraItems: const [
            TopicItem(id: 'i5', valueIds: ['a', 'd']),
          ],
        ),
      );
      await Future<void>.delayed(debounce * 3);
      repository.gate!.complete();
      repository.gate = null;

      await until(
        () => readyOf(
          seen.states,
        ).any((s) => s.graph.nodes[s.graph.indexOf('a')!].itemCount == 7),
        reason: 'el cambio de durante el cálculo',
      );
      expect(maxRunning, 1);
      await seen.subscription.cancel();
    });

    test(
      'un cambio mientras nadie mira se nota al volver: recalcula',
      () async {
        final first = listenTo(engine.watch(request));
        await until(() => readyOf(first.states).isNotEmpty);
        await first.subscription.cancel();

        repository.update(
          inputOf(
            extraItems: const [
              TopicItem(id: 'i5', valueIds: ['b', 'c']),
            ],
          ),
        );

        final second = listenTo(engine.watch(request));
        await until(
          () => readyOf(second.states).length == 2,
          reason: 'al volver',
        );

        // Primero el mapa de antes; después el nuevo.
        expect(
          readyOf(second.states).last.graph.nodes.map((n) => n.itemCount),
          [6, 7, 7, 6],
        );
        await second.subscription.cancel();
      },
    );
  });

  group('en caliente', () {
    test('recalcular conserva las identidades de las comunidades', () async {
      final seen = listenTo(engine.watch(request));
      await until(() => readyOf(seen.states).isNotEmpty);

      repository.update(
        inputOf(
          extraItems: const [
            TopicItem(id: 'i5', valueIds: ['a', 'b']),
          ],
        ),
      );
      await until(() => readyOf(seen.states).length == 2);

      final [before, after] = readyOf(seen.states);
      expect(after.detection.reassigned, 0);
      expect(
        [for (final c in after.detection.communities) c.id],
        [for (final c in before.detection.communities) c.id],
      );
      await seen.subscription.cancel();
    });

    test('filtrar no recolorea: los recuerdos son de la categoría', () async {
      final all = listenTo(engine.watch(request));
      await until(() => readyOf(all.states).isNotEmpty);
      final filtered = listenTo(
        engine.watch(
          const MapRequest(
            'tema',
            filter: LibraryQuery(sourceKinds: {SourceKind.webPage}),
          ),
        ),
      );
      await until(() => readyOf(filtered.states).isNotEmpty);

      final a = readyOf(all.states).single.detection;
      final b = readyOf(filtered.states).single.detection;
      expect(b.communityOf, a.communityOf);
      expect(b.reassigned, 0);
      await all.subscription.cancel();
      await filtered.subscription.cancel();
    });
  });

  group('el fallo aislado', () {
    test('si el cálculo falla, es un estado del mapa: el último bueno se '
        'conserva, se registra y ningún error escapa', () async {
      final seen = listenTo(engine.watch(request));
      await until(() => readyOf(seen.states).isNotEmpty);

      repository.fail(StateError('la base no responde'));
      await until(() => seen.states.last is MapFailed, reason: 'fallo');

      final failed = seen.states.last as MapFailed;
      expect(failed.error, isA<StateError>());
      expect(failed.lastGood, same(readyOf(seen.states).single));
      expect(seen.errors, isEmpty, reason: 'el stream nunca da error');
      verify(
        () => telemetry.recordError(
          any<dynamic>(),
          any(),
          hint: 'KnowledgeMapEngine',
        ),
      ).called(1);
      await seen.subscription.cancel();
    });

    test('el siguiente cambio reintenta y el mapa se recupera', () async {
      final seen = listenTo(engine.watch(request));
      await until(() => readyOf(seen.states).isNotEmpty);
      repository.fail(StateError('falla'));
      await until(() => seen.states.last is MapFailed);

      repository.recover();
      await until(() => seen.states.last is MapReady, reason: 'recuperación');

      expect(readyOf(seen.states), hasLength(2));
      await seen.subscription.cancel();
    });

    test('volver a mirar un mapa que falló lo reintenta, aunque nada haya '
        'cambiado', () async {
      final first = listenTo(engine.watch(request));
      await until(() => readyOf(first.states).isNotEmpty);
      repository.fail(StateError('falla'));
      await until(() => first.states.last is MapFailed);
      await first.subscription.cancel();

      // Se arregla lo que fallaba, sin que la base avise de ningún cambio.
      repository.failure = null;
      final second = listenTo(engine.watch(request));
      await until(
        () => second.states.any((s) => s is MapReady),
        reason: 'reintento',
      );

      expect(engine.computations, 3);
      await second.subscription.cancel();
    });

    test('un fallo del cálculo en sí también queda contenido', () async {
      await engine.dispose();
      engine = newEngine(
        compute: (input, memory) async => throw StateError('el isolate cayó'),
      );

      final seen = listenTo(engine.watch(request));
      await until(() => seen.states.any((s) => s is MapFailed));

      final failed = seen.states.whereType<MapFailed>().single;
      expect(failed.lastGood, isNull);
      expect(seen.errors, isEmpty);
      await seen.subscription.cancel();
    });

    test('un fallo del mapa no toca a otro pedido', () async {
      final seen = listenTo(engine.watch(request));
      await until(() => readyOf(seen.states).isNotEmpty);

      repository.failure = StateError('falla');
      final other = listenTo(engine.watch(const MapRequest('otra')));
      await until(() => other.states.any((s) => s is MapFailed));

      expect(seen.states.last, isA<MapReady>());
      await seen.subscription.cancel();
      await other.subscription.cancel();
    });
  });

  group('la caché', () {
    test('un mapa con filtro se descarta al dejar de mirarlo', () async {
      const filtered = MapRequest(
        'tema',
        filter: LibraryQuery(sourceKinds: {SourceKind.webPage}),
      );
      final first = listenTo(engine.watch(filtered));
      await until(() => readyOf(first.states).isNotEmpty);
      await first.subscription.cancel();

      final second = listenTo(engine.watch(filtered));
      await until(() => readyOf(second.states).isNotEmpty);

      expect(second.states.first, isA<MapLoading>());
      expect(engine.computations, 2);
      await second.subscription.cancel();
    });

    test('se guardan los últimos mapas sin filtro, y los más viejos se '
        'descartan', () async {
      await engine.dispose();
      engine = newEngine(maxCachedRequests: 2);
      for (final id in ['d1', 'd2', 'd3']) {
        final seen = listenTo(engine.watch(MapRequest(id)));
        await until(() => readyOf(seen.states).isNotEmpty);
        await seen.subscription.cancel();
      }

      // d3 y d2 siguen; d1 se fue.
      final d3 = listenTo(engine.watch(const MapRequest('d3')));
      final d1 = listenTo(engine.watch(const MapRequest('d1')));
      await until(() => readyOf(d1.states).isNotEmpty);

      expect(d3.states.first, isA<MapReady>());
      expect(d1.states.first, isA<MapLoading>());
      await d3.subscription.cancel();
      await d1.subscription.cancel();
    });
  });

  group('al terminar', () {
    test('dispose cierra los flujos y no queda nada calculando', () async {
      final seen = listenTo(engine.watch(request));
      await until(() => readyOf(seen.states).isNotEmpty);
      final done = seen.subscription.asFuture<void>();

      await engine.dispose();
      await done.timeout(const Duration(seconds: 2));

      final before = engine.computations;
      repository.notify();
      await Future<void>.delayed(debounce * 4);
      expect(engine.computations, before);
    });
  });

  group('en otro isolate', () {
    test(
      'el cálculo cruza el isolate y da lo mismo que en el propio',
      () async {
        final input = inputOf();
        const memory = CommunityMemory.none();

        final local = computeMap(input, memory);
        final remote = await computeMapInIsolate(input, memory);

        expect(
          [for (final n in remote.graph.nodes) n.valueId],
          [for (final n in local.graph.nodes) n.valueId],
        );
        expect(remote.graph.edges, hasLength(local.graph.edges.length));
        expect(remote.detection.communityOf, local.detection.communityOf);
        expect(
          remote.detection.memory.byValueId,
          local.detection.memory.byValueId,
        );
        // El índice del grafo funciona del otro lado.
        expect(remote.graph.indexOf('c'), local.graph.indexOf('c'));
      },
    );

    test('un grafo con su índice ya armado también cruza', () async {
      final input = inputOf();
      final graph = buildTopicGraph(input)..indexOf('a');

      final echoed = await _throughIsolate(graph);

      expect(echoed.indexOf('a'), graph.indexOf('a'));
    });
  });

  group('con la base de verdad', () {
    late AppDatabase db;
    late KnowledgeMapEngine real;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      real = KnowledgeMapEngine(
        repository: KnowledgeMapRepositoryImpl(
          database: db,
          library: LibraryRepositoryImpl(
            database: db,
            telemetry: MockTelemetryService(),
            files: InMemoryFileStore(),
          ),
        ),
        telemetry: MockTelemetryService(),
        debounce: debounce,
        maxWait: maxWait,
      );
    });

    tearDown(() async {
      await real.dispose();
      await db.close();
    });

    test('escribir una relación recalcula el mapa, en el isolate', () async {
      final tema =
          (await (db.select(db.propertyDefinitions)..where(
                    (d) =>
                        d.isSystem.equals(true) &
                        d.name.lower().equals(kTemaCategoryName.toLowerCase()),
                  ))
                  .getSingle())
              .id;
      final now = DateTime(2026, 9, 21, 10);
      for (final id in ['roma', 'grecia']) {
        await db
            .into(db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: id,
                definitionId: tema,
                value: id,
                createdAt: now,
              ),
            );
      }
      for (final (item, value) in [('s1', 'roma'), ('s2', 'grecia')]) {
        await insertItemRows(db, id: item, title: 'Fuente $item');
        await db
            .into(db.itemPropertyValues)
            .insert(
              ItemPropertyValuesCompanion.insert(
                itemId: item,
                propertyValueId: value,
              ),
            );
      }

      final seen = listenTo(real.watch(MapRequest(tema)));
      await until(() => readyOf(seen.states).isNotEmpty, reason: 'primer mapa');
      expect(readyOf(seen.states).single.graph.edges, isEmpty);

      await db
          .into(db.relations)
          .insert(
            RelationsCompanion.insert(
              id: 'r1',
              fromItemId: 's1',
              toItemId: 's2',
              kind: RelationKind.contradicts,
              createdAt: now,
            ),
          );
      await until(
        () => readyOf(seen.states).length == 2,
        reason: 'con la relación',
      );

      final edge = readyOf(seen.states).last.graph.edges.single;
      expect(edge.isTension, isTrue);
      expect(edge.openContradictions, 1);
      expect(
        readyOf(seen.states).last.timings.total,
        greaterThan(Duration.zero),
      );
      await seen.subscription.cancel();
    });
  });
}

/// Manda [graph] a otro isolate y lo trae de vuelta. Es una función aparte
/// porque un cierre creado dentro de `main` arrastra todo su contexto —el
/// motor y sus suscripciones—, y eso no cruza un isolate.
Future<TopicGraph> _throughIsolate(TopicGraph graph) =>
    Isolate.run(() => graph);
