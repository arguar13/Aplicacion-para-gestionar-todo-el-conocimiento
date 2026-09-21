import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Filtrar por un valor del vocabulario trae también lo de sus subtemas (F13),
/// y lo hace la consulta, no una asignación duplicada.
///
/// Contra SQLite de verdad: lo que se comprueba es lo que la base devuelve.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  final now = DateTime(2026, 9, 21, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
  });

  tearDown(() => db.close());

  Future<String> temaId() async => (await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.equals('Tema'))).getSingle()).id;

  Future<void> value(String id, {String? parent, int depth = 0}) async {
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: await temaId(),
            value: 'Valor $id',
            createdAt: now,
            parentId: Value(parent),
            depth: Value(depth),
          ),
        );
  }

  Future<void> item(String id, List<String> values) async {
    await insertItemRows(db, id: id, title: 'Elemento $id', createdAt: now);
    for (final valueId in values) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: id,
              propertyValueId: valueId,
            ),
          );
    }
  }

  Future<Set<String>> idsFor(LibraryQuery query) async => {
    for (final i in (await library.list(query)).getRight().toNullable()!) i.id,
  };

  /// roma ─ republica ─ gracos, roma ─ imperio, y grecia sola; un elemento
  /// para cada uno y uno con dos.
  Future<void> seed() async {
    await value('roma');
    await value('republica', parent: 'roma', depth: 1);
    await value('gracos', parent: 'republica', depth: 2);
    await value('imperio', parent: 'roma', depth: 1);
    await value('grecia');
    await item('e-roma', ['roma']);
    await item('e-republica', ['republica']);
    await item('e-gracos', ['gracos']);
    await item('e-imperio', ['imperio']);
    await item('e-grecia', ['grecia']);
    await item('e-dos', ['gracos', 'grecia']);
    await item('e-nada', const []);
  }

  test(
    'filtrar por un padre trae lo suyo y lo de todos sus descendientes',
    () async {
      await seed();

      final found = await idsFor(
        const LibraryQuery(propertyValueIds: {'roma'}),
      );

      expect(found, {
        'e-roma',
        'e-republica',
        'e-gracos',
        'e-imperio',
        'e-dos',
      });
    },
  );

  test(
    'filtrar por un nivel del medio trae hacia abajo y no hacia arriba',
    () async {
      await seed();

      final found = await idsFor(
        const LibraryQuery(propertyValueIds: {'republica'}),
      );

      expect(found, {'e-republica', 'e-gracos', 'e-dos'});
      expect(found, isNot(contains('e-roma')));
    },
  );

  test('filtrar por una hoja trae solo lo suyo', () async {
    await seed();

    expect(await idsFor(const LibraryQuery(propertyValueIds: {'gracos'})), {
      'e-gracos',
      'e-dos',
    });
  });

  test('asignar un valor hijo NO asigna a su padre: la jerarquía se resuelve '
      'en la consulta', () async {
    await seed();

    final assignedToRoma = await (db.select(
      db.itemPropertyValues,
    )..where((a) => a.propertyValueId.equals('roma'))).get();

    expect(assignedToRoma.map((a) => a.itemId), ['e-roma']);
  });

  test(
    'varios valores a la vez: cualquiera de ellos, cada elemento una vez',
    () async {
      await seed();

      const query = LibraryQuery(propertyValueIds: {'republica', 'grecia'});
      final found = (await library.list(query)).getRight().toNullable()!;

      expect(found.map((i) => i.id).toSet(), {
        'e-republica',
        'e-gracos',
        'e-dos',
        'e-grecia',
      });
      // `e-dos` tiene un valor de cada rama y no se repite.
      expect(found.where((i) => i.id == 'e-dos'), hasLength(1));
    },
  );

  test('un padre y su hijo pedidos juntos no duplican', () async {
    await seed();

    final found = (await library.list(
      const LibraryQuery(propertyValueIds: {'roma', 'republica'}),
    )).getRight().toNullable()!;

    expect(found.map((i) => i.id).toSet(), {
      'e-roma',
      'e-republica',
      'e-gracos',
      'e-imperio',
      'e-dos',
    });
    expect(found, hasLength(5));
  });

  test('la cuenta coincide con la lista', () async {
    await seed();
    const query = LibraryQuery(propertyValueIds: {'roma'});

    final count = (await library.count(query)).getRight().toNullable();

    expect(count, (await idsFor(query)).length);
  });

  test(
    'las etiquetas —los valores de Tema— también filtran hacia abajo',
    () async {
      await seed();

      expect(await idsFor(const LibraryQuery(tagIds: {'republica'})), {
        'e-republica',
        'e-gracos',
        'e-dos',
      });
    },
  );

  test('se combina con los demás filtros: entre filtros, todos', () async {
    await seed();

    final found = await idsFor(
      const LibraryQuery(
        propertyValueIds: {'roma'},
        ids: {'e-gracos', 'e-grecia', 'e-nada'},
      ),
    );

    expect(found, {'e-gracos'});
  });

  test('lo que está en la papelera no entra, ni por la rama', () async {
    await seed();
    await db.customStatement('UPDATE item SET deleted_at = 1 WHERE id = ?', [
      'e-gracos',
    ]);

    final found = await idsFor(const LibraryQuery(propertyValueIds: {'roma'}));

    expect(found, isNot(contains('e-gracos')));
    expect(found, contains('e-republica'));
  });

  test('un valor sin hijos se comporta como antes', () async {
    await seed();

    expect(await idsFor(const LibraryQuery(propertyValueIds: {'grecia'})), {
      'e-grecia',
      'e-dos',
    });
  });
}
