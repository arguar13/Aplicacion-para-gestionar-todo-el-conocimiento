import 'package:drift/drift.dart' show Variable;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_planner.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_fields.dart';
import 'package:sinapsis/features/vault/data/merge/space_merge.dart';
import 'package:sinapsis/features/vault/data/merge/stamp_rows.dart';
import 'package:sinapsis/features/vault/domain/merge/field_merge_rule.dart';

/// Decide qué temas quedan en los elementos que las dos bóvedas tienen al
/// fusionar la copia de otra con esta (F37, decisión 80).
///
/// Los temas de un elemento son UN campo de linaje ([MergeField.isSpaces]):
/// se decide con la misma [FieldMergeRule] que el título, y gana el conjunto
/// entero del lado más nuevo. No se unen los dos: quien sacó un tema en un
/// dispositivo lo sacó a propósito, y unir lo haría volver.
///
/// Un tema de la copia se compara con el identificador que tiene ACÁ
/// ([SpaceMerge]): «Historia» creado por separado en cada bóveda es el mismo
/// tema, y un elemento que está en los dos «Historia» no difiere.
///
/// Solo trae a Dart los elementos cuyos temas difieren: una copia casi igual
/// se planifica leyendo casi nada.
class ItemSpacesMergePlanner {
  const ItemSpacesMergePlanner(this._db);

  final AppDatabase _db;

  static const _incoming = kIncomingSchema;

  /// Cuántos elementos se leen por consulta: por debajo del tope de parámetros
  /// de SQLite.
  static const _itemsPerQuery = 400;

  /// Los cambios de [field] en los elementos comunes, ya decididos: solo los
  /// que las dos bóvedas tienen en temas distintos.
  Future<List<FieldChange>> differing(
    MergeField field,
    SpaceMerge spaces,
  ) async {
    final mapped = spaces.localIdSql('x.space_id');
    final candidates = await _db
        .customSelect(
          '''
      SELECT m.id AS item_id,
             ${StampRows.columns(localVersion: 'lf', incomingVersion: 'inf', localItem: 'm', incomingItem: 'i')}
        FROM main.item m
        JOIN $_incoming.item i ON i.id = m.id
        LEFT JOIN main.field_version lf
               ON lf.item_id = m.id AND lf.field_name = '${field.name}'
        LEFT JOIN $_incoming.field_version inf
               ON inf.item_id = m.id AND inf.field_name = '${field.name}'
       WHERE EXISTS (
               SELECT 1 FROM main.item_spaces l
                WHERE l.item_id = m.id
                  AND NOT EXISTS (
                        SELECT 1 FROM $_incoming.item_spaces x
                         WHERE x.item_id = m.id AND $mapped = l.space_id))
          OR EXISTS (
               SELECT 1 FROM $_incoming.item_spaces x
                WHERE x.item_id = m.id
                  AND NOT EXISTS (
                        SELECT 1 FROM main.item_spaces l
                         WHERE l.item_id = m.id AND l.space_id = $mapped))
       ORDER BY m.id''',
          variables: [
            for (final arg in [...spaces.localIdArgs, ...spaces.localIdArgs])
              Variable<String>(arg),
          ],
        )
        .get();

    final changes = <FieldChange>[];
    for (var start = 0; start < candidates.length; start += _itemsPerQuery) {
      final slice = candidates.skip(start).take(_itemsPerQuery).toList();
      final ids = [for (final row in slice) row.read<String>('item_id')];
      final local = await _read('main', ids);
      final incoming = await _read(_incoming, ids);
      for (final row in slice) {
        final id = row.read<String>('item_id');
        final localValue = encodeSpaceIds(local[id] ?? const {});
        // Los temas de la copia, con el identificador que tienen acá.
        final incomingValue = encodeSpaceIds({
          for (final spaceId in incoming[id] ?? const <String>{})
            spaces.localIdOf(spaceId)!,
        });
        final decision = StampRows.decide(
          row,
          valuesDiffer: localValue != incomingValue,
        );
        if (decision == FieldDecision.same) continue;
        changes.add(
          FieldChange(
            itemId: id,
            field: field,
            decision: decision,
            localValue: localValue,
            incomingValue: incomingValue,
            localStamp: StampRows.field(row, 'l'),
            incomingStamp: StampRows.field(row, 'i'),
          ),
        );
      }
    }
    return changes;
  }

  /// Los temas que la bóveda [schema] —`main` o la copia— tiene en cada uno
  /// de [ids], con sus propios identificadores.
  Future<Map<String, Set<String>>> _read(
    String schema,
    List<String> ids,
  ) async {
    final marks = List.filled(ids.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          'SELECT item_id, space_id FROM $schema.item_spaces '
          'WHERE item_id IN ($marks)',
          variables: [for (final id in ids) Variable<String>(id)],
        )
        .get();
    final byItem = <String, Set<String>>{};
    for (final row in rows) {
      (byItem[row.read<String>('item_id')] ??= {}).add(
        row.read<String>('space_id'),
      );
    }
    return byItem;
  }
}
