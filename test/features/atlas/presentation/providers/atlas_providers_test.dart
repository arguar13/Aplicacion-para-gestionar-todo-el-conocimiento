import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/atlas/presentation/providers/atlas_providers.dart';

import '../../../../support/item_rows.dart';

/// El cableado del Atlas (F13): el repositorio vive tanto como el contenedor y
/// el Atlas de una categoría se actualiza solo.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  final now = DateTime(2026, 9, 21, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> value(String id, String definitionId) => db
      .into(db.propertyValues)
      .insert(
        PropertyValuesCompanion.insert(
          id: id,
          definitionId: definitionId,
          value: 'Valor $id',
          createdAt: now,
        ),
      );

  test('el proveedor entrega el Atlas de la categoría pedida', () async {
    final tema = await temaDefinitionId(db);
    await value('roma', tema);
    await insertItemRows(db, id: 'i1', title: 'Fuente', createdAt: now);
    await db
        .into(db.itemPropertyValues)
        .insert(
          ItemPropertyValuesCompanion.insert(
            itemId: 'i1',
            propertyValueId: 'roma',
          ),
        );

    final atlas = await container.read(atlasProvider(tema).future);

    expect(atlas.definitionName, 'Tema');
    expect(atlas.nodeOf('roma')!.sourceCount, 1);
  });

  test('se actualiza solo cuando se asigna una propiedad', () async {
    final tema = await temaDefinitionId(db);
    await value('roma', tema);
    final seen = <int>[];
    final subscription = container.listen(atlasProvider(tema), (_, next) {
      final atlas = next.value;
      if (atlas != null) seen.add(atlas.nodeOf('roma')!.sourceCount);
    }, fireImmediately: true);
    addTearDown(subscription.close);
    await pumpEventQueue();

    await insertItemRows(db, id: 'i1', title: 'Fuente', createdAt: now);
    await db
        .into(db.itemPropertyValues)
        .insert(
          ItemPropertyValuesCompanion.insert(
            itemId: 'i1',
            propertyValueId: 'roma',
          ),
        );
    await pumpEventQueue();

    expect(seen.first, 0);
    expect(seen.last, 1);
  });

  test('es un solo repositorio, con una sola caché, mientras dure el '
      'contenedor', () {
    expect(
      identical(
        container.read(atlasRepositoryProvider),
        container.read(atlasRepositoryProvider),
      ),
      isTrue,
    );
  });
}
