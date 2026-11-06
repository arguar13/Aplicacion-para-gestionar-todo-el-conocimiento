import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/index/data/repositories/index_query_sql.dart';
import 'package:sinapsis/features/index/data/repositories/index_repository_impl.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_backfill.dart';

class _Telemetry extends Mock implements TelemetryService {}

/// El Índice a escala (F46, paso 2): 2.000 documentos procesados con 150
/// capítulos cada uno —300.000 entradas—, 1.000 imágenes y una Biblioteca de
/// 6.000 fuentes con sus temas. Cada consulta tiene que ir por índices —ningún
/// `SCAN` de las tablas grandes en su `EXPLAIN QUERY PLAN`— y responder en lo
/// que tarda un cuadro de la pantalla, o poco más, en la PC.
///
/// Lo único que se recorre entero es `processed_documents` (`SCAN d`): miles
/// de filas, no cientos de miles, y cada una va a lo demás por clave.
void main() {
  const documents = 2000;
  const chapters = 150;
  const library = 6000;
  const topics = 20;
  const seconds = 1790000000;

  late AppDatabase db;
  late IndexRepositoryImpl repository;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = IndexRepositoryImpl(database: db, telemetry: _Telemetry());
    final watch = Stopwatch()..start();
    await db.transaction(() async {
      Future<void> sql(String statement) => db.customStatement(statement);
      String upTo(int n) =>
          'WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n '
          'WHERE i < ${n - 1}) ';

      await sql(
        '${upTo(topics)}INSERT INTO spaces (id, name, created_at) '
        "SELECT 'tema-' || i, 'Tema ' || i, $seconds FROM n",
      );
      // La Biblioteca: fuentes con sus temas, que el Índice no tiene que
      // recorrer nunca.
      await sql(
        '${upTo(library)}INSERT INTO item (id, title, kind, state, '
        'created_at, updated_at, device_id) '
        "SELECT 'fuente-' || i, 'Fuente ' || i, 'source', 'triaged', "
        "$seconds, $seconds, 'x' FROM n",
      );
      await sql(
        '${upTo(library)}INSERT INTO item_spaces (item_id, space_id) '
        "SELECT 'fuente-' || i, 'tema-' || (i % $topics) FROM n",
      );
      // Lo procesado.
      await sql(
        '${upTo(documents)}INSERT INTO item (id, title, kind, state, '
        'created_at, updated_at, device_id, deleted_at) '
        "SELECT 'doc-' || i, 'Documento ' || i, 'note', 'processed', "
        "$seconds + i, $seconds + i, 'x', "
        'CASE WHEN i % 200 = 7 THEN $seconds END FROM n',
      );
      await sql(
        '${upTo(documents)}INSERT INTO note (item_id, note_kind, maturity) '
        "SELECT 'doc-' || i, 'processed', 'seed' FROM n",
      );
      await sql(
        '${upTo(documents)}INSERT INTO processed_documents (item_id, '
        "source_kind, created_at) SELECT 'doc-' || i, 'document', "
        '$seconds + i FROM n',
      );
      await sql(
        '${upTo(documents)}INSERT INTO item_spaces (item_id, space_id) '
        "SELECT 'doc-' || i, 'tema-' || (i % $topics) FROM n "
        'UNION ALL '
        "SELECT 'doc-' || i, 'tema-' || ((i + 1) % $topics) FROM n "
        'WHERE i % 3 = 0',
      );
      // Su texto —antes que sus entradas: escribir el texto las suelta— y
      // un resumen, que también es de `processed_parts`.
      await sql(
        '${upTo(documents)}INSERT INTO processed_parts (id, document_id, '
        'section, position, content, origin, edited, source_start, '
        'source_end, text_start, text_end, created_at, updated_at) '
        "SELECT 'texto-' || d.i || '-' || p.i, 'doc-' || d.i, 'text', p.i, "
        "'Una página del libro.', 'copied', 0, 0, 21, p.i * 21, "
        '(p.i + 1) * 21, $seconds, $seconds '
        'FROM n d, (SELECT 0 AS i UNION ALL SELECT 1 UNION ALL SELECT 2) p',
      );
      await sql(
        '${upTo(chapters)}INSERT INTO processed_headings (document_id, '
        'origin, level, position, title, text_start, text_end, text_page) '
        "SELECT 'doc-' || d.item_id_n, 'textHeading', 1 + c.i % 3, c.i, "
        "'Capítulo ' || c.i || ' ' || CASE c.i % 10 "
        "WHEN 0 THEN 'Roma y su República' WHEN 1 THEN 'El Concilio de Nicea' "
        "WHEN 2 THEN 'Arrio y la herejía' WHEN 3 THEN 'Constantino' "
        "WHEN 4 THEN 'Bizancio' WHEN 5 THEN 'Los godos' "
        "WHEN 6 THEN 'Cartago' WHEN 7 THEN 'Éfeso' "
        "WHEN 8 THEN 'Calcedonia' ELSE 'Epílogo' END "
        "|| CASE WHEN d.item_id_n = 1234 AND c.i = 77 THEN ' Zenobia' "
        "ELSE '' END, "
        'c.i * 10, c.i * 10 + 5, 1 + c.i / 50 '
        'FROM n c, (SELECT CAST(substr(item_id, 5) AS INTEGER) AS item_id_n '
        'FROM processed_documents) d',
      );
      // Mil imágenes, en 200 documentos: sus entradas las escribe la base.
      await sql(
        '${upTo(1000)}INSERT INTO renditions (id, item_id, kind, '
        'relative_path, is_primary, created_at) '
        "SELECT 'foto-' || i, 'doc-' || (i / 5), 'image', "
        "'originales/doc/imagenes/' || i || '.jpg', 0, $seconds FROM n",
      );
      await sql(
        '${upTo(1000)}INSERT INTO processed_images (rendition_id, '
        'document_id, position, source_file_path, source_file_size, '
        "copied_at, title) SELECT 'foto-' || i, 'doc-' || (i / 5), i % 5, "
        "'contenido/' || i || '.jpg', 1, $seconds, "
        "CASE WHEN i % 100 = 0 THEN NULL ELSE 'Mapa ' || i END FROM n",
      );
    });
    final count = await db
        .customSelect('SELECT COUNT(*) AS n FROM processed_headings')
        .getSingle();
    _say(
      'Bóveda armada en ${watch.elapsedMilliseconds} ms: '
      '${count.read<int>('n')} entradas.',
    );
    await db.customStatement('ANALYZE');
  });
  tearDownAll(() => db.close());

  /// El plan de [sql] con [variables]: un renglón por paso.
  Future<List<String>> plan(
    String sql,
    List<Variable<Object>> variables,
  ) async => [
    for (final row
        in await db
            .customSelect('EXPLAIN QUERY PLAN $sql', variables: variables)
            .get())
      row.read<String>('detail'),
  ];

  /// Lo que se puede recorrer entero: `processed_documents` (`d`), el índice
  /// de texto —que es su propia búsqueda—, la cadena de padres, una fila
  /// constante y el índice parcial de las imágenes sin titular.
  final allowedScans = RegExp(
    r'^SCAN (?:(?:d|c|chain)(?: USING (?:COVERING )?INDEX \w+)?|'
    'processed_heading_search VIRTUAL TABLE.*|CONSTANT ROW|'
    // Las imágenes sin titular, por su índice parcial: ninguna, pasado el
    // relleno.
    r'ui USING (?:COVERING )?INDEX idx_processed_images_untitled)$',
  );

  void expectIndexed(String name, List<String> steps) {
    _say('$name:\n  ${steps.join('\n  ')}');
    for (final step in steps) {
      if (!step.startsWith('SCAN ')) continue;
      expect(
        allowedScans.hasMatch(step),
        isTrue,
        reason: '$name recorre una tabla entera: «$step»',
      );
    }
  }

  /// Cuánto tarda [read], la mediana de cinco, en milisegundos.
  Future<double> timed(Future<Object?> Function() read) async {
    await read();
    final times = <int>[];
    for (var i = 0; i < 5; i++) {
      final watch = Stopwatch()..start();
      await read();
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    return times[2] / 1000;
  }

  test(
    'los temas con sus cuentas: una lectura, sin recorrer la Biblioteca',
    () async {
      expectIndexed('temas', await plan(indexTopicsSql, const []));
      final topicsRead = await repository.watchTopics().first;
      expect(topicsRead, hasLength(topics));
      final ms = await timed(() => repository.watchTopics().first);
      _say('temas: $ms ms');
    },
  );

  test('los documentos de un tema, de «Sin tema» y todos', () async {
    expectIndexed(
      'documentos de un tema',
      await plan(indexDocumentsOfTopicSql, [Variable.withString('tema-3')]),
    );
    expectIndexed(
      'documentos sin tema',
      await plan(indexUntopicedDocumentsSql, const []),
    );
    expectIndexed(
      'todos los documentos',
      await plan(indexDocumentsSql, const []),
    );

    final ofTopic = await repository.watchDocumentsOf('tema-3').first;
    expect(ofTopic.length, greaterThan(100));
    expect(ofTopic.first.chapterCount, chapters);
    const order = IndexDocumentOrder.title;
    final all = await repository.watchDocuments(order).first;
    expect(all, hasLength(documents - 10));
    _say(
      'documentos de un tema: '
      '${await timed(() => repository.watchDocumentsOf('tema-3').first)} ms; '
      'todos: '
      '${await timed(() => repository.watchDocuments(order).first)} ms',
    );
  });

  test('las entradas de un documento: solo las suyas, en su orden', () async {
    expectIndexed(
      'entradas',
      await plan(indexEntriesSql, [Variable.withString('doc-42')]),
    );
    final entries = await repository.watchEntries('doc-1').first;
    expect(entries, hasLength(chapters + 5));
    _say(
      'entradas de un documento: '
      '${await timed(() => repository.watchEntries('doc-1').first)} ms',
    );
  });

  test('la búsqueda va por el índice de texto y trae a cada uno con sus '
      'padres', () async {
    expectIndexed(
      'búsqueda',
      await plan(indexSearchSql, [
        Variable.withString(buildSearchQuery('nicea')),
        Variable.withInt(200),
      ]),
    );
    expectIndexed(
      'padres',
      await plan(indexAncestorsSql(3), [
        for (final key in [1, 2, 3]) Variable.withInt(key),
      ]),
    );

    final rare = await repository.watchSearch('zenobia').first;
    expect(rare.single.documentTitle, 'Documento 1234');
    expect(rare.single.entry.level, 3);
    expect(rare.single.ancestors.map((a) => (a.level, a.position)), [
      (1, 75),
      (2, 76),
    ]);
    final common = await repository.watchSearch('concilio nicea').first;
    expect(common, hasLength(200));
    for (final hit in common) {
      expect(hit.ancestors, hasLength(hit.entry.level - 1));
    }
    _say(
      'búsqueda rara: '
      '${await timed(() => repository.watchSearch('zenobia').first)} ms; '
      'común (200 con sus padres): '
      '${await timed(() => repository.watchSearch('concilio nicea').first)} ms',
    );
  });

  test('cómo va el relleno, y lo que le falta: sin recorrer las entradas ni '
      'la galería', () async {
    expectIndexed('relleno', await plan(indexProgressSql, const []));
    expectIndexed(
      'documentos sin indexar',
      await plan(headingsPendingDocumentsSql, [Variable.withInt(16)]),
    );
    expectIndexed(
      'si falta algo',
      await plan(headingsPendingWorkSql, const []),
    );
    expectIndexed(
      'imágenes sin titular',
      await plan(untitledProcessedImagesSql, [Variable.withInt(200)]),
    );
    final progress = await repository.watchProgress().first;
    expect(progress.documents, documents - 10);
    expect(progress.indexedDocuments, documents - 10);
    expect(progress.untitledImages, 10);
    _say('relleno: ${await timed(() => repository.watchProgress().first)} ms');
  });
}

/// Las cifras de la prueba, en la consola: es lo que se anota en el Avance.
void _say(String message) {
  // Una prueba de escala informa lo que midió; no hay otro canal.
  // ignore: avoid_print
  print(message);
}
