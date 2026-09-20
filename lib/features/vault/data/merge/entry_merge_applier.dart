import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_planner.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_conflict_log.dart';
import 'package:sinapsis/features/vault/data/merge/merge_fields.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';
import 'package:sinapsis/features/vault/data/merge/space_merge.dart';

/// Las columnas de las tablas de un elemento, en el orden en que se copian de
/// una bóveda a la otra. Un test comprueba que cubren la tabla entera: una
/// columna nueva que no esté acá no se llevaría en la fusión.
const kItemColumns = [
  'id',
  'title',
  'subtitle',
  'notes',
  'space_id',
  'kind',
  'state',
  'created_at',
  'updated_at',
  'deleted_at',
  'device_id',
  'rev',
];
const kNoteColumns = [
  'item_id',
  'note_kind',
  'maturity',
  'dedup_hash',
  'simhash',
];
const kSourceColumns = [
  'item_id',
  'source_type',
  'origin_url',
  'author_name',
  'author_url',
  'published_at',
  'captured_at',
  'original_blob_path',
  'content_hash',
  'dedup_hash',
  'simhash',
  'processing_status',
  'processing_error',
  'processing_attempts',
];
const kFieldVersionColumns = [
  'item_id',
  'field_name',
  'updated_at',
  'device_id',
  'base_updated_at',
  'base_device_id',
];

/// Escribe en esta bóveda lo que la fusión decidió sobre los elementos, los
/// campos y los espacios (F11).
///
/// Es, junto a `KnowledgeEntryWriter`, el único lugar que escribe `item`,
/// `note` y `source` —el test de censo lo lista con su motivo—, y escribe
/// distinto a propósito: `KnowledgeEntryWriter` registra una modificación
/// NUESTRA (pone el dispositivo de acá y una versión nueva); esto aplica
/// versiones que YA traen su linaje, y pasarlas por el escritor les cambiaría
/// el autor y perdería de qué partían. Por eso copia las filas y su
/// `field_version` tal como vienen.
///
/// Trabaja con conjuntos —una sentencia por tabla y por grupo de elementos, no
/// una por fila—: una bóveda de diez mil elementos entra en unas pocas decenas
/// de sentencias. Tiene que correr DENTRO de la transacción de la fusión, con
/// la copia adjuntada y [MergeWork] creado. Cada etapa se llama por separado:
/// el orden entre ellas y con las de las formas y del vocabulario lo pone
/// `VaultMerger`.
class EntryMergeApplier {
  EntryMergeApplier({
    required AppDatabase database,
    required MergeConflictLog conflicts,
  }) : _db = database,
       _log = conflicts;

  final AppDatabase _db;
  final MergeConflictLog _log;

  static const _incoming = kIncomingSchema;

  /// Cuántos identificadores entran en una sola sentencia: por debajo del tope
  /// de parámetros de SQLite.
  static const _idsPerStatement = 400;

  static const _newItems = MergeWork.newItems;

  /// Crea los espacios de la copia que esta bóveda no tiene.
  Future<void> addSpaces(SpaceMerge spaces) async {
    for (final space in spaces.toAdd) {
      await _db.customStatement(
        'INSERT INTO main.spaces (id, name, created_at) VALUES (?, ?, ?)',
        [space.id, space.name, space.createdAt],
      );
    }
  }

  /// Copia los elementos que esta bóveda no tiene, con su nota o su fuente y
  /// sus versiones por campo, y deja anotados cuáles son
  /// ([MergeWork.newItems]). Devuelve cuántos.
  Future<int> addItems(SpaceMerge spaces) async {
    await _db.customStatement('''
      INSERT INTO $_newItems (id)
      SELECT i.id FROM $_incoming.item i
       WHERE NOT EXISTS (SELECT 1 FROM main.item m WHERE m.id = i.id)''');
    final count =
        (await _db
                .customSelect('SELECT COUNT(*) AS n FROM $_newItems')
                .getSingle())
            .read<int>('n');
    if (count == 0) return 0;

    // El espacio de la copia con el identificador de acá. Con la copia sin
    // nada que traducir, el identificador se copia tal cual.
    final remap = spaces.remap.entries.toList();
    final space = remap.isEmpty
        ? 'x.space_id'
        : 'CASE x.space_id '
              '${List.filled(remap.length, 'WHEN ? THEN ?').join(' ')} '
              'ELSE x.space_id END';
    await _db.customStatement(
      '''
      INSERT INTO main.item (${kItemColumns.join(', ')})
      SELECT ${kItemColumns.map((c) => c == 'space_id' ? space : 'x.$c').join(', ')}
        FROM $_incoming.item x JOIN $_newItems n ON n.id = x.id''',
      [
        for (final entry in remap) ...[entry.key, entry.value],
      ],
    );

    await _copyByItem('note', kNoteColumns, 'item_id');
    await _copyByItem('source', kSourceColumns, 'item_id');
    await _copyByItem('field_version', kFieldVersionColumns, 'item_id');
    return count;
  }

  /// Copia de la copia las filas de [table] que cuelgan de un elemento nuevo.
  Future<void> _copyByItem(
    String table,
    List<String> columns,
    String itemColumn,
  ) => _db.customStatement('''
    INSERT INTO main.$table (${columns.join(', ')})
    SELECT ${columns.map((c) => 'x.$c').join(', ')}
      FROM $_incoming.$table x JOIN $_newItems n ON n.id = x.$itemColumn''');

  /// Pone en los elementos de acá el valor de la copia en cada campo que ganó,
  /// junto con su versión. No sube el `rev`: ver [bumpItems].
  Future<void> updateFields(EntryMergePlan plan) async {
    final byField = <MergeField, List<FieldChange>>{};
    for (final change in plan.updates) {
      (byField[change.field] ??= []).add(change);
    }

    for (final MapEntry(key: field, value: changes) in byField.entries) {
      if (field.isSpace) {
        // Ya traducido a los identificadores de acá: se escribe por valor.
        final byValue = <String?, List<String>>{};
        for (final change in changes) {
          (byValue[change.incomingValue] ??= []).add(change.itemId);
        }
        for (final MapEntry(key: value, value: ids) in byValue.entries) {
          await _forChunks(ids, (marks, chunk) {
            return _db.customStatement(
              'UPDATE main.item SET ${field.column} = ? WHERE id IN ($marks)',
              [value, ...chunk],
            );
          });
        }
      } else {
        await _forChunks([for (final c in changes) c.itemId], (marks, chunk) {
          return _db.customStatement('''
            UPDATE main.${field.table} SET ${field.column} = (
              SELECT x.${field.column} FROM $_incoming.${field.table} x
               WHERE x.${field.keyColumn} = ${field.table}.${field.keyColumn})
             WHERE ${field.keyColumn} IN ($marks)''', chunk);
        });
      }

      // La versión del campo pasa a ser la de la copia; si la copia no tiene
      // ninguna, el campo vuelve a ser el valor de partida.
      await _forChunks([for (final c in changes) c.itemId], (
        marks,
        chunk,
      ) async {
        await _db.customStatement(
          'DELETE FROM main.field_version '
          'WHERE field_name = ? AND item_id IN ($marks)',
          [field.name, ...chunk],
        );
        await _db.customStatement(
          '''
          INSERT INTO main.field_version (${kFieldVersionColumns.join(', ')})
          SELECT ${kFieldVersionColumns.map((c) => 'x.$c').join(', ')}
            FROM $_incoming.field_version x
           WHERE x.field_name = ? AND x.item_id IN ($marks)''',
          [field.name, ...chunk],
        );
      });
    }
  }

  /// Anota que los elementos [itemIds] cambiaron en esta bóveda, UNA vez cada
  /// uno aunque hayan cambiado por varios lados: su `rev` sube y se pone el
  /// dispositivo de acá, que es quien los cambió; su fecha es la más reciente
  /// de las dos.
  ///
  /// Lo llama `VaultMerger` con todo lo que cambió —campos y texto—, y no cada
  /// paso por su cuenta: este es el único archivo de la fusión que escribe
  /// `item`.
  Future<void> bumpItems(Iterable<String> itemIds) =>
      _forChunks(itemIds.toSet().toList(), (marks, chunk) {
        return _db.customStatement(
          '''
          UPDATE main.item
             SET rev = rev + 1,
                 device_id = ?,
                 updated_at = MAX(updated_at, (
                   SELECT x.updated_at FROM $_incoming.item x
                    WHERE x.id = item.id))
           WHERE id IN ($marks)''',
          [_db.deviceId, ...chunk],
        );
      });

  /// Guarda cada conflicto de campo: las dos versiones, de quién era cada una y
  /// cuándo se detectó. La que queda en vivo ya se escribió; esto es la otra.
  Future<void> recordConflicts(EntryMergePlan plan) async {
    for (final change in plan.conflictChanges) {
      await _log.record(
        itemId: change.itemId,
        field: change.field.name,
        localValue: change.localValue,
        incomingValue: change.incomingValue,
        localStamp: change.localStamp,
        incomingStamp: change.incomingStamp,
      );
    }
  }

  /// Corre [statement] por cada tramo de [ids] que entra en una sentencia, con
  /// los signos de pregunta que le corresponden.
  Future<void> _forChunks(
    List<String> ids,
    Future<void> Function(String marks, List<String> chunk) statement,
  ) async {
    for (var start = 0; start < ids.length; start += _idsPerStatement) {
      final chunk = ids.skip(start).take(_idsPerStatement).toList();
      await statement(List.filled(chunk.length, '?').join(', '), chunk);
    }
  }
}
