import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/search_citation.dart';
import 'package:sinapsis/features/library/domain/entities/search_hit.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// La búsqueda de la Biblioteca (F10): el texto de las fuentes se busca por
/// CHUNKS —cada uno sabe dónde empieza, en el video o en el documento— y el de
/// las notas, por el índice de elementos; y el resultado dice DÓNDE está lo que
/// se encontró.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repository;
  final now = DateTime(2026, 9, 19, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<KnowledgeItem> save(
    String title, {
    SourceKind kind = SourceKind.webPage,
    String? text,
    RenditionKind renditionKind = RenditionKind.markdown,
    DateTime? capturedAt,
  }) async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: title,
      source: Source(
        id: 'src-$n',
        kind: kind,
        capturedAt: capturedAt ?? now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        if (text != null)
          Rendition.text(
            id: 'rend-$n',
            itemId: 'item-$n',
            kind: renditionKind,
            content: text,
            isPrimary: true,
            createdAt: now,
          ),
      ],
    );
    return (await repository.save(item)).getRight().toNullable()!;
  }

  Future<List<String>> titlesOf(
    String search, {
    LibrarySort sort = LibrarySort.relevance,
  }) async {
    final items = (await repository.list(
      LibraryQuery(searchText: search, sortBy: sort),
    )).getRight().toNullable()!;
    return [for (final i in items) i.title];
  }

  /// Los resultados de una búsqueda por relevancia, con su cita.
  Future<List<SearchHit>> hitsFor(String search, {int limit = 50}) async =>
      (await repository.search(
        LibraryQuery(
          searchText: search,
          sortBy: LibrarySort.relevance,
          limit: limit,
        ),
      )).getRight().toNullable()!;

  Map<String, SearchCitation> citationsOf(List<SearchHit> hits) => {
    for (final hit in hits)
      if (hit.citation case final citation?) hit.item.id: citation,
  };

  const transcript =
      '[00:00] Introducción al tema de hoy.\n'
      '[00:30] Seguimos con la introducción.\n'
      '[01:20] Aquí hablamos del paradigma científico.\n'
      '[02:10] Y cerramos con las conclusiones.\n'
      '[03:40] Fin de la charla.';

  group('encontrar', () {
    test('el texto de una fuente se encuentra por sus chunks', () async {
      await save('Charla grabada', kind: SourceKind.youtube, text: transcript);
      await save('Otro video', kind: SourceKind.youtube, text: 'Solo música.');

      expect(await titlesOf('paradigma'), ['Charla grabada']);
    });

    test(
      'el texto de una nota se encuentra por el índice de elementos',
      () async {
        await save(
          'Una nota mía',
          kind: SourceKind.manualNote,
          renditionKind: RenditionKind.blocks,
          text: encodeContentBlocks([
            const ContentBlock.paragraph(text: 'Pienso en el paradigma.'),
          ]),
        );
        await save('Sin relación', text: 'Nada de eso.');

        expect(await titlesOf('paradigma'), ['Una nota mía']);
      },
    );

    test('un elemento que solo coincide por su título también entra', () async {
      await save('Sobre el paradigma');

      expect(await titlesOf('paradigma'), ['Sobre el paradigma']);
    });

    test('lo que coincide en el título va antes que lo que solo lo menciona '
        'en el cuerpo de una fuente', () async {
      await save(
        'Una charla larga',
        text: 'Aquí, casi al final, se menciona el paradigma una vez.',
      );
      await save('Sobre el paradigma');

      expect(await titlesOf('paradigma'), [
        'Sobre el paradigma',
        'Una charla larga',
      ]);
    });

    test('cada elemento aparece una sola vez aunque coincida en muchos '
        'chunks y en el título', () async {
      await save(
        'El paradigma',
        text: 'El paradigma uno.\n\nEl paradigma dos.\n\nEl paradigma tres.',
      );

      expect(await titlesOf('paradigma'), ['El paradigma']);
    });

    test('con dos palabras, encuentra los elementos que las tienen las dos '
        'aunque estén en fragmentos distintos, y pone antes los que las '
        'tienen juntas', () async {
      await save(
        'Separadas',
        text: 'La república nació.\n\nEl imperio romano cayó.',
      );
      await save('Juntas', text: 'La república romana cayó.');
      await save('Solo una', text: 'La república y nada más.');

      expect(await titlesOf('república roma'), ['Juntas', 'Separadas']);
    });

    test('una fuente sin texto no se encuentra por lo que no tiene', () async {
      await save('Un PDF sin procesar');

      expect(await titlesOf('paradigma'), isEmpty);
    });

    test(
      'con otro orden que la relevancia, la búsqueda respeta ese orden',
      () async {
        await save('Beta', text: 'menciona el paradigma');
        await save('Alfa', text: 'también el paradigma');

        final items = (await repository.list(
          const LibraryQuery(
            searchText: 'paradigma',
            sortBy: LibrarySort.title,
            descending: false,
          ),
        )).getRight().toNullable()!;

        expect(items.map((i) => i.title), ['Alfa', 'Beta']);
      },
    );
  });

  group('con una palabra en casi todo', () {
    test('busca en una ventana de los chunks más recientes y sigue '
        'encontrando', () async {
      // Con el tope en 1, cualquier palabra que esté en más de un chunk cuenta
      // como "en casi todo".
      final windowed = LibraryRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        files: InMemoryFileStore(),
        rankedHitsCap: 1,
      );
      for (var i = 0; i < 4; i++) {
        final item = KnowledgeItem(
          id: 'w-$i',
          title: 'Fuente $i',
          source: Source(
            id: 'src-w-$i',
            kind: SourceKind.webPage,
            capturedAt: now.add(Duration(days: i)),
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
          renditions: [
            Rendition.text(
              id: 'rend-w-$i',
              itemId: 'w-$i',
              kind: RenditionKind.markdown,
              content: 'La palabra común aparece.\n\nY otra vez la común.',
              isPrimary: true,
              createdAt: now,
            ),
          ],
        );
        await windowed.save(item);
      }

      final items = (await windowed.list(
        const LibraryQuery(searchText: 'común', sortBy: LibrarySort.relevance),
      )).getRight().toNullable()!;

      // Sin relevancia que medir, primero lo más reciente.
      expect(items.map((i) => i.title), [
        'Fuente 3',
        'Fuente 2',
        'Fuente 1',
        'Fuente 0',
      ]);
      expect(
        (await windowed.count(
          const LibraryQuery(searchText: 'común'),
        )).getRight().toNullable(),
        4,
      );
    });
  });

  group('citas', () {
    test('una transcripción cita el minuto del chunk donde está lo que se '
        'buscó', () async {
      final item = await save(
        'Charla grabada',
        kind: SourceKind.youtube,
        text: transcript,
      );

      final citation = citationsOf(await hitsFor('paradigma'))[item.id]!;

      expect(citation.chunkId, isNotEmpty);
      // El chunk que trae la cita es el que contiene la palabra, y el minuto
      // es el suyo.
      final chunk = await (db.select(
        db.chunks,
      )..where((c) => c.id.equals(citation.chunkId))).getSingle();
      expect(chunk.content, contains('paradigma'));
      expect(citation.startMs, chunk.startMs);
      expect(citation.timestamp, isNotNull);
      expect(citation.charStart, chunk.charStart);
      expect(citation.charEnd, chunk.charEnd);
    });

    test('la cita trae el fragmento con la coincidencia resaltada', () async {
      final item = await save(
        'Charla',
        text: 'Hablamos del paradigma de Kuhn.',
      );

      final citation = citationsOf(await hitsFor('paradigma'))[item.id]!;

      expect(citation.parts.where((p) => p.highlighted).map((p) => p.text), [
        'paradigma',
      ]);
      expect(citation.parts.map((p) => p.text).join(), contains('Kuhn'));
    });

    test('una fuente con página la cita', () async {
      final item = await save(
        'Un documento',
        text: 'El paradigma, en la página.',
      );
      await (db.update(db.chunks)..where((c) => c.itemId.equals(item.id)))
          .write(const ChunksCompanion(pageNumber: Value(34)));

      final citation = citationsOf(await hitsFor('paradigma'))[item.id]!;

      expect(citation.pageNumber, 34);
      expect(citation.timestamp, isNull);
    });

    test('un PDF guardado cita la página real donde está lo buscado, aunque '
        'una página anterior esté en blanco', () async {
      final n = counter++;
      await repository.save(
        KnowledgeItem(
          id: 'pdf-$n',
          title: 'Un informe',
          source: Source(
            id: 'src-pdf-$n',
            kind: SourceKind.document,
            capturedAt: now,
            originalFilePath: 'archivos/informe.pdf',
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
          renditions: [
            Rendition.text(
              id: 'rend-pdf-$n',
              itemId: 'pdf-$n',
              kind: RenditionKind.markdown,
              // La página 2 está en blanco; el paradigma está en la 3.
              content: 'Portada.\n\n---\n\n\n\n---\n\nEl paradigma científico.',
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );

      final hits = await hitsFor('paradigma');

      expect(hits.single.citation!.pageNumber, 3);
    });

    test('un elemento que coincide solo por el título, o una nota, no trae '
        'cita: no hay dónde señalar', () async {
      await save('Sobre el paradigma');
      await save(
        'Nota',
        kind: SourceKind.manualNote,
        renditionKind: RenditionKind.blocks,
        text: encodeContentBlocks([
          const ContentBlock.paragraph(text: 'Pienso en el paradigma.'),
        ]),
      );

      final hits = await hitsFor('paradigma');

      expect(hits, hasLength(2));
      expect(citationsOf(hits), isEmpty);
    });

    test('cada resultado trae la cita de SU mejor chunk', () async {
      await save(
        'A',
        text: 'Poco.\n\nEl paradigma, el paradigma y el paradigma.',
      );
      await save('B', text: 'También el paradigma.');

      final hits = await hitsFor('paradigma');

      expect(hits, hasLength(2));
      for (final hit in hits) {
        expect(
          hit.citation!.parts.where((p) => p.highlighted),
          isNotEmpty,
          reason: hit.item.title,
        );
      }
      // La de A es el chunk que tiene la palabra, no el de "Poco.".
      final a = hits.firstWhere((h) => h.item.title == 'A');
      expect(
        a.citation!.parts.map((p) => p.text).join(),
        contains('paradigma'),
      );
    });

    test('sin resultados, o con un texto sin palabras, no devuelve nada ni '
        'falla', () async {
      await save('X', text: 'El paradigma.');

      expect(await hitsFor('inexistente'), isEmpty);
      expect(await hitsFor('"'), isEmpty);
    });

    test('sin texto buscado es la lista de siempre, sin citas', () async {
      await save('X', text: 'El paradigma.');

      final hits = (await repository.search(
        const LibraryQuery(),
      )).getRight().toNullable()!;

      expect(hits.map((h) => h.item.title), ['X']);
      expect(citationsOf(hits), isEmpty);
    });

    test(
      'con otros filtros también trae las citas, por el camino largo',
      () async {
        await save('Un video', kind: SourceKind.youtube, text: transcript);
        await save('Una página', text: 'Otro paradigma más.');

        final hits = (await repository.search(
          const LibraryQuery(
            searchText: 'paradigma',
            sourceKinds: {SourceKind.youtube},
            sortBy: LibrarySort.relevance,
            limit: 50,
          ),
        )).getRight().toNullable()!;

        expect(hits.map((h) => h.item.title), ['Un video']);
        expect(hits.single.citation!.timestamp, isNotNull);
      },
    );

    test(
      'con una palabra en casi todo también cita, desde la ventana',
      () async {
        final windowed = LibraryRepositoryImpl(
          database: db,
          telemetry: MockTelemetryService(),
          files: InMemoryFileStore(),
          rankedHitsCap: 1,
        );
        final item = await save('Charla', text: 'Uno común.\n\nOtro común.');

        final hits = (await windowed.search(
          const LibraryQuery(
            searchText: 'común',
            sortBy: LibrarySort.relevance,
            limit: 50,
          ),
        )).getRight().toNullable()!;

        expect(hits.single.item.id, item.id);
        expect(hits.single.citation, isNotNull);
      },
    );

    test('muchos resultados a la vez se citan sin romper el límite de '
        'parámetros', () async {
      for (var i = 0; i < 450; i++) {
        await save('Fuente $i', text: 'El paradigma número $i.');
      }

      final hits = await hitsFor('paradigma', limit: 500);

      expect(hits, hasLength(450));
      expect(citationsOf(hits), hasLength(450));
    });

    test('con dos palabras en fragmentos distintos el elemento se encuentra, '
        'sin cita, y después de los que las tienen juntas', () async {
      await save(
        'Separadas',
        text: 'La república nació.\n\nEl imperio romano cayó.',
      );
      await save('Juntas', text: 'La república romana cayó.');

      final hits = await hitsFor('república roma');

      expect(hits.map((h) => h.item.title), ['Juntas', 'Separadas']);
      expect(hits.first.citation, isNotNull);
      expect(hits.last.citation, isNull);
    });
  });

  group('el minuto de una cita', () {
    test('se muestra como minutos y segundos, o con horas', () {
      SearchCitation at(int ms) => SearchCitation(
        itemId: 'i',
        chunkId: 'c',
        snippet: '',
        charStart: 0,
        charEnd: 1,
        startMs: ms,
      );

      expect(at(0).timestamp, '0:00');
      expect(at(65000).timestamp, '1:05');
      expect(at(760000).timestamp, '12:40');
      expect(at(3723000).timestamp, '1:02:03');
      expect(
        const SearchCitation(
          itemId: 'i',
          chunkId: 'c',
          snippet: '',
          charStart: 0,
          charEnd: 1,
        ).timestamp,
        isNull,
      );
    });
  });

  group('la papelera (F11)', () {
    /// [count] elementos YA en la papelera, cada uno con un solo chunk corto
    /// que dice [term]: un chunk corto con la palabra puntúa mejor que uno
    /// largo que la nombra una vez, así que estos ocupan los primeros lugares
    /// de cualquier ranking.
    Future<void> seedTrashedNoise(String term, int count) async {
      final ids = [for (var i = 0; i < count; i++) 'ruido-$i'];
      await db.batch((batch) {
        batch
          ..insertAll(db.knowledgeEntries, [
            for (final id in ids)
              KnowledgeEntriesCompanion.insert(
                id: id,
                title: 'Borrado $id',
                kind: ItemKind.source,
                state: ItemState.processed,
                createdAt: now,
                updatedAt: now,
                deviceId: 'test',
                deletedAt: Value(now),
              ),
          ])
          ..insertAll(db.knowledgeSources, [
            for (final id in ids)
              KnowledgeSourcesCompanion.insert(
                itemId: id,
                sourceType: SourceKind.webPage,
                capturedAt: now,
                contentHash: '',
                processingStatus: sourceProcessingStatusFor(
                  ProcessingState.ready,
                ),
              ),
          ])
          ..insertAll(db.chunks, [
            for (final id in ids)
              ChunksCompanion.insert(
                id: 'chunk-$id',
                itemId: id,
                seq: 0,
                content: 'El $term.',
                charStart: 0,
                charEnd: term.length + 4,
              ),
          ]);
      });
    }

    const longText =
        'Una crónica larga sobre la historia de la república, sus cónsules, '
        'sus campañas militares en el Mediterráneo, las guerras contra '
        'Cartago, los tribunos de la plebe, las reformas agrarias de los '
        'Gracos y, entre tantas otras instituciones, el senado, que '
        'gobernaba en la práctica la política exterior y las finanzas.';

    test('lo que está en la papelera no se encuentra, ni por su título ni por '
        'su texto', () async {
      final byTitle = await save('El senado', text: 'Un discurso.');
      final byText = await save('Otra cosa', text: 'Hablaron en el senado.');
      await save('Sin relación', text: 'Nada que ver.');
      await trashItemRows(db, byTitle.id);
      await trashItemRows(db, byText.id);

      expect(await titlesOf('senado'), isEmpty);
      expect(await hitsFor('senado'), isEmpty);

      await restoreItemRows(db, byTitle.id);
      await restoreItemRows(db, byText.id);

      expect(
        await titlesOf('senado'),
        unorderedEquals(['El senado', 'Otra cosa']),
      );
    });

    test('una papelera llena de coincidencias no tapa lo que sigue '
        'guardado', () async {
      final live = await save('Fuente viva', text: longText);
      // Más que los chunks que se piden al índice para una página: si el
      // corte se hiciera ANTES de sacar lo borrado, todos serían de la
      // papelera y la búsqueda no encontraría lo que sí está.
      await seedTrashedNoise('senado', 330);

      final hits = await hitsFor('senado', limit: 10);

      expect(hits.map((h) => h.item.id), [live.id]);
      expect(hits.single.citation, isNotNull);
    });

    test(
      'con otros filtros —otra forma de armar la cita— pasa lo mismo',
      () async {
        final live = await save('Fuente viva', text: longText);
        await seedTrashedNoise('senado', 330);

        final hits = (await repository.search(
          const LibraryQuery(
            searchText: 'senado',
            sourceKinds: {SourceKind.webPage},
            sortBy: LibrarySort.relevance,
            limit: 10,
          ),
        )).getRight().toNullable()!;

        expect(hits.map((h) => h.item.id), [live.id]);
        // La cita se busca aparte, y también tiene que saltar lo borrado.
        expect(hits.single.citation, isNotNull);
      },
    );

    test(
      'buscando en una ventana de los chunks más recientes, tampoco',
      () async {
        final windowed = LibraryRepositoryImpl(
          database: db,
          telemetry: MockTelemetryService(),
          files: InMemoryFileStore(),
          rankedHitsCap: 1,
        );
        final live = await save('Fuente viva', text: longText);
        // Más que la ventana (600), y más NUEVOS que el chunk vivo.
        await seedTrashedNoise('senado', 700);

        final items = (await windowed.list(
          const LibraryQuery(
            searchText: 'senado',
            sortBy: LibrarySort.relevance,
          ),
        )).getRight().toNullable()!;

        expect(items.map((i) => i.id), [live.id]);
      },
    );
  });
}
