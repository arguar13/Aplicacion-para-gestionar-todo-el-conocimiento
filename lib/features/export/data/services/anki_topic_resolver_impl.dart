import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';
import 'package:sinapsis/features/export/domain/services/anki_topic_resolver.dart';

class AnkiTopicResolverImpl implements AnkiTopicResolver {
  const AnkiTopicResolverImpl({required AppDatabase database})
    : _db = database;

  final AppDatabase _db;

  @override
  Future<AnkiTopicResolution> resolve(Set<String> itemIds) async {
    final definitionId = await temaDefinitionId(_db);

    final values = _db.propertyValues;
    final valueRows =
        await (_db.selectOnly(values)
              ..addColumns([values.id, values.value, values.parentId])
              ..where(values.definitionId.equals(definitionId)))
            .get();
    final labelOf = {
      for (final row in valueRows)
        row.read(values.id)!: row.read(values.value)!,
    };
    final tree = VocabularyTree([
      for (final row in valueRows)
        (id: row.read(values.id)!, parentId: row.read(values.parentId)),
    ]);

    final firstTopicByItem = <String, String?>{
      for (final id in itemIds) id: null,
    };
    if (itemIds.isEmpty || labelOf.isEmpty) {
      return AnkiTopicResolution(
        tree: tree,
        labelOf: labelOf,
        firstTopicByItem: firstTopicByItem,
      );
    }

    // Todas las asignaciones de Tema de los elementos pedidos, de una vez —no
    // una consulta por tarjeta—, con el `rowid` de cada una: es lo único que
    // dice en qué orden se asignaron, `item_property_values` no tiene una
    // columna de fecha propia.
    final marks = List.filled(itemIds.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          'SELECT ipv.item_id AS item_id, '
          'ipv.property_value_id AS property_value_id, '
          'ipv.rowid AS row_id '
          'FROM item_property_values ipv '
          'JOIN property_values pv ON pv.id = ipv.property_value_id '
          'WHERE pv.definition_id = ? AND ipv.item_id IN ($marks)',
          variables: [
            Variable.withString(definitionId),
            for (final id in itemIds) Variable.withString(id),
          ],
          readsFrom: {_db.itemPropertyValues, _db.propertyValues},
        )
        .get();

    // El mínimo `rowid` por elemento, resuelto acá: SQLite no tiene «mínimo
    // por grupo» directo —mismo motivo por el que F15 resuelve el primer
    // autor en Dart, no en SQL—.
    final bestRowId = <String, int>{};
    for (final row in rows) {
      final itemId = row.read<String>('item_id');
      final rowId = row.read<int>('row_id');
      final current = bestRowId[itemId];
      if (current == null || rowId < current) {
        bestRowId[itemId] = rowId;
        firstTopicByItem[itemId] = row.read<String>('property_value_id');
      }
    }

    return AnkiTopicResolution(
      tree: tree,
      labelOf: labelOf,
      firstTopicByItem: firstTopicByItem,
    );
  }
}
