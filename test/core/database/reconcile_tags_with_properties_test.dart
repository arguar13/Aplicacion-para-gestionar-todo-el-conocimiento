import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/migrate_tags_to_property_values_v9.dart';
import 'package:sinapsis/core/database/migrations/reconcile_tags_with_properties_v14.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/util/id_generator.dart';

import '../../support/fake_id_generator.dart';
import '../../support/silent_logger.dart';

class _RecordingLogger extends SilentLogger {
  _RecordingLogger();

  final infos = <String>[];

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) =>
      infos.add(message);
}

/// La reconciliación de etiquetas con propiedades (F8): tras F2, las
/// etiquetas nuevas vivían solo en `Tags`/`ItemTags` y los valores de Tema
/// quedaron atrás. Probada contra SQLite real, con bóvedas armadas a mano en
/// el estado en que las deja la app de antes de F8.
void main() {
  late AppDatabase db;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 19, 10);
  final jan1 = DateTime(2026);
  final jan2 = DateTime(2026, 1, 2);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator(prefix: 'gen');
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

  /// Una etiqueta como la deja la app de antes de F8: solo en `Tags` y
  /// `ItemTags`.
  Future<void> addTag(
    String id,
    String name, {
    DateTime? createdAt,
    List<String> items = const [],
  }) async {
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(id: id, name: name, createdAt: createdAt ?? now),
        );
    for (final itemId in items) {
      await db
          .into(db.itemTags)
          .insert(ItemTagsCompanion.insert(itemId: itemId, tagId: id));
    }
  }

  Future<void> addValue(
    String id,
    String label, {
    String? definitionId,
    DateTime? createdAt,
    List<String> items = const [],
    ItemPropertyOrigin origin = ItemPropertyOrigin.manual,
  }) async {
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: definitionId ?? await temaId(),
            value: label,
            createdAt: createdAt ?? now,
          ),
        );
    for (final itemId in items) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: itemId,
              propertyValueId: id,
              origin: Value(origin),
            ),
          );
    }
  }

  Future<void> addAlias(String valueId, String alias) async {
    await db
        .into(db.propertyAliases)
        .insert(
          PropertyAliasesCompanion.insert(
            id: 'alias-$valueId-$alias',
            propertyValueId: valueId,
            definitionId: await temaId(),
            alias: alias,
            createdAt: now,
          ),
        );
  }

  /// Aplica un plan como lo hace la migración: dentro de una transacción.
  Future<void> apply(TagReconciliationPlan plan) => db.transaction(
    () => applyTagReconciliation(db, plan, ids: ids, clock: () => now),
  );

  Future<List<PropertyValueRow>> temaValues() async {
    final tema = await temaId();
    return (db.select(db.propertyValues)
          ..where((v) => v.definitionId.equals(tema))
          ..orderBy([(v) => OrderingTerm(expression: v.value)]))
        .get();
  }

  Future<Set<String>> itemsOf(String valueId) async =>
      (await (db.select(
            db.itemPropertyValues,
          )..where((a) => a.propertyValueId.equals(valueId))).get())
          .map((a) => a.itemId)
          .toSet();

  Future<Set<String>> aliasesOf(String valueId) async =>
      (await (db.select(
            db.propertyAliases,
          )..where((a) => a.propertyValueId.equals(valueId))).get())
          .map((a) => a.alias)
          .toSet();

  /// Cada (elemento, texto normalizado) que tiene puesto algún valor de Tema.
  Future<Set<(String, String)>> temaPairs() async {
    final rows = await (db.select(db.itemPropertyValues).join([
      innerJoin(
        db.propertyValues,
        db.propertyValues.id.equalsExp(db.itemPropertyValues.propertyValueId),
      ),
    ])..where(db.propertyValues.definitionId.equals(await temaId()))).get();
    return {
      for (final row in rows)
        (
          row.readTable(db.itemPropertyValues).itemId,
          normalizeVocabularyLabel(row.readTable(db.propertyValues).value),
        ),
    };
  }

  /// Cada (elemento, texto normalizado) que tiene puesta alguna etiqueta.
  Future<Set<(String, String)>> tagPairs() async {
    final rows = await db.select(db.itemTags).join([
      innerJoin(db.tags, db.tags.id.equalsExp(db.itemTags.tagId)),
    ]).get();
    return {
      for (final row in rows)
        (
          row.readTable(db.itemTags).itemId,
          normalizeVocabularyLabel(row.readTable(db.tags).name),
        ),
    };
  }

  /// Lo que la reconciliación podría tocar, en una lista comparable.
  Future<List<String>> snapshot() async => [
    for (final r in await db.select(db.propertyValues).get())
      'valor ${r.id}|${r.definitionId}|${r.value}|${r.createdAt}',
    for (final r in await db.select(db.itemPropertyValues).get())
      'asignación ${r.itemId}|${r.propertyValueId}|${r.origin.name}',
    for (final r in await db.select(db.propertyAliases).get())
      'alias ${r.id}|${r.propertyValueId}|${r.alias}',
    for (final r in await db.select(db.tags).get())
      'etiqueta ${r.id}|${r.name}',
    for (final r in await db.select(db.itemTags).get())
      'itemTag ${r.itemId}|${r.tagId}',
    for (final r in await db.select(db.migrationIssues).get())
      'informe ${r.stage}|${r.itemId}',
  ]..sort();

  group('planTagReconciliation', () {
    test('una etiqueta sin valor equivalente se crea bajo Tema, con su mismo '
        'id, y pasa sus asignaciones', () async {
      await seedItem('i1');
      await seedItem('i2');
      await addTag('t1', 'Filosofía', createdAt: jan1, items: ['i1', 'i2']);

      final plan = await planTagReconciliation(db);

      expect(plan.hasChanges, isTrue);
      expect(plan.orphanTags, 1);
      expect(plan.assignmentsToAdd, 2);
      expect(plan.groups.single.createsValue, isTrue);

      await apply(plan);

      final value = (await temaValues()).single;
      expect(value.id, 't1');
      expect(value.value, 'Filosofía');
      expect(value.createdAt, jan1);
      expect(await itemsOf('t1'), {'i1', 'i2'});
      expect(await aliasesOf('t1'), isEmpty);
    });

    test('las asignaciones nuevas quedan como manuales', () async {
      await seedItem('i1');
      await addTag('t1', 'Roma', items: ['i1']);

      await apply(await planTagReconciliation(db));

      final assignment = await db.select(db.itemPropertyValues).getSingle();
      expect(assignment.origin, ItemPropertyOrigin.manual);
    });

    test('una etiqueta que F2 ya migró (mismo texto) no genera ningún '
        'cambio', () async {
      await seedItem('i1');
      await addValue('v1', 'Filosofía', items: ['i1']);
      await addTag('t1', 'Filosofía', items: ['i1']);

      final plan = await planTagReconciliation(db);

      expect(plan.hasChanges, isFalse);
      expect(plan.temaValuesWithoutTag, 0);
    });

    test('una etiqueta que solo difiere en mayúsculas del valor tampoco '
        'cambia nada, ni siquiera un alias', () async {
      await seedItem('i1');
      await addValue('v1', 'Filosofía', items: ['i1']);
      await addTag('t1', 'filosofía', items: ['i1']);

      final plan = await planTagReconciliation(db);

      expect(plan.hasChanges, isFalse);
    });

    test('una etiqueta que difiere en el acento se une al valor existente y '
        'su texto queda como alias', () async {
      await seedItem('i1');
      await seedItem('i2');
      await addValue('v1', 'Cancion', items: ['i1']);
      await addTag('t1', 'Canción', items: ['i1', 'i2']);

      final plan = await planTagReconciliation(db);
      expect(plan.orphanTags, 0);
      expect(plan.assignmentsToAdd, 1);
      expect(plan.aliasesToAdd, 1);

      await apply(plan);

      expect((await temaValues()).map((v) => v.id), ['v1']);
      expect(await itemsOf('v1'), {'i1', 'i2'});
      expect(await aliasesOf('v1'), {'Canción'});
    });

    test('dos etiquetas que solo difieren en el acento se unen: gana la más '
        'usada y la otra queda como alias', () async {
      await seedItem('i1');
      await seedItem('i2');
      await seedItem('i3');
      await addTag('t-roma', 'Roma', createdAt: jan1, items: ['i1']);
      await addTag(
        't-roma-acento',
        'Róma',
        createdAt: jan2,
        items: ['i2', 'i3'],
      );

      await apply(await planTagReconciliation(db));

      final value = (await temaValues()).single;
      expect(value.id, 't-roma-acento');
      expect(value.value, 'Róma');
      expect(await itemsOf(value.id), {'i1', 'i2', 'i3'});
      expect(await aliasesOf(value.id), {'Roma'});
    });

    test('con el mismo uso, gana la etiqueta más antigua', () async {
      await seedItem('i1');
      await seedItem('i2');
      await addTag('t-nueva', 'Róma', createdAt: jan2, items: ['i1']);
      await addTag('t-vieja', 'Roma', createdAt: jan1, items: ['i2']);

      await apply(await planTagReconciliation(db));

      final value = (await temaValues()).single;
      expect(value.id, 't-vieja');
      expect(await aliasesOf(value.id), {'Róma'});
    });

    test('dos valores de Tema repetidos por acento se fusionan en el más '
        'usado, sin romper un elemento que tenía los dos', () async {
      await seedItem('i1');
      await seedItem('i2');
      await seedItem('i3');
      await seedItem('i4');
      // El UNIQUE de SQLite solo pliega mayúsculas ASCII: estos dos conviven.
      await addValue('v-a', 'Álgebra', createdAt: jan1, items: ['i1', 'i2']);
      await addValue(
        'v-b',
        'álgebra',
        createdAt: jan2,
        items: ['i2', 'i3', 'i4'],
      );

      final plan = await planTagReconciliation(db);
      expect(plan.valueMerges, 1);

      await apply(plan);

      final value = (await temaValues()).single;
      expect(value.id, 'v-b');
      expect(await itemsOf('v-b'), {'i1', 'i2', 'i3', 'i4'});
      expect(await aliasesOf('v-b'), {'Álgebra'});
    });

    test('el origin de una asignación que ya existía no se degrada', () async {
      await seedItem('i1');
      await seedItem('i2');
      await seedItem('i3');
      await addValue(
        'v1',
        'Filosofía',
        items: ['i1'],
        origin: ItemPropertyOrigin.suggestedAccepted,
      );
      await addValue(
        'v2',
        'Ética',
        items: ['i2'],
        origin: ItemPropertyOrigin.inherited,
      );
      // Cada etiqueta repite una asignación existente y suma una nueva.
      await addTag('t1', 'Filosofía', items: ['i1', 'i3']);
      await addTag('t2', 'Ética', items: ['i2', 'i3']);

      await apply(await planTagReconciliation(db));

      Future<ItemPropertyOrigin> originOf(
        String itemId,
        String valueId,
      ) async =>
          (await (db.select(db.itemPropertyValues)..where(
                    (a) =>
                        a.itemId.equals(itemId) &
                        a.propertyValueId.equals(valueId),
                  ))
                  .getSingle())
              .origin;

      expect(await originOf('i1', 'v1'), ItemPropertyOrigin.suggestedAccepted);
      expect(await originOf('i2', 'v2'), ItemPropertyOrigin.inherited);
      expect(await originOf('i3', 'v1'), ItemPropertyOrigin.manual);
      expect(await originOf('i3', 'v2'), ItemPropertyOrigin.manual);
    });

    test(
      'las otras categorías no se tocan aunque tengan el mismo texto',
      () async {
        await seedItem('i1');
        const region = 'def-region';
        await db
            .into(db.propertyDefinitions)
            .insert(
              PropertyDefinitionsCompanion.insert(
                id: region,
                name: 'Región',
                createdAt: now,
                type: const Value(PropertyValueType.text),
              ),
            );
        await addValue('v-region', 'Roma', definitionId: region, items: ['i1']);
        await addTag('t1', 'Roma', items: ['i1']);

        await apply(await planTagReconciliation(db));

        // La etiqueta creó su propio valor bajo Tema; el de Región, intacto.
        expect((await temaValues()).map((v) => v.id), ['t1']);
        final regionValue = await (db.select(
          db.propertyValues,
        )..where((v) => v.id.equals('v-region'))).getSingle();
        expect(regionValue.definitionId, region);
        expect(await itemsOf('v-region'), {'i1'});
      },
    );

    test('un valor de Tema que ninguna etiqueta reclama se cuenta y no se '
        'toca', () async {
      await seedItem('i1');
      await addValue('v-suelto', 'Suelto', items: ['i1']);

      final plan = await planTagReconciliation(db);

      expect(plan.hasChanges, isFalse);
      expect(plan.temaValuesWithoutTag, 1);
    });

    test('una etiqueta sin nombre se reporta y no rompe el resto', () async {
      await seedItem('i1');
      await addTag('t-vacia', '   ', items: ['i1']);
      await addTag('t-ok', 'Roma', items: ['i1']);

      final plan = await planTagReconciliation(db);
      expect(plan.unmappableTags.map((t) => t.tagId), ['t-vacia']);

      await apply(plan);
      expect((await temaValues()).map((v) => v.id), ['t-ok']);
    });

    test(
      'las asignaciones de elementos que ya no existen no se migran',
      () async {
        await seedItem('i1');
        // Las claves foráneas están apagadas durante una migración: un
        // `ItemTags` de un elemento borrado puede haber quedado colgando.
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await addTag('t1', 'Roma', items: ['i1', 'fantasma']);
        await db.customStatement('PRAGMA foreign_keys = ON');

        final plan = await planTagReconciliation(db);
        expect(plan.danglingAssignments, 1);

        await apply(plan);
        expect(await itemsOf('t1'), {'i1'});
      },
    );

    test(
      'si el id de la etiqueta ya lo usa un valor, el nuevo recibe otro',
      () async {
        await seedItem('i1');
        await addValue('t1', 'Otra cosa'); // mismo id que la etiqueta de abajo
        await addTag('t1', 'Roma', items: ['i1']);

        await apply(await planTagReconciliation(db));

        final roma = (await temaValues()).firstWhere((v) => v.value == 'Roma');
        expect(roma.id, isNot('t1'));
        expect(roma.id, startsWith('gen-'));
        expect(await itemsOf(roma.id), {'i1'});
      },
    );
  });

  group('garantías', () {
    /// Una bóveda con un poco de cada caso.
    Future<void> seedMixedVault() async {
      for (final id in ['i1', 'i2', 'i3', 'i4', 'i5']) {
        await seedItem(id);
      }
      // Migradas por F2 (mismo texto), con una asignación extra en la etiqueta.
      await addValue('v-fil', 'Filosofía', items: ['i1']);
      await addTag('t-fil', 'Filosofía', items: ['i1', 'i2']);
      // Huérfanas, repetidas por acento.
      await addTag('t-roma', 'Roma', createdAt: jan1, items: ['i3']);
      await addTag('t-roma-a', 'Róma', createdAt: jan2, items: ['i3', 'i4']);
      // Valores repetidos por acento, uno con un alias ya puesto.
      await addValue('v-a', 'Álgebra', createdAt: jan1, items: ['i1', 'i5']);
      await addValue('v-b', 'álgebra', createdAt: jan2, items: ['i5']);
      await addAlias('v-b', 'Aljabr');
      // Un valor suelto y una etiqueta que difiere solo en mayúsculas.
      await addValue('v-suelto', 'Suelto', items: ['i4']);
      await addValue('v-eti', 'Ética', items: ['i2']);
      await addTag('t-eti', 'ética', items: ['i2']);
    }

    test(
      'ninguna asignación (elemento, texto) se pierde ni se inventa',
      () async {
        await seedMixedVault();
        final before = {...await temaPairs(), ...await tagPairs()};

        await apply(await planTagReconciliation(db));

        expect(await temaPairs(), before);
      },
    );

    test(
      'Tags e ItemTags no se tocan: siguen igual hasta que F10 las retire',
      () async {
        await seedMixedVault();
        final tagsBefore = (await db.select(db.tags).get()).length;
        final itemTagsBefore = (await db.select(db.itemTags).get()).length;

        await apply(await planTagReconciliation(db));

        expect((await db.select(db.tags).get()).length, tagsBefore);
        expect((await db.select(db.itemTags).get()).length, itemTagsBefore);
      },
    );

    test('el dry-run (plan) no escribe nada', () async {
      await seedMixedVault();
      final before = await snapshot();

      final plan = await planTagReconciliation(db);

      expect(plan.hasChanges, isTrue);
      expect(await snapshot(), before);
    });

    test('es idempotente: una segunda corrida no cambia nada', () async {
      await seedMixedVault();
      await apply(await planTagReconciliation(db));
      final afterFirst = await snapshot();

      final second = await planTagReconciliation(db);
      expect(second.hasChanges, isFalse);
      await apply(second);

      expect(await snapshot(), afterFirst);
    });

    test('después de la migración de F2, la reconciliación no tiene nada que '
        'hacer', () async {
      await seedItem('i1');
      await seedItem('i2');
      await addTag('t1', 'Filosofía', items: ['i1']);
      await addTag('t2', 'Roma', items: ['i2']);

      await migrateTagsToPropertyValues(
        db,
        ids: const UuidV7Generator(),
        logger: const SilentLogger(),
      );

      expect((await planTagReconciliation(db)).hasChanges, isFalse);
    });
  });

  group('reconcileTagsWithProperties', () {
    test(
      'deja el informe en MigrationIssues y en el logger, y aplica',
      () async {
        await seedItem('i1');
        await seedItem('i2');
        await addTag('t-huerfana', 'Roma', items: ['i1']);
        await addValue('v-a', 'Álgebra', createdAt: jan1, items: ['i1']);
        await addValue('v-b', 'álgebra', createdAt: jan2, items: ['i2', 'i1']);
        await addTag('t-vacia', '  ');
        final logger = _RecordingLogger();

        final plan = await db.transaction(
          () => reconcileTagsWithProperties(
            db,
            ids: ids,
            logger: logger,
            clock: () => now,
          ),
        );

        expect(plan.hasChanges, isTrue);
        expect(logger.infos.single, contains('1 etiquetas sin valor'));
        final report = await db.select(db.migrationIssues).get();
        expect(report.map((r) => r.migration).toSet(), {
          'f8_tag_reconciliation',
        });
        expect(report.map((r) => (r.stage, r.itemId)).toSet(), {
          ('orphan_tag', 't-huerfana'),
          ('merge_values', 'v-a'),
          ('unmapped_tag', 't-vacia'),
        });
        // Y aplicó: la etiqueta huérfana ya es un valor de Tema.
        expect((await temaValues()).map((v) => v.value), contains('Roma'));
      },
    );

    test(
      'sobre una bóveda ya reconciliada no escribe nada, ni informe',
      () async {
        await seedItem('i1');
        await addTag('t1', 'Roma', items: ['i1']);
        await db.transaction(
          () => reconcileTagsWithProperties(
            db,
            ids: ids,
            logger: const SilentLogger(),
            clock: () => now,
          ),
        );
        final afterFirst = await snapshot();
        final logger = _RecordingLogger();

        await db.transaction(
          () => reconcileTagsWithProperties(
            db,
            ids: ids,
            logger: logger,
            clock: () => now,
          ),
        );

        expect(await snapshot(), afterFirst);
        expect(logger.infos, isEmpty);
      },
    );

    test('una bóveda sin etiquetas no escribe nada', () async {
      final before = await snapshot();

      final plan = await reconcileTagsWithProperties(
        db,
        ids: ids,
        logger: const SilentLogger(),
      );

      expect(plan.hasChanges, isFalse);
      expect(await snapshot(), before);
    });

    test(
      'con Tema ausente falla en voz alta en vez de seguir en silencio',
      () async {
        await (db.delete(
          db.propertyDefinitions,
        )..where((d) => d.name.equals('Tema'))).go();

        expect(
          () => reconcileTagsWithProperties(
            db,
            ids: ids,
            logger: const SilentLogger(),
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
