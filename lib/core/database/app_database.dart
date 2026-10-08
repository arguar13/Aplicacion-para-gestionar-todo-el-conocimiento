import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/device_identity.dart';
import 'package:sinapsis/core/database/migrations/backfill_chunks_v16.dart';
import 'package:sinapsis/core/database/migrations/drop_legacy_model_v19.dart';
import 'package:sinapsis/core/database/migrations/repoint_item_references_v18.dart';
import 'package:sinapsis/core/database/migrations/seed_author_category_v22.dart';
import 'package:sinapsis/core/database/migrations/seed_system_property_categories_v9.dart';
import 'package:sinapsis/core/database/pre_migration_backup.dart';
import 'package:sinapsis/core/database/reference_triggers.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/database/tables/ai_runs.dart';
import 'package:sinapsis/core/database/tables/attachment_downloads.dart';
import 'package:sinapsis/core/database/tables/chat_messages.dart';
import 'package:sinapsis/core/database/tables/chunks.dart';
import 'package:sinapsis/core/database/tables/conversations.dart';
import 'package:sinapsis/core/database/tables/embeddings.dart';
import 'package:sinapsis/core/database/tables/field_versions.dart';
import 'package:sinapsis/core/database/tables/flashcard_options.dart';
import 'package:sinapsis/core/database/tables/flashcards.dart';
import 'package:sinapsis/core/database/tables/habit_events.dart';
import 'package:sinapsis/core/database/tables/highlights.dart';
import 'package:sinapsis/core/database/tables/inline_links.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/knowledge_notes.dart';
import 'package:sinapsis/core/database/tables/knowledge_sources.dart';
import 'package:sinapsis/core/database/tables/merge_conflicts.dart';
import 'package:sinapsis/core/database/tables/merged_provenances.dart';
import 'package:sinapsis/core/database/tables/migration_issues.dart';
import 'package:sinapsis/core/database/tables/note_templates.dart';
import 'package:sinapsis/core/database/tables/notebook_items.dart';
import 'package:sinapsis/core/database/tables/notebooks.dart';
import 'package:sinapsis/core/database/tables/processing_checkpoints.dart';
import 'package:sinapsis/core/database/tables/properties.dart';
import 'package:sinapsis/core/database/tables/relations.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';
import 'package:sinapsis/core/database/tables/review_log.dart';
import 'package:sinapsis/core/database/tables/saved_views.dart';
import 'package:sinapsis/core/database/tables/source_references.dart';
import 'package:sinapsis/core/database/tables/spaces.dart';
import 'package:sinapsis/core/database/tables/suggestions.dart';
import 'package:sinapsis/core/database/tables/trashed_contents.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/database/vocabulary_hierarchy.dart';
// Los enums se importan acá aunque este archivo no los nombre: el código
// generado es un `part` de este archivo y hereda sus imports, no los de las
// tablas donde cada enum se declara. Sin esto, `app_database.g.dart` no
// compila — y `flutter analyze` NO lo detecta, porque analysis_options
// excluye los archivos generados. Solo se ve al compilar.
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/domain/entities/vocabulary_hierarchy.dart';
import 'package:sinapsis/core/logging/console_app_logger.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

part 'app_database.g.dart';

/// La base de datos local. Todo lo que Sinapsis guarda vive acá o en archivos
/// que esta base referencia.
@DriftDatabase(
  tables: [
    Renditions,
    Relations,
    Highlights,
    Spaces,
    Flashcards,
    FlashcardOptions,
    Conversations,
    ChatMessages,
    PropertyDefinitions,
    PropertyValues,
    ItemPropertyValues,
    PropertyAliases,
    KnowledgeEntries,
    KnowledgeSources,
    KnowledgeNotes,
    Chunks,
    Embeddings,
    MigrationIssues,
    Suggestions,
    MergedProvenances,
    InlineLinks,
    FieldVersions,
    MergeConflicts,
    ReviewLogs,
    SourceReferences,
    SourceContributors,
    SavedViews,
    NoteTemplates,
    Notebooks,
    NotebookItems,
    HabitEvents,
    ProcessingCheckpoints,
    AiRuns,
    AiRejections,
    AiFieldChanges,
    NoteEmbeddings,
    PropertyValueEmbeddings,
    AttachmentDownloads,
    TrashedContents,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Para los tests, que pasan una base en memoria.
  ///
  /// [deviceId] es quién escribe en esta base: lo llevan `item.device_id` y
  /// cada fila de `field_version`. Los tests que no lo necesitan lo dejan en
  /// [kUnspecifiedDeviceId].
  AppDatabase(super.executor, {this.deviceId = kUnspecifiedDeviceId});

  /// La base real, en el directorio de datos de la app.
  ///
  /// `drift_flutter` resuelve por su cuenta dónde va el archivo en cada
  /// plataforma y carga las librerías nativas de SQLite que hagan falta. En
  /// la web hace falta decirle además dónde están los dos archivos que no
  /// vienen empaquetados —`sqlite3.wasm` y el worker—, traídos con
  /// `tool/fetch_sqlite3_wasm.sh` (ver la decisión 9 en
  /// docs/arquitectura.md). Fuera de la web, `web:` no se usa para nada.
  ///
  /// Antes de que drift migre una base de una versión anterior, `setup` la
  /// respalda (ver `backupBeforeMigration`). Es el único momento posible:
  /// dentro de `onUpgrade` ya hay una transacción abierta y `VACUUM INTO` no
  /// puede correr en una. En web no hay archivo que copiar y `native` se
  /// ignora: ahí la migración, al ser transaccional, revierte si falla.
  AppDatabase.open({required this.deviceId})
    : super(
        driftDatabase(
          name: 'sinapsis',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
          native: const DriftNativeOptions(setup: _backupBeforeMigrating),
        ),
      );

  /// Quién escribe en esta base: el identificador de esta instalación (ver
  /// `DeviceIdentity`). Es una propiedad de la CONEXIÓN y no de la base: la
  /// base viaja entre equipos en una copia, el identificador no.
  final String deviceId;

  /// La versión del esquema. Es una constante y no solo el getter porque el
  /// respaldo previo a migrar corre antes de que exista la instancia, y
  /// necesita saber a qué versión está por migrarse la base.
  static const currentSchemaVersion = 39;

  /// La versión de esquema más antigua que esta versión de la app sabe
  /// actualizar. Una base anterior se rechaza con [SchemaTooOldException].
  static const minimumUpgradableSchemaVersion = 15;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createSearchIndex();
      await _createChunkSearchIndex();
      await _createVocabularyHierarchyTriggers();
      await _createReferenceTriggers();
      await seedSystemPropertyCategories(this, ids: const UuidV7Generator());
    },
    onUpgrade: (migrator, from, to) async {
      // Compatibilidad mínima de actualización (F10): los pasos de v2 a v15 se
      // retiraron con sus pruebas —leían las tablas que F10 retira—. Una base
      // más vieja se corta acá, antes de tocar nada y con un mensaje que dice
      // qué hacer, en vez de fallar más adelante por una tabla que no existe.
      // La copia previa de la base ya se hizo.
      if (from < minimumUpgradableSchemaVersion) {
        throw SchemaTooOldException(
          from: from,
          minimum: minimumUpgradableSchemaVersion,
        );
      }
      // Una sola transacción para todos los pasos: las migraciones de drift NO
      // son transaccionales por sí solas —cada sentencia se confirma sola—, y
      // sin esto un conteo que no cierra, o cualquier error a mitad de camino,
      // dejaba hecho lo que ya se había hecho. Con ella, si algún paso lanza
      // no queda nada de la migración: la base sigue en la versión de antes,
      // lista para reintentar, además de la copia previa. (`alterTable` abre
      // la suya, que dentro de esta es un punto de guardado.)
      await transaction(() async {
        // Chunks vivos y búsqueda por chunks (F10): `chunk` gana una clave
        // entera propia —para que el índice de texto no dependa de un `rowid`
        // que un `VACUUM` puede renumerar—, `item` gana `notes`, se fragmenta
        // toda fuente que no lo estaba y se construye el índice de texto de los
        // chunks. Todo aditivo: el índice de siempre, `item_search`, no se toca
        // hasta que la búsqueda deje de usarlo. La copia previa de la base ya
        // se hizo, y si algún conteo no coincide, la migración entera revierte.
        if (from < 16) {
          final chunksBefore = await _count('chunks');
          await migrator.alterTable(
            TableMigration(chunks, newColumns: [chunks.rowKey]),
          );
          final chunksAfter = await _count('chunks');
          if (chunksBefore != chunksAfter) {
            throw StateError(
              'La migración a v16 cambió la cantidad de chunks: había '
              '$chunksBefore y quedaron $chunksAfter.',
            );
          }
          final orphans = await customSelect(
            'SELECT COUNT(*) AS n FROM embeddings '
            'WHERE chunk_id NOT IN (SELECT id FROM chunks)',
          ).getSingle();
          if (orphans.read<int>('n') != 0) {
            throw StateError(
              'La migración a v16 dejó ${orphans.read<int>('n')} embeddings '
              'sin su chunk.',
            );
          }
          await migrator.addColumn(knowledgeEntries, knowledgeEntries.notes);

          await backfillChunksAndNotes(
            this,
            ids: const UuidV7Generator(),
            logger: ConsoleAppLogger(),
          );

          // Recién ahora, con todos los chunks adentro: indexar de una vez es
          // mucho más rápido que chunk por chunk.
          await _createChunkSearchIndex();
          await customStatement(rebuildChunkSearch);
          final indexed = await _count('chunk_search_docsize');
          final chunksNow = await _count('chunks');
          if (indexed != chunksNow) {
            throw StateError(
              'El índice de texto de los chunks quedó con $indexed entradas y '
              'hay $chunksNow chunks.',
            );
          }
        }
        // Las claves foráneas pasan de `items` a `item` (F10), y el índice de
        // texto de los elementos —`item_search`, que desde F10 tiene título,
        // subtítulo y el texto de las notas; el de las fuentes lo indexa
        // `chunk_search` por chunks— se rehace sobre `item`: desde acá `items`
        // deja de ser la fuente de nada y sus triggers dejarían de dispararse.
        // El paso completa el espejo si faltaba algún elemento, y los conteos
        // de lo que el usuario creó son compuerta: si alguno cambia, la
        // migración entera revierte. La copia previa de la base ya se hizo.
        //
        // No hay paso `from < 17`: v17 solo rehacía `item_search`, y este paso
        // lo rehace con la forma definitiva.
        if (from < 18) {
          final before = await captureVaultCounts(this);
          await repointItemReferences(
            this,
            migrator,
            ids: const UuidV7Generator(),
            logger: ConsoleAppLogger(),
          );
          await _rebuildItemSearchIndex();
          await _requireSameCounts(before, step: 'v18');
        }
        // El modelo viejo se suelta (F10): `items`, `sources`, `tags` y
        // `item_tags`, y la columna `source.full_text` —el texto íntegro vive
        // una vez, en la forma de texto principal—. Antes de quitar la columna
        // se comprueba que ninguna fuente tenga su texto solo ahí; los conteos
        // de lo que el usuario creó y del modelo nuevo son compuerta, y la
        // migración entera revierte si alguno cambia.
        if (from < 19) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await dropLegacyModel(this, migrator, logger: ConsoleAppLogger());
          // Los dos índices de `items` que las consultas de la Biblioteca
          // usan —filtrar por espacio, ordenar por última modificación— y que
          // `item` no tenía: sin ellos esas consultas recorrerían la tabla
          // entera.
          await migrator.createIndex(idxKnowledgeEntriesSpace);
          await migrator.createIndex(idxKnowledgeEntriesUpdatedAt);
          await _requireSameCounts(before, step: 'v19', tables: tables);
        }
        // Durabilidad (F11): versión por campo, conflictos de fusión, historial
        // de repasos, de dónde salió cada tarjeta y un índice para la
        // papelera. Todo aditivo —tablas nuevas y columnas nulas—: ninguna fila
        // existente cambia, y los conteos de todo lo anterior son compuerta.
        if (from < 20) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await migrator.createTable(fieldVersions);
          await migrator.createTable(mergeConflicts);
          await migrator.createIndex(idxMergeConflictResolved);
          await migrator.createIndex(idxMergeConflictItem);
          await migrator.createTable(reviewLogs);
          await migrator.createIndex(idxReviewLogFlashcard);
          // Una base que pasó por v18 en esta misma actualización ya trae las
          // tres columnas —la reconstrucción de `flashcards` las creó—.
          for (final column in [
            flashcards.sourceChunkId,
            flashcards.sourceCharStart,
            flashcards.sourceCharEnd,
          ]) {
            if (!await _columnExists('flashcards', column.name)) {
              await migrator.addColumn(flashcards, column);
            }
          }
          await _requireSameCounts(before, step: 'v20', tables: tables);
        }
        // Jerarquía del vocabulario (F13): un valor puede tener padre dentro
        // de su categoría. Todo aditivo —dos columnas, un índice y cuatro
        // triggers—: todos los valores que ya había quedan en la raíz, con
        // profundidad 0, y nadie pierde nada. Los conteos de todo lo anterior
        // son compuerta.
        if (from < 21) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await migrator.addColumn(propertyValues, propertyValues.parentId);
          await migrator.addColumn(propertyValues, propertyValues.depth);
          await migrator.createIndex(idxPropertyValuesParent);
          await _createVocabularyHierarchyTriggers();
          await _requireSameCounts(before, step: 'v21', tables: tables);
        }
        // Biblioteca académica (F15): los datos bibliográficos de una fuente y
        // sus personas, el nombre partido en el vocabulario y la categoría de
        // sistema «Autor». Todo aditivo —dos tablas, cuatro columnas nulas, dos
        // índices y cuatro triggers—: ninguna fila existente cambia. La única
        // que se toca es una categoría «Autor» que alguien hubiera creado a
        // mano, que se reusa; ver `ensureAuthorCategory`, que anota en
        // `migration_issues` lo poco que puede perder (una jerarquía). Los
        // conteos de todo lo anterior son compuerta, y la migración entera
        // revierte si alguno cambia.
        if (from < 22) {
          // `property_definitions` se comprueba aparte: la categoría «Autor»
          // puede ser nueva, y entonces sube en una.
          final tables = [
            ...VaultCounts.userDataTables.where(
              (t) => t != 'property_definitions',
            ),
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          final definitionsBefore = await _count('property_definitions');
          for (final column in [
            propertyValues.nameFamily,
            propertyValues.nameGiven,
            propertyValues.nameSuffix,
            propertyValues.isInstitution,
          ]) {
            await migrator.addColumn(propertyValues, column);
          }
          await migrator.createTable(sourceReferences);
          await migrator.createIndex(idxSourceReferenceDoi);
          await migrator.createIndex(idxSourceReferenceIsbn);
          await migrator.createTable(sourceContributors);
          await migrator.createIndex(idxSourceContributorPerson);
          await _createReferenceTriggers();
          await ensureAuthorCategory(this, ids: const UuidV7Generator());
          final definitionsAfter = await _count('property_definitions');
          if (definitionsAfter != definitionsBefore &&
              definitionsAfter != definitionsBefore + 1) {
            throw StateError(
              'La migración a v22 cambió la cantidad de categorías: había '
              '$definitionsBefore y quedaron $definitionsAfter.',
            );
          }
          await _requireSameCounts(before, step: 'v22', tables: tables);
        }
        // Cuadernos y vistas (F16): vistas guardadas de la Biblioteca —filtro,
        // orden y modo, con nombre— y plantillas de nota. Dos tablas nuevas,
        // ninguna columna tocada: nada existente cambia. Los conteos de todo
        // lo anterior son compuerta.
        if (from < 23) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await migrator.createTable(savedViews);
          await migrator.createTable(noteTemplates);
          await _requireSameCounts(before, step: 'v23', tables: tables);
        }
        // Cuadernos (F16): un subconjunto con nombre de la bóveda, manual o
        // por consulta guardada (D1). Dos tablas nuevas, ninguna columna
        // tocada: nada existente cambia. Los conteos de todo lo anterior,
        // vistas guardadas y plantillas incluidas —ya existen desde v23—,
        // son compuerta.
        if (from < 24) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await migrator.createTable(notebooks);
          await migrator.createTable(notebookItems);
          await _requireSameCounts(before, step: 'v24', tables: tables);
        }
        // El chat se acota a un cuaderno (F16): una conversación recuerda a
        // cuál. Una columna nueva y nula en `Conversations`, ninguna fila
        // existente cambia —`null` sigue significando «toda la bóveda», lo
        // que ya valía antes de que la columna existiera—. Los conteos de
        // lo anterior, cuadernos incluidos —ya existen desde v24—, son la
        // compuerta.
        if (from < 25) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await migrator.addColumn(conversations, conversations.notebookId);
          await _requireSameCounts(before, step: 'v25', tables: tables);
        }
        // La marca de generado por IA (F16, D3): tres columnas nuevas y
        // nulas —`derived_edited` en falso, no nula— en `note`, ninguna
        // fila existente cambia de sentido: una nota de antes de esto ya
        // era «no generada», que es justo lo que `generated_by_model` nulo
        // sigue significando. Los conteos de lo anterior son compuerta.
        if (from < 26) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await migrator.addColumn(
            knowledgeNotes,
            knowledgeNotes.generatedByModel,
          );
          await migrator.addColumn(knowledgeNotes, knowledgeNotes.generatedAt);
          await migrator.addColumn(
            knowledgeNotes,
            knowledgeNotes.derivedEdited,
          );
          await _requireSameCounts(before, step: 'v26', tables: tables);
        }
        // Exportación incremental a Anki (F17, D4): una columna nueva y nula
        // en `flashcards`, ninguna fila existente cambia —nunca se exportó,
        // que es justo lo que nulo sigue significando—. Los conteos de lo
        // anterior son compuerta.
        //
        // Una base que pasó por v18 en esta misma actualización ya trae la
        // columna —la reconstrucción de `flashcards` en `repointItem
        // References` usa la definición de HOY de la tabla—, mismo motivo
        // que el `_columnExists` de v20 más arriba.
        if (from < 27) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          if (!await _columnExists(
            'flashcards',
            flashcards.lastExportedAt.name,
          )) {
            await migrator.addColumn(flashcards, flashcards.lastExportedAt);
          }
          await _requireSameCounts(before, step: 'v27', tables: tables);
        }
        // La racha (F17, D6): una tabla nueva y vacía, `habit_event`, para
        // las dos acciones que no dejan rastro con fecha en ningún otro
        // lado —triar la Bandeja, resolver algo en Vocabulario—; repasar
        // una tarjeta y editar una nota viva ya lo tienen (`review_log`,
        // `field_version`). Ninguna fila existente cambia. Los conteos de
        // lo anterior son compuerta.
        if (from < 28) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await migrator.createTable(habitEvents);
          await migrator.createIndex(idxHabitEventsOccurred);
          await _requireSameCounts(before, step: 'v28', tables: tables);
        }
        // Quizzes generados (F20): una tarjeta gana `kind` —`freeRecall` por
        // defecto para toda tarjeta que ya existía, aditivo, ninguna cambia
        // de forma— y las de opción múltiple guardan sus opciones en una
        // tabla nueva, `flashcard_options`, vacía hasta que se genere la
        // primera. Los conteos de todo lo anterior son compuerta.
        //
        // Una base que pasó por v18 en esta misma actualización ya trae la
        // columna `kind` —la reconstrucción de `flashcards` usa la
        // definición de HOY de la tabla—, mismo motivo que el
        // `_columnExists` de v20/v27 más arriba.
        if (from < 29) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          if (!await _columnExists('flashcards', flashcards.kind.name)) {
            await migrator.addColumn(flashcards, flashcards.kind);
          }
          await migrator.createTable(flashcardOptions);
          await migrator.createIndex(idxFlashcardOptionsFlashcard);
          await _requireSameCounts(before, step: 'v29', tables: tables);
        }
        // De qué elemento sale cada opción (F20): campo PROPIO, no
        // derivado del chunk —a diferencia de `sourceChunkId`, tiene que
        // seguir valiendo aunque el texto de la fuente se rehaga y el
        // chunk se pierda—, mismo criterio que `Flashcard.itemId`. Aditivo;
        // una opción ya guardada con `sourceChunkId` se rellena sola desde
        // el elemento de ese chunk, así no queda huérfana por haber nacido
        // antes de esta columna.
        if (from < 30) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          if (!await _columnExists(
            'flashcard_options',
            flashcardOptions.sourceItemId.name,
          )) {
            await migrator.addColumn(
              flashcardOptions,
              flashcardOptions.sourceItemId,
            );
          }
          await customStatement(
            'UPDATE flashcard_options SET source_item_id = ( '
            'SELECT item_id FROM chunks WHERE chunks.id = '
            'flashcard_options.source_chunk_id) '
            'WHERE source_chunk_id IS NOT NULL '
            'AND source_item_id IS NULL',
          );
          await _requireSameCounts(before, step: 'v30', tables: tables);
        }
        // El avance guardado de los trabajos largos (F21): una tabla nueva,
        // vacía, que ninguna fila de antes necesita. Aditiva; los conteos
        // de todo lo anterior son compuerta.
        if (from < 31) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
            ...VaultCounts.quizTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await migrator.createTable(processingCheckpoints);
          await _requireSameCounts(before, step: 'v31', tables: tables);
        }
        // El idioma del original (F22): con qué idioma se transcribe un
        // audio, y en cuál están los subtítulos guardados de YouTube. Una
        // columna nueva, nula en todo lo de antes —"no se sabe", que se
        // transcribe en español como siempre—. Aditiva; los conteos son
        // compuerta.
        if (from < 32) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
            ...VaultCounts.quizTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          if (!await _columnExists('source', knowledgeSources.language.name)) {
            await migrator.addColumn(
              knowledgeSources,
              knowledgeSources.language,
            );
          }
          // El índice de los chunks pasa a indexar también las palabras
          // cortadas por guion al final del renglón, unidas: el texto de un
          // PDF se guarda desde F22 tal cual, con sus renglones (ver
          // `chunkSearchText`). Se rehace entero con la definición nueva.
          await _rebuildChunkSearchIndex();
          await _requireSameCounts(before, step: 'v32', tables: tables);
        }

        // Cuándo se dice cada palabra de una transcripción (F23): una
        // columna nueva en `renditions`, nula en todo lo de antes —"no se
        // midió"—. Aditiva; los conteos son compuerta. Puede existir ya: el
        // paso v18 reconstruye `renditions` con su definición de hoy.
        if (from < 33) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
            ...VaultCounts.quizTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          if (!await _columnExists('renditions', renditions.wordTimings.name)) {
            await migrator.addColumn(renditions, renditions.wordTimings);
          }
          await _requireSameCounts(before, step: 'v33', tables: tables);
        }

        // La IA organiza sola, y todo se puede corregir (F27): quién hizo cada
        // vínculo, tarjeta y propiedad —la persona o la IA—, con qué pasada,
        // para poder deshacerla entera, y la memoria de lo que la persona dijo
        // que «no era». Aditiva: dos tablas nuevas y vacías, y columnas que, en
        // lo que ya había, dicen «lo hizo la persona» (`origin` en `user`,
        // `ai_run_id` nulo). Los conteos de todo lo anterior son compuerta.
        //
        // Las columnas pueden existir ya: el paso v18 reconstruye `relations`,
        // `flashcards` e `item_property_values` con su definición de hoy.
        if (from < 34) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
            ...VaultCounts.quizTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          await migrator.createTable(aiRuns);
          await migrator.createIndex(idxAiRunsItem);
          await migrator.createIndex(idxAiRunsStarted);
          await migrator.createTable(aiRejections);
          final provenanceColumns =
              <(TableInfo<Table, Object?>, List<GeneratedColumn>)>[
                (
                  relations,
                  [relations.origin, relations.confidence, relations.aiRunId],
                ),
                (flashcards, [flashcards.origin, flashcards.aiRunId]),
                (itemPropertyValues, [itemPropertyValues.aiRunId]),
              ];
          for (final (table, columns) in provenanceColumns) {
            for (final column in columns) {
              if (!await _columnExists(table.actualTableName, column.name)) {
                await migrator.addColumn(table, column);
              }
            }
          }
          await migrator.createIndex(idxRelationsAiRun);
          await migrator.createIndex(idxFlashcardsAiRun);
          await migrator.createIndex(idxItemPropertyValuesAiRun);
          await _requireSameCounts(before, step: 'v34', tables: tables);
        }

        // Lo que dejó pendiente el motor de F27: que deshacer una pasada se
        // lleve también el tema y los datos de la referencia que completó
        // (`ai_field_changes`), que la cola sepa si una nota cambió de
        // contenido y no solo de largo (`ai_runs.content_simhash`), que las
        // notas tengan vectores para ser destino de un vínculo
        // (`note_embedding`) y que el vocabulario que ve el modelo se elija
        // por cercanía (`property_value_embedding`). Aditiva: tablas nuevas y
        // vacías, y una columna nula en las pasadas que ya había. Los conteos
        // de todo lo anterior son compuerta.
        //
        // La columna puede existir ya: el paso v34 crea `ai_runs` con su
        // definición de hoy.
        if (from < 35) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
            ...VaultCounts.quizTables,
            ...VaultCounts.aiTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          if (!await _columnExists('ai_runs', aiRuns.contentSimhash.name)) {
            await migrator.addColumn(aiRuns, aiRuns.contentSimhash);
          }
          await migrator.createTable(aiFieldChanges);
          await migrator.createIndex(idxAiFieldChangesRun);
          await migrator.createTable(noteEmbeddings);
          await migrator.createTable(propertyValueEmbeddings);
          await _requireSameCounts(before, step: 'v35', tables: tables);
        }

        // Bajar todo de páginas y publicaciones (F30): las formas ganan lo
        // que hace falta para el «Contenido» de un elemento —título, de
        // dónde se bajó, tipo, tamaño, orden, y de qué archivo es cada
        // texto— y la lista de trabajo de lo que ofrece cada página. Aditiva:
        // columnas nulas en las formas que ya había y una tabla nueva y
        // vacía. Los conteos de todo lo anterior son compuerta.
        //
        // Las columnas pueden existir ya: el paso v18 reconstruye
        // `renditions` con su definición de hoy.
        if (from < 36) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
            ...VaultCounts.quizTables,
            ...VaultCounts.aiTables,
            ...VaultCounts.aiFieldChangeTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          for (final column in [
            renditions.title,
            renditions.originUrl,
            renditions.mimeType,
            renditions.sizeBytes,
            renditions.position,
            renditions.textOf,
          ]) {
            if (!await _columnExists('renditions', column.name)) {
              await migrator.addColumn(renditions, column);
            }
          }
          await migrator.createIndex(idxRenditionsTextOf);
          await migrator.createTable(attachmentDownloads);
          await migrator.createIndex(idxAttachmentDownloadsItem);
          await _requireSameCounts(before, step: 'v36', tables: tables);
        }

        // Qué le pidieron a cada pasada de la IA (F30): organizar el elemento
        // o solo hacerle tarjetas (`ai_runs.scope`). Hasta acá una pasada de
        // solo tarjetas se marcaba con una fila de `ai_field_changes` con el
        // campo `flashcardsOnly`, que no era un dato del elemento; esas
        // marcas pasan a la columna y se borran. Todo lo demás, con los
        // conteos como compuerta; `ai_field_changes` tiene que bajar
        // exactamente en las marcas convertidas.
        //
        // La columna puede existir ya: el paso v34 crea `ai_runs` con su
        // definición de hoy.
        if (from < 37) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
            ...VaultCounts.quizTables,
            ...VaultCounts.aiTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          final changesBefore = await _count('ai_field_changes');
          if (!await _columnExists('ai_runs', aiRuns.scope.name)) {
            await migrator.addColumn(aiRuns, aiRuns.scope);
          }
          final legacy = [Variable.withString(kLegacyFlashcardsOnlyField)];
          final marks = (await customSelect(
            'SELECT COUNT(*) AS n FROM ai_field_changes WHERE field = ?',
            variables: legacy,
          ).getSingle()).read<int>('n');
          await customUpdate(
            "UPDATE ai_runs SET scope = '${AiRunScope.flashcards.name}' "
            'WHERE id IN (SELECT ai_run_id FROM ai_field_changes '
            'WHERE field = ?)',
            variables: legacy,
            updates: {aiRuns},
          );
          await customUpdate(
            'DELETE FROM ai_field_changes WHERE field = ?',
            variables: legacy,
            updates: {aiFieldChanges},
            updateKind: UpdateKind.delete,
          );
          await _requireSameCounts(before, step: 'v37', tables: tables);
          final changesAfter = await _count('ai_field_changes');
          if (changesAfter != changesBefore - marks) {
            throw StateError(
              'La migración a v37 cambió la cantidad de filas de '
              'ai_field_changes ($changesBefore → $changesAfter); tenía que '
              'bajar solo en las $marks marcas de solo tarjetas.',
            );
          }
        }

        // La Bandeja de texto (F30, decisión 68): al triar un libro se elige
        // qué pasa —el texto, el libro o los dos—, y lo que se suelta espera
        // 30 días en la papelera del contenido (`content_trash`). «Solo el
        // libro» deja una marca en la fuente (`source.only_file`) para que la
        // cola no le vuelva a extraer el texto sola. Aditiva: una tabla nueva
        // y vacía y una columna que en todo lo de antes dice «no» —nada se
        // soltó todavía—. Los conteos de todo lo anterior son compuerta.
        //
        // La columna puede existir ya: los pasos que crean `source` lo hacen
        // con su definición de hoy.
        if (from < 38) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
            ...VaultCounts.quizTables,
            ...VaultCounts.aiTables,
            ...VaultCounts.aiFieldChangeTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          if (!await _columnExists('source', knowledgeSources.onlyFile.name)) {
            await migrator.addColumn(
              knowledgeSources,
              knowledgeSources.onlyFile,
            );
          }
          await migrator.createTable(trashedContents);
          await migrator.createIndex(idxContentTrashItem);
          await migrator.createIndex(idxContentTrashTrashedAt);
          await _requireSameCounts(before, step: 'v38', tables: tables);
        }

        // Repasar sin depender de Anki (F31, decisión 69): las tarjetas ganan
        // lo que hace falta para pausarlas, posponerlas, aprenderlas en pasos
        // cortos y agruparlas con sus hermanas (`suspended`, `buried_until`,
        // `learning_step`, `group_id`, `cloze_index`), y cada fila de
        // `review_log` guarda de qué etapa partió el repaso y lo necesario
        // para deshacerlo. Aditiva: en todo lo de antes, «no pausada, no
        // pospuesta, sin paso, sin hermanas» —el calendario programado sigue
        // igual—. La única fila que se toca es la etapa de los repasos viejos:
        // la primera respuesta de cada tarjeta (`interval_before = 0`) pasa a
        // `newCard`, para que los límites del día cuenten bien desde el primer
        // día. Los conteos de todo lo anterior son compuerta.
        //
        // Las columnas pueden existir ya: el paso v18 reconstruye `flashcards`
        // y el v20 crea `review_log` con su definición de hoy.
        if (from < 39) {
          final tables = [
            ...VaultCounts.userDataTables,
            ...VaultCounts.modelTables,
            ...VaultCounts.durabilityTables,
            ...VaultCounts.referenceTables,
            ...VaultCounts.viewsAndTemplatesTables,
            ...VaultCounts.notebookTables,
            ...VaultCounts.habitTables,
            ...VaultCounts.quizTables,
            ...VaultCounts.aiTables,
            ...VaultCounts.aiFieldChangeTables,
            ...VaultCounts.contentTrashTables,
          ];
          final before = await captureVaultCounts(this, tables: tables);
          for (final column in [
            flashcards.suspended,
            flashcards.buriedUntil,
            flashcards.learningStep,
            flashcards.groupId,
            flashcards.clozeIndex,
          ]) {
            if (!await _columnExists('flashcards', column.name)) {
              await migrator.addColumn(flashcards, column);
            }
          }
          await migrator.createIndex(idxFlashcardsGroup);
          final reviewLogColumns = <GeneratedColumn>[
            reviewLogs.phaseBefore,
            reviewLogs.stepBefore,
            reviewLogs.stepAfter,
            reviewLogs.dueBefore,
            reviewLogs.lastReviewedBefore,
            reviewLogs.repetitionsBefore,
          ];
          for (final column in reviewLogColumns) {
            if (!await _columnExists('review_log', column.name)) {
              await migrator.addColumn(reviewLogs, column);
            }
          }
          await customUpdate(
            "UPDATE review_log SET phase_before = '${CardPhase.newCard.name}' "
            'WHERE interval_before = 0',
            updates: {reviewLogs},
          );
          await _requireSameCounts(before, step: 'v39', tables: tables);
        }
      });
    },
    beforeOpen: (details) async {
      // SQLite trae las claves foráneas DESACTIVADAS por defecto, por
      // compatibilidad con versiones de hace veinte años. Sin este pragma,
      // todas las cascadas del esquema son decoración: borrar un elemento
      // dejaría sus formas y sus subrayados flotando para siempre, ocupando
      // lugar y apareciendo en consultas que no deberían encontrarlos.
      //
      // Va en `beforeOpen` y no en la migración porque es una propiedad *de
      // la conexión*, no del esquema: hay que volver a activarlo cada vez que
      // se abre la base.
      await customStatement('PRAGMA foreign_keys = ON');

      // El índice de la papelera: ver `createTrashIndex`. Va acá y no en la
      // migración porque no es parte del modelo de datos —drift no modela un
      // índice parcial— sino un objeto de la base, como `item_search`, y así
      // lo tiene también una base que ya estaba en v20 antes de que existiera.
      await customStatement(dropSupersededTrashIndex);
      await customStatement(createTrashIndex);
    },
  );

  /// Crea los triggers que hacen cumplir la jerarquía del vocabulario: ver
  /// `vocabulary_hierarchy.dart`.
  Future<void> _createVocabularyHierarchyTriggers() async {
    for (final trigger in vocabularyHierarchyTriggers) {
      await customStatement(trigger);
    }
  }

  /// Crea los triggers de las referencias bibliográficas: ver
  /// `reference_triggers.dart`.
  Future<void> _createReferenceTriggers() async {
    for (final trigger in referenceTriggers) {
      await customStatement(trigger);
    }
  }

  /// Crea la tabla de búsqueda y sus triggers.
  ///
  /// Va por `customStatement` porque drift no modela tablas virtuales de
  /// FTS5 en su API de esquema; el SQL está en `search_index.dart`, con la
  /// explicación de por qué cada trigger existe.
  Future<void> _createSearchIndex() async {
    await customStatement(createSearchTable);
    for (final trigger in searchTriggers) {
      await customStatement(trigger);
    }
  }

  /// Rehace `item_search` con la forma de v17: título, subtítulo y texto de
  /// las notas. Quita los triggers y la tabla de antes —con el cuerpo de todas
  /// las formas— y los vuelve a crear.
  Future<void> _rebuildItemSearchIndex() async {
    for (final name in [...searchTriggerNames, ...legacySearchTriggerNames]) {
      await customStatement('DROP TRIGGER IF EXISTS $name');
    }
    await customStatement('DROP TABLE IF EXISTS item_search');
    await _createSearchIndex();
    await customStatement(populateItemSearch);

    final indexed = await _count('item_search');
    final items = await _count('item');
    if (indexed != items) {
      throw StateError(
        'El índice de texto de los elementos quedó con $indexed entradas y '
        'hay $items elementos.',
      );
    }
  }

  /// Crea el índice de texto de los chunks, su vista de vocabulario y los
  /// triggers que lo mantienen.
  Future<void> _createChunkSearchIndex() async {
    await customStatement(createChunkSearchTextView);
    await customStatement(createChunkSearchTable);
    await customStatement(createChunkVocabTable);
    for (final trigger in chunkSearchTriggers) {
      await customStatement(trigger);
    }
  }

  /// Suelta el índice de texto de los chunks —triggers, vocabulario, tabla y
  /// vista— y lo vuelve a crear y a llenar con la definición de hoy. El
  /// índice es derivado: rehacerlo no toca ningún dato. Exige al final una
  /// entrada por chunk.
  Future<void> _rebuildChunkSearchIndex() async {
    for (final trigger in chunkSearchTriggerNames) {
      await customStatement('DROP TRIGGER IF EXISTS $trigger');
    }
    await customStatement('DROP TABLE IF EXISTS chunk_vocab');
    await customStatement('DROP TABLE IF EXISTS chunk_search');
    await customStatement('DROP VIEW IF EXISTS chunk_search_text');
    await _createChunkSearchIndex();
    await customStatement(rebuildChunkSearch);
    final indexed = await _count('chunk_search_docsize');
    final chunksNow = await _count('chunks');
    if (indexed != chunksNow) {
      throw StateError(
        'El índice de texto de los chunks quedó con $indexed entradas y '
        'hay $chunksNow chunks.',
      );
    }
  }

  /// Lanza si alguna tabla de [tables] tiene hoy otra cantidad de filas que en
  /// [before]. Como corre dentro de la transacción de la migración, lanzar
  /// revierte todo: nada se sigue "a ver qué pasa".
  Future<void> _requireSameCounts(
    VaultCounts before, {
    required String step,
    Iterable<String> tables = VaultCounts.userDataTables,
  }) async {
    final changed = before.differencesWith(
      await captureVaultCounts(this, tables: tables),
    );
    if (changed.isEmpty) return;
    final detail = [
      for (final e in changed.entries)
        '${e.key} (${e.value.$1} → ${e.value.$2})',
    ].join(', ');
    throw StateError(
      'La migración a $step cambió la cantidad de filas de $detail.',
    );
  }

  /// Si la tabla [table] ya tiene una columna llamada [column].
  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect(
      'SELECT 1 AS present FROM pragma_table_info(?) WHERE name = ?',
      variables: [Variable.withString(table), Variable.withString(column)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<int> _count(String table) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM $table',
    ).getSingle();
    return row.read<int>('n');
  }
}

/// El `setup` de la conexión nativa: corre sobre el SQLite crudo, antes de
/// que drift ejecute migración alguna.
///
/// Función de nivel superior y no un cierre porque drift la envía al isolate
/// que hospeda la base, y solo se pueden enviar funciones que no capturan
/// estado. Si el respaldo falla lanza, y drift cierra la base y relanza: la
/// app no abre la bóveda en vez de migrarla sin red de seguridad.
void _backupBeforeMigrating(CommonDatabase db) {
  backupBeforeMigration(db, targetVersion: AppDatabase.currentSchemaVersion);
}
