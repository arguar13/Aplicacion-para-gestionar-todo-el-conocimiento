import 'package:drift/drift.dart' show Variable;
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/graph/domain/services/graph_layout.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';
import 'package:sinapsis/features/health/data/repositories/health_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/timeline/data/repositories/timeline_repository_impl.dart';
import 'package:sinapsis/features/vocabulary/data/repositories/vocabulary_repository_impl.dart';
import 'package:sinapsis/features/vocabulary/domain/services/merge_candidates.dart';

import '../support/fake_id_generator.dart';
import '../support/in_memory_file_store.dart';
import 'synthetic_vault.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Los escenarios del benchmark de la bóveda sintética, compartidos por la
/// prueba de escritorio (`vault_benchmark_test.dart`) y por la de dispositivo
/// (`integration_test/vault_benchmark_test.dart`): la misma medición en los dos
/// sitios, no dos que puedan diverger.
///
/// Se corre a propósito y no con toda la suite: arma —la primera vez— una
/// bóveda de 10.000 elementos y ~300.000 chunks, que tarda.
///
///     flutter test test/benchmark/vault_benchmark_test.dart \
///       --dart-define=BENCH=true --timeout none
///
/// Mide lo que la app hace de verdad para cada pantalla, no una versión
/// ideal. Los umbrales son los objetivos de la medición previa de F10 dividos
/// por [kDesktopFactor]: una PC de escritorio corre esto varias veces más
/// rápido que un Android de gama media, y el factor es una estimación, no una
/// medición —para medir en el teléfono, ver `integration_test`—.
/// Cuánto más rápida se supone que es esta máquina que un Android de gama
/// media. Estimación conservadora, no un dato.
const kDesktopFactor = 3;

class Measurement {
  Measurement(this.name, this.target, this.samples);

  final String name;

  /// El objetivo en milisegundos para un teléfono, o `null` si el encargo no
  /// fija ninguno y lo pone este benchmark como referencia.
  final int? target;
  final List<Duration> samples;

  Duration get cold => samples.first;

  Duration get median {
    final warm = [...samples.skip(1)]..sort();
    return warm.isEmpty ? cold : warm[warm.length ~/ 2];
  }

  int get ms => median.inMilliseconds;

  @override
  String toString() =>
      '${name.padRight(46)}'
      ' frío ${cold.inMilliseconds.toString().padLeft(6)} ms'
      '   mediana ${ms.toString().padLeft(6)} ms'
      '${target == null ? '' : '   objetivo $target ms'}';
}

Future<Measurement> measure(
  String name,
  Future<void> Function() action, {
  int? target,
  int runs = 5,
}) async {
  final samples = <Duration>[];
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    await action();
    samples.add(watch.elapsed);
  }
  return Measurement(name, target, samples);
}

/// Dónde y cómo corre el benchmark: de dónde sale la bóveda, adónde va lo que
/// se imprime y cuánto se divide el objetivo.
class BenchmarkEnvironment {
  const BenchmarkEnvironment({
    required this.open,
    required this.log,
    required this.save,
    this.targetDivisor = 1,
  });

  final Future<({AppDatabase db, SyntheticVault vault})> Function() open;
  final void Function(String message) log;

  /// Guarda un informe con este nombre, si el entorno tiene dónde: en el
  /// escritorio, `.dart_tool`; en un teléfono no hace falta: alcanza con el
  /// log.
  final void Function(String name, String content) save;

  /// El umbral que se exige es el objetivo del encargo dividido por esto. En
  /// escritorio es [kDesktopFactor], porque el objetivo es para un teléfono; en
  /// el teléfono mismo es 1: se exige el objetivo tal cual.
  final int targetDivisor;
}

/// Registra los escenarios: cada uno mide lo que hace la app de verdad para una
/// pantalla, contra la bóveda de [env].
void registerVaultBenchmark(BenchmarkEnvironment env) {
  late AppDatabase db;
  late SyntheticVault vault;
  late LibraryRepositoryImpl library;
  late OrganizeRepositoryImpl organize;
  final results = <Measurement>[];

  setUpAll(() async {
    final opened = await env.open();
    db = opened.db;
    vault = opened.vault;
    final telemetry = MockTelemetryService();
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: telemetry,
      files: InMemoryFileStore(),
      ids: FakeIdGenerator(prefix: 'bench'),
      clock: () => vault.now,
    );
    organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: telemetry,
      ids: FakeIdGenerator(prefix: 'org'),
      clock: () => vault.now,
    );
    final counts = vault.counts.entries.map((e) => '${e.key}=${e.value}');
    env.log('Bóveda: ${counts.join(', ')}');
  });

  tearDownAll(() async {
    final report = StringBuffer('# Benchmark de la bóveda sintética\n\n')
      ..writeln('Esquema v${AppDatabase.currentSchemaVersion}')
      ..writeln()
      ..writeln('```');
    for (final m in results) {
      report.writeln(m);
    }
    report.writeln('```');
    env.log('\n$report');
    env.save('latest_report.md', report.toString());
    await db.close();
  });

  void check(Measurement m) {
    results.add(m);
    env.log('$m');
    final target = m.target;
    if (target != null) {
      expect(
        m.ms,
        lessThan(target ~/ env.targetDivisor),
        reason:
            '${m.name}: ${m.ms} ms; el umbral es '
            '${target ~/ env.targetDivisor} ms '
            '($target ms / ${env.targetDivisor})',
      );
    }
  }

  LibraryQuery search(String term) =>
      LibraryQuery(searchText: term, sortBy: LibrarySort.relevance, limit: 50);

  // -------------------------------------------------------------------
  // Cuánto pesa el texto en disco: cuántas veces está guardado.
  // -------------------------------------------------------------------
  test('el peso del texto en disco', () async {
    Future<int> bytes(String sql) async =>
        (await db.customSelect(sql).getSingle()).read<int>('n');

    final copies = {
      'formas de contenido (renditions.content)': await bytes(
        'SELECT COALESCE(SUM(LENGTH(CAST(content AS BLOB))), 0) AS n '
        'FROM renditions',
      ),
      'texto íntegro (source.full_text)': await bytes(
        'SELECT COALESCE(SUM(LENGTH(CAST(full_text AS BLOB))), 0) AS n '
        'FROM source',
      ),
      'chunks (chunks.content)': await bytes(
        'SELECT COALESCE(SUM(LENGTH(CAST(content AS BLOB))), 0) AS n '
        'FROM chunks',
      ),
      'cuerpo del índice (item_search_content.c3)': await bytes(
        'SELECT COALESCE(SUM(LENGTH(CAST(c3 AS BLOB))), 0) AS n '
        'FROM item_search_content',
      ),
    };
    final pages = await bytes(
      'SELECT page_count AS n FROM pragma_page_count()',
    );
    final pageSize = await bytes(
      'SELECT page_size AS n FROM pragma_page_size()',
    );
    String line(String label, int size) =>
        '${label.padRight(46)} ${(size / 1048576).toStringAsFixed(1)} MB';
    final lines = [
      for (final e in copies.entries) line(e.key, e.value),
      line('el archivo de la base entero', pages * pageSize),
    ];
    env.log(lines.join('\n'));
    env.save('latest_footprint.txt', lines.join('\n'));
  });

  // -------------------------------------------------------------------
  // Búsqueda: objetivo del encargo, 300 ms.
  // -------------------------------------------------------------------
  for (final (label, term) in [
    ('palabra rara', () => vault.rareTerm),
    ('palabra mediana', () => vault.mediumTerm),
    ('palabra en casi todo', () => vault.commonTerm),
    ('dos palabras', () => '${vault.mediumTerm} ${vault.rareTerm}'),
    ('prefijo', () => vault.mediumTerm.substring(0, 3)),
  ]) {
    test('búsqueda de texto: $label', () async {
      check(
        await measure(
          'búsqueda: $label',
          () => library.list(search(term())),
          target: 300,
        ),
      );
    });
  }

  // -------------------------------------------------------------------
  // Detalle: objetivo del encargo, 200 ms.
  // -------------------------------------------------------------------
  test('abrir el detalle de la fuente más larga', () async {
    final renditionId =
        (await db
                .customSelect(
                  'SELECT id FROM renditions WHERE item_id = ?',
                  variables: [Variable.withString(vault.largestSourceId)],
                )
                .getSingle())
            .read<String>('id');
    check(
      await measure('detalle: la fuente con más chunks', () async {
        await library.findById(vault.largestSourceId);
        await organize.watchRelationsForItem(vault.largestSourceId).first;
        await organize.watchHighlightsForRendition(renditionId).first;
      }, target: 200),
    );
  });

  test('abrir el detalle de una nota', () async {
    check(
      await measure('detalle: una nota con enlaces', () async {
        await library.findById(vault.noteWithLinksId);
        await organize.watchRelationsForItem(vault.noteWithLinksId).first;
      }, target: 200),
    );
  });

  // -------------------------------------------------------------------
  // Grafo local: objetivo del encargo, 500 ms. Es el camino real de la
  // app: el vecindario desde la base, los elementos de esos vecinos, el
  // recorte y el layout.
  // -------------------------------------------------------------------
  Future<void> localGraph(
    String seed, {
    required int maxNodes,
    required Size canvas,
    int? degree = 1,
    int iterations = 150,
  }) async {
    final hood = await organize
        .watchNeighborhood(seedItemId: seed, maxNodes: maxNodes, degree: degree)
        .first;
    final items = (await library.list(
      LibraryQuery(ids: hood.nodeIds),
    )).getRight().toNullable()!;
    final scope = localGraphFrom(
      seedItemId: seed,
      items: items,
      edges: hood.edges,
      degree: degree,
    );
    computeGraphLayout(
      nodeIds: scope.nodeIds,
      edges: [for (final e in scope.edges) (e.fromItemId, e.toItemId)],
      canvasSize: canvas,
      iterations: iterations,
    );
  }

  const panelCanvas = Size(360, 240);
  const screenCanvas = Size(
    kLocalGraphScreenMaxNodes * 160.0,
    kLocalGraphScreenMaxNodes * 160.0,
  );

  test('grafo local: panel del detalle, elemento típico', () async {
    check(
      await measure(
        'grafo local: panel, elemento típico',
        () => localGraph(
          vault.typicalItemId,
          maxNodes: kLocalGraphPanelMaxNodes,
          canvas: panelCanvas,
        ),
        target: 500,
      ),
    );
  });

  test('grafo local: panel del detalle, el más conectado', () async {
    check(
      await measure(
        'grafo local: panel, el más conectado',
        () => localGraph(
          vault.hubItemId,
          maxNodes: kLocalGraphPanelMaxNodes,
          canvas: panelCanvas,
        ),
        target: 500,
      ),
    );
  });

  test('grafo local: pantalla completa, el más conectado', () async {
    check(
      await measure(
        'grafo local: pantalla, el más conectado',
        () => localGraph(
          vault.hubItemId,
          maxNodes: kLocalGraphScreenMaxNodes,
          canvas: screenCanvas,
          iterations: 300,
        ),
        target: 500,
        runs: 3,
      ),
    );
  });

  // -------------------------------------------------------------------
  // Sin objetivo fijado por el encargo: referencias de este benchmark.
  // -------------------------------------------------------------------
  test('línea de tiempo: los eventos de toda la bóveda', () async {
    final timeline = TimelineRepositoryImpl(
      database: db,
      library: library,
      telemetry: MockTelemetryService(),
    );
    check(
      await measure(
        'línea de tiempo: leer los eventos',
        () => timeline.watchEvents(const LibraryQuery()).first,
        target: 1000,
      ),
    );
  });

  test('panel de salud: los indicadores', () async {
    final health = HealthRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
    );
    check(
      await measure('panel de salud: todos los indicadores', () async {
        await health.watchNoteComposition().first;
        await health.watchUnreviewedContradictionCount().first;
        await health.watchBrokenLinkCount().first;
        await health
            .watchGrownNotes(since: vault.now.subtract(const Duration(days: 7)))
            .first;
      }, target: 600),
    );
  });

  test('vocabulario: candidatos a fusionar', () async {
    final vocabulary = VocabularyRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(prefix: 'voc'),
      clock: () => vault.now,
    );
    check(
      await measure('vocabulario: estadísticas + candidatos', () async {
        final stats = await vocabulary.watchValueStats().first;
        groupMergeCandidates(findMergeCandidates(stats));
      }, target: 3000),
    );
  });
}
