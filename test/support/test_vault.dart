import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart'
    show
        BooleanExpressionOperators,
        OrderingTerm,
        QueryExecutor,
        Value,
        driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/vault_merger.dart';
import 'package:sinapsis/features/vault/data/services/backup_layout.dart';
import 'package:sinapsis/features/vault/data/services/local_vault_backup_service.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v19.dart' as v19;
import 'in_memory_file_store.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Un `.zip` con estas [entries] —nombre → bytes—: para armar a mano copias
/// válidas y rotas, con los nombres que se quiera.
Uint8List zipOf(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach(
    (name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)),
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// Los bytes de un archivo de SQLite cualquiera que dice ser del esquema
/// [version]: sin las tablas de Sinapsis, solo lo que hace falta para que la
/// copia se rechace o se acepte por su versión.
Future<Uint8List> sqliteBytesAtVersion(int version) async {
  final dir = await Directory.systemTemp.createTemp('sinapsis_version_');
  try {
    final file = File(p.join(dir.path, 'x.sqlite'));
    sqlite3.sqlite3.open(file.path)
      ..execute('CREATE TABLE t (x INTEGER)')
      ..execute('PRAGMA user_version = $version')
      ..close();
    return await file.readAsBytes();
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Una copia de una bóveda como la dejaba la versión 19 de la app: una fuente
/// [sourceId] con su texto, sin ninguna de las tablas que llegaron en la 20.
Future<Uint8List> vaultCopyAtV19({
  String sourceId = 'legacy-src',
  String text = 'Texto de una bóveda vieja.',
}) async {
  final dir = await Directory.systemTemp.createTemp('sinapsis_v19_');
  try {
    final schema = await SchemaVerifier(GeneratedHelper()).schemaAt(19);
    final db = v19.DatabaseAtV19(schema.newConnection());
    const at = 1789000000;
    await db
        .into(db.item)
        .insert(
          v19.ItemCompanion.insert(
            id: sourceId,
            title: 'Fuente vieja',
            kind: 'source',
            state: 'processed',
            createdAt: at,
            updatedAt: at,
            deviceId: 'f3-espejo-sin-sync',
          ),
        );
    await db
        .into(db.source)
        .insert(
          v19.SourceCompanion.insert(
            itemId: sourceId,
            sourceType: 'webPage',
            capturedAt: at,
            contentHash: '',
            processingStatus: 'done',
          ),
        );
    await db
        .into(db.renditions)
        .insert(
          v19.RenditionsCompanion.insert(
            id: 'r-$sourceId',
            itemId: sourceId,
            kind: 'markdown',
            content: Value(text),
            isPrimary: 1,
            createdAt: at,
          ),
        );
    final file = File(p.join(dir.path, 'v19.sqlite'));
    await db.customStatement('VACUUM INTO ?', [file.path]);
    await db.close();
    return zipOf({kBackupDatabaseEntryName: await file.readAsBytes()});
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Una bóveda de prueba entera: su base, su carpeta de documentos y todo lo que
/// hace falta para llenarla y para hacerle una copia (F11).
///
/// Sirve a las pruebas de la fusión, que necesitan DOS bóvedas —la de acá y la
/// que llega en una copia— con dispositivos distintos, y un `.zip` de verdad
/// entre ellas. Llenarla pasa por `LibraryRepositoryImpl.save`, el camino de la
/// app, para que las filas sean las que produce de verdad.
class TestVault {
  TestVault._({required this.deviceId, required this.db, required this.docs}) {
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: _SilentTelemetry(),
      files: InMemoryFileStore(),
      clock: () => _now,
    );
    writer = KnowledgeEntryWriter(db, clock: () => _now);
    backup = LocalVaultBackupService(
      database: db,
      documentsDirectory: () async => docs,
    );
  }

  /// Una bóveda nueva y vacía. Su reloj es suyo —los dos dispositivos de una
  /// prueba no comparten hora— y se mueve con [at]. Con [executor] la base es
  /// esa —una en memoria a la que se le mira lo que ejecuta, por ejemplo— y no
  /// la de siempre.
  static Future<TestVault> create({
    required String deviceId,
    QueryExecutor? executor,
  }) async {
    final docs = await Directory.systemTemp.createTemp(
      'sinapsis_vault_$deviceId',
    );
    // Dos bóvedas en una misma prueba son dos bases de la misma clase, cada una
    // con su propia conexión: el aviso de drift —que habla de una MISMA
    // conexión— es un falso positivo, y aquí se calla para todo el archivo.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(
      executor ?? NativeDatabase.memory(),
      deviceId: deviceId,
    );
    return TestVault._(deviceId: deviceId, db: db, docs: docs);
  }

  /// Una bóveda de prueba sobre la base del archivo [file] —una copia de la
  /// bóveda grande de un banco de medida— en lugar de una en memoria.
  static Future<TestVault> onFile(File file, {required String deviceId}) async {
    final docs = await Directory.systemTemp.createTemp(
      'sinapsis_vault_$deviceId',
    );
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase(file), deviceId: deviceId);
    return TestVault._(deviceId: deviceId, db: db, docs: docs);
  }

  final String deviceId;
  final AppDatabase db;

  /// La carpeta de documentos: donde viven los archivos originales.
  final Directory docs;

  DateTime _now = _origin;

  /// La hora de partida de todas las bóvedas de una prueba: las 12:00.
  static final _origin = DateTime(2026, 9, 20, 12);

  late final LibraryRepositoryImpl library;
  late final KnowledgeEntryWriter writer;
  late final LocalVaultBackupService backup;

  /// La hora de esta bóveda.
  DateTime get now => _now;

  /// Pone el reloj de esta bóveda [minutes] minutos después de las 12:00. Todo
  /// lo que se guarde a partir de ahí lleva esa hora: es lo que permite armar
  /// «tel editó a las 5 y pc a las 7» sin esperar.
  void at(int minutes) => _now = _origin.add(Duration(minutes: minutes));

  /// Guarda una fuente con [text] en su forma principal, y opcionalmente un
  /// archivo original con ese [originalName] y [originalContent].
  Future<KnowledgeItem> saveSource(
    String id, {
    String? title,
    String text = 'Texto de la fuente.',
    String? originalName,
    String originalContent = 'bytes',
    String? subtitle,
    String? notes,
    String? spaceId,
    String? author,
  }) async {
    String? originalPath;
    if (originalName != null) {
      originalPath = 'originales/$id/$originalName';
      await writeOriginal(originalPath, originalContent);
    }
    final at = now;
    final item = KnowledgeItem(
      id: id,
      title: title ?? 'Fuente $id',
      subtitle: subtitle,
      notes: notes,
      spaceId: spaceId,
      source: Source(
        id: id,
        kind: SourceKind.webPage,
        capturedAt: at,
        url: 'https://ejemplo.org/$id',
        authorName: author,
        originalFilePath: originalPath,
      ),
      processingState: ProcessingState.ready,
      createdAt: at,
      updatedAt: at,
      renditions: [
        Rendition.text(
          id: 'rend-$id',
          itemId: id,
          kind: RenditionKind.markdown,
          content: text,
          isPrimary: true,
          createdAt: at,
        ),
      ],
    );
    return (await library.save(item)).getRight().toNullable()!;
  }

  /// Guarda una nota viva con [text].
  Future<KnowledgeItem> saveNote(
    String id, {
    String? title,
    String text = 'Una idea.',
    NoteKind? kind,
  }) async {
    final at = now;
    final item = KnowledgeItem(
      id: id,
      title: title ?? 'Nota $id',
      source: Source(id: id, kind: SourceKind.manualNote, capturedAt: at),
      processingState: ProcessingState.ready,
      createdAt: at,
      updatedAt: at,
      renditions: [
        Rendition.text(
          id: 'rend-$id',
          itemId: id,
          kind: RenditionKind.plainText,
          content: text,
          isPrimary: true,
          createdAt: at,
        ),
      ],
    );
    final saved = (await library.save(item)).getRight().toNullable()!;
    if (kind != null) await writer.setNoteKind(id, kind);
    return saved;
  }

  /// Guarda una nota de bloques —la que admite enlaces `[[Título]]`— con un
  /// párrafo por cada uno de [paragraphs].
  Future<KnowledgeItem> saveBlocksNote(
    String id,
    List<String> paragraphs, {
    String? title,
  }) async {
    final at = now;
    final item = KnowledgeItem(
      id: id,
      title: title ?? 'Nota $id',
      source: Source(id: id, kind: SourceKind.manualNote, capturedAt: at),
      processingState: ProcessingState.ready,
      createdAt: at,
      updatedAt: at,
      renditions: [
        Rendition.text(
          id: 'blocks-$id',
          itemId: id,
          kind: RenditionKind.blocks,
          content: encodeContentBlocks([
            for (final text in paragraphs) ContentBlock.paragraph(text: text),
          ]),
          isPrimary: true,
          createdAt: at,
        ),
      ],
    );
    return (await library.save(item)).getRight().toNullable()!;
  }

  /// Carga [sources] fuentes y [notes] notas directamente en las tablas, sin
  /// pasar por el guardado: para armar una bóveda grande en una fracción del
  /// tiempo. Cada fuente lleva [textLength] caracteres de texto. Los
  /// identificadores son `s0`, `s1`… y `n0`, `n1`…, desde [from].
  Future<void> bulk({
    int sources = 0,
    int notes = 0,
    int textLength = 1200,
    int from = 0,
  }) async {
    final seconds = now.millisecondsSinceEpoch ~/ 1000;
    await db.transaction(() async {
      for (var i = from; i < from + sources; i++) {
        final id = 's$i';
        final text = List.generate(
          (textLength / 40).ceil(),
          (k) => 'Frase $k de la fuente $i, con algo de texto.',
        ).join(' ');
        await db.customStatement(
          'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
          "device_id) VALUES (?, ?, 'source', 'processed', ?, ?, ?)",
          [id, 'Fuente $i', seconds, seconds, deviceId],
        );
        await db.customStatement(
          'INSERT INTO source (item_id, source_type, captured_at, '
          'content_hash, processing_status) '
          "VALUES (?, 'webPage', ?, '', 'done')",
          [id, seconds],
        );
        await db.customStatement(
          'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
          "created_at) VALUES (?, ?, 'markdown', ?, 1, ?)",
          ['rend-$id', id, text, seconds],
        );
      }
      for (var i = from; i < from + notes; i++) {
        final id = 'n$i';
        await db.customStatement(
          'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
          "device_id) VALUES (?, ?, 'note', 'processed', ?, ?, ?)",
          [id, 'Nota $i', seconds, seconds, deviceId],
        );
        await db.customStatement(
          'INSERT INTO note (item_id, note_kind, maturity) '
          "VALUES (?, 'living', 'seed')",
          [id],
        );
        await db.customStatement(
          'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
          "created_at) VALUES (?, ?, 'plainText', ?, 1, ?)",
          ['rend-$id', id, 'Una idea $i.', seconds],
        );
      }
    });
  }

  /// Un vínculo [from] → [to] de tipo [kind].
  Future<void> addRelation(
    String id,
    String from,
    String to, {
    RelationKind kind = RelationKind.cites,
  }) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: id,
          fromItemId: from,
          toItemId: to,
          kind: kind,
          createdAt: now,
        ),
      );

  /// Un resaltado sobre el texto de [itemId] (la forma de `saveSource`).
  Future<void> addHighlight(
    String id,
    String itemId, {
    int start = 0,
    int end = 5,
  }) => db
      .into(db.highlights)
      .insert(
        HighlightsCompanion.insert(
          id: id,
          renditionId: 'rend-$itemId',
          startOffset: start,
          endOffset: end,
          excerpt: 'extracto',
          createdAt: now,
        ),
      );

  /// Una tarjeta de [itemId].
  Future<void> addFlashcard(
    String id,
    String itemId, {
    String front = '¿Qué?',
    String back = 'Eso.',
    FlashcardKind kind = FlashcardKind.freeRecall,
  }) => db
      .into(db.flashcards)
      .insert(
        FlashcardsCompanion.insert(
          id: id,
          itemId: itemId,
          front: front,
          back: back,
          dueAt: now,
          createdAt: now,
          kind: Value(kind),
        ),
      );

  /// Una opción de una tarjeta de opción múltiple (F20).
  Future<void> addFlashcardOption(
    String id,
    String flashcardId, {
    String content = 'Una opción',
    bool isCorrect = false,
    int position = 0,
  }) => db
      .into(db.flashcardOptions)
      .insert(
        FlashcardOptionsCompanion.insert(
          id: id,
          flashcardId: flashcardId,
          content: content,
          isCorrect: isCorrect,
          position: position,
        ),
      );

  /// Un espacio.
  Future<void> addSpace(String id, String name) => db
      .into(db.spaces)
      .insert(SpacesCompanion.insert(id: id, name: name, createdAt: now));

  /// Una forma de texto más para [itemId].
  Future<void> addRendition(
    String itemId,
    String id,
    String text, {
    bool primary = false,
  }) => db
      .into(db.renditions)
      .insert(
        RenditionsCompanion.insert(
          id: id,
          itemId: itemId,
          kind: RenditionKind.plainText,
          content: Value(text),
          isPrimary: primary,
          createdAt: now,
        ),
      );

  /// Las formas de [itemId], por identificador.
  Future<List<RenditionRow>> renditionsOf(String itemId) =>
      (db.select(db.renditions)
            ..where((r) => r.itemId.equals(itemId))
            ..orderBy([(r) => OrderingTerm.asc(r.id)]))
          .get();

  /// El id de la categoría «Tema» de esta bóveda: cada una la siembra con uno
  /// propio.
  Future<String> temaId() => temaDefinitionId(db);

  /// Una propiedad nueva.
  Future<void> addDefinition(String id, String name) => db
      .into(db.propertyDefinitions)
      .insert(
        PropertyDefinitionsCompanion.insert(id: id, name: name, createdAt: now),
      );

  /// Un valor de la propiedad [definitionId].
  Future<void> addPropertyValue(String id, String definitionId, String value) =>
      db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: id,
              definitionId: definitionId,
              value: value,
              createdAt: now,
            ),
          );

  /// Un alias del valor [valueId].
  Future<void> addAlias(
    String id,
    String valueId,
    String definitionId,
    String alias,
  ) => db
      .into(db.propertyAliases)
      .insert(
        PropertyAliasesCompanion.insert(
          id: id,
          propertyValueId: valueId,
          definitionId: definitionId,
          alias: alias,
          createdAt: now,
        ),
      );

  /// Le asigna el valor [valueId] al elemento [itemId].
  Future<void> assignValue(String itemId, String valueId) => db
      .into(db.itemPropertyValues)
      .insert(
        ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: valueId,
        ),
      );

  /// Una conversación con la hora de esta bóveda.
  Future<void> addConversation(
    String id, {
    String? title,
    String? notebookId,
  }) => db
      .into(db.conversations)
      .insert(
        ConversationsCompanion.insert(
          id: id,
          mode: ChatConversationMode.vault,
          title: Value(title),
          notebookId: Value(notebookId),
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// Un cuaderno manual con la hora de esta bóveda (F16).
  Future<void> addNotebook(String id, {String name = 'Cuaderno'}) => db
      .into(db.notebooks)
      .insert(
        NotebooksCompanion.insert(
          id: id,
          name: name,
          mode: NotebookMode.manual,
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// Un mensaje de [conversationId].
  Future<void> addMessage(
    String id,
    String conversationId, {
    String content = 'Hola',
  }) => db
      .into(db.chatMessages)
      .insert(
        ChatMessagesCompanion.insert(
          id: id,
          conversationId: conversationId,
          isUser: true,
          content: content,
          createdAt: now,
        ),
      );

  /// De dónde salió una parte de lo que se fusionó en [itemId].
  Future<void> addProvenance(String id, String itemId) => db
      .into(db.mergedProvenances)
      .insert(
        MergedProvenancesCompanion.insert(
          id: id,
          itemId: itemId,
          sourceKind: SourceKind.webPage,
          capturedAt: now,
          mergedAt: now,
        ),
      );

  /// Un repaso de la tarjeta [flashcardId].
  Future<void> addReview(String id, String flashcardId) => db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          id: id,
          flashcardId: flashcardId,
          reviewedAt: now,
          grade: 'good',
          quality: 4,
          intervalBefore: 1,
          intervalAfter: 3,
          easeBefore: 2.5,
          easeAfter: 2.5,
          deviceId: deviceId,
        ),
      );

  /// El rastro mínimo de la racha (F17, D6): triar la Bandeja, resolver
  /// algo en Vocabulario.
  Future<void> addHabitEvent(String id, HabitEventKind kind) => db
      .into(db.habitEvents)
      .insert(HabitEventsCompanion.insert(id: id, kind: kind, occurredAt: now));

  /// Repasa la tarjeta [flashcardId] a la hora de esta bóveda: cambia su
  /// calendario.
  Future<void> reviewCard(String flashcardId, {int intervalDays = 6}) =>
      (db.update(db.flashcards)..where((f) => f.id.equals(flashcardId))).write(
        FlashcardsCompanion(
          intervalDays: Value(intervalDays),
          repetitions: const Value(2),
          dueAt: Value(now.add(Duration(days: intervalDays))),
          lastReviewedAt: Value(now),
        ),
      );

  /// Escribe un archivo en la carpeta de documentos.
  Future<void> writeOriginal(String relativePath, String content) async {
    final file = File(
      p.join(docs.path, p.joinAll(p.posix.split(relativePath))),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  /// Si la carpeta de documentos tiene el archivo [relativePath].
  bool hasOriginal(String relativePath) => File(
    p.join(docs.path, p.joinAll(p.posix.split(relativePath))),
  ).existsSync();

  /// El contenido del archivo [relativePath] de la carpeta de documentos.
  String readOriginal(String relativePath) => File(
    p.join(docs.path, p.joinAll(p.posix.split(relativePath))),
  ).readAsStringSync();

  /// Una copia de esta bóveda, como la exportaría la app.
  Future<Uint8List> zip() => backup.buildBackup();

  /// Qué traería la copia de [other] a esta bóveda, sin escribir nada: lo que
  /// ve quien la elige en la pantalla. La copia se lee del disco, por su ruta,
  /// como hace la app.
  Future<VaultMergePreview> previewFrom(TestVault other) async =>
      previewZip(await other.zip());

  /// Lo mismo con la copia [zipBytes], escrita antes a un archivo.
  Future<VaultMergePreview> previewZip(Uint8List zipBytes) async {
    final dir = await Directory.systemTemp.createTemp('sinapsis_preview_');
    try {
      final file = File(p.join(dir.path, 'copia.zip'));
      await file.writeAsBytes(zipBytes);
      return await backup.previewMerge(file.path);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Fusiona la copia [zipBytes] con el SERVICIO, como lo hace la app: el
  /// `.zip` se escribe antes a un archivo y se lee del disco, por su ruta.
  Future<VaultMergeResult> mergeBackupZip(Uint8List zipBytes) async {
    final dir = await Directory.systemTemp.createTemp('sinapsis_merge_zip_');
    try {
      final file = File(p.join(dir.path, 'copia.zip'));
      await file.writeAsBytes(zipBytes);
      return await backup.mergeBackup(file.path);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Fusiona la copia de [other] con el servicio (ver [mergeBackupZip]).
  Future<VaultMergeResult> mergeBackupFrom(TestVault other) async =>
      mergeBackupZip(await other.zip());

  /// Fusiona la copia de [other] en esta bóveda, como lo haría la app. Con
  /// [afterWrites] y [afterFiles] se rompe algo a propósito a mitad de la
  /// fusión: ver `VaultMerger`.
  Future<VaultMergeResult> mergeFrom(
    TestVault other, {
    Future<void> Function(AppDatabase)? afterWrites,
    Future<void> Function(AppDatabase)? afterFiles,
  }) async => mergeZip(
    await other.zip(),
    afterWrites: afterWrites,
    afterFiles: afterFiles,
  );

  /// Solo la fusión de [incoming] en esta bóveda, ya armada y desempaquetada
  /// la copia: lo que hay que cronometrar cuando se mide la fusión —armar el
  /// `.zip` y abrirlo cuestan lo mismo cambie lo que cambie—. Quien la llama
  /// libera [incoming].
  Future<VaultMergeResult> mergeIncoming(IncomingVault incoming) => VaultMerger(
    database: db,
    documentsDirectory: docs,
    clock: () => _now,
  ).merge(incoming);

  /// La copia de [other], armada y abierta, lista para [mergeIncoming].
  Future<IncomingVault> incomingFrom(TestVault other) async =>
      IncomingVault.open(await other.zip());

  /// Fusiona la copia [zipBytes] en esta bóveda.
  Future<VaultMergeResult> mergeZip(
    Uint8List zipBytes, {
    Future<void> Function(AppDatabase)? afterWrites,
    Future<void> Function(AppDatabase)? afterFiles,
  }) async {
    final incoming = await IncomingVault.open(zipBytes);
    try {
      return await VaultMerger(
        database: db,
        documentsDirectory: docs,
        clock: () => _now,
        afterWrites: afterWrites,
        afterFiles: afterFiles,
      ).merge(incoming);
    } finally {
      await incoming.dispose();
    }
  }

  /// Fusiona la copia cuya base es [databaseFile], ya desempaquetada: para las
  /// bóvedas que no caben en un `.zip` en memoria.
  Future<VaultMergeResult> mergeDatabaseFile(File databaseFile) async {
    final incoming = await IncomingVault.fromDatabaseFile(databaseFile);
    try {
      return await VaultMerger(
        database: db,
        documentsDirectory: docs,
        clock: () => _now,
      ).merge(incoming);
    } finally {
      await incoming.dispose();
    }
  }

  /// La fila de `item` de [id].
  Future<KnowledgeEntryRow> entry(String id) => (db.select(
    db.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle();

  /// La versión que esta bóveda tiene del campo [field] del elemento [id], o
  /// `null` si nadie lo modificó desde que se llevan versiones.
  Future<FieldVersionRow?> version(String id, String field) =>
      (db.select(db.fieldVersions)
            ..where((f) => f.itemId.equals(id) & f.fieldName.equals(field)))
          .getSingleOrNull();

  /// Los conflictos de fusión guardados, del más viejo al más nuevo.
  Future<List<MergeConflictRow>> conflicts() =>
      (db.select(db.mergeConflicts)..orderBy([
            (c) => OrderingTerm.asc(c.detectedAt),
            (c) => OrderingTerm.asc(c.fieldName),
          ]))
          .get();

  /// Cuántas filas tiene [table].
  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  /// Cuántas filas tiene cada tabla de datos: para comprobar que algo no tocó
  /// nada.
  Future<Map<String, int>> counts() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '%_search%' "
          "AND name NOT LIKE '%_vocab%' ORDER BY name",
        )
        .get();
    return {
      for (final row in tables)
        row.read<String>('name'): await count(row.read<String>('name')),
    };
  }

  Future<void> dispose() async {
    await db.close();
    if (docs.existsSync()) await docs.delete(recursive: true);
  }
}
