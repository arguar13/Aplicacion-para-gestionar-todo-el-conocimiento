import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
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
  /// prueba no comparten hora— y se mueve con [at].
  static Future<TestVault> create({required String deviceId}) async {
    final docs = await Directory.systemTemp.createTemp(
      'sinapsis_vault_$deviceId',
    );
    // Dos bóvedas en una misma prueba son dos bases de la misma clase, cada una
    // con su propia conexión: el aviso de drift —que habla de una MISMA
    // conexión— es un falso positivo, y aquí se calla para todo el archivo.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory(), deviceId: deviceId);
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
        ),
      );

  /// Un espacio.
  Future<void> addSpace(String id, String name) => db
      .into(db.spaces)
      .insert(SpacesCompanion.insert(id: id, name: name, createdAt: now));

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

  /// Fusiona la copia de [other] en esta bóveda, como lo haría la app.
  Future<VaultMergeResult> mergeFrom(TestVault other) async =>
      mergeZip(await other.zip());

  /// Fusiona la copia [zipBytes] en esta bóveda.
  Future<VaultMergeResult> mergeZip(Uint8List zipBytes) async {
    final incoming = await IncomingVault.open(zipBytes);
    try {
      return await VaultMerger(database: db, clock: () => _now).merge(incoming);
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
