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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator(prefix: 'gen');
    final telemetry = MockTelemetryService();
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: telemetry,
      files: InMemoryFileStore(),
      ids: ids,
      clock: () => now,
    );
    repository = LinkRepositoryImpl(
      database: db,
      library: library,
      inbox: InboxRepositoryImpl(database: db, telemetry: telemetry),
      telemetry: telemetry,
      ids: ids,
      clock: () => now,
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
      // Lo mismo que el editor guarda para una nota sin tocar.
      expect(decodeContentBlocks(rendition.content), [
        const ContentBlock.paragraph(text: ''),
      ]);

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
      expect(await db.select(db.items).get(), hasLength(1));
    });

    test('un título vacío es un fallo de validación y no crea nada', () async {
      final result = await repository.createNoteForLink(title: '   ');

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await db.select(db.items).get(), isEmpty);
    });

    test('crear dos veces el mismo título deja una sola nota', () async {
      await repository.createNoteForLink(title: 'Cartago');
      await repository.createNoteForLink(title: 'CARTAGO');

      expect(await db.select(db.items).get(), hasLength(1));
    });
  });
}
