import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/chunk_passage_retriever.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';

import '../text_notes_harness.dart';

/// La búsqueda de la Biblioteca, la de Procesado y el chat encuentran las
/// notas en el texto (F45, mejora 19): son texto de la persona. Cada una en
/// lo suyo (decisión H), y nada de la papelera.
void main() {
  late TextNotesHarness h;

  const text = 'Moisés sube al monte. Baja con las tablas de la ley.';

  setUp(() async => h = await TextNotesHarness.create());
  tearDown(() => h.close());

  Future<List<String>> library(
    String search, {
    LibrarySort sort = LibrarySort.capturedAt,
    int? limit,
  }) async => [
    for (final item
        in await h.vault.library
            .watch(LibraryQuery(searchText: search, sortBy: sort, limit: limit))
            .first)
      item.id,
  ];

  Future<List<String>> ranked(String search) async => [
    for (final hit in (await h.vault.library.search(
      LibraryQuery(
        searchText: search,
        sortBy: LibrarySort.relevance,
        limit: 20,
      ),
    )).getRight().toNullable()!)
      hit.item.id,
  ];

  Future<List<String>> processed(String search) async => [
    for (final document
        in await h.creations.processed.repository
            .watchDocuments(ProcessedQuery(searchText: search))
            .first)
      document.id,
  ];

  group('la Biblioteca', () {
    test('encuentra la fuente por lo que la persona escribió en su original, '
        'sin acentos y mientras se escribe, también por relevancia', () async {
      final source = await h.source('fuente', text: text);
      await h.source('otra', text: 'Nada que ver.');
      await h.noteOn(source, text, 'monte', note: 'El Sinaí, según Éxodo 19');

      expect(await library('sinai'), ['fuente']);
      expect(await library('exod'), ['fuente']);
      expect(await ranked('sinai'), ['fuente']);
      expect(
        await h.vault.library
            .watchCount(const LibraryQuery(searchText: 'sinai'))
            .first,
        1,
      );
    });

    test('lo escrito en una nota cuenta como su propio texto: va antes que '
        'lo que solo lo menciona en el cuerpo de otra fuente', () async {
      final noted = await h.source('anotada', text: text);
      await h.source('menciona', text: 'El Sinaí aparece acá, en el cuerpo.');
      await h.noteOn(noted, text, 'monte', note: 'Sinaí');

      expect((await ranked('sinai')).first, 'anotada');
    });

    test('también encuentra la nota de un resaltado de antes', () async {
      await h.source('fuente', text: text);
      await h.highlightWithNote(
        'r1',
        'fuente',
        text,
        'tablas',
        note: 'Decálogo',
      );

      expect(await library('decalogo'), ['fuente']);
    });

    test(
      'no encuentra lo que se anotó en Procesado, ni en lo creado',
      () async {
        await h.source('fuente', text: text);
        final documentId = await h.creations.processedDoc('fuente', text: text);
        await h.noteOn(
          ProcessedOriginalNotes(documentId),
          text,
          'monte',
          note: 'Sinaí',
        );
        await h.noteOn(
          ProcessedTextNotes(documentId),
          text,
          'ley',
          note: 'Ley',
        );
        await h.noteOn(await h.creation(), text, 'tablas', note: 'Tablas');

        expect(await library('sinai'), isEmpty);
        expect(await library('ley'), [
          'fuente',
        ]); // por su texto, no por la nota
        expect(await library('tablas'), ['fuente']);
        expect(await ranked('sinai'), isEmpty);
      },
    );

    test('ni la de una fuente que está en la papelera', () async {
      final source = await h.source('fuente', text: text);
      await h.noteOn(source, text, 'monte', note: 'Sinaí');
      await h.vault.writer.trash(['fuente']);

      expect(await library('sinai'), isEmpty);
      expect(await ranked('sinai'), isEmpty);
    });
  });

  group('Procesado', () {
    test('encuentra el documento por las notas de su copia y de su texto, y no '
        'por las del original de la Biblioteca', () async {
      final source = await h.source('fuente', text: text);
      final documentId = await h.creations.processedDoc('fuente', text: text);
      await h.noteOn(source, text, 'monte', note: 'Sinaí');
      await h.noteOn(
        ProcessedOriginalNotes(documentId),
        text,
        'tablas',
        note: 'Decálogo',
      );
      await h.noteOn(ProcessedTextNotes(documentId), text, 'ley', note: 'Torá');

      expect(await processed('sinai'), isEmpty);
      expect(await processed('decalogo'), [documentId]);
      expect(await processed('tora'), [documentId]);
      // Cada palabra, en cualquier lado: el título, las partes o una nota.
      expect(await processed('decalogo moises'), [documentId]);
    });
  });

  group('el chat', () {
    test('trae la nota, con el pedazo que cita, de la fuente o del procesado; '
        'sin posición: la nota no es texto de la fuente', () async {
      final source = await h.source('fuente', text: text);
      await h.noteOn(source, text, 'tablas', note: 'El Decálogo, dos veces');

      final [passage] = await ChunkPassageRetriever(
        database: h.db,
      ).retrieve('¿Qué es el decálogo?');

      expect(passage.itemId, 'fuente');
      expect(passage.excerpt, contains('El Decálogo, dos veces'));
      expect(passage.excerpt, contains('«tablas»'));
      expect(passage.sourceCharStart, isNull);
    });

    test('también la de un resaltado de antes, y la de lo procesado', () async {
      await h.source('fuente', text: text);
      final documentId = await h.creations.processedDoc('fuente', text: text);
      await h.highlightWithNote('r1', 'fuente', text, 'monte', note: 'Horeb');
      await h.noteOn(ProcessedTextNotes(documentId), text, 'ley', note: 'Torá');

      final retriever = ChunkPassageRetriever(database: h.db);
      final horeb = await retriever.retrieve('horeb');
      expect([for (final p in horeb) p.itemId], ['fuente']);
      expect(horeb.single.excerpt, contains('«monte»'));
      final tora = await retriever.retrieve('tora');
      expect([for (final p in tora) p.itemId], [documentId]);
    });

    test('no trae lo de la papelera ni lo de fuera del alcance', () async {
      final a = await h.source('a', text: text);
      final b = await h.source('b', text: text);
      await h.noteOn(a, text, 'monte', note: 'Horeb');
      await h.noteOn(b, text, 'monte', note: 'Horeb');
      final retriever = ChunkPassageRetriever(database: h.db);

      expect(
        [
          for (final p in await retriever.retrieve('horeb', scopeIds: {'b'}))
            p.itemId,
        ],
        ['b'],
      );
      await h.vault.writer.trash(['b']);
      expect(
        [for (final p in await retriever.retrieve('horeb')) p.itemId],
        ['a'],
      );
    });
  });
}
