import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vocabulary_lookup.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vocabulary/data/repositories/vocabulary_repository_impl.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_operation.dart';

import '../../../../support/fake_id_generator.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Falla al pedir el identificador número [failAfter] + 1: sirve para probar
/// que un lote que se rompe a la mitad no deja NADA aplicado.
class _FailingIds implements IdGenerator {
  _FailingIds({required this.failAfter});

  final int failAfter;
  var _calls = 0;

  @override
  String next() {
    if (_calls >= failAfter) throw StateError('ids agotados');
    return 'gen-${_calls++}';
  }
}

class _ForeignOperation implements VocabularyOperation {
  @override
  VocabularyOperationKind get kind => VocabularyOperationKind.merge;
  @override
  int get valueCount => 1;
  @override
  String get label => 'ajena';
  @override
  int get affectedItems => 0;
}

/// El mantenimiento del vocabulario, contra SQLite real en memoria.
void main() {
  late AppDatabase db;
  late VocabularyRepositoryImpl repository;

  final now = DateTime(2026, 9, 19, 10);

  VocabularyRepositoryImpl buildRepository(IdGenerator ids) =>
      VocabularyRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        ids: ids,
        clock: () => now,
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = buildRepository(FakeIdGenerator(prefix: 'gen'));
  });

  tearDown(() => db.close());

  Future<void> seedItem(String id) async {
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'src-$id',
            kind: SourceKind.webPage,
            capturedAt: now,
          ),
        );
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            title: 'Elemento $id',
            sourceId: 'src-$id',
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<String> temaId() async => (await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.equals('Tema'))).getSingle()).id;

  Future<void> addValue(
    String id,
    String label, {
    List<String> items = const [],
    String? definitionId,
  }) async {
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: definitionId ?? await temaId(),
            value: label,
            createdAt: now,
          ),
        );
    for (final itemId in items) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: itemId,
              propertyValueId: id,
            ),
          );
    }
  }

  Future<void> addAlias(String id, String valueId, String alias) async {
    await db
        .into(db.propertyAliases)
        .insert(
          PropertyAliasesCompanion.insert(
            id: id,
            propertyValueId: valueId,
            definitionId: await temaId(),
            alias: alias,
            createdAt: now,
          ),
        );
  }

  Future<List<String>> snapshot() async => [
    for (final r in await db.select(db.propertyValues).get())
      'valor ${r.id}|${r.definitionId}|${r.value}',
    for (final r in await db.select(db.itemPropertyValues).get())
      'asignación ${r.itemId}|${r.propertyValueId}|${r.origin.name}',
    for (final r in await db.select(db.propertyAliases).get())
      'alias ${r.id}|${r.propertyValueId}|${r.alias}',
  ]..sort();

  Future<Set<String>> itemsOf(String valueId) async =>
      (await (db.select(
            db.itemPropertyValues,
          )..where((a) => a.propertyValueId.equals(valueId))).get())
          .map((a) => a.itemId)
          .toSet();

  /// La operación de un resultado que se espera exitoso.
  VocabularyOperation opOf(Either<Failure, VocabularyOperation> result) =>
      result.getRight().toNullable()!;

  Future<void> seedRomas() async {
    for (final id in ['i1', 'i2', 'i3', 'i4']) {
      await seedItem(id);
    }
    await addValue('roma', 'Roma', items: ['i1']);
    await addValue('roma-acento', 'Róma', items: ['i2', 'i3']);
    await addValue('rome', 'Rome', items: ['i3']);
    await addValue('roma-antigua', 'Roma antigua', items: ['i4']);
  }

  group('fusionar', () {
    test('varios valores se fusionan en uno solo, en una operación', () async {
      await seedRomas();

      final result = await repository.mergeValues(
        keepId: 'roma',
        discardIds: ['roma-acento', 'rome', 'roma-antigua'],
      );

      final op = result.getRight().toNullable()!;
      expect(op.kind, VocabularyOperationKind.merge);
      expect(op.valueCount, 3);
      expect(op.label, 'Roma');
      // i3 tenía dos de los descartados: cuenta una sola vez.
      expect(op.affectedItems, 3);
      expect(await itemsOf('roma'), {'i1', 'i2', 'i3', 'i4'});
      final values = await db.select(db.propertyValues).get();
      expect(values.map((v) => v.id), ['roma']);
      final aliases = await db.select(db.propertyAliases).get();
      expect(aliases.map((a) => a.alias).toSet(), {
        'Róma',
        'Rome',
        'Roma antigua',
      });
    });

    test(
      'deshacer devuelve todo el lote, dejando la base como estaba',
      () async {
        await seedRomas();
        final before = await snapshot();
        final op = opOf(
          await repository.mergeValues(
            keepId: 'roma',
            discardIds: ['roma-acento', 'rome', 'roma-antigua'],
          ),
        );
        expect(await snapshot(), isNot(before));

        final undone = await repository.undo(op);

        expect(undone.isRight(), isTrue);
        expect(await snapshot(), before);
      },
    );

    test('es atómico: si una fusión del lote falla, no queda ninguna '
        'aplicada', () async {
      await seedRomas();
      // Alcanza para el alias de la primera fusión y no para el de la segunda.
      repository = buildRepository(_FailingIds(failAfter: 1));
      final before = await snapshot();

      final result = await repository.mergeValues(
        keepId: 'roma',
        discardIds: ['roma-acento', 'rome'],
      );

      expect(result.isLeft(), isTrue);
      expect(await snapshot(), before);
    });

    test('sin nada que fusionar se rechaza', () async {
      await seedRomas();

      final result = await repository.mergeValues(
        keepId: 'roma',
        discardIds: const [],
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('un valor no se fusiona consigo mismo', () async {
      await seedRomas();
      final before = await snapshot();

      final result = await repository.mergeValues(
        keepId: 'roma',
        discardIds: ['roma'],
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await snapshot(), before);
    });

    test('no se fusionan valores de categorías distintas, ni se aplica '
        'ninguno del lote', () async {
      await seedRomas();
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'def-region',
              name: 'Región',
              createdAt: now,
              type: const Value(PropertyValueType.text),
            ),
          );
      await addValue('region-roma', 'Roma', definitionId: 'def-region');
      final before = await snapshot();

      final result = await repository.mergeValues(
        keepId: 'roma',
        discardIds: ['rome', 'region-roma'],
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await snapshot(), before);
    });

    test('un valor que ya no existe devuelve un fallo, no revienta', () async {
      await seedRomas();

      final result = await repository.mergeValues(
        keepId: 'roma',
        discardIds: ['no-existe'],
      );

      expect(result.isLeft(), isTrue);
    });

    test('la previsualización cuenta los elementos distintos y no cambia '
        'nada', () async {
      await seedRomas();
      final before = await snapshot();

      final result = await repository.previewMerge(
        keepId: 'roma',
        discardIds: ['roma-acento', 'rome'],
      );

      final preview = result.getRight().toNullable()!;
      expect(preview.valueCount, 2);
      // roma-acento: i2, i3. rome: i3. Distintos: i2 e i3.
      expect(preview.affectedItems, 2);
      expect(await snapshot(), before);
    });
  });

  group('renombrar', () {
    test('cambia el nombre y se puede deshacer', () async {
      await seedRomas();

      final op = opOf(
        await repository.renameValue(id: 'roma-acento', label: 'Roma latina'),
      );

      expect(op.kind, VocabularyOperationKind.rename);
      expect(op.label, 'Roma latina');
      expect(op.affectedItems, 2);
      expect(
        (await (db.select(
          db.propertyValues,
        )..where((v) => v.id.equals('roma-acento'))).getSingle()).value,
        'Roma latina',
      );

      await repository.undo(op);

      expect(
        (await (db.select(
          db.propertyValues,
        )..where((v) => v.id.equals('roma-acento'))).getSingle()).value,
        'Róma',
      );
    });

    test('no puede chocar con otro valor, sin distinguir acentos', () async {
      await seedRomas();

      final result = await repository.renameValue(id: 'rome', label: 'ROMA');

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('no puede chocar con un alias de la categoría', () async {
      await seedRomas();
      await addAlias('a1', 'roma', 'Urbe');

      final result = await repository.renameValue(id: 'rome', label: 'urbe');

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('corregirle el acento o las mayúsculas a su propio nombre sí se '
        'permite', () async {
      // Solo en su categoría: sin un casi-duplicado que sí chocaría.
      await addValue('solo', 'Rome');

      // Solo las mayúsculas, y solo el acento: el valor no choca consigo
      // mismo aunque, normalizado, el nombre nuevo sea el suyo de siempre.
      final upper = await repository.renameValue(id: 'solo', label: 'ROME');
      expect(upper.isRight(), isTrue);

      final accent = await repository.renameValue(id: 'solo', label: 'Rómé');
      expect(accent.isRight(), isTrue);
    });

    test(
      'renombrar uno para que quede como un casi-duplicado se rechaza',
      () async {
        await seedRomas();

        // "Roma" y "Róma" ya conviven en la base; renombrar un tercero a
        // cualquiera de los dos los volvería tres.
        final result = await repository.renameValue(id: 'rome', label: 'ROMA');

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      },
    );

    test(
      'un nombre en blanco se rechaza y uno que ya no existe falla',
      () async {
        await seedRomas();

        expect(
          (await repository.renameValue(
            id: 'roma',
            label: '  ',
          )).getLeft().toNullable(),
          isA<ValidationFailure>(),
        );
        expect(
          (await repository.renameValue(id: 'no-existe', label: 'X')).isLeft(),
          isTrue,
        );
      },
    );

    test('deshacer vuelve a un nombre que era casi-duplicado de otro valor: '
        'ese estado ya existía', () async {
      await seedRomas(); // "Roma" y "Róma" conviven desde antes.
      final op = opOf(
        await repository.renameValue(id: 'roma-acento', label: 'Roma latina'),
      );

      final undone = await repository.undo(op);

      expect(undone.isRight(), isTrue);
    });

    test('deshacer se niega si el valor volvió a cambiar de nombre', () async {
      await seedRomas();
      final op = opOf(
        await repository.renameValue(id: 'rome', label: 'Roma B'),
      );
      await repository.renameValue(id: 'rome', label: 'Roma C');

      final undone = await repository.undo(op);

      expect(undone.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('deshacer se niega si el nombre viejo ya lo usa otro valor', () async {
      await seedRomas();
      final op = opOf(
        await repository.renameValue(id: 'rome', label: 'Roma B'),
      );
      await addValue('nuevo', 'Rome');

      final undone = await repository.undo(op);

      expect(undone.getLeft().toNullable(), isA<ValidationFailure>());
    });
  });

  group('borrar sin uso', () {
    test(
      'borra varios en una operación, con sus alias, y se puede deshacer',
      () async {
        await seedItem('i1');
        await addValue('usado', 'Usado', items: ['i1']);
        await addValue('sobra-a', 'Sobra A');
        await addValue('sobra-b', 'Sobra B');
        await addAlias('a1', 'sobra-a', 'Alias de A');
        final before = await snapshot();

        final op = opOf(
          await repository.deleteUnusedValues(['sobra-a', 'sobra-b']),
        );

        expect(op.kind, VocabularyOperationKind.delete);
        expect(op.valueCount, 2);
        expect(op.affectedItems, 0);
        expect((await db.select(db.propertyValues).get()).map((v) => v.id), [
          'usado',
        ]);
        expect(await db.select(db.propertyAliases).get(), isEmpty);

        await repository.undo(op);

        expect(await snapshot(), before);
      },
    );

    test(
      'un valor en uso rechaza el lote ENTERO, sin borrar ninguno',
      () async {
        await seedItem('i1');
        await addValue('usado', 'Usado', items: ['i1']);
        await addValue('sobra', 'Sobra');
        final before = await snapshot();

        final result = await repository.deleteUnusedValues(['sobra', 'usado']);

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        expect(await snapshot(), before);
      },
    );

    test('un valor que ya no existe rechaza el lote', () async {
      await addValue('sobra', 'Sobra');
      final before = await snapshot();

      final result = await repository.deleteUnusedValues(['sobra', 'fantasma']);

      expect(result.isLeft(), isTrue);
      expect(await snapshot(), before);
    });

    test('sin ningún valor se rechaza', () async {
      final result = await repository.deleteUnusedValues(const []);

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test(
      'deshacer se niega si un valor con ese nombre se creó después',
      () async {
        await addValue('sobra', 'Sobra');
        final op = opOf(await repository.deleteUnusedValues(['sobra']));
        await addValue('otro', 'sobra');

        final undone = await repository.undo(op);

        expect(undone.getLeft().toNullable(), isA<ValidationFailure>());
      },
    );
  });

  group('alias', () {
    test('un alias nuevo se resuelve al valor, y se puede deshacer', () async {
      await seedRomas();

      final op = opOf(
        await repository.addAlias(valueId: 'roma', alias: 'Urbe eterna'),
      );

      expect(op.kind, VocabularyOperationKind.addAlias);
      final resolved = await findValueByLabelOrAlias(
        db,
        await temaId(),
        'urbe eterna',
      );
      expect(resolved?.id, 'roma');

      await repository.undo(op);

      expect(
        await findValueByLabelOrAlias(db, await temaId(), 'urbe eterna'),
        isNull,
      );
    });

    test('no puede repetir el nombre de un valor, ni el propio', () async {
      await seedRomas();

      final otro = await repository.addAlias(valueId: 'roma', alias: 'rome');
      final propio = await repository.addAlias(valueId: 'roma', alias: 'ROMA');

      expect(otro.getLeft().toNullable(), isA<ValidationFailure>());
      expect(propio.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('no puede repetir otro alias, sin distinguir acentos', () async {
      await seedRomas();
      await addAlias('a1', 'rome', 'Constantinopla');

      final result = await repository.addAlias(
        valueId: 'roma',
        alias: 'constantínopla',
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('un alias vacío se rechaza y un valor que no existe falla', () async {
      await seedRomas();

      expect(
        (await repository.addAlias(
          valueId: 'roma',
          alias: ' ',
        )).getLeft().toNullable(),
        isA<ValidationFailure>(),
      );
      expect(
        (await repository.addAlias(valueId: 'no-existe', alias: 'X')).isLeft(),
        isTrue,
      );
    });

    test('quitar un alias lo borra, y deshacer lo vuelve a poner', () async {
      await seedRomas();
      await addAlias('a1', 'roma', 'Urbe');
      final before = await snapshot();

      final op = opOf(await repository.removeAlias('a1'));

      expect(op.kind, VocabularyOperationKind.removeAlias);
      expect(await db.select(db.propertyAliases).get(), isEmpty);

      await repository.undo(op);

      expect(await snapshot(), before);
    });

    test('quitar un alias que ya no existe falla', () async {
      final result = await repository.removeAlias('fantasma');

      expect(result.isLeft(), isTrue);
    });

    test(
      'deshacer quitar un alias se niega si otro ya usa ese texto',
      () async {
        await seedRomas();
        await addAlias('a1', 'roma', 'Urbe');
        final op = opOf(await repository.removeAlias('a1'));
        await addAlias('a2', 'rome', 'Urbe');

        final undone = await repository.undo(op);

        expect(undone.getLeft().toNullable(), isA<ValidationFailure>());
      },
    );
  });

  group('borrar categorías vacías', () {
    Future<void> addCategory(String id, String name) => db
        .into(db.propertyDefinitions)
        .insert(
          PropertyDefinitionsCompanion.insert(
            id: id,
            name: name,
            createdAt: now,
            type: const Value(PropertyValueType.text),
          ),
        );

    Future<List<String>> categoryNames() async =>
        (await db.select(db.propertyDefinitions).get())
            .map((d) => d.name)
            .toList()
          ..sort();

    test('borra varias en una operación y se puede deshacer', () async {
      await addCategory('c1', 'Vacía uno');
      await addCategory('c2', 'Vacía dos');
      final before = await categoryNames();

      final op = opOf(await repository.deleteEmptyCategories(['c1', 'c2']));

      expect(op.kind, VocabularyOperationKind.deleteCategory);
      expect(op.valueCount, 2);
      expect(await categoryNames(), ['Fecha del hecho', 'Tema']);

      final undone = await repository.undo(op);

      expect(undone.isRight(), isTrue);
      expect(await categoryNames(), before);
    });

    test('una de sistema se rechaza, y no se borra ninguna del lote', () async {
      await addCategory('c1', 'Vacía');
      final tema = await temaId();
      final before = await categoryNames();

      final result = await repository.deleteEmptyCategories(['c1', tema]);

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await categoryNames(), before);
    });

    test(
      'una que todavía tiene valores se rechaza, y no se borra ninguna',
      () async {
        await addCategory('c1', 'Vacía');
        await addCategory('c2', 'Con valores');
        await addValue('v1', 'Algo', definitionId: 'c2');
        final before = await categoryNames();

        final result = await repository.deleteEmptyCategories(['c1', 'c2']);

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        expect(await categoryNames(), before);
      },
    );

    test(
      'una que ya no existe rechaza el lote, y sin ninguna se rechaza',
      () async {
        await addCategory('c1', 'Vacía');
        final before = await categoryNames();

        expect(
          (await repository.deleteEmptyCategories(['c1', 'fantasma'])).isLeft(),
          isTrue,
        );
        expect(await categoryNames(), before);
        expect(
          (await repository.deleteEmptyCategories(
            const [],
          )).getLeft().toNullable(),
          isA<ValidationFailure>(),
        );
      },
    );

    test(
      'deshacer se niega si ya existe una categoría con ese nombre',
      () async {
        await addCategory('c1', 'Vacía');
        final op = opOf(await repository.deleteEmptyCategories(['c1']));
        await addCategory('c2', 'vacía');

        final undone = await repository.undo(op);

        expect(undone.getLeft().toNullable(), isA<ValidationFailure>());
      },
    );
  });

  group('estadísticas', () {
    test(
      'cada valor con en cuántos elementos está y cuántos alias tiene',
      () async {
        await seedRomas();
        await addAlias('a1', 'roma', 'Urbe');
        await addAlias('a2', 'roma', 'Ciudad eterna');

        final stats = await repository.watchValueStats().first;

        final roma = stats.firstWhere((s) => s.id == 'roma');
        expect(roma.usage, 1);
        expect(roma.aliasCount, 2);
        expect(roma.label, 'Roma');
        expect(roma.definitionName, 'Tema');
        final acento = stats.firstWhere((s) => s.id == 'roma-acento');
        expect(acento.usage, 2);
        expect(acento.aliasCount, 0);
      },
    );

    test('un valor sin ningún elemento cuenta cero, no falta', () async {
      await addValue('sobra', 'Sobra');

      final stats = await repository.watchValueStats().first;

      expect(stats.single.usage, 0);
    });

    test('ordenados por categoría y luego por nombre', () async {
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'def-epoca',
              name: 'Época',
              createdAt: now,
              type: const Value(PropertyValueType.text),
            ),
          );
      await addValue('t2', 'Zeta');
      await addValue('t1', 'Alfa');
      await addValue('e1', 'Medieval', definitionId: 'def-epoca');

      final stats = await repository.watchValueStats().first;

      expect(stats.map((s) => s.id), ['e1', 't1', 't2']);
    });

    test('marca las categorías que no son de texto', () async {
      final fecha = (await (db.select(
        db.propertyDefinitions,
      )..where((d) => d.name.equals('Fecha del hecho'))).getSingle()).id;
      await addValue('f1', '44 a.C.', definitionId: fecha);
      await addValue('t1', 'Roma');

      final stats = await repository.watchValueStats().first;

      expect(stats.firstWhere((s) => s.id == 'f1').isText, isFalse);
      expect(stats.firstWhere((s) => s.id == 't1').isText, isTrue);
    });

    test('las categorías con cuántos valores tienen, y cuáles quedaron '
        'huérfanas', () async {
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'def-vacia',
              name: 'Vacía',
              createdAt: now,
              type: const Value(PropertyValueType.text),
            ),
          );
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'def-epoca',
              name: 'Época',
              createdAt: now,
              type: const Value(PropertyValueType.text),
            ),
          );
      await addValue('e1', 'Medieval', definitionId: 'def-epoca');

      final stats = await repository.watchCategoryStats().first;

      final byName = {for (final c in stats) c.name: c};
      expect(byName['Época']!.valueCount, 1);
      expect(byName['Época']!.isOrphan, isFalse);
      expect(byName['Vacía']!.valueCount, 0);
      expect(byName['Vacía']!.isOrphan, isTrue);
      // Las de sistema están vacías y no se consideran huérfanas: no se
      // pueden borrar, y "Tema" vacía es lo normal en una bóveda nueva.
      expect(byName['Tema']!.isSystem, isTrue);
      expect(byName['Tema']!.isOrphan, isFalse);
      expect(byName['Fecha del hecho']!.isOrphan, isFalse);
      // Alfabéticas sin distinguir mayúsculas ni acentos: "Época" va antes
      // que "Tema", no después de la z.
      final names = stats.map((c) => c.name).toList();
      expect(names.indexOf('Época'), lessThan(names.indexOf('Tema')));
    });

    test('se actualizan solas cuando el vocabulario cambia', () async {
      final appears = repository.watchValueStats().firstWhere(
        (stats) => stats.any((s) => s.id == 'nuevo'),
      );

      await addValue('nuevo', 'Nuevo');

      expect((await appears.timeout(const Duration(seconds: 5))).length, 1);
    });
  });

  test(
    'una operación que no viene de este repositorio no se deshace',
    () async {
      final result = await repository.undo(_ForeignOperation());

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    },
  );
}
