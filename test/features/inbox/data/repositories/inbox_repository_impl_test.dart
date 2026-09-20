import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/inbox/data/repositories/inbox_repository_impl.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria, sembrando filas directo en
/// `knowledgeEntries`/`knowledgeNotes` a mano: no hace falta pasar por
/// `LibraryRepositoryImpl` para probar solo el espejo, que es lo único
/// que `InboxRepositoryImpl` lee y escribe.
void main() {
  late AppDatabase db;
  late InboxRepositoryImpl repository;

  final now = DateTime(2026, 9, 18, 10);
  var counter = 0;
  var clockNow = DateTime(2026, 9, 20, 9);

  setUp(() {
    clockNow = DateTime(2026, 9, 20, 9);
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    repository = InboxRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      clock: () => clockNow,
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<String> seedEntry({
    ItemKind kind = ItemKind.source,
    ItemState state = ItemState.processed,
    String title = 'Un elemento',
    DateTime? updatedAt,
  }) async {
    final id = 'item-${counter++}';
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: id,
            title: title,
            kind: kind,
            state: state,
            createdAt: now,
            updatedAt: updatedAt ?? now,
            deviceId: 'test',
          ),
        );
    return id;
  }

  Future<void> seedNote(
    String itemId, {
    NoteKind noteKind = NoteKind.living,
    NoteMaturity maturity = NoteMaturity.seed,
  }) async {
    await db
        .into(db.knowledgeNotes)
        .insert(
          KnowledgeNotesCompanion.insert(
            itemId: itemId,
            noteKind: noteKind,
            maturity: maturity,
          ),
        );
  }

  group('watchPendingIds', () {
    test('solo trae fuentes en processed', () async {
      final pending = await seedEntry();
      final captured = await seedEntry(state: ItemState.captured);
      final triaged = await seedEntry(state: ItemState.triaged);
      final noteId = await seedEntry(kind: ItemKind.note);
      await seedNote(noteId);

      final ids = await repository.watchPendingIds().first;

      expect(ids, [pending]);
      expect(ids, isNot(contains(captured)));
      expect(ids, isNot(contains(triaged)));
      expect(ids, isNot(contains(noteId)));
    });

    test('ordena de más vieja a más nueva por updatedAt', () async {
      final nueva = await seedEntry(
        title: 'Nueva',
        updatedAt: now.add(const Duration(hours: 2)),
      );
      final vieja = await seedEntry(
        title: 'Vieja',
        updatedAt: now.add(const Duration(hours: 1)),
      );

      final ids = await repository.watchPendingIds().first;

      expect(ids, [vieja, nueva]);
    });

    test('se actualiza sola cuando un elemento cambia de estado', () async {
      final id = await seedEntry();

      expect(await repository.watchPendingIds().first, [id]);

      await repository.transitionState(itemId: id, to: ItemState.discarded);

      expect(await repository.watchPendingIds().first, isEmpty);
    });
  });

  group('transitionState', () {
    test('cambia el estado del elemento', () async {
      final id = await seedEntry();

      final result = await repository.transitionState(
        itemId: id,
        to: ItemState.triaged,
      );

      expect(result.isRight(), isTrue);
      final entry = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(id))).getSingle();
      expect(entry.state, ItemState.triaged);
    });

    test('un elemento que no existe devuelve un fallo, no revienta', () async {
      final result = await repository.transitionState(
        itemId: 'no-existe',
        to: ItemState.discarded,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('watchLivingNotes', () {
    test('solo trae notas con noteKind living', () async {
      final viva = await seedEntry(kind: ItemKind.note, title: 'Viva');
      await seedNote(viva);
      final atomica = await seedEntry(kind: ItemKind.note, title: 'Atómica');
      await seedNote(atomica, noteKind: NoteKind.atomic);
      final fuente = await seedEntry();

      final notes = await repository.watchLivingNotes().first;

      expect(notes.map((n) => n.id), [viva]);
      expect(notes.map((n) => n.id), isNot(contains(atomica)));
      expect(notes.map((n) => n.id), isNot(contains(fuente)));
    });

    test('filtra por título, sin distinguir mayúsculas', () async {
      final roma = await seedEntry(kind: ItemKind.note, title: 'Roma antigua');
      await seedNote(roma);
      final egipto = await seedEntry(kind: ItemKind.note, title: 'Egipto');
      await seedNote(egipto);

      final notes = await repository.watchLivingNotes(searchText: 'roma').first;

      expect(notes.map((n) => n.id), [roma]);
    });
  });

  group('watchNoteMaturity', () {
    test('null para una fuente', () async {
      final id = await seedEntry();

      expect(await repository.watchNoteMaturity(id).first, isNull);
    });

    test('el valor real para una nota', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id, maturity: NoteMaturity.developing);

      expect(
        await repository.watchNoteMaturity(id).first,
        NoteMaturity.developing,
      );
    });
  });

  group('watchNoteKind', () {
    test('null para una fuente', () async {
      final id = await seedEntry();

      expect(await repository.watchNoteKind(id).first, isNull);
    });

    test('el valor real para una nota', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id, noteKind: NoteKind.atomic);

      expect(await repository.watchNoteKind(id).first, NoteKind.atomic);
    });

    test('se actualiza sola tras setNoteKind', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);

      expect(await repository.watchNoteKind(id).first, NoteKind.living);

      await repository.setNoteKind(itemId: id, kind: NoteKind.map);

      expect(await repository.watchNoteKind(id).first, NoteKind.map);
    });
  });

  group('setNoteKind', () {
    test('cambia el tipo de la nota', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);

      final result = await repository.setNoteKind(
        itemId: id,
        kind: NoteKind.map,
      );

      expect(result.isRight(), isTrue);
      final row = await (db.select(
        db.knowledgeNotes,
      )..where((n) => n.itemId.equals(id))).getSingle();
      expect(row.noteKind, NoteKind.map);
    });

    test('sin espejo de nota devuelve un fallo, no revienta', () async {
      final id = await seedEntry(kind: ItemKind.note);
      // Sin `seedNote`: el elemento existe pero no tiene fila en
      // `knowledgeNotes` — el mismo caso que un elemento que todavía no
      // pasó por el espejo.

      final result = await repository.setNoteKind(
        itemId: id,
        kind: NoteKind.map,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('setNoteMaturity', () {
    test('cambia la madurez de la nota', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);

      final result = await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.mature,
      );

      expect(result.isRight(), isTrue);
      final row = await (db.select(
        db.knowledgeNotes,
      )..where((n) => n.itemId.equals(id))).getSingle();
      expect(row.maturity, NoteMaturity.mature);
    });

    test(
      'se puede volver atrás: la madurez no es un escalón de una sola vía',
      () async {
        final id = await seedEntry(kind: ItemKind.note);
        await seedNote(id, maturity: NoteMaturity.mature);

        await repository.setNoteMaturity(
          itemId: id,
          maturity: NoteMaturity.seed,
        );

        expect(await repository.watchNoteMaturity(id).first, NoteMaturity.seed);
      },
    );

    test('no toca el tipo de la nota ni a las demás', () async {
      final id = await seedEntry(kind: ItemKind.note);
      final other = await seedEntry(kind: ItemKind.note);
      await seedNote(id, noteKind: NoteKind.map);
      await seedNote(other);

      await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.developing,
      );

      expect(await repository.watchNoteKind(id).first, NoteKind.map);
      expect(
        await repository.watchNoteMaturity(other).first,
        NoteMaturity.seed,
      );
    });

    test('se refleja sola en watchNoteMaturity', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);
      final emissions = repository.watchNoteMaturity(id);
      final expectation = expectLater(
        emissions,
        emitsThrough(NoteMaturity.developing),
      );

      await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.developing,
      );

      await expectation.timeout(const Duration(seconds: 5));
    });

    test('sin espejo de nota devuelve un fallo, no revienta', () async {
      final id = await seedEntry(kind: ItemKind.note);

      final result = await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.mature,
      );

      expect(result.isLeft(), isTrue);
    });

    test('una fuente no tiene madurez: falla', () async {
      final id = await seedEntry();

      final result = await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.mature,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('quién y cuándo (F11)', () {
    Future<KnowledgeEntryRow> entryOf(String id) => (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(id))).getSingle();

    Future<Map<String, FieldVersionRow>> versionsOf(String id) async => {
      for (final row in await (db.select(
        db.fieldVersions,
      )..where((f) => f.itemId.equals(id))).get())
        row.fieldName: row,
    };

    test('pasar un elemento de estado deja su firma y su versión', () async {
      final id = await seedEntry();

      await repository.transitionState(itemId: id, to: ItemState.triaged);

      final entry = await entryOf(id);
      expect(entry.state, ItemState.triaged);
      expect(entry.rev, 2);
      expect(entry.deviceId, 'telefono');
      final state = (await versionsOf(id))[EntryField.state]!;
      expect(state.updatedAt, clockNow);
      expect(state.deviceId, 'telefono');
    });

    test('«pasar» al estado que ya tiene no cuenta como un cambio', () async {
      final id = await seedEntry();

      final result = await repository.transitionState(
        itemId: id,
        to: ItemState.processed,
      );

      expect(result.isRight(), isTrue);
      expect((await entryOf(id)).rev, 1);
      expect(await versionsOf(id), isEmpty);
    });

    test('cambiar el subtipo y la madurez de una nota los versiona', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);

      await repository.setNoteKind(itemId: id, kind: NoteKind.atomic);
      clockNow = clockNow.add(const Duration(minutes: 5));
      await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.mature,
      );

      expect((await entryOf(id)).rev, 3);
      final fields = await versionsOf(id);
      expect(fields[EntryField.noteKind]!.deviceId, 'telefono');
      expect(fields[EntryField.maturity]!.updatedAt, clockNow);
    });
  });
}
