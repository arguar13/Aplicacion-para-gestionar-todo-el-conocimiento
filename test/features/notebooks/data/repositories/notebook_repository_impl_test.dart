import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: lo que importa es que un cuaderno manual
/// resuelve por sus elementos (`notebook_item`) y uno por consulta por su
/// `LibraryQuery` guardada, y que sacar un elemento de un cuaderno no lo
/// borra de la bóveda.
void main() {
  late AppDatabase db;
  late NotebookRepositoryImpl repository;
  late FakeIdGenerator ids;
  var now = DateTime(2026, 9, 24, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    now = DateTime(2026, 9, 24, 10);
    repository = NotebookRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  group('create', () {
    test('un cuaderno manual nace sin consulta y sin elementos', () async {
      final notebook = await repository.create(
        name: 'Tesis',
        mode: NotebookMode.manual,
      );

      expect(notebook.name, 'Tesis');
      expect(notebook.mode, NotebookMode.manual);
      expect(notebook.query, isNull);
      expect(notebook.createdAt, now);
      expect(notebook.updatedAt, now);

      final resolved = await repository.resolveQuery(notebook.id);
      expect(resolved.ids, isEmpty);
    });

    test(
      'un cuaderno por consulta guarda esa consulta y la devuelve igual',
      () async {
        const query = LibraryQuery(
          searchText: 'paradigma',
          sortBy: LibrarySort.title,
        );

        final notebook = await repository.create(
          name: 'Por consulta',
          mode: NotebookMode.query,
          query: query,
        );

        expect(notebook.query, query);
        final all = await repository.watchAll().first;
        expect(all.single.query, query);
        expect(await repository.resolveQuery(notebook.id), query);
      },
    );
  });

  group('addItem / removeItem', () {
    test('agregar y sacar cambian a quién resuelve la consulta', () async {
      await insertItemRows(db, id: 'a', title: 'Uno');
      await insertItemRows(db, id: 'b', title: 'Dos');
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );

      await repository.addItem(notebookId: notebook.id, itemId: 'a');
      await repository.addItem(notebookId: notebook.id, itemId: 'b');
      expect((await repository.resolveQuery(notebook.id)).ids, {'a', 'b'});

      await repository.removeItem(notebookId: notebook.id, itemId: 'a');
      expect((await repository.resolveQuery(notebook.id)).ids, {'b'});

      // Sacarlo del cuaderno no lo borra de la bóveda.
      final items = await db.select(db.knowledgeEntries).get();
      expect(items.map((i) => i.id), containsAll(['a', 'b']));
    });

    test('agregar el mismo elemento dos veces no es un error', () async {
      await insertItemRows(db, id: 'a', title: 'Uno');
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );

      await repository.addItem(notebookId: notebook.id, itemId: 'a');
      await repository.addItem(notebookId: notebook.id, itemId: 'a');

      expect((await repository.resolveQuery(notebook.id)).ids, {'a'});
    });

    test('agregar o sacar un elemento actualiza `updatedAt`', () async {
      await insertItemRows(db, id: 'a', title: 'Uno');
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );

      now = DateTime(2026, 9, 24, 11);
      await repository.addItem(notebookId: notebook.id, itemId: 'a');

      final after = (await repository.watchAll().first).single;
      expect(after.updatedAt, now);
    });
  });

  group('rename y delete', () {
    test('cada uno cambia solo lo suyo', () async {
      final a = await repository.create(name: 'A', mode: NotebookMode.manual);
      final b = await repository.create(name: 'B', mode: NotebookMode.manual);

      await repository.rename(id: a.id, name: 'A renombrado');

      final afterRename = await repository.watchAll().first;
      expect(afterRename.firstWhere((n) => n.id == a.id).name, 'A renombrado');
      expect(afterRename.firstWhere((n) => n.id == b.id).name, 'B');

      await repository.delete(a.id);
      final afterDelete = await repository.watchAll().first;
      expect(afterDelete.map((n) => n.id), [b.id]);
    });
  });

  group('watchById', () {
    test('emite el cuaderno, y `null` si se borra', () async {
      final notebook = await repository.create(
        name: 'Tesis',
        mode: NotebookMode.manual,
      );

      expect((await repository.watchById(notebook.id).first)?.name, 'Tesis');

      await repository.delete(notebook.id);
      expect(await repository.watchById(notebook.id).first, isNull);
    });

    test('un id que nunca existió emite `null`', () async {
      expect(await repository.watchById('no-existe').first, isNull);
    });
  });

  group('watchItemIds', () {
    test('se actualiza solo con addItem/removeItem', () async {
      await insertItemRows(db, id: 'a', title: 'Uno');
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );

      expect(await repository.watchItemIds(notebook.id).first, isEmpty);

      await repository.addItem(notebookId: notebook.id, itemId: 'a');
      expect(await repository.watchItemIds(notebook.id).first, {'a'});

      await repository.removeItem(notebookId: notebook.id, itemId: 'a');
      expect(await repository.watchItemIds(notebook.id).first, isEmpty);
    });

    test('un cuaderno por consulta no tiene ids propios', () async {
      final notebook = await repository.create(
        name: 'Por consulta',
        mode: NotebookMode.query,
        query: const LibraryQuery(),
      );

      expect(await repository.watchItemIds(notebook.id).first, isEmpty);
    });
  });

  test('borrar un elemento lo saca de sus cuadernos manuales', () async {
    await insertItemRows(db, id: 'a', title: 'Uno');
    final notebook = await repository.create(
      name: 'A mano',
      mode: NotebookMode.manual,
    );
    await repository.addItem(notebookId: notebook.id, itemId: 'a');

    await deleteItemRows(db, 'a');

    expect((await repository.resolveQuery(notebook.id)).ids, isEmpty);
    // El cuaderno sigue existiendo.
    expect(await repository.watchAll().first, hasLength(1));
  });
}
