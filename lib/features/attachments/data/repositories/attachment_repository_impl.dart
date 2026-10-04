import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/domain/repositories/attachment_repository.dart';

/// [AttachmentRepository] sobre la base: los archivos son formas con
/// `position` y su texto, formas con `text_of` (v36).
class AttachmentRepositoryImpl implements AttachmentRepository {
  AttachmentRepositoryImpl(
    this._db, {
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  $AttachmentDownloadsTable get _downloads => _db.attachmentDownloads;

  // --- La lista de trabajo -------------------------------------------------

  @override
  Future<void> plan(String itemId, List<AttachmentCandidate> candidates) =>
      _db.batch((batch) {
        batch.insertAll(_downloads, [
          for (final candidate in candidates)
            AttachmentDownloadsCompanion.insert(
              id: _ids.next(),
              itemId: itemId,
              url: candidate.url.toString(),
              kind: candidate.kind,
              title: Value(candidate.title),
              position: candidate.position,
              status: AttachmentDownloadStatus.pending,
              createdAt: _clock(),
            ),
        ], mode: InsertMode.insertOrIgnore);
      });

  SimpleSelectStatement<$AttachmentDownloadsTable, AttachmentDownloadRow>
  _downloadsQuery(String itemId) => _db.select(_downloads)
    ..where((d) => d.itemId.equals(itemId))
    ..orderBy([
      (d) => OrderingTerm.asc(d.position),
      (d) => OrderingTerm.asc(d.createdAt),
    ]);

  @override
  Future<List<AttachmentDownload>> downloadsOf(String itemId) async =>
      (await _downloadsQuery(itemId).get()).map(_toDownload).toList();

  @override
  Stream<List<AttachmentDownload>> watchDownloads(String itemId) =>
      _downloadsQuery(
        itemId,
      ).watch().map((rows) => rows.map(_toDownload).toList());

  @override
  Future<void> markDownload(
    String downloadId, {
    required AttachmentDownloadStatus status,
    int? expectedBytes,
    String? renditionId,
  }) => (_db.update(_downloads)..where((d) => d.id.equals(downloadId))).write(
    AttachmentDownloadsCompanion(
      status: Value(status),
      expectedBytes: expectedBytes == null
          ? const Value.absent()
          : Value(expectedBytes),
      renditionId: renditionId == null
          ? const Value.absent()
          : Value(renditionId),
    ),
  );

  @override
  Future<int> requestRest(String itemId) => _db.transaction(() async {
    final leftOut =
        await (_db.update(_downloads)..where(
              (d) =>
                  d.itemId.equals(itemId) &
                  d.status.equalsValue(AttachmentDownloadStatus.leftOut),
            ))
            .write(
              const AttachmentDownloadsCompanion(
                status: Value(AttachmentDownloadStatus.pending),
                forced: Value(true),
              ),
            );
    final noSpace =
        await (_db.update(_downloads)..where(
              (d) =>
                  d.itemId.equals(itemId) &
                  d.status.equalsValue(AttachmentDownloadStatus.noSpace),
            ))
            .write(
              const AttachmentDownloadsCompanion(
                status: Value(AttachmentDownloadStatus.pending),
              ),
            );
    return leftOut + noSpace;
  });

  AttachmentDownload _toDownload(AttachmentDownloadRow row) =>
      AttachmentDownload(
        id: row.id,
        itemId: row.itemId,
        url: Uri.parse(row.url),
        kind: row.kind,
        position: row.position,
        status: row.status,
        title: row.title,
        forced: row.forced,
        expectedBytes: row.expectedBytes,
        renditionId: row.renditionId,
      );

  // --- Los archivos ---------------------------------------------------------

  @override
  Future<Attachment> addAttachment({
    required String itemId,
    required RenditionKind kind,
    required String relativePath,
    required int position,
    String? title,
    String? originUrl,
    String? mimeType,
    int? sizeBytes,
  }) async {
    final id = _ids.next();
    final now = _clock();
    await _db
        .into(_db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: id,
            itemId: itemId,
            kind: kind,
            isPrimary: false,
            createdAt: now,
            relativePath: Value(relativePath),
            title: Value(title),
            originUrl: Value(originUrl),
            mimeType: Value(mimeType),
            sizeBytes: Value(sizeBytes),
            position: Value(position),
          ),
        );
    return Attachment(
      id: id,
      itemId: itemId,
      kind: kind,
      relativePath: relativePath,
      position: position,
      createdAt: now,
      title: title,
      originUrl: originUrl,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
    );
  }

  /// Los archivos de [itemId], con el largo de su texto calculado en la base:
  /// el texto de un libro entero no viaja hasta acá para contarlo.
  Selectable<Attachment> _attachmentsQuery(String itemId) => _db
      .customSelect(
        '''
        SELECT f.id, f.item_id, f.kind, f.relative_path, f.position,
               f.created_at, f.title, f.origin_url, f.mime_type, f.size_bytes,
               (SELECT length(t.content) FROM renditions t
                 WHERE t.text_of = f.id
                 ORDER BY t.created_at DESC LIMIT 1) AS text_length
          FROM renditions f
         WHERE f.item_id = ? AND f.position IS NOT NULL
           AND f.relative_path IS NOT NULL
         ORDER BY f.position, f.created_at, f.id''',
        variables: [Variable.withString(itemId)],
        readsFrom: {_db.renditions},
      )
      .map(
        (row) => Attachment(
          id: row.read<String>('id'),
          itemId: row.read<String>('item_id'),
          kind: RenditionKind.values.byName(row.read<String>('kind')),
          relativePath: row.read<String>('relative_path'),
          position: row.read<int>('position'),
          createdAt: row.read<DateTime>('created_at'),
          title: row.read<String?>('title'),
          originUrl: row.read<String?>('origin_url'),
          mimeType: row.read<String?>('mime_type'),
          sizeBytes: row.read<int?>('size_bytes'),
          textLength: row.read<int?>('text_length'),
        ),
      );

  @override
  Future<List<Attachment>> attachmentsOf(String itemId) =>
      _attachmentsQuery(itemId).get();

  @override
  Stream<List<Attachment>> watchAttachments(String itemId) =>
      _attachmentsQuery(itemId).watch();

  @override
  Future<int> totalBytes(String itemId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(size_bytes), 0) AS total FROM renditions '
          'WHERE item_id = ? AND position IS NOT NULL',
          variables: [Variable.withString(itemId)],
          readsFrom: {_db.renditions},
        )
        .getSingle();
    return row.read<int>('total');
  }

  @override
  Future<String?> textOf(String attachmentId) async {
    final row =
        await (_db.select(_db.renditions)
              ..where((r) => r.textOf.equals(attachmentId))
              ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.content;
  }

  @override
  Future<void> saveText(
    String attachmentId,
    String text, {
    RenditionKind kind = RenditionKind.plainText,
  }) => _db.transaction(() async {
    final file = await (_db.select(
      _db.renditions,
    )..where((r) => r.id.equals(attachmentId))).getSingleOrNull();
    // El archivo se sacó mientras se leía: su texto no tiene dónde ir.
    if (file == null) return;
    await (_db.delete(
      _db.renditions,
    )..where((r) => r.textOf.equals(attachmentId))).go();
    await _db
        .into(_db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: _ids.next(),
            itemId: file.itemId,
            kind: kind,
            isPrimary: false,
            createdAt: _clock(),
            content: Value(text),
            textOf: Value(attachmentId),
          ),
        );
  });

  @override
  Future<String?> removeAttachment(String attachmentId) =>
      _db.transaction(() async {
        final file =
            await (_db.select(_db.renditions)..where(
                  (r) => r.id.equals(attachmentId) & r.position.isNotNull(),
                ))
                .getSingleOrNull();
        if (file == null) return null;
        // El texto se va solo, por la clave de `text_of`.
        await (_db.delete(
          _db.renditions,
        )..where((r) => r.id.equals(attachmentId))).go();
        return file.relativePath;
      });

  // --- Para la cola ---------------------------------------------------------

  @override
  Future<bool> hasWork(String itemId) async {
    final row = await _db
        .customSelect(
          '''
          SELECT EXISTS (
                   SELECT 1 FROM attachment_download
                    WHERE item_id = ?1 AND status = 'pending')
              OR EXISTS (
                   SELECT 1 FROM renditions f
                    WHERE f.item_id = ?1 AND f.position IS NOT NULL
                      AND f.kind IN ('pdf', 'document', 'image', 'audio',
                                     'video')
                      AND NOT EXISTS (SELECT 1 FROM renditions t
                                       WHERE t.text_of = f.id)) AS work''',
          variables: [Variable.withString(itemId)],
          readsFrom: {_db.renditions, _downloads},
        )
        .getSingle();
    return row.read<bool>('work');
  }
}
