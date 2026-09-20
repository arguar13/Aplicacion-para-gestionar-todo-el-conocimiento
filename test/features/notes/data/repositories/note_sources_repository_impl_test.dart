import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/notes/data/repositories/note_sources_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// De dónde sale lo que dice una nota viva: las fuentes que cita ella misma y
/// las de las notas atómicas que enlaza, contra SQLite real.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late OrganizeRepositoryImpl organize;
  late NoteSourcesRepositoryImpl repository;

  final now = DateTime(2026, 9, 18, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(),
      clock: () => now,
    );
    repository = NoteSourcesRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
    );
  });

  tearDown(() => db.close());

  Future<String> seed(
    String id, {
    String? title,
    SourceKind kind = SourceKind.webPage,
  }) async {
    await library.save(
      KnowledgeItem(
        id: id,
        title: title ?? 'Título de $id',
        source: Source(
          id: 'src-$id',
          kind: kind,
          capturedAt: now,
          url: kind == SourceKind.manualNote ? null : 'https://e.org/$id',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> relate(
    String from,
    String to,
    RelationKind kind, {
    int? start,
    int? end,
  }) => organize.createRelation(
    fromItemId: from,
    toItemId: to,
    kind: kind,
    sourceCharStart: start,
    sourceCharEnd: end,
  );

  /// Una nota atómica extraída de [source], enlazada desde [living].
  Future<String> atomic(
    String id, {
    required String living,
    required String source,
    int? start,
    int? end,
    RelationKind link = RelationKind.relatedTo,
  }) async {
    await seed(id, kind: SourceKind.manualNote);
    await relate(
      id,
      source,
      RelationKind.extractedFrom,
      start: start,
      end: end,
    );
    await relate(living, id, link);
    return id;
  }

  Future<void> addChunk(
    String sourceId, {
    required int seq,
    required int charStart,
    required int charEnd,
    int? startMs,
    int? pageNumber,
  }) => db
      .into(db.chunks)
      .insert(
        ChunksCompanion.insert(
          id: 'chunk-$sourceId-$seq',
          itemId: sourceId,
          seq: seq,
          content: 'trozo $seq',
          charStart: charStart,
          charEnd: charEnd,
          startMs: Value(startMs),
          pageNumber: Value(pageNumber),
        ),
      );

  Future<List<CitedSourceView>> cited(String noteId) async {
    final sources = await repository.watchCitedSources(noteId).first;
    return [
      for (final s in sources)
        (
          id: s.sourceId,
          title: s.title,
          direct: s.isDirect,
          fragments: [
            for (final f in s.fragments)
              (
                note: f.noteId,
                start: f.start,
                end: f.end,
                ms: f.startMs,
                page: f.pageNumber,
              ),
          ],
        ),
    ];
  }

  group('sin fuentes', () {
    test('una nota sin vínculos no cita nada', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);

      expect(await cited(note), isEmpty);
    });

    test('una nota que enlaza una nota viva no cita ninguna fuente', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final other = await seed('otra', kind: SourceKind.manualNote);
      await relate(note, other, RelationKind.relatedTo);

      expect(await cited(note), isEmpty);
    });
  });

  group('directo', () {
    test('un vínculo cites hacia una fuente la cita', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente', title: 'Una fuente');
      await relate(note, source, RelationKind.cites);

      final sources = await repository.watchCitedSources(note).first;

      expect(sources, hasLength(1));
      expect(sources.single.sourceId, source);
      expect(sources.single.title, 'Una fuente');
      expect(sources.single.sourceKind, SourceKind.webPage);
      expect(sources.single.isDirect, isTrue);
      expect(sources.single.fragments, isEmpty);
    });

    test('el título y el tipo de la fuente citada salen de item y de source, '
        'no de las tablas viejas', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente', title: 'Título de antes');
      await relate(note, source, RelationKind.cites);
      // Se cambia SOLO el modelo nuevo.
      await (db.update(db.knowledgeEntries)..where((e) => e.id.equals(source)))
          .write(const KnowledgeEntriesCompanion(title: Value('De ahora')));
      await (db.update(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals(source))).write(
        const KnowledgeSourcesCompanion(sourceType: Value(SourceKind.document)),
      );

      final cited = (await repository.watchCitedSources(note).first).single;

      expect(cited.title, 'De ahora');
      expect(cited.sourceKind, SourceKind.document);
    });

    test('lo extraído de una nota, que no tiene fila de fuente, se cita como '
        'nota manual', () async {
      final living = await seed('viva', kind: SourceKind.manualNote);
      final origin = await seed('origen', kind: SourceKind.manualNote);
      await atomic('atomica', living: living, source: origin);

      final cited = (await repository.watchCitedSources(living).first).single;

      expect(cited.sourceId, origin);
      expect(cited.sourceKind, SourceKind.manualNote);
    });

    test('un cites hacia otra nota no es una fuente citada', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final other = await seed('otra', kind: SourceKind.manualNote);
      await relate(note, other, RelationKind.cites);

      expect(await cited(note), isEmpty);
    });

    test('un vínculo que no es cites hacia una fuente no la cita', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await relate(note, source, RelationKind.relatedTo);

      expect(await cited(note), isEmpty);
    });
  });

  group('a través de las notas atómicas', () {
    test('la fuente de una atómica enlazada cuenta, con el lugar del que '
        'salió', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      final a = await atomic(
        'atomica',
        living: note,
        source: source,
        start: 120,
        end: 180,
      );

      final sources = await repository.watchCitedSources(note).first;

      expect(sources, hasLength(1));
      expect(sources.single.sourceId, source);
      expect(sources.single.isDirect, isFalse);
      expect(sources.single.fragments, hasLength(1));
      expect(sources.single.fragments.single.noteId, a);
      expect(sources.single.fragments.single.noteTitle, 'Título de atomica');
      expect(sources.single.fragments.single.start, 120);
      expect(sources.single.fragments.single.end, 180);
    });

    test('sirve cualquier vínculo que no sea una contradicción', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await atomic(
        'a1',
        living: note,
        source: source,
        start: 1,
        end: 5,
        link: RelationKind.cites,
      );
      await atomic(
        'a2',
        living: note,
        source: source,
        start: 10,
        end: 15,
        link: RelationKind.summarizes,
      );

      final result = await cited(note);

      expect(result.single.fragments.map((f) => f.note), ['a1', 'a2']);
    });

    test('una atómica que la nota contradice no cuenta', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await atomic(
        'atomica',
        living: note,
        source: source,
        start: 1,
        end: 5,
        link: RelationKind.contradicts,
      );

      expect(await cited(note), isEmpty);
    });

    test('solo se siguen los vínculos que salen de la nota', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await seed('atomica', kind: SourceKind.manualNote);
      await relate(
        'atomica',
        source,
        RelationKind.extractedFrom,
        start: 1,
        end: 5,
      );
      // La atómica enlaza a la viva, no al revés.
      await relate('atomica', note, RelationKind.relatedTo);

      expect(await cited(note), isEmpty);
    });

    test('no se sigue a una nota que no es atómica', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      final other = await seed('otra-viva', kind: SourceKind.manualNote);
      await relate(other, source, RelationKind.cites);
      await relate(note, other, RelationKind.relatedTo);

      expect(await cited(note), isEmpty);
    });

    test('varias atómicas de la misma fuente son una fuente con varios '
        'fragmentos, en el orden del texto', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await atomic('tarde', living: note, source: source, start: 900, end: 950);
      await atomic(
        'temprano',
        living: note,
        source: source,
        start: 10,
        end: 40,
      );

      final result = await cited(note);

      expect(result, hasLength(1));
      expect(result.single.fragments.map((f) => f.note), ['temprano', 'tarde']);
    });

    test('una atómica sin posición guardada cuenta, al final', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await atomic('vieja', living: note, source: source);
      await atomic('nueva', living: note, source: source, start: 10, end: 40);

      final fragments = (await cited(note)).single.fragments;

      expect(fragments.map((f) => f.note), ['nueva', 'vieja']);
      expect(fragments.last.start, isNull);
      expect(fragments.last.end, isNull);
    });

    test('atómicas de fuentes distintas son fuentes distintas', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final one = await seed('f1');
      final two = await seed('f2');
      await atomic('a1', living: note, source: one, start: 1, end: 5);
      await atomic('a2', living: note, source: two, start: 1, end: 5);

      expect((await cited(note)).map((s) => s.id), unorderedEquals([one, two]));
    });
  });

  group('las dos maneras a la vez', () {
    test('una fuente citada directo y por una atómica aparece una vez, con '
        'las dos cosas', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await relate(note, source, RelationKind.cites);
      await atomic('atomica', living: note, source: source, start: 5, end: 9);

      final result = await cited(note);

      expect(result, hasLength(1));
      expect(result.single.direct, isTrue);
      expect(result.single.fragments.map((f) => f.note), ['atomica']);
    });
  });

  group('orden', () {
    test('por título, sin distinguir mayúsculas ni acentos', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      for (final (id, title) in [
        ('a', 'zorro'),
        ('b', 'Árbol'),
        ('c', 'mesa'),
      ]) {
        await seed(id, title: title);
        await relate(note, id, RelationKind.cites);
      }

      final titles = (await cited(note)).map((s) => s.title).toList();

      expect(titles, ['Árbol', 'mesa', 'zorro']);
    });
  });

  group('el lugar en la fuente', () {
    test('un trozo con marca de tiempo dice en qué instante está', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('video', kind: SourceKind.youtube);
      await addChunk(source, seq: 0, charStart: 0, charEnd: 100, startMs: 0);
      await addChunk(
        source,
        seq: 1,
        charStart: 100,
        charEnd: 200,
        startMs: 12000,
      );
      await atomic('a', living: note, source: source, start: 130, end: 160);

      final fragment = (await cited(note)).single.fragments.single;

      expect(fragment.ms, 12000);
      expect(fragment.page, isNull);
    });

    test('un trozo con página dice en cuál', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('pdf', kind: SourceKind.document);
      await addChunk(source, seq: 0, charStart: 0, charEnd: 500, pageNumber: 4);
      await atomic('a', living: note, source: source, start: 20, end: 60);

      final fragment = (await cited(note)).single.fragments.single;

      expect(fragment.page, 4);
      expect(fragment.ms, isNull);
    });

    test('el borde del trozo pertenece al trozo siguiente', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('video', kind: SourceKind.youtube);
      await addChunk(source, seq: 0, charStart: 0, charEnd: 100, startMs: 0);
      await addChunk(
        source,
        seq: 1,
        charStart: 100,
        charEnd: 200,
        startMs: 5000,
      );
      await atomic('a', living: note, source: source, start: 100, end: 120);

      expect((await cited(note)).single.fragments.single.ms, 5000);
    });

    test('sin trozos, o con un texto que no los cubre, no hay lugar', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await addChunk(source, seq: 0, charStart: 0, charEnd: 50, startMs: 1000);
      await atomic('a', living: note, source: source, start: 500, end: 520);

      final fragment = (await cited(note)).single.fragments.single;

      expect(fragment.ms, isNull);
      expect(fragment.page, isNull);
    });

    test('sin posición guardada no se busca el trozo', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await addChunk(source, seq: 0, charStart: 0, charEnd: 500, startMs: 1000);
      await atomic('a', living: note, source: source);

      expect((await cited(note)).single.fragments.single.ms, isNull);
    });
  });

  group('actualización', () {
    test('citar una fuente emite de nuevo', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      final emissions = repository.watchCitedSources(note);
      final expectation = expectLater(
        emissions,
        emitsThrough(
          predicate<List<Object?>>((sources) => sources.length == 1),
        ),
      );

      await relate(note, source, RelationKind.cites);

      await expectation.timeout(const Duration(seconds: 5));
    });

    test('borrar la fuente la saca de la lista', () async {
      final note = await seed('viva', kind: SourceKind.manualNote);
      final source = await seed('fuente');
      await relate(note, source, RelationKind.cites);
      final emissions = repository.watchCitedSources(note);
      final expectation = expectLater(emissions, emitsThrough(isEmpty));

      await library.delete(source);

      await expectation.timeout(const Duration(seconds: 5));
    });
  });

  group('la papelera (F11)', () {
    test(
      'una fuente en la papelera no se cita, y vuelve al restaurarla',
      () async {
        final note = await seed('viva', kind: SourceKind.manualNote);
        final source = await seed('fuente');
        await relate(note, source, RelationKind.cites);

        await trashItemRows(db, source);
        expect(await cited(note), isEmpty);

        await restoreItemRows(db, source);
        expect((await cited(note)).map((c) => c.id), [source]);
      },
    );

    test(
      'lo que salió de una nota atómica en la papelera no se cita',
      () async {
        final note = await seed('viva', kind: SourceKind.manualNote);
        final source = await seed('fuente');
        final atomic1 = await atomic(
          'atomica-1',
          living: note,
          source: source,
          start: 1,
          end: 5,
        );
        await atomic(
          'atomica-2',
          living: note,
          source: source,
          start: 9,
          end: 20,
        );

        await trashItemRows(db, atomic1);

        final fragments = (await cited(note)).single.fragments;
        expect(fragments.map((f) => f.note), ['atomica-2']);
      },
    );
  });
}

/// Lo que importa de una `CitedSource` para comparar en los tests.
typedef CitedSourceView = ({
  String id,
  String title,
  bool direct,
  List<({String note, int? start, int? end, int? ms, int? page})> fragments,
});
