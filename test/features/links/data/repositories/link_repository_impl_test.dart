import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/inbox/data/repositories/inbox_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/links/data/repositories/link_repository_impl.dart';
import 'package:sinapsis/features/links/domain/entities/broken_link.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria y con los repositorios reales de biblioteca
/// y bandeja: crear la nota tiene que dejar el espejo, los enlaces y las
/// relaciones como los deja la app de verdad.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late LinkRepositoryImpl repository;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 19, 10);

  /// Un segundo más con cada llamada: lo que se guarda primero es más antiguo,
  /// sin depender del orden alfabético de identificadores como `gen-10`.
  var tick = 0;
  DateTime clock() => now.add(Duration(seconds: tick++));

  setUp(() {
    tick = 0;
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator(prefix: 'gen');
    final telemetry = MockTelemetryService();
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: telemetry,
      files: InMemoryFileStore(),
      ids: ids,
      clock: clock,
    );
    repository = LinkRepositoryImpl(
      database: db,
      library: library,
      inbox: InboxRepositoryImpl(database: db, telemetry: telemetry),
      telemetry: telemetry,
      ids: ids,
      clock: clock,
    );
  });

  tearDown(() => db.close());

  /// Un elemento común, guardado por el camino real.
  Future<void> seedItem(String id, String title) async {
    await library.save(
      KnowledgeItem(
        id: id,
        title: title,
        source: Source(
          id: 'src-$id',
          kind: SourceKind.webPage,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Una nota de bloques con un párrafo por cada texto.
  Future<void> seedNote(
    String id,
    String title,
    List<String> paragraphs,
  ) async {
    await library.save(
      KnowledgeItem(
        id: id,
        title: title,
        source: Source(
          id: 'src-$id',
          kind: SourceKind.manualNote,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'blocks-$id',
            itemId: id,
            kind: RenditionKind.blocks,
            content: encodeContentBlocks([
              for (final text in paragraphs) ContentBlock.paragraph(text: text),
            ]),
            isPrimary: true,
            createdAt: now,
          ),
        ],
      ),
    );
  }

  Future<KnowledgeNoteRow> mirrorOf(String itemId) => (db.select(
    db.knowledgeNotes,
  )..where((n) => n.itemId.equals(itemId))).getSingle();

  group('findMissingTitles', () {
    test('devuelve solo los títulos que ningún elemento tiene', () async {
      await seedItem('roma', 'Roma');

      final result = await repository.findMissingTitles({'roma', 'cartago'});

      expect(result.getRight().toNullable(), {'cartago'});
    });

    test(
      'compara sin distinguir mayúsculas, también fuera del ASCII',
      () async {
        await seedItem('epoca', 'Época');

        final result = await repository.findMissingTitles({'época'});

        expect(result.getRight().toNullable(), isEmpty);
      },
    );

    test('un enlace a la propia nota no es un enlace roto', () async {
      await seedItem('yo', 'Yo');

      final result = await repository.findMissingTitles({
        'yo',
      }, excludingItemId: 'yo');

      expect(result.getRight().toNullable(), isEmpty);
    });

    test('un homónimo de la propia nota sí cuenta como destino', () async {
      await seedItem('a', 'Tema');
      await seedItem('b', 'Tema');

      final result = await repository.findMissingTitles({
        'tema',
      }, excludingItemId: 'a');

      expect(result.getRight().toNullable(), isEmpty);
    });

    test('sin títulos no devuelve ninguno', () async {
      final result = await repository.findMissingTitles(const {});

      expect(result.getRight().toNullable(), isEmpty);
    });
  });

  group('createNoteForLink', () {
    test('crea una nota viva y vacía, con el título recortado', () async {
      final result = await repository.createNoteForLink(title: '  Cartago  ');

      final note = result.getRight().toNullable()!;
      expect(note.title, 'Cartago');
      expect(note.source.kind, SourceKind.manualNote);

      final stored = (await library.findById(note.id)).getRight().toNullable()!;
      final rendition = stored.renditions.whereType<TextRendition>().single;
      expect(rendition.kind, RenditionKind.blocks);
      // Lo mismo que el editor guarda para una nota sin tocar: un párrafo
      // vacío que lleva la fecha de su nacimiento. Sin ella, lo que se
      // escriba después en ese párrafo nunca contaría como un bloque nuevo.
      final blocks = decodeContentBlocks(rendition.content);
      expect(blocks.map((b) => b.text), ['']);
      expect(blocks.single.addedAt!.isAtSameMomentAs(note.createdAt), isTrue);

      final mirror = await mirrorOf(note.id);
      expect(mirror.noteKind, NoteKind.living);
      expect(mirror.maturity, NoteMaturity.seed);
    });

    test('escribe el subtipo elegido', () async {
      final atomic = await repository.createNoteForLink(
        title: 'Una idea',
        kind: NoteKind.atomic,
      );
      final map = await repository.createNoteForLink(
        title: 'Un índice',
        kind: NoteKind.map,
      );

      expect(
        (await mirrorOf(atomic.getRight().toNullable()!.id)).noteKind,
        NoteKind.atomic,
      );
      expect(
        (await mirrorOf(map.getRight().toNullable()!.id)).noteKind,
        NoteKind.map,
      );
    });

    test('resuelve el enlace roto de una nota ya guardada y crea su '
        'relación en el momento', () async {
      await seedNote('n1', 'Viaje', ['Fui a [[Cartago]].']);
      final before = await db.select(db.inlineLinks).getSingle();
      expect(before.toItemId, isNull);

      final created = (await repository.createNoteForLink(
        title: 'Cartago',
      )).getRight().toNullable()!;

      final after = await db.select(db.inlineLinks).getSingle();
      expect(after.toItemId, created.id);
      final relations = await db.select(db.relations).get();
      expect(relations.map((r) => (r.fromItemId, r.toItemId, r.kind)), [
        ('n1', created.id, RelationKind.relatedTo),
      ]);
    });

    test('una nota que se guarda después encuentra el destino y se '
        'vincula sola', () async {
      // Es el caso del editor con una nota nueva: primero se crea la nota que
      // falta y recién después se guarda la que la enlaza.
      final created = (await repository.createNoteForLink(
        title: 'Cartago',
      )).getRight().toNullable()!;

      await seedNote('n1', 'Viaje', ['Fui a [[Cartago]].']);

      final link = await db.select(db.inlineLinks).getSingle();
      expect(link.toItemId, created.id);
      expect(
        (await db.select(db.relations).get()).map(
          (r) => (r.fromItemId, r.toItemId),
        ),
        [('n1', created.id)],
      );
    });

    test('si ya existe un elemento con ese título devuelve ese, sin crear un '
        'homónimo', () async {
      await seedItem('roma', 'Roma');

      final result = await repository.createNoteForLink(title: 'roma');

      expect(result.getRight().toNullable()!.id, 'roma');
      expect(await db.select(db.knowledgeEntries).get(), hasLength(1));
    });

    test('un título vacío es un fallo de validación y no crea nada', () async {
      final result = await repository.createNoteForLink(title: '   ');

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await db.select(db.knowledgeEntries).get(), isEmpty);
    });

    test('crear dos veces el mismo título deja una sola nota', () async {
      await repository.createNoteForLink(title: 'Cartago');
      await repository.createNoteForLink(title: 'CARTAGO');

      expect(await db.select(db.knowledgeEntries).get(), hasLength(1));
    });
  });

  group('watchBrokenLinks', () {
    Future<List<BrokenLink>> current() => repository.watchBrokenLinks().first;

    test('agrupa por título y lista las notas que lo escriben', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', ['[[Cartago]], [[Atenas]] y [[Roma]]']);
      await seedNote('n2', 'Diario', ['Otra vez [[cartago]].']);

      final links = await current();

      // "Roma" existe: su enlace no está roto. "Cartago" lo escriben dos
      // notas, "Atenas" una.
      expect(links.map((l) => l.title), ['Cartago', 'Atenas']);
      expect(links.first.normalizedTitle, 'cartago');
      // Las notas, por título; el título del grupo, como lo escribió la
      // primera nota que lo escribió.
      expect(links.first.sources.map((s) => (s.itemId, s.title)), [
        ('n2', 'Diario'),
        ('n1', 'Viaje'),
      ]);
      expect(links.last.sources.map((s) => s.itemId), ['n1']);
    });

    test('a igual cantidad de notas ordena alfabéticamente sin mirar los '
        'acentos', () async {
      await seedNote('n1', 'Viaje', ['[[Zeta]] [[Época]] [[Beta]]']);

      final links = await current();

      // "Época" va con las E, no después de la Z.
      expect(links.map((l) => l.title), ['Beta', 'Época', 'Zeta']);
    });

    test('sin enlaces rotos emite una lista vacía', () async {
      await seedItem('roma', 'Roma');
      await seedNote('n1', 'Viaje', ['[[Roma]]']);

      expect(await current(), isEmpty);
    });

    test('un enlace deja de estar roto en cuanto se crea su nota', () async {
      await seedNote('n1', 'Viaje', ['[[Cartago]] y [[Atenas]]']);
      final queue = StreamQueue(repository.watchBrokenLinks());
      addTearDown(queue.cancel);
      expect((await queue.next).map((l) => l.title), ['Atenas', 'Cartago']);

      await repository.createNoteForLink(title: 'Cartago');

      // Puede haber una emisión intermedia por cada tabla que cambia: se
      // espera a la que ya refleja la nota creada.
      var links = await queue.next;
      while (links.length != 1) {
        links = await queue.next.timeout(const Duration(seconds: 5));
      }
      expect(links.single.title, 'Atenas');
    });
  });

  group('los títulos salen del modelo nuevo (F10)', () {
    Future<void> retitleOnlyEntry(String id, String title) =>
        (db.update(db.knowledgeEntries)..where((e) => e.id.equals(id))).write(
          KnowledgeEntriesCompanion(title: Value(title)),
        );

    Future<List<InlineLinkRow>> linksOf(String itemId) => (db.select(
      db.inlineLinks,
    )..where((l) => l.fromItemId.equals(itemId))).get();

    test('qué títulos existen lo dice item, no la tabla vieja', () async {
      await seedItem('roma', 'Roma');
      // Se cambia SOLO la fila nueva: si la lectura saliera de la vieja, "Roma"
      // seguiría existiendo y "Cartago" no.
      await retitleOnlyEntry('roma', 'Cartago');

      final result = await repository.findMissingTitles({'roma', 'cartago'});

      expect(result.getRight().toNullable(), {'roma'});
    });

    test('los enlaces rotos nombran la nota por el título de item, y la lista '
        'se actualiza sola cuando cambia', () async {
      await seedNote('n1', 'Viaje', ['[[Cartago]]']);
      final queue = StreamQueue(repository.watchBrokenLinks());
      addTearDown(queue.cancel);
      expect((await queue.next).single.sources.single.title, 'Viaje');

      await retitleOnlyEntry('n1', 'Diario de viaje');

      var links = await queue.next;
      while (links.single.sources.single.title != 'Diario de viaje') {
        links = await queue.next.timeout(const Duration(seconds: 5));
      }
      expect(links.single.sources.single.title, 'Diario de viaje');
    });

    test('una nota nueva que se menciona a sí misma no queda con un enlace '
        'roto hacia sí misma', () async {
      // Al guardarla, el modelo nuevo tiene que conocerla antes de resolver sus
      // enlaces: si no, su propio título no existe todavía para ella.
      await seedNote('yo', 'Yo', ['Me llamo [[Yo]].']);

      expect(await linksOf('yo'), isEmpty);
      expect(await repository.watchBrokenLinks().first, isEmpty);
    });

    test('una nota que pasa a llamarse como su enlace roto deja de tenerlo, '
        'al guardarla', () async {
      await seedNote('n1', 'Viaje', ['[[Roma]]']);
      expect(await linksOf('n1'), hasLength(1));

      await seedNote('n1', 'Roma', ['[[Roma]]']);

      expect(await linksOf('n1'), isEmpty);
    });
  });

  group('createNotesForLinks', () {
    test('crea una nota por título, del subtipo elegido, y devuelve '
        'cuántas', () async {
      final result = await repository.createNotesForLinks([
        'Cartago',
        'Atenas',
      ], kind: NoteKind.atomic);

      expect(result.getRight().toNullable(), 2);
      final items = await db.select(db.knowledgeEntries).get();
      expect(items.map((i) => i.title).toSet(), {'Cartago', 'Atenas'});
      for (final item in items) {
        expect((await mirrorOf(item.id)).noteKind, NoteKind.atomic);
      }
    });

    test('resuelve el enlace en todas las notas que lo escriben', () async {
      await seedNote('n1', 'Viaje', ['[[Cartago]]']);
      await seedNote('n2', 'Diario', ['[[cartago]]']);

      await repository.createNotesForLinks(['Cartago']);

      final links = await db.select(db.inlineLinks).get();
      expect(links.map((l) => l.toItemId).toSet(), hasLength(1));
      expect(links.every((l) => l.toItemId != null), isTrue);
      final relations = await db.select(db.relations).get();
      expect(relations.map((r) => r.fromItemId).toSet(), {'n1', 'n2'});
    });

    test('un título que ya tiene nota, o repetido en el lote, no crea un '
        'homónimo ni cuenta', () async {
      await seedItem('roma', 'Roma');

      final result = await repository.createNotesForLinks([
        'Roma',
        'Atenas',
        'atenas',
      ]);

      expect(result.getRight().toNullable(), 1);
      expect(
        (await db.select(db.knowledgeEntries).get())
            .map((i) => i.title)
            .toSet(),
        {'Roma', 'Atenas'},
      );
    });

    test('es atómico: si una falla no queda ninguna', () async {
      await seedNote('n1', 'Viaje', ['[[Cartago]]']);

      // El segundo título es inválido: la primera nota, ya creada dentro del
      // lote, tiene que deshacerse.
      final result = await repository.createNotesForLinks([
        'Cartago',
        '   ',
        'Atenas',
      ]);

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect((await db.select(db.knowledgeEntries).get()).map((i) => i.title), [
        'Viaje',
      ]);
      final link = await db.select(db.inlineLinks).getSingle();
      expect(link.toItemId, isNull);
      expect(await db.select(db.relations).get(), isEmpty);
    });

    test('una lista vacía no crea nada', () async {
      final result = await repository.createNotesForLinks(const []);

      expect(result.getRight().toNullable(), 0);
      expect(await db.select(db.knowledgeEntries).get(), isEmpty);
    });
  });
}
