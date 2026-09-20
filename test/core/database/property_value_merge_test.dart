import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/property_value_merge.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';

import '../../support/fake_id_generator.dart';
import '../../support/item_rows.dart';

/// El motor de fusión de valores y su deshacer, contra SQLite real. El
/// invariante que importa: fusionar y deshacer deja el vocabulario EXACTAMENTE
/// como estaba —mismas filas, mismos origin, mismos alias—.
void main() {
  late AppDatabase db;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 19, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator(prefix: 'gen');
  });

  tearDown(() => db.close());

  Future<void> seedItem(String id) =>
      insertItemRows(db, id: id, title: 'Elemento $id', createdAt: now);

  Future<String> temaId() async => (await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.equals('Tema'))).getSingle()).id;

  Future<void> addValue(
    String id,
    String label, {
    Map<String, ItemPropertyOrigin> items = const {},
    DateTime? createdAt,
  }) async {
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: await temaId(),
            value: label,
            createdAt: createdAt ?? now,
          ),
        );
    for (final entry in items.entries) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: entry.key,
              propertyValueId: id,
              origin: Value(entry.value),
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

  Future<PropertyValueRow> valueRow(String id) =>
      (db.select(db.propertyValues)..where((v) => v.id.equals(id))).getSingle();

  Future<PropertyValueMergeUndo> merge(String keepId, String discardId) =>
      db.transaction(
        () async => mergePropertyValueRows(
          db,
          keep: await valueRow(keepId),
          discard: await valueRow(discardId),
          ids: ids,
          clock: () => now,
        ),
      );

  /// Lo que la fusión toca, en una lista comparable.
  Future<List<String>> snapshot() async => [
    for (final r in await db.select(db.propertyValues).get())
      'valor ${r.id}|${r.definitionId}|${r.value}|${r.createdAt}',
    for (final r in await db.select(db.itemPropertyValues).get())
      'asignación ${r.itemId}|${r.propertyValueId}|${r.origin.name}',
    for (final r in await db.select(db.propertyAliases).get())
      'alias ${r.id}|${r.propertyValueId}|${r.alias}',
  ]..sort();

  /// Un vocabulario con un poco de todo:
  ///  * `keep` la tiene i1 (manual) e i2 (suggestedAccepted);
  ///  * `discard` la tiene i2 (inherited: la repite) e i3 (suggestedAccepted);
  ///  * `discard` ya tenía un alias propio.
  Future<void> seedVocabulary() async {
    for (final id in ['i1', 'i2', 'i3']) {
      await seedItem(id);
    }
    await addValue(
      'keep',
      'Roma',
      items: {
        'i1': ItemPropertyOrigin.manual,
        'i2': ItemPropertyOrigin.suggestedAccepted,
      },
    );
    await addValue(
      'discard',
      'Róma',
      items: {
        'i2': ItemPropertyOrigin.inherited,
        'i3': ItemPropertyOrigin.suggestedAccepted,
      },
    );
    await addAlias('alias-propio', 'discard', 'Urbe');
  }

  group('mergePropertyValueRows', () {
    test('el registro describe lo que pasó', () async {
      await seedVocabulary();

      final undo = await merge('keep', 'discard');

      expect(undo.keepId, 'keep');
      expect(undo.discard.id, 'discard');
      // i3 pasó al que se conserva; i2 ya lo tenía y la fila de sobra se fue.
      expect(undo.movedAssignments.map((a) => a.itemId), ['i3']);
      expect(undo.droppedAssignments.map((a) => a.itemId), ['i2']);
      expect(
        undo.droppedAssignments.single.origin,
        ItemPropertyOrigin.inherited,
      );
      expect(undo.movedAliasIds, ['alias-propio']);
      expect(undo.createdAliasId, isNotNull);
      expect(undo.affectedItems, 2);
    });

    test('lo que tenía el descartado queda en el que se conserva', () async {
      await seedVocabulary();

      await merge('keep', 'discard');

      final assigned = await (db.select(
        db.itemPropertyValues,
      )..where((a) => a.propertyValueId.equals('keep'))).get();
      expect(assigned.map((a) => a.itemId).toSet(), {'i1', 'i2', 'i3'});
      // El descartado ya no existe, y su label y su alias viajaron.
      expect(
        await (db.select(
          db.propertyValues,
        )..where((v) => v.id.equals('discard'))).get(),
        isEmpty,
      );
      final aliases = await db.select(db.propertyAliases).get();
      expect(aliases.map((a) => (a.propertyValueId, a.alias)).toSet(), {
        ('keep', 'Urbe'),
        ('keep', 'Róma'),
      });
    });

    test('si el label del descartado ya es alias de un tercero, no se crea '
        'ese alias y el registro lo dice', () async {
      await seedVocabulary();
      await addValue('tercero', 'Latium');
      await addAlias('alias-tercero', 'tercero', 'Róma');

      final undo = await merge('keep', 'discard');

      expect(undo.createdAliasId, isNull);
    });
  });

  group('undoPropertyValueMerge', () {
    test(
      'fusionar y deshacer deja el vocabulario exactamente como estaba',
      () async {
        await seedVocabulary();
        final before = await snapshot();

        final undo = await merge('keep', 'discard');
        expect(await snapshot(), isNot(before));
        await db.transaction(() => undoPropertyValueMerge(db, undo));

        expect(await snapshot(), before);
      },
    );

    test(
      'con un alias de un tercero en el camino, deshacer tampoco lo toca',
      () async {
        await seedVocabulary();
        await addValue('tercero', 'Latium');
        await addAlias('alias-tercero', 'tercero', 'Róma');
        final before = await snapshot();

        final undo = await merge('keep', 'discard');
        await db.transaction(() => undoPropertyValueMerge(db, undo));

        expect(await snapshot(), before);
      },
    );

    test('se niega si el valor en el que se fusionó ya no existe, sin tocar '
        'nada', () async {
      await seedVocabulary();
      final undo = await merge('keep', 'discard');
      await (db.delete(
        db.propertyValues,
      )..where((v) => v.id.equals('keep'))).go();
      final before = await snapshot();

      await expectLater(
        db.transaction(() => undoPropertyValueMerge(db, undo)),
        throwsA(isA<MergeUndoConflict>()),
      );

      expect(await snapshot(), before);
    });

    test('se niega si una asignación que la fusión movió ya no está', () async {
      await seedVocabulary();
      final undo = await merge('keep', 'discard');
      // Después de fusionar, alguien quitó el valor de i3.
      await (db.delete(db.itemPropertyValues)..where(
            (a) => a.itemId.equals('i3') & a.propertyValueId.equals('keep'),
          ))
          .go();
      final before = await snapshot();

      await expectLater(
        db.transaction(() => undoPropertyValueMerge(db, undo)),
        throwsA(isA<MergeUndoConflict>()),
      );

      expect(await snapshot(), before);
    });

    test('se niega si el descartado ya fue recreado', () async {
      await seedVocabulary();
      final undo = await merge('keep', 'discard');
      await addValue('discard', 'Otra cosa con el mismo id');
      final before = await snapshot();

      await expectLater(
        db.transaction(() => undoPropertyValueMerge(db, undo)),
        throwsA(isA<MergeUndoConflict>()),
      );

      expect(await snapshot(), before);
    });

    test(
      'lo que se agregó DESPUÉS de fusionar sobrevive al deshacer',
      () async {
        await seedVocabulary();
        await seedItem('i4');
        final undo = await merge('keep', 'discard');
        // Un elemento nuevo recibe el valor que se conservó.
        await db
            .into(db.itemPropertyValues)
            .insert(
              ItemPropertyValuesCompanion.insert(
                itemId: 'i4',
                propertyValueId: 'keep',
              ),
            );

        await db.transaction(() => undoPropertyValueMerge(db, undo));

        final keepItems = await (db.select(
          db.itemPropertyValues,
        )..where((a) => a.propertyValueId.equals('keep'))).get();
        expect(keepItems.map((a) => a.itemId).toSet(), {'i1', 'i2', 'i4'});
      },
    );
  });
}
