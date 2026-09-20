import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_applier.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_planner.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_conflict_log.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';
import 'package:sinapsis/features/vault/data/merge/rendition_merge.dart';
import 'package:sinapsis/features/vault/data/merge/set_union_merge.dart';
import 'package:sinapsis/features/vault/data/merge/space_merge.dart';
import 'package:sinapsis/features/vault/data/merge/vocabulary_merge.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';

/// Fusiona la copia de otra bóveda con esta, sin borrar nada de lo que hay
/// (F11).
///
/// Adjunta la copia a la conexión de esta bóveda y, en UNA transacción, lee las
/// dos, decide y escribe: si algo falla a la mitad no queda nada a medias. La
/// copia se adjunta antes de abrir la transacción porque SQLite no deja
/// adjuntar dentro de una, y se suelta después, pase lo que pase.
///
/// Primero se DECIDE todo —qué campos, qué formas— leyendo las dos bóvedas tal
/// como están, y recién después se escribe, en un orden que respeta lo que
/// referencia a qué: los espacios, los elementos, sus formas, los campos de los
/// elementos que ya estaban, el vocabulario y, al final, lo que cuelga de todo
/// eso.
class VaultMerger {
  VaultMerger({
    required AppDatabase database,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  /// Fusiona [incoming] con esta bóveda. No la cierra: quien la abrió la
  /// suelta.
  Future<VaultMergeResult> merge(IncomingVault incoming) async {
    await incoming.attachTo(_db);
    try {
      final result = await _db.transaction(() async {
        await MergeWork.create(_db);
        try {
          return await _merge();
        } finally {
          await MergeWork.drop(_db);
        }
      });
      // Se escribió con SQL crudo: lo que mira estas tablas —las pantallas, por
      // sus consultas en vivo— no se enteró.
      _db.markTablesUpdated([
        _db.spaces,
        _db.knowledgeEntries,
        _db.knowledgeNotes,
        _db.knowledgeSources,
        _db.renditions,
        _db.fieldVersions,
        _db.mergeConflicts,
      ]);
      return result;
    } finally {
      await incoming.detachFrom(_db);
    }
  }

  Future<VaultMergeResult> _merge() async {
    final conflicts = MergeConflictLog(database: _db, ids: _ids, clock: _clock);
    final known = await conflicts.known();

    // Se decide todo antes de escribir nada: las dos bóvedas tal como están.
    final spaces = await SpaceMerge.compute(_db);
    final fields = await EntryMergePlanner(_db).plan(spaces, known: known);
    final texts = await RenditionMergePlanner(_db).plan(known: known);

    final entries = EntryMergeApplier(database: _db, conflicts: conflicts);
    await entries.addSpaces(spaces);
    final itemsAdded = await entries.addItems(spaces);
    final renditions = await RenditionMergeApplier(
      database: _db,
      conflicts: conflicts,
      ids: _ids,
    ).apply(texts);
    await entries.updateFields(fields);
    // Cada elemento que cambió, una vez, aunque hayan cambiado un campo y un
    // texto.
    final changedItems = {
      ...fields.updates.map((c) => c.itemId),
      ...texts.updatedItems,
    };
    await entries.bumpItems(changedItems);
    await entries.recordConflicts(fields);
    final vocabulary = await VocabularyMerge(database: _db, ids: _ids).apply();
    final unions = await SetUnionMerge(_db).apply();

    return VaultMergeResult(
      itemsAdded: itemsAdded,
      itemsUpdated: changedItems.length,
      fieldsUpdated: fields.fieldsToUpdate + renditions.updated,
      conflictsRecorded: fields.conflicts + renditions.conflicts,
      spacesAdded: spaces.toAdd.length,
      renditionsAdded: renditions.added,
      textsUpdated: renditions.updated,
      relationsAdded: unions.relations,
      highlightsAdded: unions.highlights,
      flashcardsAdded: unions.flashcards,
      flashcardsUpdated: unions.flashcardsUpdated,
      reviewsAdded: unions.reviews,
      provenancesAdded: unions.provenances,
      conversationsAdded: unions.conversations,
      messagesAdded: unions.messages,
      propertyDefinitionsAdded: vocabulary.definitions,
      propertyValuesAdded: vocabulary.values,
      propertyAliasesAdded: vocabulary.aliases,
      propertyAssignmentsAdded: vocabulary.assignments,
    );
  }
}
