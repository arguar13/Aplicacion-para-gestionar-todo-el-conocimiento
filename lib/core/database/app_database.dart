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
import 'package:sinapsis/core/database/tables/chat_messages.dart';
import 'package:sinapsis/core/database/tables/chunks.dart';
import 'package:sinapsis/core/database/tables/conversations.dart';
import 'package:sinapsis/core/database/tables/embeddings.dart';
import 'package:sinapsis/core/database/tables/field_versions.dart';
import 'package:sinapsis/core/database/tables/flashcards.dart';
import 'package:sinapsis/core/database/tables/highlights.dart';
import 'package:sinapsis/core/database/tables/inline_links.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/knowledge_notes.dart';
import 'package:sinapsis/core/database/tables/knowledge_sources.dart';
import 'package:sinapsis/core/database/tables/merge_conflicts.dart';
import 'package:sinapsis/core/database/tables/merged_provenances.dart';
import 'package:sinapsis/core/database/tables/migration_issues.dart';
import 'package:sinapsis/core/database/tables/properties.dart';
import 'package:sinapsis/core/database/tables/relations.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';
import 'package:sinapsis/core/database/tables/review_log.dart';
import 'package:sinapsis/core/database/tables/source_references.dart';
import 'package:sinapsis/core/database/tables/spaces.dart';
import 'package:sinapsis/core/database/tables/suggestions.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/database/vocabulary_hierarchy.dart';
// Los enums se importan acá aunque este archivo no los nombre: el código
// generado es un `part` de este archivo y hereda sus imports, no los de las
// tablas donde cada enum se declara. Sin esto, `app_database.g.dart` no
// compila — y `flutter analyze` NO lo detecta, porque analysis_options
// excluye los archivos generados. Solo se ve al compilar.
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
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
  static const currentSchemaVersion = 22;

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
    await customStatement(createChunkSearchTable);
    await customStatement(createChunkVocabTable);
    for (final trigger in chunkSearchTriggers) {
      await customStatement(trigger);
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
