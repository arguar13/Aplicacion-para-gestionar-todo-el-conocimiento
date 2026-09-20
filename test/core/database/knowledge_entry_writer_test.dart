import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// El único escritor de los campos de un elemento (F11): lo que hace con `rev`,
/// `deviceId` y `field_version`, y la regla de linaje que le permite a una
/// fusión distinguir «edité encima de tu versión» de «edité a la vez».
///
/// Contra SQLite real, en memoria.
void main() {
  const me = 'telefono';
  const other = 'computadora';

  late AppDatabase db;
  late KnowledgeEntryWriter writer;
  var clockNow = DateTime(2026, 9, 20, 9);

  final captured = DateTime(2026, 9, 11, 10);

  setUp(() {
    clockNow = DateTime(2026, 9, 20, 9);
    db = AppDatabase(NativeDatabase.memory(), deviceId: me);
    writer = KnowledgeEntryWriter(db, clock: () => clockNow);
  });

  tearDown(() => db.close());

  /// Adelanta el reloj: cada escritura ocurre en su propio instante.
  void tick() => clockNow = clockNow.add(const Duration(minutes: 5));

  KnowledgeItem sourceItem({
    String id = 'art',
    String title = 'La república romana',
    String? subtitle,
    String? notes,
    String? spaceId,
    String? url = 'https://ejemplo.org/roma',
    String? authorName,
    ProcessingState state = ProcessingState.ready,
  }) => KnowledgeItem(
    id: id,
    title: title,
    subtitle: subtitle,
    notes: notes,
    spaceId: spaceId,
    source: Source(
      id: 'src-$id',
      kind: SourceKind.webPage,
      capturedAt: captured,
      url: url,
      authorName: authorName,
    ),
    processingState: state,
    createdAt: captured,
    updatedAt: captured,
  );

  KnowledgeItem noteItem({String id = 'nota', String title = 'Una idea'}) =>
      KnowledgeItem(
        id: id,
        title: title,
        source: Source(
          id: 'src-$id',
          kind: SourceKind.manualNote,
          capturedAt: captured,
        ),
        processingState: ProcessingState.ready,
        createdAt: captured,
        updatedAt: captured,
      );

  Future<KnowledgeEntryRow> entry(String id) => (db.select(
    db.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle();

  Future<Map<String, FieldVersionRow>> versions(String id) async => {
    for (final row in await (db.select(
      db.fieldVersions,
    )..where((f) => f.itemId.equals(id))).get())
      row.fieldName: row,
  };

  Future<void> putForeignVersion(
    String id,
    String field, {
    required DateTime at,
    String device = other,
  }) => db
      .into(db.fieldVersions)
      .insertOnConflictUpdate(
        FieldVersionsCompanion.insert(
          itemId: id,
          fieldName: field,
          updatedAt: at,
          deviceId: device,
        ),
      );

  group('crear un elemento', () {
    test(
      'lo firma con el dispositivo de esta base, no con un texto fijo',
      () async {
        await writer.upsert(sourceItem());

        final row = await entry('art');

        expect(row.deviceId, me);
        expect(row.rev, 1);
        expect(row.deletedAt, isNull);
      },
    );

    test(
      'registra la primera versión de cada campo que tiene un valor',
      () async {
        await writer.upsert(
          sourceItem(subtitle: 'Livio', authorName: 'Tito Livio'),
        );

        final fields = await versions('art');

        expect(
          fields.keys,
          unorderedEquals([
            EntryField.title,
            EntryField.subtitle,
            EntryField.state,
            EntryField.originUrl,
            EntryField.authorName,
          ]),
        );
        // Un campo vacío no tiene versión: nadie lo escribió.
        expect(fields.containsKey(EntryField.notes), isFalse);
        for (final version in fields.values) {
          expect(version.deviceId, me);
          expect(version.updatedAt, clockNow);
          // Es la primera: no parte de ninguna versión ajena.
          expect(version.baseUpdatedAt, isNull);
          expect(version.baseDeviceId, isNull);
        }
      },
    );

    test('una nota versiona lo suyo y no inventa campos de fuente', () async {
      await writer.upsert(noteItem());

      final fields = await versions('nota');

      expect(
        fields.keys,
        unorderedEquals([EntryField.title, EntryField.state]),
      );
      final note = await (db.select(
        db.knowledgeNotes,
      )..where((n) => n.itemId.equals('nota'))).getSingle();
      expect(note.noteKind, NoteKind.living);
      expect(note.maturity, NoteMaturity.seed);
    });

    test('las formas que se guardan quedan versionadas por su id', () async {
      await writer.upsert(sourceItem(), changedRenditions: ['r-1']);

      final fields = await versions('art');

      expect(fields.containsKey(EntryField.rendition('r-1')), isTrue);
      expect(EntryField.isRendition(EntryField.rendition('r-1')), isTrue);
      // Crear el elemento con su forma es UN guardado: no queda en revisión 2.
      expect((await entry('art')).rev, 1);
    });
  });

  group('guardar de nuevo', () {
    test(
      'un guardado que no cambia nada no toca ni la revisión ni la versión',
      () async {
        await writer.upsert(sourceItem());
        final before = await versions('art');
        tick();

        await writer.upsert(sourceItem());

        final row = await entry('art');
        expect(row.rev, 1);
        expect(row.deviceId, me);
        final after = await versions('art');
        for (final entry in before.entries) {
          expect(after[entry.key]!.updatedAt, entry.value.updatedAt);
        }
      },
    );

    test(
      'un cambio sube la revisión una vez y versiona solo ese campo',
      () async {
        await writer.upsert(sourceItem(subtitle: 'Livio'));
        final created = clockNow;
        tick();

        await writer.upsert(sourceItem(subtitle: 'Livio', title: 'Roma'));

        expect((await entry('art')).rev, 2);
        final fields = await versions('art');
        expect(fields[EntryField.title]!.updatedAt, clockNow);
        expect(fields[EntryField.subtitle]!.updatedAt, created);
        expect(fields[EntryField.state]!.updatedAt, created);
      },
    );

    test(
      'varios campos y una forma a la vez son un solo cambio de revisión',
      () async {
        await writer.upsert(sourceItem());
        tick();

        await writer.upsert(
          sourceItem(title: 'Roma', notes: 'Ver también Cartago'),
          changedRenditions: ['r-1'],
        );

        expect((await entry('art')).rev, 2);
        final fields = await versions('art');
        expect(fields[EntryField.title]!.updatedAt, clockNow);
        expect(fields[EntryField.notes]!.updatedAt, clockNow);
        expect(fields[EntryField.rendition('r-1')]!.updatedAt, clockNow);
      },
    );

    test(
      'el estado que otra cosa cambió se conserva, y no se versiona de más',
      () async {
        await writer.upsert(sourceItem());
        await writer.setState('art', ItemState.triaged);
        tick();

        await writer.upsert(sourceItem());

        expect((await entry('art')).state, ItemState.triaged);
      },
    );

    test('el hash del contenido de una fuente no se pisa', () async {
      await writer.upsert(sourceItem());
      await (db.update(db.knowledgeSources)
            ..where((s) => s.itemId.equals('art')))
          .write(const KnowledgeSourcesCompanion(contentHash: Value('abc123')));

      await writer.upsert(sourceItem(title: 'Roma'));

      final source = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('art'))).getSingle();
      expect(source.contentHash, 'abc123');
    });

    test('nunca toca la marca de borrado', () async {
      await writer.upsert(sourceItem());
      final deletedAt = DateTime(2026, 9, 19);
      await (db.update(db.knowledgeEntries)..where((e) => e.id.equals('art')))
          .write(KnowledgeEntriesCompanion(deletedAt: Value(deletedAt)));

      await writer.upsert(sourceItem(title: 'Roma'));

      expect((await entry('art')).deletedAt, deletedAt);
    });
  });

  group('el linaje de una edición', () {
    test('sin versión anterior, la edición parte de nada', () async {
      await writer.upsert(sourceItem());

      final title = (await versions('art'))[EntryField.title]!;

      expect(title.baseUpdatedAt, isNull);
      expect(title.baseDeviceId, isNull);
    });

    test('editar de nuevo lo propio conserva de dónde se partió', () async {
      await writer.upsert(sourceItem());
      tick();
      await writer.upsert(sourceItem(title: 'Roma'));
      tick();

      await writer.upsert(sourceItem(title: 'Roma antigua'));

      final title = (await versions('art'))[EntryField.title]!;
      expect(title.baseUpdatedAt, isNull);
      expect(title.baseDeviceId, isNull);
      expect(title.updatedAt, clockNow);
    });

    test('editar encima de una versión ajena la deja como base', () async {
      await writer.upsert(sourceItem());
      final theirs = clockNow.add(const Duration(hours: 1));
      await putForeignVersion('art', EntryField.title, at: theirs);
      tick();

      await writer.upsert(sourceItem(title: 'Roma'));

      final title = (await versions('art'))[EntryField.title]!;
      expect(title.deviceId, me);
      expect(title.baseUpdatedAt, theirs);
      expect(title.baseDeviceId, other);
    });

    test(
      'una edición posterior mía sigue partiendo de esa misma versión ajena',
      () async {
        await writer.upsert(sourceItem());
        final theirs = clockNow.add(const Duration(hours: 1));
        await putForeignVersion('art', EntryField.title, at: theirs);
        tick();
        await writer.upsert(sourceItem(title: 'Roma'));
        tick();

        await writer.upsert(sourceItem(title: 'Roma antigua'));

        final title = (await versions('art'))[EntryField.title]!;
        expect(title.baseUpdatedAt, theirs);
        expect(title.baseDeviceId, other);
      },
    );

    test('cada campo lleva su propio linaje', () async {
      await writer.upsert(sourceItem(subtitle: 'Livio'));
      final theirs = clockNow.add(const Duration(hours: 1));
      await putForeignVersion('art', EntryField.title, at: theirs);
      tick();

      await writer.upsert(sourceItem(title: 'Roma', subtitle: 'Tito Livio'));

      final fields = await versions('art');
      expect(fields[EntryField.title]!.baseDeviceId, other);
      // El subtítulo nunca lo tocó nadie más: su cadena es solo mía.
      expect(fields[EntryField.subtitle]!.baseDeviceId, isNull);
    });
  });

  group('cambiar el espacio', () {
    test(
      'solo los elementos que cambian de espacio suben de revisión',
      () async {
        await writer.upsert(sourceItem(id: 'a'));
        await writer.upsert(sourceItem(id: 'b'));
        await writer.upsert(noteItem(id: 'c'));
        // `spaces` es una tabla de verdad: el espacio existe.
        await db
            .into(db.spaces)
            .insert(
              SpacesCompanion.insert(
                id: 'esp',
                name: 'Historia',
                createdAt: captured,
              ),
            );
        await writer.setSpace(['a'], 'esp');
        tick();

        await writer.setSpace(['a', 'b'], 'esp');

        expect((await entry('a')).rev, 2, reason: 'ya estaba en el espacio');
        expect((await entry('b')).rev, 2);
        expect((await entry('c')).rev, 1, reason: 'no estaba en la lista');
        expect((await entry('b')).spaceId, 'esp');
        expect((await versions('b'))[EntryField.spaceId]!.updatedAt, clockNow);
      },
    );

    test('sacar un elemento de su espacio también es un cambio', () async {
      await db
          .into(db.spaces)
          .insert(
            SpacesCompanion.insert(
              id: 'esp',
              name: 'Historia',
              createdAt: captured,
            ),
          );
      await writer.upsert(sourceItem(spaceId: 'esp'));
      tick();

      await writer.setSpace(['art'], null);

      expect((await entry('art')).spaceId, isNull);
      expect((await entry('art')).rev, 2);
      expect((await versions('art'))[EntryField.spaceId]!.updatedAt, clockNow);
    });

    test(
      'una lista larga se reparte en varias consultas sin perder ninguno',
      () async {
        await db
            .into(db.spaces)
            .insert(
              SpacesCompanion.insert(
                id: 'esp',
                name: 'Historia',
                createdAt: captured,
              ),
            );
        final ids = [for (var i = 0; i < 1000; i++) 'e$i'];
        await db.batch(
          (batch) => batch.insertAll(db.knowledgeEntries, [
            for (final id in ids)
              KnowledgeEntriesCompanion.insert(
                id: id,
                title: id,
                kind: ItemKind.source,
                state: ItemState.processed,
                createdAt: captured,
                updatedAt: captured,
                deviceId: me,
              ),
          ]),
        );

        await writer.setSpace(ids, 'esp');

        final moved = await (db.select(
          db.knowledgeEntries,
        )..where((e) => e.spaceId.equals('esp'))).get();
        expect(moved, hasLength(1000));
        expect(moved.every((e) => e.rev == 2), isTrue);
        expect(
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM field_version')
                  .getSingle())
              .read<int>('n'),
          1000,
        );
      },
    );

    test('una lista vacía no hace nada', () async {
      await writer.upsert(sourceItem());

      await writer.setSpace(const [], 'esp');

      expect((await entry('art')).rev, 1);
    });
  });

  group('estado, subtipo y madurez', () {
    test('cambiar el estado sube la revisión y registra la versión', () async {
      await writer.upsert(sourceItem());
      tick();

      final found = await writer.setState('art', ItemState.triaged);

      expect(found, isTrue);
      expect((await entry('art')).state, ItemState.triaged);
      expect((await entry('art')).rev, 2);
      expect((await versions('art'))[EntryField.state]!.updatedAt, clockNow);
    });

    test('«cambiar» al estado que ya tiene no ensucia la historia', () async {
      await writer.upsert(sourceItem());
      final state = (await entry('art')).state;
      tick();

      final found = await writer.setState('art', state);

      expect(found, isTrue);
      expect((await entry('art')).rev, 1);
    });

    test('un elemento que no existe devuelve false', () async {
      expect(await writer.setState('nada', ItemState.triaged), isFalse);
      expect(await writer.setNoteKind('nada', NoteKind.atomic), isFalse);
      expect(await writer.setMaturity('nada', NoteMaturity.mature), isFalse);
    });

    test('el subtipo y la madurez de una nota se versionan', () async {
      await writer.upsert(noteItem());
      tick();

      await writer.setNoteKind('nota', NoteKind.atomic);
      tick();
      await writer.setMaturity('nota', NoteMaturity.mature);

      final note = await (db.select(
        db.knowledgeNotes,
      )..where((n) => n.itemId.equals('nota'))).getSingle();
      expect(note.noteKind, NoteKind.atomic);
      expect(note.maturity, NoteMaturity.mature);
      expect((await entry('nota')).rev, 3);
      final fields = await versions('nota');
      expect(fields[EntryField.noteKind], isNotNull);
      expect(fields[EntryField.maturity]!.updatedAt, clockNow);
    });

    test('el subtipo y la madurez de una fuente no existen: false', () async {
      await writer.upsert(sourceItem());

      expect(await writer.setNoteKind('art', NoteKind.atomic), isFalse);
      expect(await writer.setMaturity('art', NoteMaturity.mature), isFalse);
    });
  });

  group('borrar para siempre', () {
    Future<int> count(String table) async =>
        (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
            .read<int>('n');

    test('se lleva la fila y todo lo que cuelga de ella', () async {
      await writer.upsert(sourceItem(), changedRenditions: ['r-1']);
      await writer.upsert(sourceItem(id: 'otro'));
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'r-1',
              itemId: 'art',
              kind: RenditionKind.plainText,
              isPrimary: true,
              createdAt: captured,
              content: const Value('El texto.'),
            ),
          );

      await writer.purge('art');

      expect(await count('item'), 1);
      expect(await count('source'), 1);
      expect(await count('renditions'), 0);
      // Sus versiones por campo también: solo quedan las del otro elemento.
      final left = await db.select(db.fieldVersions).get();
      expect(left.map((f) => f.itemId).toSet(), {'otro'});
    });

    test('un elemento que no existe no es un error', () async {
      await writer.purge('nada');

      expect(await count('item'), 0);
    });
  });
}
