import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/file_references.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/content_trash/domain/repositories/content_trash_repository.dart';

/// [ContentTrashRepository] sobre la base (`content_trash`, v38) y el
/// almacén de archivos.
///
/// Soltar y recuperar son una transacción cada uno: o el elemento queda con
/// su mitad en la papelera, o queda como estaba. El disco se toca solo al
/// vencer —y después de la base—, nunca antes de los 30 días: un archivo
/// soltado sigue donde estaba.
class ContentTrashRepositoryImpl implements ContentTrashRepository {
  ContentTrashRepositoryImpl({
    required AppDatabase database,
    required FileStore files,
    required TelemetryService telemetry,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _files = files,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final FileStore _files;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  /// Quien escribe la fuente: ver [KnowledgeEntryWriter].
  KnowledgeEntryWriter get _writer =>
      KnowledgeEntryWriter(_db, clock: _clock, ids: _ids);

  $TrashedContentsTable get _trash => _db.trashedContents;

  @override
  Future<Either<Failure, List<TrashedContent>>> keepOnlyText(String itemId) =>
      _guard('keepOnlyText', () async {
        final halves = await _halvesOf(itemId);
        if (halves == null) return left(_cannotSplit(itemId));
        final (:path, texts: _) = halves;

        // Afuera de la transacción: medir el archivo es leer el disco.
        final size = await _files.sizeOf(path);
        final row = TrashedContentsCompanion.insert(
          id: _ids.next(),
          itemId: itemId,
          kind: TrashedContentKind.file,
          relativePath: Value(path),
          sizeBytes: Value(size),
          trashedAt: _clock(),
        );
        await _db.transaction(() async {
          await _db.into(_trash).insert(row);
          // Por el escritor: es un campo con linaje (`originalBlobPath`), y una
          // fusión tiene que saber que acá se soltó.
          await _writer.setFieldFromText(
            itemId,
            EntryField.originalBlobPath,
            null,
          );
        });
        return right([_toEntity(await _rowById(row.id.value))]);
      });

  @override
  Future<Either<Failure, List<TrashedContent>>> keepOnlyFile(
    String itemId,
  ) => _guard('keepOnlyFile', () async {
    final halves = await _halvesOf(itemId);
    if (halves == null) return left(_cannotSplit(itemId));

    final ids = <String>[];
    await _db.transaction(() async {
      final now = _clock();
      for (final text in halves.texts) {
        final highlights = await (_db.select(
          _db.highlights,
        )..where((h) => h.renditionId.equals(text.id))).get();
        final id = _ids.next();
        await _db
            .into(_trash)
            .insert(
              TrashedContentsCompanion.insert(
                id: id,
                itemId: itemId,
                kind: TrashedContentKind.text,
                renditionId: Value(text.id),
                renditionKind: Value(text.kind),
                content: Value(text.content),
                isPrimary: Value(text.isPrimary),
                renditionCreatedAt: Value(text.createdAt),
                wordTimings: Value(text.wordTimings),
                highlights: Value(encodeTrashedHighlights(highlights)),
                trashedAt: now,
              ),
            );
        ids.add(id);
        // Los subrayados se van con la forma, en cascada: ya están copiados.
        await (_db.delete(
          _db.renditions,
        )..where((r) => r.id.equals(text.id))).go();
      }
      // Los chunks describen un texto que ya no está: la búsqueda no puede
      // encontrar el elemento por él ni citar un pasaje que no se ve. Sus
      // vectores se van con ellos; recuperar el texto los rehace.
      await (_db.delete(
        _db.chunks,
      )..where((c) => c.itemId.equals(itemId))).go();
      await _writer.setOnlyFile(itemId, onlyFile: true);
    });
    return right([for (final id in ids) _toEntity(await _rowById(id))]);
  });

  @override
  Future<Either<Failure, ContentRestoreOutcome>> restore(String trashedId) =>
      _guard('restore', () async {
        final row = await (_db.select(
          _trash,
        )..where((t) => t.id.equals(trashedId))).getSingleOrNull();
        if (row == null) return right(ContentRestoreOutcome.gone);
        return right(switch (row.kind) {
          TrashedContentKind.file => await _restoreFile(row),
          TrashedContentKind.text => await _restoreText(row),
        });
      });

  Future<ContentRestoreOutcome> _restoreFile(TrashedContentRow row) async {
    final path = row.relativePath!;
    final source = await _sourceOf(row.itemId);
    final current = source?.originalBlobPath;
    if (current != null && current != path) {
      return ContentRestoreOutcome.alreadyHasFile;
    }
    if (!await _files.exists(path)) {
      // Alguien vació el almacenamiento de la app: no hay qué recuperar, y
      // dejarlo en la papelera prometería algo que no está.
      await (_db.delete(_trash)..where((t) => t.id.equals(row.id))).go();
      return ContentRestoreOutcome.fileMissing;
    }
    await _db.transaction(() async {
      if (current == null) {
        await _writer.setFieldFromText(
          row.itemId,
          EntryField.originalBlobPath,
          path,
        );
      }
      await (_db.delete(_trash)..where((t) => t.id.equals(row.id))).go();
    });
    return ContentRestoreOutcome.restored;
  }

  Future<ContentRestoreOutcome> _restoreText(TrashedContentRow row) async {
    await _db.transaction(() async {
      final taken =
          await (_db.select(
            _db.renditions,
          )..where((r) => r.id.equals(row.renditionId!))).getSingleOrNull() !=
          null;
      // El mismo identificador, para que valgan de nuevo los subrayados y lo
      // que apuntaba a ese texto. Si otra forma lo ocupa —no debería: la
      // fusión no trae de vuelta lo soltado acá—, uno nuevo, con los
      // subrayados detrás.
      final id = taken ? _ids.next() : row.renditionId!;
      // Principal si lo era y el elemento no consiguió otro texto principal
      // mientras tanto —se volvió a extraer—: recuperar nunca le saca el
      // lugar a lo que hay.
      final hasPrimary = await _mainTextsOf(
        row.itemId,
      ).then((texts) => texts.any((t) => t.isPrimary));
      await _db
          .into(_db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: id,
              itemId: row.itemId,
              kind: row.renditionKind!,
              content: Value(row.content),
              isPrimary: row.isPrimary! && !hasPrimary,
              createdAt: row.renditionCreatedAt!,
              wordTimings: Value(row.wordTimings),
            ),
          );
      for (final highlight in decodeTrashedHighlights(row.highlights)) {
        await _db
            .into(_db.highlights)
            .insert(
              highlight.copyWith(renditionId: Value(id)),
              mode: InsertMode.insertOrIgnore,
            );
      }
      await (_db.delete(_trash)..where((t) => t.id.equals(row.id))).go();
      await _writer.setOnlyFile(row.itemId, onlyFile: false);
      await chunkAndPersistSource(
        _db,
        itemId: row.itemId,
        ids: _ids,
        reportedBy: 'f30_content_trash',
        assignPages: true,
      );
    });
    return ContentRestoreOutcome.restored;
  }

  @override
  Stream<List<TrashedContent>> watchOf(String itemId) =>
      (_db.select(_trash)
            ..where((t) => t.itemId.equals(itemId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.trashedAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .watch()
          .map((rows) => rows.map(_toEntity).toList());

  @override
  Future<Either<Failure, int>> purgeExpired() => _guard(
    'purgeExpired',
    () async {
      final cutoff = _clock().subtract(kContentTrashRetention);
      final expired = await (_db.select(
        _trash,
      )..where((t) => t.trashedAt.isSmallerOrEqualValue(cutoff))).get();

      var purged = 0;
      for (final row in expired) {
        // La fila primero, el disco después: si el archivo se resiste, queda un
        // archivo de más —que se avisa—, nunca una papelera que promete algo
        // que ya no está.
        final deleted = await (_db.delete(
          _trash,
        )..where((t) => t.id.equals(row.id))).go();
        if (deleted == 0) continue;
        purged++;
        final path = row.relativePath;
        if (path != null && !await isFileReferenced(_db, path)) {
          await _deleteFileQuietly(path, row.itemId);
        }
      }
      return right(purged);
    },
  );

  // ---------------------------------------------------------------------

  /// El archivo y los textos de [itemId] —lo que se puede separar—, o `null`
  /// si le falta alguna de las dos mitades o ya no está vivo.
  Future<({String path, List<RenditionRow> texts})?> _halvesOf(
    String itemId,
  ) async {
    final alive = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId) & e.isActive)).getSingleOrNull();
    if (alive == null) return null;
    final path = (await _sourceOf(itemId))?.originalBlobPath;
    if (path == null) return null;
    final texts = [
      for (final text in await _mainTextsOf(itemId))
        if (text.content!.trim().isNotEmpty) text,
    ];
    if (texts.isEmpty) return null;
    return (path: path, texts: texts);
  }

  /// Las formas de texto del elemento en sí: sin las del «Contenido» (F30) ni
  /// las de bloques —esas son de las notas—.
  Future<List<RenditionRow>> _mainTextsOf(String itemId) =>
      (_db.select(_db.renditions)..where(
            (r) =>
                r.itemId.equals(itemId) &
                r.content.isNotNull() &
                r.position.isNull() &
                r.textOf.isNull() &
                r.kind.equalsValue(RenditionKind.blocks).not(),
          ))
          .get();

  Future<KnowledgeSourceRow?> _sourceOf(String itemId) => (_db.select(
    _db.knowledgeSources,
  )..where((s) => s.itemId.equals(itemId))).getSingleOrNull();

  Future<TrashedContentRow> _rowById(String id) =>
      (_db.select(_trash)..where((t) => t.id.equals(id))).getSingle();

  TrashedContent _toEntity(TrashedContentRow row) => TrashedContent(
    id: row.id,
    itemId: row.itemId,
    kind: row.kind,
    trashedAt: row.trashedAt,
    sizeBytes: row.sizeBytes,
    textLength: row.content?.length,
  );

  Failure _cannotSplit(String itemId) => Failure.unexpected(
    message:
        'El elemento $itemId no tiene archivo y texto a la vez: no hay una '
        'mitad que soltar sin dejarlo vacío.',
  );

  Future<void> _deleteFileQuietly(String path, String itemId) async {
    try {
      await _files.delete(path);
      // Catch-all deliberado: el disco puede fallar de muchas formas, y
      // ninguna vuelve atrás un vencimiento que en la base ya ocurrió.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint:
            'ContentTrashRepositoryImpl.purgeExpired: quedó el archivo de '
            '$itemId',
      );
    }
  }

  Future<Either<Failure, T>> _guard<T>(
    String name,
    Future<Either<Failure, T>> Function() body,
  ) async {
    try {
      return await body();
      // Un TypeError de una fila rara es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'ContentTrashRepositoryImpl.$name',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}

/// Los subrayados de una forma de texto, para guardarlos en la papelera con
/// ella: en la base cuelgan de la forma, y al soltarla se irían en cascada.
String encodeTrashedHighlights(List<HighlightRow> highlights) => jsonEncode([
  for (final h in highlights)
    {
      'id': h.id,
      'start': h.startOffset,
      'end': h.endOffset,
      'excerpt': h.excerpt,
      if (h.note != null) 'note': h.note,
      'createdAt': h.createdAt.millisecondsSinceEpoch,
    },
]);

/// Lo guardado por [encodeTrashedHighlights], listo para volver a la base
/// (con la forma que corresponda: ver `ContentTrashRepositoryImpl.restore`).
List<HighlightsCompanion> decodeTrashedHighlights(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  return [
    for (final raw in (jsonDecode(stored) as List).cast<Map<String, dynamic>>())
      HighlightsCompanion.insert(
        id: raw['id'] as String,
        renditionId: '',
        startOffset: raw['start'] as int,
        endOffset: raw['end'] as int,
        excerpt: raw['excerpt'] as String,
        note: Value(raw['note'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(raw['createdAt'] as int),
      ),
  ];
}
