import 'package:drift/drift.dart' show Variable;
import 'package:meta/meta.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_conflict_log.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';
import 'package:sinapsis/features/vault/data/merge/stamp_rows.dart';
import 'package:sinapsis/features/vault/domain/merge/field_merge_rule.dart';

/// Qué hacer con una forma de un elemento que las dos bóvedas tienen (F11).
enum RenditionAction {
  /// La copia trae una forma que este elemento no tiene: se agrega, no
  /// principal.
  add,

  /// El texto de una NOTA que la copia editó partiendo del de acá: pasa a ser
  /// el de la copia.
  overwrite,

  /// Los dos textos son distintos y ninguno partió del otro —o es una fuente,
  /// cuyo texto no se pisa nunca—: el de acá queda en vivo y el de la copia
  /// entra como otra forma del mismo elemento, con un conflicto que la señala.
  keepBoth,
}

/// La decisión sobre una forma de la copia.
@immutable
class RenditionChange {
  const RenditionChange({
    required this.itemId,
    required this.incomingId,
    required this.action,
    this.localStamp,
    this.incomingStamp,
  });

  final String itemId;

  /// El identificador de la forma en la copia; también el de la de acá, si la
  /// tiene.
  final String incomingId;
  final RenditionAction action;

  /// Las versiones del texto en cada lado, para guardar el conflicto.
  final FieldStamp? localStamp;
  final FieldStamp? incomingStamp;
}

/// Lo que hay que hacer con las formas de los elementos que las dos bóvedas
/// tienen.
class RenditionMergePlan {
  const RenditionMergePlan(this.changes, this.notPlaced);

  final List<RenditionChange> changes;

  /// Las formas de la copia que NO entran con su identificador, y dónde queda
  /// su texto acá: el identificador de la forma que ya lo tiene, o `null` si no
  /// hay dónde. Lo necesitan los resaltados, cuyas posiciones son de un texto.
  final Map<String, String?> notPlaced;

  static const empty = RenditionMergePlan([], {});

  /// Formas nuevas para elementos que esta bóveda ya tenía.
  int get toAdd => changes.where((c) => c.action == RenditionAction.add).length;

  /// Textos de nota que cambian.
  int get toUpdate =>
      changes.where((c) => c.action == RenditionAction.overwrite).length;

  /// Textos distintos que entran como otra forma, con su conflicto.
  int get conflicts =>
      changes.where((c) => c.action == RenditionAction.keepBoth).length;

  /// Los elementos cuyo texto de una nota cambia.
  Set<String> get updatedItems => {
    for (final c in changes)
      if (c.action == RenditionAction.overwrite) c.itemId,
  };
}

/// Decide qué pasa con las formas de los elementos que las dos bóvedas tienen
/// (F11): la copia adjuntada, sin escribir nada.
///
/// El texto de una FUENTE no se pisa nunca ni se pierde: si el de la copia es
/// distinto, entra como otra forma. El de una NOTA es lo que el usuario
/// escribe, y se fusiona como cualquier campo —`rendition:<id>` en
/// `field_version`—: lo que la copia editó partiendo de lo de acá se toma; lo
/// demás se guarda al lado.
///
/// Las formas de los elementos NUEVOS no pasan por acá: se copian enteras.
class RenditionMergePlanner {
  const RenditionMergePlanner(this._db);

  final AppDatabase _db;

  static const _incoming = kIncomingSchema;

  /// [known] son los conflictos que ya hay ([MergeConflictLog.known]).
  ///
  /// Solo trae a Dart las formas que faltan acá o que difieren, y ni siquiera
  /// su texto: una bóveda de diez mil fuentes iguales se planifica sin leer una
  /// línea.
  Future<RenditionMergePlan> plan({required Set<String> known}) async {
    final stamps = StampRows.columns(
      localVersion: 'lf',
      incomingVersion: 'inf',
      localItem: 'mi',
      incomingItem: 'ii',
    );
    final rows = await _db.customSelect('''
      SELECT r.id AS r_id, r.item_id AS item_id, m.id AS m_id,
             mi.kind AS item_kind,
             (SELECT x.id FROM main.renditions x
               WHERE x.item_id = r.item_id AND x.id <> r.id
                 AND x.content IS r.content
                 AND x.relative_path IS r.relative_path
               LIMIT 1) AS same_content_id,
             $stamps
        FROM $_incoming.renditions r
        JOIN main.item mi ON mi.id = r.item_id
        JOIN $_incoming.item ii ON ii.id = r.item_id
        LEFT JOIN main.renditions m ON m.id = r.id
        LEFT JOIN main.field_version lf
               ON lf.item_id = r.item_id
              AND lf.field_name = 'rendition:' || r.id
        LEFT JOIN $_incoming.field_version inf
               ON inf.item_id = r.item_id
              AND inf.field_name = 'rendition:' || r.id
       WHERE m.id IS NULL
          OR m.content IS NOT r.content
          OR m.relative_path IS NOT r.relative_path
       ORDER BY r.item_id, r.id''').get();

    final changes = <RenditionChange>[];
    final notPlaced = <String, String?>{};
    for (final row in rows) {
      final incomingId = row.read<String>('r_id');
      final itemId = row.read<String>('item_id');

      // El mismo texto ya está acá, con otro identificador —una fusión anterior
      // lo trajo, o se procesó dos veces—: no se agrega otro igual.
      final sameContent = row.read<String?>('same_content_id');
      if (sameContent != null) {
        notPlaced[incomingId] = sameContent;
        continue;
      }

      if (row.read<String?>('m_id') == null) {
        changes.add(
          RenditionChange(
            itemId: itemId,
            incomingId: incomingId,
            action: RenditionAction.add,
            incomingStamp: StampRows.field(row, 'i'),
          ),
        );
        continue;
      }

      // El mismo identificador y un texto distinto.
      final localStamp = StampRows.field(row, 'l');
      final incomingStamp = StampRows.field(row, 'i');
      final decision = row.read<String>('item_kind') == 'source'
          ? FieldDecision.conflictKeepLocal
          : StampRows.decide(row, valuesDiffer: true);

      if (decision == FieldDecision.takeIncoming) {
        changes.add(
          RenditionChange(
            itemId: itemId,
            incomingId: incomingId,
            action: RenditionAction.overwrite,
            localStamp: localStamp,
            incomingStamp: incomingStamp,
          ),
        );
        continue;
      }

      // Lo que sigue deja el texto de acá en vivo: el de la copia no tiene
      // dónde ponerse con el mismo identificador.
      notPlaced[incomingId] = null;
      final repeated = known.contains(
        MergeConflictLog.keyFor(
          itemId,
          EntryField.rendition(incomingId),
          incomingStamp,
        ),
      );
      if (decision.isConflict && !repeated) {
        changes.add(
          RenditionChange(
            itemId: itemId,
            incomingId: incomingId,
            action: RenditionAction.keepBoth,
            localStamp: localStamp,
            incomingStamp: incomingStamp,
          ),
        );
      }
    }
    return RenditionMergePlan(changes, notPlaced);
  }
}

/// Lo que hizo [RenditionMergeApplier].
class RenditionMergeResult {
  const RenditionMergeResult({
    this.added = 0,
    this.updated = 0,
    this.conflicts = 0,
  });

  /// Formas escritas: las de los elementos nuevos, las que faltaban y las de
  /// textos distintos que entraron al lado.
  final int added;

  /// Textos de nota que pasaron a ser los de la copia.
  final int updated;

  /// Conflictos guardados.
  final int conflicts;
}

/// Escribe en esta bóveda las formas que [RenditionMergePlanner] decidió, y las
/// de los elementos nuevos.
///
/// Corre dentro de la transacción de la fusión, con la copia adjuntada y
/// [MergeWork] creado, y DESPUÉS de que entraron los elementos nuevos.
class RenditionMergeApplier {
  RenditionMergeApplier({
    required AppDatabase database,
    required MergeConflictLog conflicts,
    IdGenerator ids = const UuidV7Generator(),
  }) : _db = database,
       _log = conflicts,
       _ids = ids;

  final AppDatabase _db;
  final MergeConflictLog _log;
  final IdGenerator _ids;

  static const _incoming = kIncomingSchema;

  static const _columns = [
    'id',
    'item_id',
    'kind',
    'content',
    'relative_path',
    'is_primary',
    'created_at',
  ];

  Future<RenditionMergeResult> apply(RenditionMergePlan plan) async {
    // Las formas de los elementos nuevos entran tal cual, y esos elementos hay
    // que reprocesarlos: sus derivados no viajan.
    var added = await _db.customUpdate(
      '''
      INSERT INTO main.renditions (${_columns.join(', ')})
      SELECT ${_columns.map((c) => 'x.$c').join(', ')}
        FROM $_incoming.renditions x
        JOIN ${MergeWork.newItems} n ON n.id = x.item_id''',
      updates: {_db.renditions},
    );
    await _db.customStatement(
      'INSERT OR IGNORE INTO ${MergeWork.touchedItems} (id) '
      'SELECT id FROM ${MergeWork.newItems}',
    );

    // Dónde quedó el texto de las formas que no entran con su identificador.
    for (final entry in plan.notPlaced.entries) {
      await _mapRendition(entry.key, entry.value);
    }

    var updated = 0;
    var conflicts = 0;
    for (final change in plan.changes) {
      switch (change.action) {
        case RenditionAction.add:
          await _add(change);
          added++;
        case RenditionAction.overwrite:
          await _overwrite(change);
          updated++;
        case RenditionAction.keepBoth:
          await _keepBoth(change);
          added++;
          conflicts++;
      }
    }
    return RenditionMergeResult(
      added: added,
      updated: updated,
      conflicts: conflicts,
    );
  }

  /// Agrega la forma a un elemento que la tenía distinta o no la tenía. Es la
  /// principal solo si el elemento no tiene ya una: no puede haber dos.
  Future<void> _add(RenditionChange change) async {
    final hasPrimary = await _hasPrimary(change.itemId);
    final demoted = hasPrimary ? 1 : 0;
    await _db.customStatement(
      '''
      INSERT INTO main.renditions (${_columns.join(', ')})
      SELECT x.id, x.item_id, x.kind, x.content, x.relative_path,
             CASE WHEN ? THEN 0 ELSE x.is_primary END, x.created_at
        FROM $_incoming.renditions x WHERE x.id = ?''',
      [demoted, change.incomingId],
    );
    await _copyVersion(change);
    if (!hasPrimary) await _touch(change.itemId, change.incomingId);
  }

  /// Pone el texto de la copia en la forma de acá: una nota editada partiendo
  /// del texto de acá.
  Future<void> _overwrite(RenditionChange change) async {
    await _db.customStatement(
      '''
      UPDATE main.renditions SET
        content = (SELECT x.content FROM $_incoming.renditions x
                    WHERE x.id = renditions.id),
        relative_path = (SELECT x.relative_path FROM $_incoming.renditions x
                          WHERE x.id = renditions.id)
       WHERE id = ?''',
      [change.incomingId],
    );
    await _copyVersion(change);
    await _touch(change.itemId, change.incomingId);
    // El `rev` del elemento lo sube `EntryMergeApplier.bumpItems`, una sola
    // vez aunque hayan cambiado un campo y un texto: este archivo no escribe
    // `item`.
  }

  /// El texto de la copia entra como OTRA forma del elemento —no principal, con
  /// un identificador nuevo—, y el conflicto la señala.
  Future<void> _keepBoth(RenditionChange change) async {
    final extraId = _ids.next();
    await _db.customStatement(
      '''
      INSERT INTO main.renditions (${_columns.join(', ')})
      SELECT ?, x.item_id, x.kind, x.content, x.relative_path, 0, x.created_at
        FROM $_incoming.renditions x WHERE x.id = ?''',
      [extraId, change.incomingId],
    );
    await _mapRendition(change.incomingId, extraId);
    await _log.record(
      itemId: change.itemId,
      field: EntryField.rendition(change.incomingId),
      otherRenditionId: extraId,
      localStamp: change.localStamp,
      incomingStamp: change.incomingStamp,
    );
  }

  Future<bool> _hasPrimary(String itemId) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 FROM main.renditions WHERE item_id = ? AND is_primary = 1 '
          'LIMIT 1',
          variables: [Variable<String>(itemId)],
        )
        .get();
    return rows.isNotEmpty;
  }

  /// La versión del texto pasa a ser la de la copia; si la copia no tiene
  /// ninguna, vuelve a ser el valor de partida.
  Future<void> _copyVersion(RenditionChange change) async {
    final field = EntryField.rendition(change.incomingId);
    await _db.customStatement(
      'DELETE FROM main.field_version WHERE item_id = ? AND field_name = ?',
      [change.itemId, field],
    );
    await _db.customStatement(
      '''
      INSERT INTO main.field_version (
        item_id, field_name, updated_at, device_id,
        base_updated_at, base_device_id)
      SELECT x.item_id, x.field_name, x.updated_at, x.device_id,
             x.base_updated_at, x.base_device_id
        FROM $_incoming.field_version x
       WHERE x.item_id = ? AND x.field_name = ?''',
      [change.itemId, field],
    );
  }

  /// Marca el elemento para reprocesar si la forma es su texto principal.
  Future<void> _touch(String itemId, String renditionId) => _db.customStatement(
    '''
    INSERT OR IGNORE INTO ${MergeWork.touchedItems} (id)
    SELECT item_id FROM main.renditions
     WHERE id = ? AND item_id = ? AND is_primary = 1''',
    [renditionId, itemId],
  );

  Future<void> _mapRendition(String incomingId, String? localId) =>
      _db.customStatement(
        'INSERT OR REPLACE INTO ${MergeWork.renditionMap} '
        '(incoming_id, local_id) VALUES (?, ?)',
        [incomingId, localId],
      );
}
