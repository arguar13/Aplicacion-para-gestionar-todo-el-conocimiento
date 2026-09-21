import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/vocabulary/data/repositories/vocabulary_repository_impl.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_operation.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// La jerarquía del vocabulario, desde el repositorio (F13): mover una rama,
/// su vista previa, y cómo la respetan la fusión y el borrado de F8 —con
/// deshacer—.
///
/// Contra SQLite de verdad: lo que importa es que los niveles queden
/// recalculados en la base y que cada negativa deje todo como estaba.
void main() {
  late AppDatabase db;
  late VocabularyRepositoryImpl repository;
  final now = DateTime(2026, 9, 21, 10);
  var seededItems = <String>{};

  setUp(() {
    seededItems = {};
    db = AppDatabase(NativeDatabase.memory());
    repository = VocabularyRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(prefix: 'gen'),
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  Future<String> temaId() async => (await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.equals('Tema'))).getSingle()).id;

  Future<void> addValue(
    String id, {
    String? parent,
    int depth = 0,
    String? definitionId,
    List<String> items = const [],
  }) async {
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: definitionId ?? await temaId(),
            value: 'Valor $id',
            createdAt: now,
            parentId: Value(parent),
            depth: Value(depth),
          ),
        );
    for (final item in items) {
      if (seededItems.add(item)) {
        await insertItemRows(
          db,
          id: item,
          title: 'Elemento $item',
          createdAt: now,
        );
      }
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: item,
              propertyValueId: id,
            ),
          );
    }
  }

  /// roma ─ republica ─ gracos, roma ─ imperio, y grecia sola.
  Future<void> seedRoma() async {
    await addValue('roma');
    await addValue('republica', parent: 'roma', depth: 1);
    await addValue('gracos', parent: 'republica', depth: 2);
    await addValue('imperio', parent: 'roma', depth: 1);
    await addValue('grecia');
  }

  Future<Map<String, (String?, int)>> tree() async => {
    for (final row in await db.select(db.propertyValues).get())
      row.id: (row.parentId, row.depth),
  };

  Future<String> categoryOfType(PropertyValueType type) async {
    final id = 'cat-${type.name}';
    await db
        .into(db.propertyDefinitions)
        .insert(
          PropertyDefinitionsCompanion.insert(
            id: id,
            name: 'Categoría ${type.name}',
            createdAt: now,
            type: Value(type),
          ),
        );
    return id;
  }

  /// El motivo de un fallo, o `null` si salió bien.
  String? messageOf(Either<Failure, Object?> result) =>
      result.fold((failure) => failure.message, (_) => null);

  group('previewMove', () {
    test(
      'cuenta la rama y dice el nivel en que quedaría, sin cambiar nada',
      () async {
        await seedRoma();
        final before = await tree();

        final preview = (await repository.previewMove(
          valueId: 'republica',
          parentId: 'grecia',
        )).getRight().toNullable()!;

        expect(preview.valueCount, 2);
        expect(preview.newDepth, 1);
        expect(await tree(), before);
      },
    );

    test('«a la raíz» deja la rama en el nivel 0', () async {
      await seedRoma();

      final preview = (await repository.previewMove(
        valueId: 'republica',
        parentId: null,
      )).getRight().toNullable()!;

      expect(preview.newDepth, 0);
      expect(preview.valueCount, 2);
    });
  });

  group('moveValue', () {
    test(
      'pone la rama bajo otro padre y recalcula el nivel de cada uno',
      () async {
        await seedRoma();

        final result = await repository.moveValue(
          valueId: 'republica',
          parentId: 'grecia',
        );

        expect(result.isRight(), isTrue);
        expect(await tree(), {
          'roma': (null, 0),
          'republica': ('grecia', 1),
          'gracos': ('republica', 2),
          'imperio': ('roma', 1),
          'grecia': (null, 0),
        });
        final operation = result.getRight().toNullable()!;
        expect(operation.kind, VocabularyOperationKind.move);
        expect(operation.valueCount, 2);
        expect(operation.label, 'Valor republica');
      },
    );

    test(
      'a la raíz sube toda la rama un nivel por cada padre que pierde',
      () async {
        await seedRoma();

        await repository.moveValue(valueId: 'republica', parentId: null);

        expect(await tree(), containsPair('republica', (null, 0)));
        expect(await tree(), containsPair('gracos', ('republica', 1)));
      },
    );

    test('una raíz con sus hijos baja de nivel al ponerla bajo otra', () async {
      await seedRoma();

      await repository.moveValue(valueId: 'roma', parentId: 'grecia');

      expect(await tree(), {
        'roma': ('grecia', 1),
        'republica': ('roma', 2),
        'gracos': ('republica', 3),
        'imperio': ('roma', 2),
        'grecia': (null, 0),
      });
    });

    test('mover un valor no cambia a qué elementos está asignado', () async {
      await seedRoma();
      await addValue('otro', items: ['e1', 'e2']);

      await repository.moveValue(valueId: 'otro', parentId: 'grecia');

      final rows = await db.select(db.itemPropertyValues).get();
      expect(
        {for (final r in rows) (r.itemId, r.propertyValueId)},
        {('e1', 'otro'), ('e2', 'otro')},
      );
    });

    group('se niega, sin tocar nada, si', () {
      Future<void> expectRejected(
        Future<Either<Failure, Object?>> Function() attempt,
        String reason,
      ) async {
        final before = await tree();
        final result = await attempt();
        expect(messageOf(result), contains(reason));
        expect(await tree(), before);
      }

      test('el padre es un descendiente suyo', () async {
        await seedRoma();

        await expectRejected(
          () => repository.moveValue(valueId: 'roma', parentId: 'gracos'),
          'sí mismo',
        );
      });

      test('el padre es él mismo', () async {
        await seedRoma();

        await expectRejected(
          () => repository.moveValue(valueId: 'roma', parentId: 'roma'),
          'sí mismo',
        );
      });

      test('el padre es de otra categoría', () async {
        await seedRoma();
        final other = await categoryOfType(PropertyValueType.text);
        await addValue('ajeno', definitionId: other);

        await expectRejected(
          () => repository.moveValue(valueId: 'grecia', parentId: 'ajeno'),
          'misma categoría',
        );
      });

      test('la categoría no es de texto', () async {
        final date = await categoryOfType(PropertyValueType.date);
        await addValue('a', definitionId: date);
        await addValue('b', definitionId: date);

        await expectRejected(
          () => repository.moveValue(valueId: 'b', parentId: 'a'),
          'de texto',
        );
      });

      test('la rama pasaría de cinco niveles', () async {
        await addValue('a');
        await addValue('b', parent: 'a', depth: 1);
        await addValue('c', parent: 'b', depth: 2);
        await addValue('d', parent: 'c', depth: 3);
        await addValue('e', parent: 'd', depth: 4);
        await addValue('roma');
        await addValue('republica', parent: 'roma', depth: 1);

        await expectRejected(
          () => repository.moveValue(valueId: 'roma', parentId: 'e'),
          'cinco niveles',
        );
      });

      test('ya está en ese lugar', () async {
        await seedRoma();

        await expectRejected(
          () => repository.moveValue(valueId: 'republica', parentId: 'roma'),
          'ya está',
        );
      });

      test('el valor ya no existe', () async {
        await seedRoma();

        final result = await repository.moveValue(
          valueId: 'fantasma',
          parentId: 'roma',
        );

        expect(result.isLeft(), isTrue);
      });

      test('el destino ya no existe', () async {
        await seedRoma();

        final result = await repository.moveValue(
          valueId: 'grecia',
          parentId: 'fantasma',
        );

        expect(result.isLeft(), isTrue);
        expect((await tree())['grecia'], (null, 0));
      });
    });

    group('deshacer', () {
      test('devuelve la rama a donde estaba, con sus niveles', () async {
        await seedRoma();
        final before = await tree();
        final operation = (await repository.moveValue(
          valueId: 'republica',
          parentId: 'grecia',
        )).getRight().toNullable()!;

        final undone = await repository.undo(operation);

        expect(undone.isRight(), isTrue);
        expect(await tree(), before);
      });

      test('se niega si el valor se movió otra vez', () async {
        await seedRoma();
        final operation = (await repository.moveValue(
          valueId: 'republica',
          parentId: 'grecia',
        )).getRight().toNullable()!;
        await repository.moveValue(valueId: 'republica', parentId: 'imperio');
        final moved = await tree();

        final undone = await repository.undo(operation);

        expect(undone.isLeft(), isTrue);
        expect(await tree(), moved);
      });

      test('se niega si el valor ya no existe', () async {
        await seedRoma();
        final operation = (await repository.moveValue(
          valueId: 'grecia',
          parentId: 'roma',
        )).getRight().toNullable()!;
        await db.customStatement(
          "DELETE FROM property_values WHERE id = 'grecia'",
        );

        final undone = await repository.undo(operation);

        expect(undone.isLeft(), isTrue);
      });
    });
  });

  group('la fusión respeta la jerarquía', () {
    test(
      'los hijos del descartado pasan al que se conserva, con su nivel',
      () async {
        await seedRoma();
        await addValue('roma-2');

        final result = await repository.mergeValues(
          keepId: 'roma-2',
          discardIds: ['roma'],
        );

        expect(result.isRight(), isTrue);
        expect(await tree(), {
          'roma-2': (null, 0),
          'republica': ('roma-2', 1),
          'gracos': ('republica', 2),
          'imperio': ('roma-2', 1),
          'grecia': (null, 0),
        });
      },
    );

    test(
      'si el que se conserva es un ancestro, los hijos suben a él',
      () async {
        await seedRoma();

        // «imperio» absorbe a «republica»: los dos son hijos de «roma».
        await repository.mergeValues(
          keepId: 'imperio',
          discardIds: ['republica'],
        );

        expect(await tree(), {
          'roma': (null, 0),
          'gracos': ('imperio', 2),
          'imperio': ('roma', 1),
          'grecia': (null, 0),
        });
      },
    );

    test('si el que se conserva estaba DENTRO de la rama descartada, toma su '
        'lugar y no se forma un ciclo', () async {
      await seedRoma();

      // «republica» —hijo de «roma»— absorbe a su propio padre.
      final result = await repository.mergeValues(
        keepId: 'republica',
        discardIds: ['roma'],
      );

      expect(result.isRight(), isTrue);
      expect(await tree(), {
        'republica': (null, 0),
        'gracos': ('republica', 1),
        'imperio': ('republica', 1),
        'grecia': (null, 0),
      });
    });

    test('lo mismo con un descendiente más lejano', () async {
      await seedRoma();

      // «gracos» absorbe a «roma», su abuelo.
      final result = await repository.mergeValues(
        keepId: 'gracos',
        discardIds: ['roma'],
      );

      expect(result.isRight(), isTrue);
      expect(await tree(), {
        'gracos': (null, 0),
        'republica': ('gracos', 1),
        'imperio': ('gracos', 1),
        'grecia': (null, 0),
      });
    });

    test(
      'deshacer devuelve el árbol entero, también el caso del ciclo',
      () async {
        await seedRoma();
        final before = await tree();
        final operation = (await repository.mergeValues(
          keepId: 'republica',
          discardIds: ['roma'],
        )).getRight().toNullable()!;

        final undone = await repository.undo(operation);

        expect(undone.isRight(), isTrue);
        expect(await tree(), before);
      },
    );

    test('deshacer devuelve al hijo a su padre original', () async {
      await seedRoma();
      await addValue('roma-2');
      final before = await tree();
      final operation = (await repository.mergeValues(
        keepId: 'roma-2',
        discardIds: ['roma'],
      )).getRight().toNullable()!;

      await repository.undo(operation);

      expect(await tree(), before);
    });

    test(
      'fusionar valores sin hijos no toca la jerarquía de los demás',
      () async {
        await seedRoma();
        await addValue('imperio-2');
        final before = await tree();

        await repository.mergeValues(
          keepId: 'imperio',
          discardIds: ['imperio-2'],
        );

        expect(await tree(), {...before}..remove('imperio-2'));
      },
    );
  });

  group('borrar sin uso respeta la jerarquía', () {
    test('no borra un padre con subtemas que no se borran con él', () async {
      await seedRoma();
      final before = await tree();

      final result = await repository.deleteUnusedValues(['roma']);

      expect(messageOf(result), contains('subtemas'));
      expect(await tree(), before);
    });

    test('borra una hoja sin uso', () async {
      await seedRoma();

      final result = await repository.deleteUnusedValues(['gracos']);

      expect(result.isRight(), isTrue);
      expect((await tree()).containsKey('gracos'), isFalse);
    });

    test('borra un padre junto con todos sus subtemas', () async {
      await seedRoma();

      final result = await repository.deleteUnusedValues([
        'roma',
        'republica',
        'gracos',
        'imperio',
      ]);

      expect(result.isRight(), isTrue);
      expect(await tree(), {'grecia': (null, 0)});
    });

    test('deshacer vuelve a crear la rama de arriba hacia abajo', () async {
      await seedRoma();
      final before = await tree();
      final operation = (await repository.deleteUnusedValues([
        'gracos',
        'imperio',
        'republica',
        'roma',
      ])).getRight().toNullable()!;

      final undone = await repository.undo(operation);

      expect(undone.isRight(), isTrue);
      expect(await tree(), before);
    });

    test(
      'deshacer se niega si el padre de una hoja borrada ya no existe',
      () async {
        await seedRoma();
        final operation = (await repository.deleteUnusedValues([
          'gracos',
        ])).getRight().toNullable()!;
        await db.customStatement(
          "DELETE FROM property_values WHERE id = 'republica'",
        );

        final undone = await repository.undo(operation);

        expect(undone.isLeft(), isTrue);
        expect((await tree()).containsKey('gracos'), isFalse);
      },
    );
  });

  group('las estadísticas', () {
    test('cada valor trae su padre y su nivel', () async {
      await seedRoma();

      final stats = await repository.watchValueStats().first;
      final byId = {for (final s in stats) s.id: s};

      expect(byId['gracos']!.parentId, 'republica');
      expect(byId['gracos']!.depth, 2);
      expect(byId['roma']!.parentId, isNull);
      expect(byId['roma']!.depth, 0);
    });
  });
}
