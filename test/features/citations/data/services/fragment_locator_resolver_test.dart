import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/data/services/fragment_locator_resolver.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';

/// Dónde de una fuente está un pasaje (F15): lo dice el chunk que lo contiene.
/// Contra SQLite real.
void main() {
  late AppDatabase db;
  late FragmentLocatorResolver resolver;
  final now = DateTime(2026, 9, 21, 9);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    resolver = FragmentLocatorResolver(db);
    await KnowledgeEntryWriter(db, clock: () => now).upsert(
      KnowledgeItem(
        id: 'fuente',
        title: 'Una fuente',
        source: Source(id: 'src', kind: SourceKind.document, capturedAt: now),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> rendition(String id, {bool primary = true}) => db
      .into(db.renditions)
      .insert(
        RenditionsCompanion.insert(
          id: id,
          itemId: 'fuente',
          kind: RenditionKind.plainText,
          content: const Value('texto'),
          isPrimary: primary,
          createdAt: now,
        ),
      );

  Future<void> chunk(int seq, int start, int end, {int? page, int? startMs}) =>
      db
          .into(db.chunks)
          .insert(
            ChunksCompanion.insert(
              id: 'chunk-$seq',
              itemId: 'fuente',
              seq: seq,
              content: 'x' * (end - start),
              charStart: start,
              charEnd: end,
              pageNumber: Value(page),
              startMs: Value(startMs),
            ),
          );

  Future<CitationLocator?> locate(int offset, {String renditionId = 'texto'}) =>
      resolver.locate(
        itemId: 'fuente',
        renditionId: renditionId,
        charOffset: offset,
      );

  group('la página', () {
    setUp(() async {
      await rendition('texto');
      await chunk(0, 0, 100, page: 1);
      await chunk(1, 100, 250, page: 2);
      await chunk(2, 250, 400, page: 12);
    });

    test('la del fragmento que contiene el pasaje', () async {
      expect(await locate(0), const CitationLocator.page('1'));
      expect(await locate(99), const CitationLocator.page('1'));
      expect(await locate(180), const CitationLocator.page('2'));
      expect(await locate(399), const CitationLocator.page('12'));
    });

    test('el límite entre dos fragmentos es del segundo', () async {
      expect(await locate(100), const CitationLocator.page('2'));
      expect(await locate(250), const CitationLocator.page('12'));
    });

    test('pasado el final del texto, no se sabe', () async {
      expect(await locate(400), isNull);
      expect(await locate(5000), isNull);
    });
  });

  group('el minuto', () {
    test(
      'el instante en que empieza el fragmento, como en un reproductor',
      () async {
        await rendition('texto');
        await chunk(0, 0, 100, startMs: 0);
        await chunk(1, 100, 250, startMs: 127000);
        await chunk(2, 250, 400, startMs: 3727000);

        expect(await locate(10), const CitationLocator.time('0:00'));
        expect(await locate(120), const CitationLocator.time('2:07'));
        expect(await locate(300), const CitationLocator.time('1:02:07'));
      },
    );

    test('si el fragmento tiene página y minuto, gana la página', () async {
      await rendition('texto');
      await chunk(0, 0, 100, page: 3, startMs: 5000);

      expect(await locate(10), const CitationLocator.page('3'));
    });
  });

  group('cuando no se sabe', () {
    test('un fragmento sin página ni minuto', () async {
      await rendition('texto');
      await chunk(0, 0, 100);

      expect(await locate(10), isNull);
    });

    test('una fuente sin fragmentos', () async {
      await rendition('texto');

      expect(await locate(10), isNull);
    });

    test('una fuente sin texto', () async {
      expect(await locate(10), isNull);
    });

    test('una fuente que no existe', () async {
      final result = await resolver.locate(
        itemId: 'fantasma',
        renditionId: 'texto',
        charOffset: 0,
      );

      expect(result, isNull);
    });
  });

  group('solo vale para el texto de donde salen los fragmentos', () {
    test('la forma principal', () async {
      await rendition('principal');
      await rendition('otra', primary: false);
      await chunk(0, 0, 100, page: 4);

      expect(
        await locate(10, renditionId: 'principal'),
        const CitationLocator.page('4'),
      );
    });

    test(
      'otra forma de texto: sus posiciones no son las de los fragmentos',
      () async {
        await rendition('principal');
        await rendition('otra', primary: false);
        await chunk(0, 0, 100, page: 4);

        expect(await locate(10, renditionId: 'otra'), isNull);
      },
    );
  });

  group('locateMany (F17): el mismo locator, por lotes', () {
    test('resuelve varios pasajes de una sola vez, sin mezclarlos', () async {
      await rendition('texto');
      await chunk(0, 0, 100, page: 1);
      await chunk(1, 100, 250, page: 2);
      await KnowledgeEntryWriter(db, clock: () => now).upsert(
        KnowledgeItem(
          id: 'otra',
          title: 'Otra',
          source: Source(
            id: 'src2',
            kind: SourceKind.document,
            capturedAt: now,
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db
          .into(db.chunks)
          .insert(
            ChunksCompanion.insert(
              id: 'ajena-0',
              itemId: 'otra',
              seq: 0,
              content: 'x' * 50,
              charStart: 0,
              charEnd: 50,
              startMs: const Value(60000),
            ),
          );

      final result = await resolver.locateMany([
        (key: 'card-1', itemId: 'fuente', charOffset: 10),
        (key: 'card-2', itemId: 'fuente', charOffset: 180),
        (key: 'card-3', itemId: 'otra', charOffset: 20),
      ]);

      expect(result['card-1'], const CitationLocator.page('1'));
      expect(result['card-2'], const CitationLocator.page('2'));
      expect(result['card-3'], const CitationLocator.time('1:00'));
    });

    test('dos pedidos de la misma fuente, con offsets distintos', () async {
      await rendition('texto');
      await chunk(0, 0, 100, page: 1);
      await chunk(1, 100, 250, page: 2);

      final result = await resolver.locateMany([
        (key: 'card-1', itemId: 'fuente', charOffset: 10),
        (key: 'card-2', itemId: 'fuente', charOffset: 180),
      ]);

      expect(result['card-1'], const CitationLocator.page('1'));
      expect(result['card-2'], const CitationLocator.page('2'));
    });

    test('sin locator para un pasaje sin fragmento que lo contenga', () async {
      await rendition('texto');
      await chunk(0, 0, 100, page: 1);

      final result = await resolver.locateMany([
        (key: 'card-1', itemId: 'fuente', charOffset: 10),
        (key: 'card-2', itemId: 'fuente', charOffset: 5000),
        (key: 'card-3', itemId: 'fantasma', charOffset: 0),
      ]);

      expect(result.containsKey('card-1'), isTrue);
      expect(result.containsKey('card-2'), isFalse);
      expect(result.containsKey('card-3'), isFalse);
    });

    test('un lote vacío no consulta nada ni rompe', () async {
      final result = await resolver.locateMany(const []);

      expect(result, isEmpty);
    });
  });

  test('un fragmento de otra fuente no cuenta', () async {
    await rendition('texto');
    await KnowledgeEntryWriter(db, clock: () => now).upsert(
      KnowledgeItem(
        id: 'otra',
        title: 'Otra',
        source: Source(id: 'src2', kind: SourceKind.document, capturedAt: now),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db
        .into(db.chunks)
        .insert(
          ChunksCompanion.insert(
            id: 'ajeno',
            itemId: 'otra',
            seq: 0,
            content: 'x' * 100,
            charStart: 0,
            charEnd: 100,
            pageNumber: const Value(9),
          ),
        );

    expect(await locate(10), isNull);
  });
}
