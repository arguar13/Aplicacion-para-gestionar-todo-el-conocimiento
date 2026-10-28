import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_scope.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/processed_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: lo que importa es que un cuaderno manual
/// resuelve por sus elementos (`notebook_item`) y uno por consulta por su
/// vista guardada, traducida a procesados; que en un cuaderno entran solo
/// documentos procesados (F41, paso 5); y que sacar uno de un cuaderno no lo
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
      processed: ProcessedRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        files: InMemoryFileStore(),
      ),
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
        expect(
          await repository.resolveQuery(notebook.id),
          processedQueryForView(query),
        );
      },
    );
  });

  group('addItem / removeItem', () {
    test('agregar y sacar cambian a quién resuelve la consulta', () async {
      await insertProcessedRows(db, id: 'a', title: 'Uno');
      await insertProcessedRows(db, id: 'b', title: 'Dos');
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
      await insertProcessedRows(db, id: 'a', title: 'Uno');
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );

      await repository.addItem(notebookId: notebook.id, itemId: 'a');
      await repository.addItem(notebookId: notebook.id, itemId: 'a');

      expect((await repository.resolveQuery(notebook.id)).ids, {'a'});
    });

    test('addItems agrega varios de una vez, con un solo aviso, y los que '
        'ya estaban no cambian nada (F30)', () async {
      await insertProcessedRows(db, id: 'a', title: 'Uno');
      await insertProcessedRows(db, id: 'b', title: 'Dos');
      await insertProcessedRows(db, id: 'c', title: 'Tres');
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );
      await repository.addItem(notebookId: notebook.id, itemId: 'a');

      final emitted = <Set<String>>[];
      final subscription = repository
          .watchItemIds(notebook.id)
          .listen(emitted.add);
      await pumpEventQueue();
      now = DateTime(2026, 9, 24, 12);

      await repository.addItems(
        notebookId: notebook.id,
        itemIds: ['a', 'b', 'c', 'b'],
      );
      await pumpEventQueue();
      await subscription.cancel();

      expect((await repository.resolveQuery(notebook.id)).ids, {'a', 'b', 'c'});
      expect(emitted, [
        {'a'},
        {'a', 'b', 'c'},
      ]);
      expect((await repository.watchAll().first).single.updatedAt, now);
    });

    test('addItems sin ninguno no toca el cuaderno', () async {
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );
      now = DateTime(2026, 9, 24, 12);

      await repository.addItems(notebookId: notebook.id, itemIds: const []);

      expect(
        (await repository.watchAll().first).single.updatedAt,
        DateTime(2026, 9, 24, 10),
      );
    });

    test('agregar o sacar un elemento actualiza `updatedAt`', () async {
      await insertProcessedRows(db, id: 'a', title: 'Uno');
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

  group('el aviso del cuaderno vaciado (F41, v46)', () {
    test('se lee de la marca, y descartarlo la deja en null sin tocar nada '
        'más', () async {
      final notebook = await repository.create(
        name: 'Tesis',
        mode: NotebookMode.manual,
      );
      final emptied = DateTime(2026, 10, 28, 9);
      await (db.update(db.notebooks)..where((n) => n.id.equals(notebook.id)))
          .write(NotebooksCompanion(emptiedForProcessedAt: Value(emptied)));

      final marked = (await repository.watchById(notebook.id).first)!;
      expect(marked.emptiedForProcessedAt, emptied);
      expect(marked.showsEmptiedNotice, isTrue);

      now = DateTime(2026, 10, 28, 12);
      await repository.dismissEmptiedNotice(notebook.id);

      final dismissed = (await repository.watchById(notebook.id).first)!;
      expect(dismissed.emptiedForProcessedAt, isNull);
      expect(dismissed.showsEmptiedNotice, isFalse);
      // Es un aviso, no un cambio del cuaderno.
      expect(dismissed.updatedAt, marked.updatedAt);
      expect(dismissed.name, 'Tesis');
    });

    test('un cuaderno nuevo no tiene aviso', () async {
      final notebook = await repository.create(
        name: 'Nuevo',
        mode: NotebookMode.manual,
      );

      expect(notebook.showsEmptiedNotice, isFalse);
      expect(
        (await repository.watchById(notebook.id).first)!.showsEmptiedNotice,
        isFalse,
      );
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
      await insertProcessedRows(db, id: 'a', title: 'Uno');
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

  group('solo documentos procesados (F41, paso 5)', () {
    test('una fuente, una nota, uno en la papelera o un id que no existe no '
        'entran: solo el procesado vivo', () async {
      await insertItemRows(db, id: 'fuente', title: 'Una fuente');
      await insertItemRows(
        db,
        id: 'nota',
        title: 'Una nota',
        kind: SourceKind.manualNote,
      );
      await insertProcessedRows(db, id: 'pro', title: 'Procesado');
      await insertProcessedRows(db, id: 'borrado', title: 'En la papelera');
      await trashItemRows(db, 'borrado');
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );

      await repository.addItems(
        notebookId: notebook.id,
        itemIds: ['fuente', 'nota', 'fantasma', 'borrado', 'pro'],
      );
      await repository.addItem(notebookId: notebook.id, itemId: 'fuente');

      expect(await repository.watchItemIds(notebook.id).first, {'pro'});
      expect(
        (await repository.memberIds(notebook.id)).getRight().toNullable(),
        ['pro'],
      );
    });

    test('memberIds deja afuera lo que está en la papelera, y vuelve cuando '
        'se recupera', () async {
      await insertProcessedRows(db, id: 'a', title: 'Uno');
      await insertProcessedRows(db, id: 'b', title: 'Dos');
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );
      await repository.addItems(notebookId: notebook.id, itemIds: ['a', 'b']);

      await trashItemRows(db, 'a');
      expect(
        (await repository.memberIds(notebook.id)).getRight().toNullable(),
        ['b'],
      );

      await restoreItemRows(db, 'a');
      expect(
        (await repository.memberIds(notebook.id)).getRight().toNullable(),
        unorderedEquals(['a', 'b']),
      );
    });

    test('uno por consulta trae los procesados que cumplen su vista, nunca '
        'las fuentes', () async {
      await insertItemRows(db, id: 'fuente', title: 'Roma antigua');
      await insertProcessedRows(
        db,
        id: 'roma',
        title: 'Apuntes',
        parts: {
          ProcessedSection.summary: ['Los acueductos de Roma.'],
        },
      );
      await insertProcessedRows(db, id: 'grecia', title: 'Atenas');
      final notebook = await repository.create(
        name: 'Roma',
        mode: NotebookMode.query,
        query: const LibraryQuery(searchText: 'roma'),
      );

      expect(
        (await repository.memberIds(notebook.id)).getRight().toNullable(),
        ['roma'],
      );
    });

    group('la vista, sobre lo que tiene un procesado', () {
      Future<List<String>?> membersOf(LibraryQuery query) async {
        final notebook = await repository.create(
          name: 'Vista',
          mode: NotebookMode.query,
          query: query,
        );
        return (await repository.memberIds(
          notebook.id,
        )).getRight().toNullable();
      }

      Future<void> value(String id, {String? parent}) => db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: id,
              definitionId: 'cat',
              value: id,
              createdAt: now,
              parentId: Value(parent),
            ),
          );

      Future<void> assign(String itemId, String valueId) => db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: itemId,
              propertyValueId: valueId,
            ),
          );

      setUp(() async {
        await db
            .into(db.propertyDefinitions)
            .insert(
              PropertyDefinitionsCompanion.insert(
                id: 'cat',
                name: 'Período',
                createdAt: now,
              ),
            );
        await value('antigua');
        await value('roma', parent: 'antigua');
        await value('grecia', parent: 'antigua');
        await insertProcessedRows(
          db,
          id: 'p-roma',
          title: 'Roma',
          sourceKind: SourceKind.youtube,
        );
        await insertProcessedRows(db, id: 'p-grecia', title: 'Grecia');
        await insertProcessedRows(db, id: 'p-suelto', title: 'Suelto');
        // Una fuente con la misma etiqueta: no es de un cuaderno.
        await insertItemRows(db, id: 'fuente', title: 'Fuente');
        await assign('p-roma', 'roma');
        await assign('p-grecia', 'grecia');
        await assign('fuente', 'roma');
        await db
            .into(db.spaces)
            .insert(
              SpacesCompanion.insert(id: 'sp', name: 'Sp', createdAt: now),
            );
        await placeItemRowsInSpace(db, ['p-roma'], 'sp');
      });

      test('una etiqueta o un valor trae también sus ramas', () async {
        expect(
          await membersOf(const LibraryQuery(tagIds: {'antigua'})),
          unorderedEquals(['p-roma', 'p-grecia']),
        );
        expect(
          await membersOf(const LibraryQuery(propertyValueIds: {'roma'})),
          ['p-roma'],
        );
        // Entre los dos filtros, se cumplen los dos.
        expect(
          await membersOf(
            const LibraryQuery(
              tagIds: {'antigua'},
              propertyValueIds: {'grecia'},
            ),
          ),
          ['p-grecia'],
        );
      });

      test('un tema, y el tipo de la fuente de origen', () async {
        expect(await membersOf(const LibraryQuery(spaceId: 'sp')), ['p-roma']);
        expect(
          await membersOf(
            const LibraryQuery(sourceKinds: {SourceKind.youtube}),
          ),
          ['p-roma'],
        );
      });

      test('se ordena como pide la vista', () async {
        expect(
          await membersOf(
            const LibraryQuery(sortBy: LibrarySort.title, descending: false),
          ),
          ['p-grecia', 'p-roma', 'p-suelto'],
        );
      });

      test('cambiar las etiquetas de un procesado cambia lo que trae, en '
          'vivo', () async {
        final notebook = await repository.create(
          name: 'Grecia',
          mode: NotebookMode.query,
          query: const LibraryQuery(tagIds: {'grecia'}),
        );
        final processed = ProcessedRepositoryImpl(
          database: db,
          telemetry: MockTelemetryService(),
          files: InMemoryFileStore(),
        );
        final query = await repository.resolveQuery(notebook.id);
        final emitted = <List<String>>[];
        final subscription = processed
            .watchDocuments(query)
            .listen((docs) => emitted.add([for (final d in docs) d.id]));
        await pumpEventQueue();

        await assign('p-suelto', 'grecia');
        await pumpEventQueue();
        await subscription.cancel();

        expect(emitted.first, ['p-grecia']);
        expect(emitted.last, unorderedEquals(['p-grecia', 'p-suelto']));
      });
    });

    test(
      'memberIds de un cuaderno que ya no existe falla, y lo dice',
      () async {
        final result = await repository.memberIds('no-existe');

        expect(result.isLeft(), isTrue);
      },
    );
  });

  test('borrar un elemento lo saca de sus cuadernos manuales', () async {
    await insertProcessedRows(db, id: 'a', title: 'Uno');
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
