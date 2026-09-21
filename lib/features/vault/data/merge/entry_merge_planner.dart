import 'package:meta/meta.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_conflict_log.dart';
import 'package:sinapsis/features/vault/data/merge/merge_fields.dart';
import 'package:sinapsis/features/vault/data/merge/reference_merge.dart';
import 'package:sinapsis/features/vault/data/merge/space_merge.dart';
import 'package:sinapsis/features/vault/data/merge/stamp_rows.dart';
import 'package:sinapsis/features/vault/domain/merge/field_merge_rule.dart';

/// La decisión sobre un campo de un elemento que las dos bóvedas tienen
/// distinto (F11).
@immutable
class FieldChange {
  const FieldChange({
    required this.itemId,
    required this.field,
    required this.decision,
    required this.localValue,
    required this.incomingValue,
    required this.localStamp,
    required this.incomingStamp,
  });

  final String itemId;
  final MergeField field;
  final FieldDecision decision;

  /// Los dos valores tal como quedan guardados, como texto —una fecha son
  /// segundos desde 1970—: para guardar la versión que no queda como conflicto.
  /// El de la copia ya está traducido a los identificadores de acá.
  final String? localValue;
  final String? incomingValue;

  /// La versión de cada lado, o `null` si nadie modificó el campo desde que se
  /// llevan versiones.
  final FieldStamp? localStamp;
  final FieldStamp? incomingStamp;

  FieldChange withDecision(FieldDecision decision) => FieldChange(
    itemId: itemId,
    field: field,
    decision: decision,
    localValue: localValue,
    incomingValue: incomingValue,
    localStamp: localStamp,
    incomingStamp: incomingStamp,
  );
}

/// Lo que hay que escribir en los campos de los elementos que las dos bóvedas
/// tienen: solo las decisiones que escriben algo —tomar el valor de la copia o
/// guardar un conflicto—.
class EntryMergePlan {
  const EntryMergePlan(this.changes);

  final List<FieldChange> changes;

  /// Los campos cuyo valor pasa a ser el de la copia.
  Iterable<FieldChange> get updates =>
      changes.where((change) => change.decision.takesIncoming);

  /// Los campos que se guardan como conflicto.
  Iterable<FieldChange> get conflictChanges =>
      changes.where((change) => change.decision.isConflict);

  int get fieldsToUpdate => updates.length;

  int get itemsToUpdate => {for (final c in updates) c.itemId}.length;

  int get conflicts => conflictChanges.length;
}

/// Decide, campo a campo, qué versión queda en los elementos que las dos
/// bóvedas tienen (F11).
///
/// Lee las dos bases —la de la copia adjuntada a la conexión de esta— y no
/// escribe nada: la vista previa la usa para contar y la fusión para aplicar,
/// con la misma regla ([FieldMergeRule]) y por eso sin poder discrepar. Solo
/// trae a Dart los campos que DIFIEREN: una copia casi igual a esta bóveda se
/// planifica leyendo casi nada.
class EntryMergePlanner {
  const EntryMergePlanner(this._db);

  final AppDatabase _db;

  static const _incoming = kIncomingSchema;

  /// [known] son los conflictos que esta bóveda ya tiene
  /// ([MergeConflictLog.known]): uno que ya se guardó no se guarda otra vez.
  Future<EntryMergePlan> plan(
    SpaceMerge spaces, {
    required Set<String> known,
  }) async {
    final byItem = <String, List<FieldChange>>{};
    for (final field in kMergeFields) {
      // Un campo compuesto —los datos bibliográficos— no es una columna: se
      // compara y se lee de otra manera, pero entra en la misma decisión, y por
      // eso cuenta para lo que un borrado no debe esconder.
      final changes = field.isComposite
          ? await ReferenceMergePlanner(_db).differing(field)
          : await _differing(field, spaces);
      for (final change in changes) {
        (byItem[change.itemId] ??= []).add(change);
      }
    }

    final writes = <FieldChange>[];
    for (final changes in byItem.values) {
      for (final change in _keepAliveWhenEdited(changes)) {
        final decision = _withoutRepeatedConflict(change, known);
        if (decision.takesIncoming || decision.isConflict) {
          writes.add(change.withDecision(decision));
        }
      }
    }
    return EntryMergePlan(writes);
  }

  /// Los campos de [field] que las dos bóvedas tienen distintos en los
  /// elementos comunes, ya decididos.
  Future<List<FieldChange>> _differing(
    MergeField field,
    SpaceMerge spaces,
  ) async {
    final table = field.table;
    // `item` ES el elemento; `note` y `source` cuelgan de él.
    final local = table == 'item' ? 'm' : 'lt';
    final incoming = table == 'item' ? 'i' : 'it';
    final joins = table == 'item'
        ? ''
        : '''
        JOIN main.$table lt ON lt.${field.keyColumn} = m.id
        JOIN $_incoming.$table it ON it.${field.keyColumn} = m.id''';

    final rows = await _db.customSelect('''
      SELECT m.id AS item_id,
             CAST($local.${field.column} AS TEXT) AS local_value,
             CAST($incoming.${field.column} AS TEXT) AS incoming_value,
             ${StampRows.columns(localVersion: 'lf', incomingVersion: 'inf', localItem: 'm', incomingItem: 'i')}
        FROM main.item m
        JOIN $_incoming.item i ON i.id = m.id$joins
        LEFT JOIN main.field_version lf
               ON lf.item_id = m.id AND lf.field_name = '${field.name}'
        LEFT JOIN $_incoming.field_version inf
               ON inf.item_id = m.id AND inf.field_name = '${field.name}'
       WHERE $local.${field.column} IS NOT $incoming.${field.column}
       ORDER BY m.id''').get();

    final changes = <FieldChange>[];
    for (final row in rows) {
      final localValue = row.read<String?>('local_value');
      var incomingValue = row.read<String?>('incoming_value');
      // El espacio de la copia, con el nombre que tiene acá.
      if (field.isSpace) incomingValue = spaces.localIdOf(incomingValue);
      final differ = localValue != incomingValue;

      final decision = StampRows.decide(row, valuesDiffer: differ);
      if (decision == FieldDecision.same) continue;

      changes.add(
        FieldChange(
          itemId: row.read<String>('item_id'),
          field: field,
          decision: decision,
          localValue: localValue,
          incomingValue: incomingValue,
          localStamp: StampRows.field(row, 'l'),
          incomingStamp: StampRows.field(row, 'i'),
        ),
      );
    }
    return changes;
  }

  /// Un borrado que llega junto a una edición del otro lado no se aplica.
  ///
  /// Si una bóveda mandó el elemento a la papelera y la otra lo siguió
  /// modificando, borrar y editar son concurrentes: quien editó no sabía del
  /// borrado, y quien borró no sabía de la edición. El elemento queda VIVO y el
  /// borrado se guarda como conflicto, en lugar de esconder en la papelera un
  /// trabajo reciente. Un borrado que llega solo —sin nada que el otro lado
  /// haya cambiado— sí se aplica.
  ///
  /// Y si las dos bóvedas lo mandaron a la papelera, a horas distintas, no hay
  /// nada que revisar: el elemento está borrado en las dos y solo difiere el
  /// momento. Queda la hora más reciente, sin conflicto.
  ///
  /// [changes] son todas las decisiones de UN elemento, también las que dejan
  /// lo de acá: saber que el lado vivo modificó algo es saber que sus campos
  /// ganan.
  List<FieldChange> _keepAliveWhenEdited(List<FieldChange> changes) {
    final deletion = changes
        .where((c) => c.field.name == EntryField.deletedAt)
        .firstOrNull;
    if (deletion == null) return changes;

    final localTrashed = deletion.localValue != null;
    final incomingTrashed = deletion.incomingValue != null;
    if (localTrashed && incomingTrashed) {
      final decision = deletion.decision;
      if (!decision.isConflict) return changes;
      final plain = decision.takesIncoming
          ? FieldDecision.takeIncoming
          : FieldDecision.keepLocal;
      return changes
          .map((c) => identical(c, deletion) ? c.withDecision(plain) : c)
          .toList();
    }
    // Vivo en las dos no puede diferir: no hay nada que proteger.
    if (localTrashed == incomingTrashed) return changes;

    final decision = deletion.decision;
    final endsTrashed =
        (decision.takesIncoming && incomingTrashed) ||
        (decision.keepsLocal && localTrashed);
    if (!endsTrashed) return changes;

    // El lado vivo es el que no borró.
    final aliveIsIncoming = localTrashed;
    final aliveEdited = changes.any(
      (c) =>
          c.field.name != EntryField.deletedAt &&
          (aliveIsIncoming ? c.decision.takesIncoming : c.decision.keepsLocal),
    );
    if (!aliveEdited) return changes;

    final kept = deletion.withDecision(
      aliveIsIncoming
          ? FieldDecision.conflictTakeIncoming
          : FieldDecision.conflictKeepLocal,
    );
    return changes.map((c) => identical(c, deletion) ? kept : c).toList();
  }

  /// Un conflicto que ya se guardó —resuelto o no— no se guarda otra vez:
  /// fusionar dos veces la misma copia no puede llenar la lista de repetidos,
  /// ni volver a molestar por lo que el usuario ya resolvió.
  FieldDecision _withoutRepeatedConflict(
    FieldChange change,
    Set<String> known,
  ) {
    final decision = change.decision;
    final key = MergeConflictLog.keyFor(
      change.itemId,
      change.field.name,
      change.incomingStamp,
    );
    if (!decision.isConflict || !known.contains(key)) return decision;
    return decision.takesIncoming
        ? FieldDecision.takeIncoming
        : FieldDecision.keepLocal;
  }
}
