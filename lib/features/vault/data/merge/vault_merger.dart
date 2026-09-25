import 'dart:io';

import 'package:meta/meta.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/bulk_write_scope.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vault/data/merge/derived_rebuild.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_applier.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_planner.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_conflict_log.dart';
import 'package:sinapsis/features/vault/data/merge/merge_gates.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';
import 'package:sinapsis/features/vault/data/merge/original_files_merge.dart';
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
/// El orden, todo dentro de la transacción:
///
/// 1. Se toma cómo está la bóveda y se instalan las **guardas**
///    ([MergeGates]): lo que una fusión nunca debe hacer queda imposible.
/// 2. Se DECIDE todo —qué campos, qué formas— leyendo las dos bóvedas tal como
///    están, y recién después se escribe, en un orden que respeta lo que
///    referencia a qué: los espacios, los elementos, sus formas, los campos de
///    los elementos que ya estaban, el vocabulario y lo que cuelga de todo eso.
/// 3. Se rehace lo derivado de lo que llegó ([DerivedRebuild]).
/// 4. Se comprueban las **compuertas**: si alguna falla, se revierte todo.
/// 5. Se copian los archivos originales que faltan. Es lo último porque el
///    disco no tiene transacciones: si algo falla desde acá, lo copiado se
///    borra ([OriginalFilesMerge.rollback]).
///
/// Confirmada la transacción, se avisa a las pantallas qué tablas cambiaron.
class VaultMerger {
  VaultMerger({
    required AppDatabase database,
    required Directory documentsDirectory,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
    @visibleForTesting this.afterWrites,
    @visibleForTesting this.afterFiles,
  }) : _db = database,
       _documents = documentsDirectory,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final Directory _documents;
  final IdGenerator _ids;
  final Clock _clock;

  /// Solo para pruebas: corre después de escribir y de rehacer lo derivado,
  /// antes de las compuertas. Sirve para romper algo a propósito y comprobar
  /// que la fusión se revierte.
  @visibleForTesting
  final Future<void> Function(AppDatabase database)? afterWrites;

  /// Solo para pruebas: corre después de copiar los archivos, antes de
  /// confirmar.
  @visibleForTesting
  final Future<void> Function(AppDatabase database)? afterFiles;

  /// Fusiona [incoming] con esta bóveda. No la cierra: quien la abrió la
  /// suelta.
  ///
  /// Lanza `VaultMergeGateException` si una compuerta no se cumple; en ese
  /// caso, y en cualquier otro fallo, ni la base ni la carpeta de documentos
  /// quedan cambiadas.
  Future<VaultMergeResult> merge(IncomingVault incoming) async {
    final files = OriginalFilesMerge(documents: _documents);
    await incoming.attachTo(_db);
    try {
      final result = await _db.transaction(() async {
        await MergeWork.create(_db);
        final gates = MergeGates(_db);
        try {
          final before = await gates.snapshot();
          await gates.installGuards();

          final written = await _write();
          // `MergeWork.touchedItems` ya está completo acá —es lo que
          // `DerivedRebuild.apply()` lee para saber qué rehacer—, así que se
          // puede pedir antes de abrir el lote: `item_search` se repuebla
          // acotado a esos elementos (F19, 19.4) en vez de la bóveda entera.
          // `chunk_search` sigue con el rebuild completo —acá sí hace falta:
          // es la fuente real del costo medido en F15/Decisión 48, no algo
          // que este lote evita tocar como en `KnowledgeEntryWriter.runBulk`—
          // y el escenario medido (una bóveda vacía) es exactamente donde el
          // lote y la bóveda son casi lo mismo, así que el rebuild completo
          // no paga de más.
          final touchedForIndex = await _touchedItems();
          final derived = await withSuspendedSearchIndexes(
            _db,
            () =>
                DerivedRebuild(database: _db, ids: _ids, clock: _clock).apply(),
            touchedItemIds: () => touchedForIndex,
          );
          await afterWrites?.call(_db);

          await gates.verify(
            before: before,
            itemsAdded: written.itemsAdded,
            rebuilt: touchedForIndex,
          );

          final copied = await files.copy(database: _db, incoming: incoming);
          await afterFiles?.call(_db);

          return written.copyWith(
            sourcesChunked: derived.sourcesChunked,
            sourcesPending: derived.sourcesPending,
            filesCopied: copied.copied,
            filesCopiedBytes: copied.copiedBytes,
            filesMissing: copied.missing,
            filesDiffering: copied.differing,
          );
        } finally {
          await gates.removeGuards();
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
        _db.sourceReferences,
        _db.sourceContributors,
        _db.fieldVersions,
        _db.mergeConflicts,
      ]);
      return result;
      // Cualquier fallo —una compuerta, la base, el disco— deja los archivos
      // como estaban: lo que se copió, se borra.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      await files.rollback();
      rethrow;
    } finally {
      await incoming.detachFrom(_db);
    }
  }

  Future<List<String>> _touchedItems() async => [
    for (final row
        in await _db
            .customSelect('SELECT id FROM ${MergeWork.touchedItems}')
            .get())
      row.read<String>('id'),
  ];

  /// Escribe lo que se decidió, sin lo derivado ni los archivos.
  Future<VaultMergeResult> _write() async {
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
    // Los datos bibliográficos llevan a las personas, que ya están fusionadas.
    await entries.updateReferences(fields);
    await entries.addReferences();
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
      flashcardOptionsAdded: unions.flashcardOptions,
      reviewsAdded: unions.reviews,
      provenancesAdded: unions.provenances,
      conversationsAdded: unions.conversations,
      messagesAdded: unions.messages,
      propertyDefinitionsAdded: vocabulary.definitions,
      propertyValuesAdded: vocabulary.values,
      propertyAliasesAdded: vocabulary.aliases,
      propertyAssignmentsAdded: vocabulary.assignments,
      valueParentsAdopted: vocabulary.parentsAdopted,
      valueParentsIgnored: vocabulary.parentsIgnored,
      habitEventsAdded: unions.habitEvents,
    );
  }
}
