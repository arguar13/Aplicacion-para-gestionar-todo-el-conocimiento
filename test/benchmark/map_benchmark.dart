import 'dart:typed_data' show Int32List;

import 'package:async/async.dart' show StreamQueue;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_repository_impl.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/community_detector.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';
import 'package:sinapsis/features/map/domain/services/map_layout.dart';
import 'package:sinapsis/features/map/domain/services/topic_graph_builder.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layout_runner.dart';

import '../support/fake_id_generator.dart';
import '../support/in_memory_file_store.dart';
import 'structured_map_repository.dart';
import 'structured_topics.dart';
import 'synthetic_vault.dart';
import 'vault_benchmark.dart'
    show BenchmarkEnvironment, Measurement, MockTelemetryService, measure;

/// Las iteraciones del layout que usa la vista del grafo: desde cero y en
/// caliente. Son las de `map_graph_view.dart`; se repiten acá para medir lo
/// mismo.
const _kColdIterations = 260;
const _kWarmIterations = 60;

/// El trabajo de layout de una escena, como lo arma la vista.
MapLayoutJob _jobOf(
  GraphScene scene, {
  required int iterations,
  MapLayout? from,
}) {
  final groups = Int32List(scene.nodes.length);
  for (var i = 0; i < groups.length; i++) {
    groups[i] = scene.nodes[i].group ?? -1 - i;
  }
  return (
    count: scene.nodes.length,
    links: scene.links,
    groups: groups,
    startX: from?.xs,
    startY: from?.ys,
    iterations: iterations,
  );
}

/// Los escenarios del benchmark del mapa de conocimiento (F14), compartidos por
/// la prueba de escritorio (`map_benchmark_test.dart`) y por la de dispositivo
/// (`integration_test/map_benchmark_test.dart`).
///
/// Mide lo que el mapa calcula y lee, contra la bóveda sintética de 10.000
/// elementos y 2.000 temas. Los tiempos son de referencia: el encargo no fija
/// un objetivo para ellos. El criterio de la fase —interacción fluida con 2.000
/// temas— es de cuadros, y se mide en el benchmark de dispositivo con la
/// pantalla real.
///
/// Dos bóvedas de temas, y no es un descuido:
///
/// - **La de la base** (v5), cuyos temas se asignan al azar. Su grafo es una
///   maraña sin estructura —una sola comunidad, decenas de miles de uniones—:
///   es el PEOR caso de coste de armarlo, y lo que la base tarda en entregar
///   cada vista. No sirve para juzgar comunidades ni panorama.
/// - **La estructurada**, que conserva el árbol de temas de la base y reparte
///   los elementos por áreas, con puentes entre ellas (ver
///   `structured_topics.dart`): la que tiene comunidades de verdad, y con la
///   que se miden el recálculo tras un cambio, cada nivel del grafo y el motor
///   entero.
void registerMapBenchmark(BenchmarkEnvironment env) {
  late AppDatabase db;
  late SyntheticVault vault;
  late KnowledgeMapRepositoryImpl repository;
  final results = <Measurement>[];
  final notes = <String>[];

  void check(Measurement m) {
    results.add(m);
    env.log('$m');
  }

  void note(String line) {
    notes.add(line);
    env.log(line);
  }

  setUpAll(() async {
    final opened = await env.open();
    db = opened.db;
    vault = opened.vault;
    final telemetry = MockTelemetryService();
    repository = KnowledgeMapRepositoryImpl(
      database: db,
      library: LibraryRepositoryImpl(
        database: db,
        telemetry: telemetry,
        files: InMemoryFileStore(),
        ids: FakeIdGenerator(prefix: 'bench'),
        clock: () => vault.now,
      ),
    );
  });

  tearDownAll(() async {
    final report = StringBuffer('# Benchmark del mapa de conocimiento\n\n')
      ..writeln('Esquema v${AppDatabase.currentSchemaVersion}')
      ..writeln('Equipo: ${env.description}')
      ..writeln(
        'Bóveda: ${vault.profile.items} elementos, '
        '${vault.profile.tagValues} temas en la categoría «Tema»',
      )
      ..writeln()
      ..writeln('```');
    for (final m in results) {
      report.writeln(m);
    }
    report
      ..writeln('```')
      ..writeln();
    for (final line in notes) {
      report.writeln('- $line');
    }
    env.log('\n$report');
    env.save('latest_map_report.md', report.toString());
    await db.close();
  });

  // -------------------------------------------------------------------
  // La bóveda de la base: sus temas están asignados al azar.
  // -------------------------------------------------------------------
  group('bóveda de la base (temas al azar)', () {
    late TopicGraphInput input;

    setUpAll(() async {
      input = await repository.readTopicInput(vault.temaDefinitionId);
    });

    test('leer de la base lo que pide el grafo (SQL)', () async {
      late TopicGraphInput read;
      check(
        await measure(
          'Mapa (base): leer elementos, valores y vínculos',
          () async {
            read = await repository.readTopicInput(vault.temaDefinitionId);
          },
          runs: 7,
        ),
      );
      expect(read.values, isNotEmpty);
      expect(read.items, isNotEmpty);
    });

    test('armar el grafo y detectar comunidades: el peor caso', () async {
      late TopicGraph graph;
      check(
        await measure('Mapa (base): armar el grafo de temas', () async {
          graph = buildTopicGraph(input);
        }, runs: 7),
      );
      late CommunityDetection detection;
      check(
        await measure('Mapa (base): comunidades en frío', () async {
          detection = detectCommunities(graph);
        }, runs: 7),
      );
      note(
        'Con los temas de la base, asignados al azar: ${graph.nodes.length} '
        'temas, ${graph.edges.length} uniones, '
        '${detection.communities.length} comunidad'
        '${detection.communities.length == 1 ? '' : 'es'} en '
        '${detection.passes} pasadas. Es el peor caso de coste de armar el '
        'grafo, y no dice nada de cómo salen las comunidades de una bóveda '
        'real.',
      );
    });

    test('lo que la base entrega a cada vista (SQL)', () async {
      check(
        await measure(
          'Mapa (base): el tablero',
          () => repository.readDashboard(),
          runs: 7,
        ),
      );
      check(
        await measure(
          'Mapa (base): esquema, los vínculos de la rama mayor',
          () => repository.schemaLinks(SchemaRef.topic(vault.bigRootValueId)),
          runs: 7,
        ),
      );
      check(
        await measure(
          'Mapa (base): esquema, las notas mapa',
          () => repository.readMapNotes(),
          runs: 7,
        ),
      );
      check(
        await measure(
          'Mapa (base): los elementos de la rama mayor',
          () => repository.readTopicItems(vault.bigRootValueId),
          runs: 7,
        ),
      );
      check(
        await measure(
          'Mapa (base): los elementos de una hoja',
          () => repository.readTopicItems(vault.leafValueId),
          runs: 7,
        ),
      );
    });

    test('con un filtro puesto: solo un tipo de fuente', () async {
      const filter = LibraryQuery(sourceKinds: {SourceKind.webPage});
      late TopicGraphInput read;
      check(
        await measure('Mapa (base): leer con un filtro por tipo', () async {
          read = await repository.readTopicInput(
            vault.temaDefinitionId,
            filter: filter,
          );
        }, runs: 7),
      );
      check(
        await measure(
          'Mapa (base): armar y detectar con el filtro',
          () async => computeMap(read, const CommunityMemory.none()),
          runs: 7,
        ),
      );
      expect(read.items.length, lessThan(input.items.length));
    });
  });

  // -------------------------------------------------------------------
  // Los mismos temas con estructura: comunidades de verdad.
  // -------------------------------------------------------------------
  group('temas con estructura', () {
    late TopicGraphInput input;
    late MapComputation cold;

    setUpAll(() async {
      final real = await repository.readTopicInput(vault.temaDefinitionId);
      input = structuredTopicInput(
        real,
        items: vault.profile.items,
        relations: vault.profile.relations,
      );
      cold = computeMap(input, const CommunityMemory.none());
    });

    test('armar el grafo y detectar comunidades, en frío', () async {
      late TopicGraph graph;
      check(
        await measure('Mapa: armar el grafo de temas', () async {
          graph = buildTopicGraph(input);
        }, runs: 7),
      );
      late CommunityDetection detection;
      check(
        await measure('Mapa: comunidades en frío', () async {
          detection = detectCommunities(graph);
        }, runs: 7),
      );
      final sizes = [for (final c in detection.communities) c.members.length]
        ..sort();
      final overview = aggregateCommunities(graph, detection);
      note(
        'Con los temas con estructura: ${graph.nodes.length} temas, '
        '${graph.edges.length} uniones, ${detection.communities.length} '
        'comunidades (la mayor, de ${sizes.last}; la menor, de ${sizes.first}) '
        'en ${detection.passes} pasadas'
        '${detection.converged ? '' : ', sin converger'}; el panorama dibuja '
        '${overview.nodes.length} nodos.',
      );
      expect(detection.communities.length, greaterThan(3));
    });

    test('tras un cambio, con lo ya calculado como punto de partida', () async {
      // Una captura: un elemento con tres temas de la misma área, vinculado a
      // otro de esa área.
      final area = input.items.first.valueIds;
      final capture = TopicGraphInput(
        definitionId: input.definitionId,
        definitionName: input.definitionName,
        values: input.values,
        items: [
          ...input.items,
          TopicItem(id: 'nuevo-1', valueIds: area),
        ],
        relations: [
          ...input.relations,
          TopicRelation(
            fromItemId: 'nuevo-1',
            toItemId: input.items.first.id,
            kind: RelationKind.relatedTo,
          ),
        ],
      );
      late MapComputation afterCapture;
      check(
        await measure(
          'Mapa: recalcular tras una captura (grafo + comunidades)',
          () async => afterCapture = computeMap(capture, cold.detection.memory),
          runs: 7,
        ),
      );
      note(
        'Tras una captura se reasignan ${afterCapture.detection.reassigned} '
        'temas de ${afterCapture.graph.nodes.length}, en '
        '${afterCapture.detection.passes} pasadas'
        '${afterCapture.detection.converged ? '' : ', sin converger'}.',
      );

      // Una importación: doscientos elementos de golpe.
      final import = TopicGraphInput(
        definitionId: input.definitionId,
        definitionName: input.definitionName,
        values: input.values,
        items: [
          ...input.items,
          for (var i = 0; i < 200; i++)
            TopicItem(
              id: 'importado-$i',
              valueIds: input.items[i * 7 % input.items.length].valueIds,
            ),
        ],
        relations: input.relations,
      );
      late MapComputation afterImport;
      check(
        await measure(
          'Mapa: recalcular tras importar 200 elementos',
          () async => afterImport = computeMap(import, cold.detection.memory),
          runs: 7,
        ),
      );
      note(
        'Tras importar 200 elementos se reasignan '
        '${afterImport.detection.reassigned} temas, en '
        '${afterImport.detection.passes} pasadas'
        '${afterImport.detection.converged ? '' : ', sin converger'}.',
      );
      // Las identidades no saltan: solo se mueve una fracción.
      expect(
        afterCapture.detection.reassigned,
        lessThan(afterCapture.graph.nodes.length ~/ 10),
      );
    });

    test('acomodar cada nivel del grafo', () async {
      // El panorama: una comunidad por nodo.
      final overview = sceneOfOverview(
        cold.graph,
        aggregateCommunities(cold.graph, cold.detection),
      );
      late MapLayout overviewLayout;
      check(
        await measure(
          'Mapa: acomodar el panorama (${overview.nodes.length}), en frío',
          () async => overviewLayout = runLayout(
            _jobOf(overview, iterations: _kColdIterations),
          ),
          runs: 7,
        ),
      );
      check(
        await measure(
          'Mapa: acomodar el panorama, en caliente',
          () async => runLayout(
            _jobOf(
              overview,
              iterations: _kWarmIterations,
              from: overviewLayout,
            ),
          ),
          runs: 7,
        ),
      );

      // Los temas: los más relevantes, hasta 300.
      final topics = sceneOfTopics(
        cold.graph,
        cold.detection,
        selectTopics(cold.graph),
      );
      late MapLayout topicsLayout;
      check(
        await measure(
          'Mapa: acomodar los temas (${topics.nodes.length}), en frío',
          () async => topicsLayout = runLayout(
            _jobOf(topics, iterations: _kColdIterations),
          ),
          runs: 7,
        ),
      );
      check(
        await measure(
          'Mapa: acomodar los temas, en caliente',
          () async => runLayout(
            _jobOf(topics, iterations: _kWarmIterations, from: topicsLayout),
          ),
          runs: 7,
        ),
      );

      // Los elementos de la rama mayor, hasta 200: de la base.
      final items = sceneOfItems(
        await repository.readTopicItems(vault.bigRootValueId),
      );
      check(
        await measure(
          'Mapa: acomodar los elementos (${items.nodes.length}), en frío',
          () async => runLayout(_jobOf(items, iterations: _kColdIterations)),
          runs: 7,
        ),
      );
      note(
        'El panorama tiene ${overview.nodes.length} nodos y '
        '${overview.edges.length} uniones; el nivel de temas, '
        '${topics.nodes.length} y ${topics.edges.length}; el de elementos, '
        '${items.nodes.length} y ${items.edges.length}.',
      );
    });

    test('el motor entero, con el isolate de verdad', () async {
      final structured = StructuredMapRepository(repository, input);
      addTearDown(structured.dispose);
      final engine = KnowledgeMapEngine(
        repository: structured,
        telemetry: MockTelemetryService(),
        debounce: const Duration(milliseconds: 100),
        maxWait: const Duration(seconds: 1),
      );
      addTearDown(engine.dispose);
      final queue = StreamQueue<KnowledgeMapState>(
        engine.watch(MapRequest(vault.temaDefinitionId)),
      );
      addTearDown(queue.cancel);

      /// El próximo mapa listo con una secuencia posterior a [after].
      Future<KnowledgeMapSnapshot> nextReady(int after) async {
        while (true) {
          final state = await queue.next.timeout(const Duration(minutes: 2));
          if (state is MapReady && state.snapshot.sequence > after) {
            return state.snapshot;
          }
        }
      }

      // El primer cálculo: leer, armar, detectar y traer el resultado.
      final firstWatch = Stopwatch()..start();
      final first = await nextReady(0);
      final firstMs = firstWatch.elapsedMilliseconds;

      // Una escritura y el recálculo, hasta que llega el mapa nuevo. La espera
      // por lotes (100 ms aquí; 400 ms en la app) va incluida.
      final writeWatch = Stopwatch()..start();
      structured.write(
        TopicGraphInput(
          definitionId: input.definitionId,
          definitionName: input.definitionName,
          values: input.values,
          items: [
            ...input.items,
            TopicItem(id: 'nuevo-2', valueIds: input.items.first.valueIds),
          ],
          relations: input.relations,
        ),
      );
      final second = await nextReady(first.sequence);
      final secondMs = writeWatch.elapsedMilliseconds;

      String inside(MapTimings t) =>
          'leer ${t.read.inMilliseconds} ms, armar '
          '${t.build.inMilliseconds} ms, comunidades '
          '${t.communities.inMilliseconds} ms, total '
          '${t.total.inMilliseconds} ms';
      note(
        'Motor entero, con el isolate: el primer mapa tarda $firstMs ms desde '
        'que se pide hasta que llega (${inside(first.timings)}); tras una '
        'escritura, $secondMs ms, con la espera de 100 ms incluida '
        '(${inside(second.timings)}).',
      );
      expect(second.sequence, greaterThan(first.sequence));
    });
  });
}
