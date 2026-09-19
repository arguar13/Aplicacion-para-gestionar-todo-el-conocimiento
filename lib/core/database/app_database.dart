import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sinapsis/core/database/migrations/backfill_inline_links_v15.dart';
import 'package:sinapsis/core/database/migrations/backfill_source_chunks_v12.dart';
import 'package:sinapsis/core/database/migrations/classify_existing_items_v8.dart';
import 'package:sinapsis/core/database/migrations/fragment_existing_sources_v8.dart';
import 'package:sinapsis/core/database/migrations/migrate_tags_to_property_values_v9.dart';
import 'package:sinapsis/core/database/migrations/mirror_unmirrored_items_v10.dart';
import 'package:sinapsis/core/database/migrations/reconcile_tags_with_properties_v14.dart';
import 'package:sinapsis/core/database/migrations/seed_system_property_categories_v9.dart';
import 'package:sinapsis/core/database/pre_migration_backup.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/database/tables/chat_messages.dart';
import 'package:sinapsis/core/database/tables/chunks.dart';
import 'package:sinapsis/core/database/tables/conversations.dart';
import 'package:sinapsis/core/database/tables/embeddings.dart';
import 'package:sinapsis/core/database/tables/flashcards.dart';
import 'package:sinapsis/core/database/tables/highlights.dart';
import 'package:sinapsis/core/database/tables/inline_links.dart';
import 'package:sinapsis/core/database/tables/items.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/knowledge_notes.dart';
import 'package:sinapsis/core/database/tables/knowledge_sources.dart';
import 'package:sinapsis/core/database/tables/merged_provenances.dart';
import 'package:sinapsis/core/database/tables/migration_issues.dart';
import 'package:sinapsis/core/database/tables/properties.dart';
import 'package:sinapsis/core/database/tables/relations.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';
import 'package:sinapsis/core/database/tables/sources.dart';
import 'package:sinapsis/core/database/tables/spaces.dart';
import 'package:sinapsis/core/database/tables/suggestions.dart';
import 'package:sinapsis/core/database/tables/tags.dart';
// Los enums se importan acá aunque este archivo no los nombre: el código
// generado es un `part` de este archivo y hereda sus imports, no los de las
// tablas donde cada enum se declara. Sin esto, `app_database.g.dart` no
// compila — y `flutter analyze` NO lo detecta, porque analysis_options
// excluye los archivos generados. Solo se ve al compilar.
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/logging/console_app_logger.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

part 'app_database.g.dart';

/// La base de datos local. Todo lo que Sinapsis guarda vive acá o en archivos
/// que esta base referencia.
@DriftDatabase(
  tables: [
    Sources,
    Items,
    Renditions,
    Tags,
    ItemTags,
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
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Para los tests, que pasan una base en memoria.
  AppDatabase(super.executor);

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
  AppDatabase.open()
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

  /// La versión del esquema. Es una constante y no solo el getter porque el
  /// respaldo previo a migrar corre antes de que exista la instancia, y
  /// necesita saber a qué versión está por migrarse la base.
  static const currentSchemaVersion = 15;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createSearchIndex();
      await seedSystemPropertyCategories(this, ids: const UuidV7Generator());
    },
    onUpgrade: (migrator, from, to) async {
      // Primera migración real del esquema: hasta acá, `schemaVersion` nunca
      // había subido de 1. Espacios (carpetas) se suma como tabla nueva y una
      // columna nullable en `Items` — nullable a propósito, para que las
      // bóvedas que ya existen abran con todo sin clasificar en vez de
      // fallar por una columna NOT NULL sin valor por defecto.
      if (from < 2) {
        await migrator.createTable(spaces);
        await migrator.addColumn(items, items.spaceId);
      }
      // Tarjetas de repaso: una tabla nueva, sin ninguna columna nueva en
      // otra tabla — ninguna bóveda existente pierde nada ni queda con un
      // valor por defecto que inventar.
      if (from < 3) {
        await migrator.createTable(flashcards);
      }
      // Historial del chat: dos tablas nuevas, sin tocar ninguna existente
      // — nada que migrar en una bóveda que ya tenía conversaciones, porque
      // hasta ahora el chat no guardaba nada.
      if (from < 4) {
        await migrator.createTable(conversations);
        await migrator.createTable(chatMessages);
      }
      // El paso que iba acá creaba las tablas de carpetas del Explorador
      // (`from < 5`). El paso `from < 7`, más abajo, las elimina — para
      // cualquiera que migre desde antes de la versión 5, crearlas y
      // borrarlas en la misma sesión de migración no deja rastro, así que
      // el paso completo se sacó en vez de dejarlo sin efecto.
      //
      // Propiedades tipadas: tres tablas nuevas, sin tocar ninguna
      // existente — conviven con las etiquetas planas de siempre, no las
      // reemplazan.
      if (from < 6) {
        await migrator.createTable(propertyDefinitions);
        await migrator.createTable(propertyValues);
        await migrator.createTable(itemPropertyValues);
      }
      // El Explorador cambió de carpetas a filtros: las tablas que
      // ubicaban un elemento dentro de una carpeta ya no tienen para qué
      // existir. Los elementos en sí no se tocan — solo pierden una
      // ubicación que ya no significa nada.
      if (from < 7) {
        await migrator.deleteTable('item_folders');
        await migrator.deleteTable('folders');
      }
      // El modelo de conocimiento nuevo: Fuente/Nota en vez de un único
      // `Items` que mezcla las dos cosas — ver la decisión sobre este
      // modelo en docs/arquitectura.md. Solo el esquema por ahora: el
      // backfill de lo ya capturado se suma en un paso posterior, sin
      // volver a subir `schemaVersion` para eso.
      if (from < 8) {
        await migrator.createTable(knowledgeEntries);
        await migrator.createTable(knowledgeSources);
        await migrator.createTable(knowledgeNotes);
        await migrator.createTable(chunks);
        await migrator.createTable(embeddings);
        await migrator.createTable(migrationIssues);
        // `createTable` no crea los índices de `@TableIndex` —a
        // diferencia de `createAll()`, que sí los incluye para una base
        // recién creada—, así que acá van explícitos.
        await migrator.createIndex(idxKnowledgeEntriesStateKind);
        await migrator.createIndex(idxKnowledgeEntriesKindUpdated);
        await migrator.createIndex(idxKnowledgeSourcesContentHash);
        await migrator.createIndex(idxKnowledgeSourcesProcessingStatus);
        await migrator.createIndex(idxChunksItemSeq);
        await migrator.createIndex(idxChunksItemStartMs);
        await classifyExistingItems(this, ids: const UuidV7Generator());
        await fragmentExistingSources(
          this,
          ids: const UuidV7Generator(),
          logger: ConsoleAppLogger(),
        );
      }
      // Vocabulario controlado: tipo y "categoría de sistema" sobre las
      // categorías que ya existían, más los alias que resuelven un
      // sinónimo al valor real — ver la decisión sobre esto en
      // docs/arquitectura.md. Solo el esquema por ahora: sembrar "Tema"/
      // "Fecha del hecho" y migrar las etiquetas existentes son pasos
      // posteriores, sin volver a subir `schemaVersion`.
      if (from < 9) {
        await migrator.addColumn(propertyDefinitions, propertyDefinitions.type);
        await migrator.addColumn(
          propertyDefinitions,
          propertyDefinitions.isSystem,
        );
        await migrator.addColumn(propertyValues, propertyValues.numberValue);
        await migrator.addColumn(propertyValues, propertyValues.dateFromYear);
        await migrator.addColumn(propertyValues, propertyValues.dateFromMonth);
        await migrator.addColumn(propertyValues, propertyValues.dateFromDay);
        await migrator.addColumn(propertyValues, propertyValues.dateToYear);
        await migrator.addColumn(propertyValues, propertyValues.dateToMonth);
        await migrator.addColumn(propertyValues, propertyValues.dateToDay);
        await migrator.addColumn(propertyValues, propertyValues.datePrecision);
        await migrator.addColumn(propertyValues, propertyValues.dateIsCirca);
        await migrator.createTable(propertyAliases);
        await migrator.createIndex(idxPropertyAliasesValue);
        await seedSystemPropertyCategories(this, ids: const UuidV7Generator());
        await migrateTagsToPropertyValues(
          this,
          ids: const UuidV7Generator(),
          logger: ConsoleAppLogger(),
        );
      }
      // El espejo en vivo del modelo Fuente/Nota — ver la decisión sobre
      // F3 en docs/arquitectura.md. Sin tabla ni columna nueva: solo el
      // catch-up de lo que se capturó entre el backfill de F1 y este
      // commit, que `LibraryRepositoryImpl.save()` no llegó a espejar
      // porque el espejo en vivo todavía no existía.
      if (from < 10) {
        await mirrorUnmirroredItems(this);
      }
      // Clasificación asistida (F4): de dónde viene una propiedad puesta
      // —a mano, heredada al extraer una nota, o una sugerencia
      // aceptada—, y la cola de sugerencias del modelo, todavía sin
      // aplicar. Sin backfill: `origin` trae su propio valor por
      // defecto (`manual`, la única procedencia que podía tener algo
      // ya asignado antes de que esta columna existiera) y
      // `Suggestions` nace vacía — nada que migrar.
      if (from < 11) {
        await migrator.addColumn(itemPropertyValues, itemPropertyValues.origin);
        await migrator.createTable(suggestions);
        // `createTable` no crea los índices de `@TableIndex` solo — ver
        // el mismo recordatorio más arriba, en el paso `from < 8`.
        await migrator.createIndex(idxSuggestionsTargetStatus);
      }
      // Motor de relaciones (F5): backfill de catch-up de
      // `chunk`/`fullText`/`contentHash` para toda fuente que el
      // backfill histórico de F1 no llegó a cubrir —prácticamente todo
      // lo capturado desde entonces—. Sin tabla ni columna nueva, solo
      // poblar lo que quedó vacío: mismo criterio que el catch-up del
      // espejo en F3 (`from < 10`).
      if (from < 12) {
        await backfillSourceChunks(this, ids: const UuidV7Generator());
      }
      // Deduplicación (F7): `dedupHash` (SHA-256 sobre texto normalizado,
      // distinto de `KnowledgeSources.contentHash`, que hashea el texto
      // crudo y sirve un propósito aparte —guarda de idempotencia del
      // chunking—) en las dos tablas, `simhash` nuevo en `note` —en
      // `source` ya existía, reservado desde F1, sin calcular hasta
      // ahora—, y la tabla de procedencias fusionadas. Todo nullable:
      // los fingerprints se calculan la primera vez que cada generador
      // corre sobre un elemento desde acá en adelante, sin backfill de
      // lo ya capturado en esta ronda.
      if (from < 13) {
        // Quien migra desde antes de v8 nunca pasa por `addColumn` para
        // estas dos: el `createTable` de más arriba (`from < 8`) ya las
        // crea con las columnas que la clase Dart tiene HOY —`dedupHash`/
        // `simhash` incluidas—, así que agregarlas de nuevo acá
        // reventaría con "duplicate column name". Solo hace falta para
        // quien ya tenía la tabla de una migración anterior.
        if (from >= 8) {
          await migrator.addColumn(
            knowledgeSources,
            knowledgeSources.dedupHash,
          );
          await migrator.addColumn(knowledgeNotes, knowledgeNotes.dedupHash);
          await migrator.addColumn(knowledgeNotes, knowledgeNotes.simhash);
        }
        // Los índices, en cambio, `createTable` nunca los incluye —a
        // diferencia de `createAll()`—, así que van siempre, sin importar
        // por dónde entró.
        await migrator.createIndex(idxKnowledgeSourcesDedupHash);
        await migrator.createIndex(idxKnowledgeNotesDedupHash);
        await migrator.createTable(mergedProvenances);
        await migrator.createIndex(idxMergedProvenancesItem);
      }
      // Etiquetas unificadas con propiedades (F8): F2 las copió a valores
      // de Tema una sola vez, y las creadas después nunca llegaron. Sin
      // tabla ni columna nueva —por eso no hay snapshot de v14—: une lo
      // que quedó separado, calculando un informe ANTES de escribir
      // nada (ver `reconcileTagsWithProperties`). La copia previa de la
      // base ya se hizo, antes de que drift empezara a migrar. Si algo
      // falla, la migración entera revierte: mejor no abrir la bóveda
      // que dejar una etiqueta sin valor.
      if (from < 14) {
        // Idempotente, y este paso depende de que Tema exista: en una base
        // real ya está —la creó la migración a v9 o `onCreate`, y no se
        // puede borrar—, pero no conviene apoyarse en eso desde acá.
        await seedSystemPropertyCategories(this, ids: const UuidV7Generator());
        await reconcileTagsWithProperties(
          this,
          ids: const UuidV7Generator(),
          logger: ConsoleAppLogger(),
        );
      }
      // Consolidación (F9): los `[[ ]]` de las notas persistidos como
      // tabla —con el destino nullable: un enlace roto deja de ser invisible—,
      // y tres columnas nullable en `Relations`: cuándo se revisó una
      // contradicción, y dónde de la fuente sale una cita. Todo aditivo. El
      // backfill calcula un informe antes de escribir, y la copia previa de
      // la base ya se hizo.
      if (from < 15) {
        await migrator.createTable(inlineLinks);
        // `createTable` no crea los índices de `@TableIndex` solo.
        await migrator.createIndex(idxInlineLinkTarget);
        await migrator.createIndex(idxInlineLinkTitle);
        await migrator.addColumn(relations, relations.reviewedAt);
        await migrator.addColumn(relations, relations.sourceCharStart);
        await migrator.addColumn(relations, relations.sourceCharEnd);
        await backfillInlineLinks(
          this,
          ids: const UuidV7Generator(),
          logger: ConsoleAppLogger(),
        );
      }
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
    },
  );

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
