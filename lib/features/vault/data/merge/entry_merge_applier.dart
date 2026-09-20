import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_planner.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_fields.dart';
import 'package:sinapsis/features/vault/data/merge/space_merge.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';

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
/// la copia adjuntada.
class EntryMergeApplier {
  EntryMergeApplier({
    required AppDatabase database,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  static const _incoming = kIncomingSchema;

  /// Cuántos identificadores entran en una sola sentencia: por debajo del tope
  /// de parámetros de SQLite.
  static const _idsPerStatement = 400;

  /// Los elementos que están en la copia y no aquí, y solo mientras dura la
  /// fusión: es lo que une las tablas de un elemento nuevo entre sí.
  static const _newItems = 'temp.merge_new_items';

  Future<VaultMergeResult> apply({
    required SpaceMerge spaces,
    required EntryMergePlan plan,
  }) async {
    await _addSpaces(spaces);
    final itemsAdded = await _addItems(spaces);
    await _updateFields(plan);
    await _recordConflicts(plan);

    return VaultMergeResult(
      itemsAdded: itemsAdded,
      itemsUpdated: plan.itemsToUpdate,
      fieldsUpdated: plan.fieldsToUpdate,
      conflictsRecorded: plan.conflicts,
      spacesAdded: spaces.toAdd.length,
    );
  }

  Future<void> _addSpaces(SpaceMerge spaces) async {
    for (final space in spaces.toAdd) {
      await _db.customStatement(
        'INSERT INTO main.spaces (id, name, created_at) VALUES (?, ?, ?)',
        [space.id, space.name, space.createdAt],
      );
    }
  }

  /// Copia los elementos que esta bóveda no tiene, con su nota o su fuente y
  /// sus versiones por campo. Devuelve cuántos.
  Future<int> _addItems(SpaceMerge spaces) async {
    await _db.customStatement('DROP TABLE IF EXISTS $_newItems');
    try {
      await _db.customStatement('''
        CREATE TEMP TABLE merge_new_items AS
        SELECT i.id AS id FROM $_incoming.item i
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
    } finally {
      await _db.customStatement('DROP TABLE IF EXISTS $_newItems');
    }
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
  /// junto con su versión, y sube el `rev` de cada elemento que cambió.
  Future<void> _updateFields(EntryMergePlan plan) async {
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

    // Cada elemento cambiado, una vez: su `rev` sube y se pone el dispositivo
    // de acá, que es quien lo cambió en esta bóveda; su fecha es la más
    // reciente de las dos.
    final changed = {for (final c in plan.updates) c.itemId}.toList();
    await _forChunks(changed, (marks, chunk) {
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
  }

  /// Guarda cada conflicto: las dos versiones, de quién era cada una y cuándo
  /// se detectó. La que queda en vivo ya se escribió; esto es la otra.
  Future<void> _recordConflicts(EntryMergePlan plan) async {
    final detectedAt = _clock().millisecondsSinceEpoch ~/ 1000;
    for (final change in plan.conflictChanges) {
      await _db.customStatement(
        '''
        INSERT INTO main.merge_conflict (
          id, item_id, field_name, local_value, incoming_value,
          local_updated_at, local_device_id,
          incoming_updated_at, incoming_device_id, detected_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          _ids.next(),
          change.itemId,
          change.field.name,
          change.localValue,
          change.incomingValue,
          _seconds(change.localStamp?.updatedAt),
          change.localStamp?.deviceId,
          _seconds(change.incomingStamp?.updatedAt),
          change.incomingStamp?.deviceId,
          detectedAt,
        ],
      );
    }
  }

  static int? _seconds(DateTime? at) =>
      at == null ? null : at.millisecondsSinceEpoch ~/ 1000;

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
