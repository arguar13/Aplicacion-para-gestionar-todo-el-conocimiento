import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/network/bounded_download.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/domain/repositories/attachment_repository.dart';
import 'package:sinapsis/features/attachments/domain/services/linked_file_fetcher.dart';

/// Un archivo que sirve [FakeLinkedFileFetcher].
class FakeServedFile {
  const FakeServedFile(
    this.bytes, {
    this.contentType,
    this.fileName,
    this.error,
  });

  final List<int> bytes;
  final String? contentType;

  /// El nombre que ofrece el servidor; si no, el de la dirección.
  final String? fileName;

  /// Lo que lanza en vez de bajar: un 404, una IP privada…
  final Exception? error;
}

/// Baja de un mapa de direcciones, respetando el tope, y guarda en el
/// almacén que se le dé (el de memoria, en las pruebas).
class FakeLinkedFileFetcher implements LinkedFileFetcher {
  FakeLinkedFileFetcher(this.files, [Map<String, FakeServedFile>? served])
    : served = served ?? {};

  final FileStore files;
  final Map<String, FakeServedFile> served;
  final requested = <Uri>[];

  @override
  Future<FetchedFile> fetch(
    Uri url, {
    required String storeId,
    required int maxBytes,
    String? folder,
    bool unique = true,
    String? preferredName,
    bool Function(String? contentType)? accept,
    Future<void>? whenCancelled,
    void Function(int received, int? total)? onProgress,
  }) async {
    requested.add(url);
    final file = served['$url'];
    if (file == null) {
      final request = RequestOptions(path: '$url');
      throw DioException.badResponse(
        statusCode: 404,
        requestOptions: request,
        response: Response<void>(requestOptions: request, statusCode: 404),
      );
    }
    if (file.error != null) throw file.error!;
    if (accept != null && !accept(file.contentType)) {
      throw UnwantedContentException(file.contentType);
    }
    if (file.bytes.length > maxBytes) {
      throw DownloadTooLargeException(
        limit: maxBytes,
        declared: file.bytes.length,
      );
    }
    final offered =
        file.fileName ?? url.pathSegments.where((s) => s.isNotEmpty).last;
    final ext = offered.contains('.')
        ? offered.substring(offered.lastIndexOf('.'))
        : '';
    final name = preferredName == null
        ? offered
        : preferredName.endsWith(ext)
        ? preferredName
        : '$preferredName$ext';
    onProgress?.call(file.bytes.length, file.bytes.length);
    final path = await files.saveStream(
      bytes: Stream.value(file.bytes),
      suggestedName: name,
      id: storeId,
      folder: folder,
      unique: unique,
    );
    return FetchedFile(
      relativePath: path,
      bytes: file.bytes.length,
      contentType: file.contentType,
      fileName: offered,
      finalUrl: url,
    );
  }
}

/// [AttachmentRepository] en memoria.
class FakeAttachmentRepository implements AttachmentRepository {
  final downloads = <AttachmentDownload>[];
  final attachments = <Attachment>[];
  final texts = <String, String>{};
  var _next = 0;

  @override
  Future<void> plan(
    String itemId,
    List<AttachmentCandidate> candidates, {
    AttachmentDownloadStatus status = AttachmentDownloadStatus.pending,
  }) async {
    for (final c in candidates) {
      if (downloads.any((d) => d.itemId == itemId && d.url == c.url)) continue;
      downloads.add(
        AttachmentDownload(
          id: 'bajada-${_next++}',
          itemId: itemId,
          url: c.url,
          kind: c.kind,
          position: c.position,
          status: status,
          title: c.title,
          expectedBytes: c.expectedBytes,
        ),
      );
    }
  }

  @override
  Future<List<AttachmentDownload>> downloadsOf(String itemId) async =>
      downloads.where((d) => d.itemId == itemId).toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  @override
  Stream<List<AttachmentDownload>> watchDownloads(String itemId) =>
      Stream.fromFuture(downloadsOf(itemId));

  @override
  Future<void> markDownload(
    String downloadId, {
    required AttachmentDownloadStatus status,
    int? expectedBytes,
    String? renditionId,
  }) async {
    final i = downloads.indexWhere((d) => d.id == downloadId);
    final d = downloads[i];
    downloads[i] = AttachmentDownload(
      id: d.id,
      itemId: d.itemId,
      url: d.url,
      kind: d.kind,
      position: d.position,
      status: status,
      title: d.title,
      forced: d.forced,
      expectedBytes: expectedBytes ?? d.expectedBytes,
      renditionId: renditionId ?? d.renditionId,
    );
  }

  @override
  Future<int> requestRest(String itemId) async {
    var count = 0;
    for (var i = 0; i < downloads.length; i++) {
      final d = downloads[i];
      if (d.itemId != itemId) continue;
      if (d.status != AttachmentDownloadStatus.leftOut &&
          d.status != AttachmentDownloadStatus.noSpace &&
          d.status != AttachmentDownloadStatus.failed) {
        continue;
      }
      count++;
      downloads[i] = AttachmentDownload(
        id: d.id,
        itemId: d.itemId,
        url: d.url,
        kind: d.kind,
        position: d.position,
        status: AttachmentDownloadStatus.pending,
        title: d.title,
        forced: d.forced || d.status == AttachmentDownloadStatus.leftOut,
        expectedBytes: d.expectedBytes,
        renditionId: d.renditionId,
      );
    }
    return count;
  }

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
    final attachment = Attachment(
      id: 'adjunto-${_next++}',
      itemId: itemId,
      kind: kind,
      relativePath: relativePath,
      position: position,
      createdAt: DateTime(2026, 10, 4),
      title: title,
      originUrl: originUrl,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
    );
    attachments.add(attachment);
    return attachment;
  }

  Attachment _withText(Attachment a) {
    final text = texts[a.id];
    return Attachment(
      id: a.id,
      itemId: a.itemId,
      kind: a.kind,
      relativePath: a.relativePath,
      position: a.position,
      createdAt: a.createdAt,
      title: a.title,
      originUrl: a.originUrl,
      mimeType: a.mimeType,
      sizeBytes: a.sizeBytes,
      textLength: text?.length,
    );
  }

  @override
  Future<List<Attachment>> attachmentsOf(String itemId) async => [
    for (final a in attachments)
      if (a.itemId == itemId) _withText(a),
  ]..sort((a, b) => a.position.compareTo(b.position));

  @override
  Stream<List<Attachment>> watchAttachments(String itemId) =>
      Stream.fromFuture(attachmentsOf(itemId));

  @override
  Future<int> totalBytes(String itemId) async => attachments
      .where((a) => a.itemId == itemId)
      .fold<int>(0, (sum, a) => sum + (a.sizeBytes ?? 0));

  @override
  Future<String?> textOf(String attachmentId) async => texts[attachmentId];

  @override
  Future<void> saveText(
    String attachmentId,
    String text, {
    RenditionKind kind = RenditionKind.plainText,
  }) async {
    if (attachments.any((a) => a.id == attachmentId)) {
      texts[attachmentId] = text;
    }
  }

  @override
  Future<String?> removeAttachment(String attachmentId) async {
    final i = attachments.indexWhere((a) => a.id == attachmentId);
    if (i < 0) return null;
    texts.remove(attachmentId);
    return attachments.removeAt(i).relativePath;
  }

  @override
  Future<bool> hasWork(String itemId) async =>
      downloads.any(
        (d) =>
            d.itemId == itemId && d.status == AttachmentDownloadStatus.pending,
      ) ||
      (await attachmentsOf(
        itemId,
      )).any((a) => a.canHaveText && !a.textAttempted);
}
