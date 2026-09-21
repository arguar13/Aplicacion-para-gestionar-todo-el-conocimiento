import 'package:drift/drift.dart' show Variable;
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/atlas/data/repositories/atlas_query_sql.dart';
import 'package:sinapsis/features/atlas/data/repositories/atlas_repository_impl.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_view.dart';
import 'package:sinapsis/features/atlas/presentation/services/atlas_markdown.dart';
import 'package:sinapsis/features/graph/domain/services/graph_layout.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';
import 'package:sinapsis/features/health/data/repositories/health_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_query_sql.dart'
    show valuesWithDescendantsSql;
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/timeline/data/repositories/timeline_repository_impl.dart';
import 'package:sinapsis/features/vocabulary/data/repositories/vocabulary_repository_impl.dart';
import 'package:sinapsis/features/vocabulary/domain/services/merge_candidates.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../support/fake_id_generator.dart';
import '../support/in_memory_file_store.dart';
import '../support/rss_sampler.dart';
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
    this.description = 'escritorio, sin describir',
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

  /// Dónde corrió, para el encabezado del informe: el modelo del teléfono, su
  /// Android y su memoria; o el equipo de escritorio. Un informe sin esto no
  /// dice de qué máquina son sus cifras.
  final String description;
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
      ..writeln('Equipo: ${env.description}')
      ..writeln(
        'Umbral: objetivo del encargo'
        '${env.targetDivisor == 1 ? '' : ' / ${env.targetDivisor}'}',
      )
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
  // Cuánto pesa el texto en disco: cuántas veces está guardado. Desde F10 el
  // texto íntegro de una fuente vive UNA vez en su forma principal
  // (`renditions.content`) y sus trozos en `chunks.content`; la tercera copia,
  // `source.full_text`, se retiró en v19.
  // -------------------------------------------------------------------
  test('el peso del texto en disco', () async {
    Future<int> bytes(String sql) async =>
        (await db.customSelect(sql).getSingle()).read<int>('n');

    final copies = {
      'formas de contenido (renditions.content)': await bytes(
        'SELECT COALESCE(SUM(LENGTH(CAST(content AS BLOB))), 0) AS n '
        'FROM renditions',
      ),
      'chunks (chunks.content)': await bytes(
        'SELECT COALESCE(SUM(LENGTH(CAST(content AS BLOB))), 0) AS n '
        'FROM chunks',
      ),
      'cuerpo del índice de elementos (item_search_content.c3)': await bytes(
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
    // Lo que ocupan los índices de texto, solo donde la compilación de SQLite
    // permite verlo (`dbstat`).
    final indexes = <String, int>{};
    try {
      for (final (label, prefix) in [
        ('índice de texto de los chunks (chunk_search)', 'chunk_search'),
        ('índice de texto de los elementos (item_search)', 'item_search'),
      ]) {
        indexes[label] = await bytes(
          'SELECT COALESCE(SUM(pgsize), 0) AS n FROM dbstat '
          "WHERE name LIKE '${prefix}_%'",
        );
      }
      // Cualquier fallo de `dbstat` —no existe en todas las compilaciones de
      // SQLite— deja el informe sin esa línea; no es un fallo de la medición.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      indexes.clear();
    }
    final lines = [
      for (final e in copies.entries) line(e.key, e.value),
      for (final e in indexes.entries) line(e.key, e.value),
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
          // Lo que hace la pantalla: la página de resultados, cada uno con
          // dónde está lo que se encontró.
          () => library.search(search(term())),
          target: 300,
          runs: 9,
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

  test('abrir el detalle del elemento más conectado', () async {
    // Sin objetivo del encargo: es el peor caso de la lista de relaciones, que
    // crece con las que tiene el elemento (aquí, más de mil). Referencia.
    check(
      await measure('detalle: el elemento más conectado', () async {
        await library.findById(vault.hubItemId);
        await organize.watchRelationsForItem(vault.hubItemId).first;
      }),
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

  // -------------------------------------------------------------------
  // F13: la jerarquía del vocabulario. Filtrar por un tema trae también lo de
  // sus subtemas. El encargo no fija un umbral: el plan aprobado pide el de la
  // búsqueda, 300 ms.
  // -------------------------------------------------------------------
  test(
    'filtrar por el tema raíz grande: lo suyo y lo de sus subtemas',
    () async {
      check(
        await measure(
          'filtro: tema raíz grande (con subtemas)',
          () => library.list(
            LibraryQuery(propertyValueIds: {vault.bigRootValueId}, limit: 50),
          ),
          target: 300,
          runs: 9,
        ),
      );
    },
  );

  test('filtrar por una hoja: el mismo filtro sin descendientes', () async {
    check(
      await measure(
        'filtro: una hoja (sin subtemas)',
        () => library.list(
          LibraryQuery(propertyValueIds: {vault.leafValueId}, limit: 50),
        ),
        target: 300,
        runs: 9,
      ),
    );
  });

  test(
    'todos los ids del tema raíz grande (línea de tiempo, Explorador)',
    () async {
      check(
        await measure(
          'filtro: los ids de todo el tema raíz grande',
          () => library.matchingIds(
            LibraryQuery(propertyValueIds: {vault.bigRootValueId}),
          ),
          // Sin objetivo del encargo: lo que la línea de tiempo pide para
          // filtrar sus eventos. Referencia.
        ),
      );
    },
  );

  // -------------------------------------------------------------------
  // F13, D3: dos maneras de resolver «el valor y todos sus descendientes».
  // La que está en la app es la CTE recursiva sobre `property_values`; la otra
  // es un CIERRE materializado —una fila por cada par (ascendiente,
  // descendiente)—, que aquí se arma como tabla temporal solo para medir: lo
  // que cuesta la consulta y lo que cuesta tenerlo. Se elige con estas cifras.
  // -------------------------------------------------------------------
  test('D3: CTE recursiva contra cierre materializado', () async {
    Future<int> count(String sql, List<Variable> args) async =>
        (await db.customSelect(sql, variables: args).getSingle()).read<int>(
          'n',
        );

    final tema = Variable.withString(vault.temaDefinitionId);
    final root = Variable.withString(vault.bigRootValueId);

    final buildWatch = Stopwatch()..start();
    await db.customStatement('DROP TABLE IF EXISTS temp.bench_closure');
    await db.customStatement(
      'CREATE TEMP TABLE bench_closure ( '
      'ancestor TEXT NOT NULL, descendant TEXT NOT NULL, '
      'PRIMARY KEY (ancestor, descendant)) WITHOUT ROWID',
    );
    await db.customStatement(
      'INSERT INTO bench_closure '
      'WITH RECURSIVE c(ancestor, descendant) AS ('
      ' SELECT id, id FROM property_values WHERE definition_id = ? '
      ' UNION SELECT c.ancestor, pv.id FROM property_values pv '
      '  JOIN c ON pv.parent_id = c.descendant) '
      'SELECT ancestor, descendant FROM c',
      [vault.temaDefinitionId],
    );
    final buildMs = buildWatch.elapsedMilliseconds;
    addTearDown(
      () => db.customStatement('DROP TABLE IF EXISTS temp.bench_closure'),
    );
    final closureRows = await count(
      'SELECT COUNT(*) AS n FROM bench_closure',
      [],
    );
    final temaValues = await count(
      'SELECT COUNT(*) AS n FROM property_values WHERE definition_id = ?',
      [tema],
    );
    final branchValues = await count(
      'SELECT COUNT(*) AS n FROM bench_closure WHERE ancestor = ?',
      [root],
    );

    // Lo que hace el filtro de la biblioteca, con una u otra fuente de
    // «el valor y sus descendientes».
    const items =
        'SELECT COUNT(*) AS n FROM item WHERE item.deleted_at IS NULL '
        'AND item.id IN (SELECT item_id FROM item_property_values '
        'WHERE property_value_id IN (';
    final cteSql =
        '$items'
        '${valuesWithDescendantsSql(1)}))';
    const closureSql =
        '$items'
        'SELECT descendant FROM bench_closure WHERE ancestor = ?))';

    late int viaCte;
    late int viaClosure;
    final cte = await measure(
      'D3: CTE recursiva, elementos del tema raíz grande',
      () async => viaCte = await count(cteSql, [root]),
      runs: 9,
    );
    final closure = await measure(
      'D3: cierre materializado, lo mismo',
      () async => viaClosure = await count(closureSql, [root]),
      runs: 9,
    );
    // Las dos maneras tienen que decir lo mismo: si no, la comparación no vale.
    expect(viaClosure, viaCte);
    results
      ..add(cte)
      ..add(closure);
    env.log('$cte');
    env.log('$closure');

    final vaultLine =
        'Bóveda: $temaValues valores de «Tema»; el tema raíz grande tiene '
        '$branchValues valores (él y sus descendientes) y $viaCte elementos.';
    final closureLine =
        'El cierre tiene $closureRows filas para $temaValues valores y se '
        'armó en $buildMs ms (tabla temporal, solo para medir).';
    final lines = [
      '# D3: CTE recursiva o cierre materializado',
      '',
      vaultLine,
      '',
      '```',
      '$cte',
      '$closure',
      '```',
      '',
      closureLine,
    ];
    env.log(lines.join('\n'));
    env.save('latest_hierarchy_report.md', lines.join('\n'));
  });

  // -------------------------------------------------------------------
  // F13: el Atlas. Abrirlo con 10.000 elementos y 2.000 valores en menos de
  // 500 ms (criterio de cierre de F13): los agregados de todas las ramas y el
  // árbol armado. La pantalla después solo dibuja las filas a la vista.
  // -------------------------------------------------------------------
  test('Atlas: abrir, con los agregados de todas las ramas', () async {
    AtlasRepositoryImpl newRepository() => AtlasRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      clock: () => vault.now,
    );

    late int nodes;
    late int gaps;
    late int mapNotes;
    final open = await measure(
      'Atlas: abrir (agregados + armado del árbol)',
      () async {
        // Un repositorio nuevo por vez: sin caché, que es lo que pasa la
        // primera vez que se abre.
        final repository = newRepository();
        try {
          final atlas = await repository.snapshot(vault.temaDefinitionId);
          nodes = atlas.nodes.length;
          gaps = atlas.gaps.length;
          mapNotes = atlas.nodes.fold(0, (sum, n) => sum + n.mapNotes.length);
        } finally {
          await repository.dispose();
        }
      },
      target: 500,
      runs: 7,
    );

    // Cuánto crece la memoria del proceso mientras se abre: muestreada desde
    // otro aislado, con el Atlas de más ramas que hay.
    final repository = newRepository();
    final sampler = await RssSampler.start();
    await repository.snapshot(vault.temaDefinitionId);
    final growth = await sampler.stop();
    await repository.dispose();

    String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
    final title =
        '# Atlas: abrirlo con ${vault.profile.items} elementos y '
        '${vault.profile.tagValues} temas';
    final shape =
        '$nodes ramas, $gaps vacíos detectados y $mapNotes marcas de notas '
        'mapa repartidas entre ellas.';
    final memory =
        'Memoria residente del proceso: +${mb(growth)} como máximo durante una '
        'apertura más. Es una cota: el montón ya viene calentado por las '
        'siete aperturas y los escenarios anteriores, no es el costo de la '
        'primera.';
    final lines = [title, '', shape, '', '```', '$open', '```', '', memory];
    env.log(lines.join('\n'));
    env.save('latest_atlas_report.md', lines.join('\n'));
    check(open);
    // Que midió trabajo de verdad: casi todos los valores de «Tema» son ramas.
    expect(nodes, greaterThan(vault.profile.tagValues ~/ 2));
  });

  test('Atlas: reabrirlo sin haber tocado nada (la caché)', () async {
    final repository = AtlasRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      clock: () => vault.now,
    );
    addTearDown(repository.dispose);
    // La primera vez calcula; las demás salen de la caché: la mediana es lo que
    // cuesta volver.
    check(
      await measure(
        'Atlas: reabrir con la caché',
        () => repository.snapshot(vault.temaDefinitionId),
        runs: 7,
      ),
    );
    expect(repository.computations, 1);
  });

  test('Atlas: solo lo que se lee de la base (SQL)', () async {
    // Un elemento por fila con sus valores de la categoría, y las notas mapa:
    // lo demás de abrir el Atlas es sumar por rama y armar el árbol, en Dart.
    check(
      await measure(
        'Atlas: leer los elementos y las notas mapa (SQL)',
        () async {
          await db
              .customSelect(
                atlasItemsSql,
                variables: [
                  Variable.withString(vault.temaDefinitionId),
                  Variable.withString(kFechaDelHechoCategoryName),
                ],
              )
              .get();
          await db
              .customSelect(
                atlasMapNotesSql,
                variables: [Variable.withString(vault.temaDefinitionId)],
              )
              .get();
        },
        runs: 7,
      ),
    );
  });

  test(
    'Atlas: buscar un tema entre todos y exportarlo como Markdown',
    () async {
      final repository = AtlasRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        clock: () => vault.now,
      );
      addTearDown(repository.dispose);
      final atlas = await repository.snapshot(vault.temaDefinitionId);

      check(
        await measure(
          'Atlas: buscar un tema (letras sueltas)',
          () async => visibleAtlasNodes(atlas, expanded: {}, query: 'ar'),
          runs: 9,
        ),
      );
      late int length;
      check(
        await measure('Atlas: exportar a Markdown', () async {
          length = atlasToMarkdown(
            atlas,
            AppLocalizationsEs(),
            now: vault.now,
          ).length;
        }),
      );
      env.log('Atlas exportado: ${length ~/ 1024} KB');
    },
  );

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
