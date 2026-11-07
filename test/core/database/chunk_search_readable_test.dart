import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_search_text_backfill.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../support/fake_id_generator.dart';
import '../../support/in_memory_file_store.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

const _thumb = 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/84';
const _wiki = 'https://es.wikipedia.org/wiki';

/// El índice de los chunks busca lo que se LEE de un texto en Markdown, no sus
/// direcciones (F46, paso 5i), contra SQLite real: en el emulador, buscar
/// «Fotosintesis» encontraba la palabra adentro de la dirección de una foto.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  final now = DateTime(2026, 11, 6, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: _MockTelemetry(),
      files: InMemoryFileStore(),
    );
    counter = 0;
  });

  tearDown(() => db.close());

  /// Guarda una fuente con [text] por el camino de la app, que la fragmenta.
  Future<String> save(
    String text, {
    SourceKind kind = SourceKind.webPage,
    String? originalFilePath,
  }) async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: 'Fuente $n',
      source: Source(
        id: 'src-$n',
        kind: kind,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
        originalFilePath: originalFilePath,
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        Rendition.text(
          id: 'rend-$n',
          itemId: 'item-$n',
          kind: RenditionKind.markdown,
          content: text,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
    return (await library.save(item)).getRight().toNullable()!.id;
  }

  Future<int> matches(String userInput) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM chunk_search WHERE chunk_search MATCH ?',
          variables: [Variable.withString(buildSearchQuery(userInput))],
        )
        .getSingle();
    return row.read<int>('n');
  }

  Future<void> integrityCheck() => db.customStatement(
    "INSERT INTO chunk_search (chunk_search) VALUES ('integrity-check')",
  );

  const page =
      'La planta crece al sol.\n'
      '\n'
      '![]($_thumb/Fotosintesis_ox_ano.png)\n'
      '\n'
      'El oxígeno sube debido a la '
      '[**fotosíntesis**]($_wiki/Fotos%C3%ADntesis) de las algas[1].';

  group('lo que se busca de un chunk', () {
    test('de una página web, lo que se lee: las palabras de las direcciones '
        'no están', () async {
      await save(page);

      expect(await matches('wikimedia'), 0);
      expect(await matches('upload'), 0);
      expect(await matches('ox_ano'), 0);
      expect(await matches('wiki'), 0);
      // La palabra se encuentra donde se lee, una sola vez: la foto no
      // tiene texto alternativo, y su dirección ya no cuenta.
      expect(await matches('fotosintesis'), 1);
      expect(await matches('algas'), 1);
    });

    test('una palabra que solo está en la dirección de una foto no encuentra '
        'el chunk', () async {
      await save(
        'Las hojas verdes.\n\n'
        '![](https://upload.wikimedia.org/Fotosintesis.png)',
      );

      expect(await matches('fotosintesis'), 0);
      expect(await matches('hojas'), 1);
    });

    test('cada chunk guardado lleva la versión de la regla: el relleno no '
        'tiene nada que rehacer', () async {
      await save(page);
      await save(
        'Ver https://upload.wikimedia.org/a.png',
        kind: SourceKind.document,
        originalFilePath: 'a.pdf',
      );

      final chunks = await db.select(db.chunks).get();
      expect(chunks.map((c) => c.searchTextRule).toSet(), {
        kChunkSearchTextRule,
      });
      expect(await ChunkSearchTextBackfill(database: db).run(), 0);
    });

    test('se guarda lo que se lee, y el texto de la Biblioteca queda tal '
        'cual', () async {
      final id = await save(page);

      final chunks = await (db.select(
        db.chunks,
      )..where((c) => c.itemId.equals(id))).get();
      expect(chunks.map((c) => c.content).join(), page);
      final read = chunks.map((c) => c.searchText ?? c.content).join('\n');
      expect(read, isNot(contains('](')));
      expect(read, isNot(contains('![')));
      expect(read, isNot(contains('http')));
      expect(read, isNot(contains('**')));
      expect(read, contains('debido a la fotosíntesis de las algas.'));
      final rendition = await (db.select(
        db.renditions,
      )..where((r) => r.itemId.equals(id))).getSingle();
      expect(rendition.content, page);
    });

    test('un texto que no es Markdown se busca tal cual: un PDF con una '
        'dirección la encuentra', () async {
      await save(
        'Ver la foto en https://upload.wikimedia.org/foto.png del anexo.',
        kind: SourceKind.document,
        originalFilePath: 'libros/anexo.pdf',
      );

      expect(await matches('wikimedia'), 1);
      final chunk = await db.select(db.chunks).getSingle();
      expect(chunk.searchText, isNull);
    });

    test('un Word convertido es Markdown: sus direcciones tampoco se '
        'encuentran', () async {
      await save(
        'Ver la [cita](https://upload.wikimedia.org/cita) del anexo.',
        kind: SourceKind.document,
        originalFilePath: 'notas/tesis.docx',
      );

      expect(await matches('wikimedia'), 0);
      expect(await matches('cita'), 1);
    });

    test('un Markdown sin nada que no se lea no se guarda dos veces', () async {
      await save('Un párrafo sin marcas.\n\nY otro igual.');

      final chunks = await db.select(db.chunks).get();
      expect(chunks, isNotEmpty);
      expect(chunks.every((c) => c.searchText == null), isTrue);
    });

    test('las palabras cortadas con guion al final del renglón se siguen '
        'encontrando en un Markdown (F22)', () async {
      await save(
        'He eludido las ex-\nplicaciones de la [fuente](https://x.org).',
      );

      expect(await matches('explicaciones'), 1);
      expect(await matches('las explicaciones de la fuente'), 1);
      expect(await matches('fuente'), 1);
      expect(await matches('x.org'), 0);
    });

    test(
      'rehacer los chunks —el texto cambió— deja el índice exacto',
      () async {
        final id = await save(page);
        await integrityCheck();

        await (db.update(
          db.renditions,
        )..where((r) => r.itemId.equals(id))).write(
          const RenditionsCompanion(
            content: Value('Otra [página](https://otra.org/clorofila).'),
          ),
        );
        final outcome = await chunkAndPersistSource(
          db,
          itemId: id,
          ids: FakeIdGenerator(),
        );

        expect(outcome, SourceChunkingOutcome.rebuilt);
        expect(await matches('fotosintesis'), 0);
        expect(await matches('clorofila'), 0);
        expect(await matches('pagina'), 1);
        // Si una baja le hubiera dicho al índice otro texto que el indexado,
        // esto falla.
        await integrityCheck();
      },
    );

    test('cambiar lo que se lee de un chunk lo cambia en el índice', () async {
      await save(page);
      final chunk = (await db.select(db.chunks).get()).last;

      await (db.update(db.chunks)..where((c) => c.rowKey.equals(chunk.rowKey)))
          .write(const ChunksCompanion(searchText: Value('Clorofila.')));

      expect(await matches('algas'), 0);
      expect(await matches('clorofila'), 1);
      await integrityCheck();
    });

    test('reconstruir el índice indexa exactamente lo mismo que los '
        'triggers', () async {
      await save(page);
      await save('Las ex-\nplicaciones.');
      await save(
        'Ver https://upload.wikimedia.org/a.png',
        kind: SourceKind.document,
        originalFilePath: 'a.pdf',
      );
      final before = [
        for (final term in ['fotosintesis', 'wikimedia', 'explicaciones'])
          await matches(term),
      ];

      await db.customStatement(rebuildChunkSearch);
      await integrityCheck();

      expect([
        for (final term in ['fotosintesis', 'wikimedia', 'explicaciones'])
          await matches(term),
      ], before);
      expect(before, [1, 1, 1]);
    });
  });

  group('chunkSearchSource', () {
    test('sin Markdown no hay nada que guardar', () {
      expect(chunkSearchSource(page, markdown: false), isNull);
    });

    test('con Markdown, lo que se lee, con los renglones de cada párrafo en '
        'el suyo', () {
      expect(
        chunkSearchSource(
          'Las ex-\nplicaciones [aquí](https://x.org).',
          markdown: true,
        ),
        'Las ex-\nplicaciones aquí.',
      );
    });

    test('lo que ya se lee igual da null', () {
      expect(chunkSearchSource('Texto llano.', markdown: true), isNull);
    });

    test('un chunk que es solo una foto sin texto alternativo no tiene nada '
        'que buscar', () {
      expect(
        chunkSearchSource(
          '![](https://x.org/Fotosintesis.png)',
          markdown: true,
        ),
        '',
      );
    });
  });
}
