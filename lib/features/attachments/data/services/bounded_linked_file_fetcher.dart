import 'dart:async';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/bounded_download.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/attachments/domain/services/linked_file_fetcher.dart';

/// [LinkedFileFetcher] sobre [BoundedDownloader], guardando en el almacén de
/// archivos.
class BoundedLinkedFileFetcher implements LinkedFileFetcher {
  const BoundedLinkedFileFetcher({
    required BoundedDownloader downloader,
    required FileStore files,
  }) : _downloader = downloader,
       _files = files;

  final BoundedDownloader _downloader;
  final FileStore _files;

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
    final cancel = CancelToken();
    unawaited(
      whenCancelled?.then((_) {
        if (!cancel.isCancelled) cancel.cancel('Se abandonó la bajada.');
      }),
    );
    final result = await _downloader.download(
      url,
      maxBytes: maxBytes,
      accept: accept,
      cancelToken: cancel,
      onProgress: onProgress,
      save: (bytes, offeredName) => _files.saveStream(
        bytes: bytes,
        suggestedName: fileNameFor(
          preferred: preferredName,
          offered: offeredName,
        ),
        id: storeId,
        folder: folder,
        unique: unique,
      ),
    );
    return FetchedFile(
      relativePath: result.savedAs,
      bytes: result.bytes,
      contentType: result.contentType,
      fileName: result.fileName,
      finalUrl: result.finalUrl,
    );
  }
}

/// El nombre con que se guarda un archivo bajado: el que le da la página
/// —el texto del enlace, "Informe anual 2026"— si lo hay, con la extensión
/// del archivo que llegó si no trae una; si no, el que ofrece el servidor.
///
/// El nombre de la página se prefiere porque es el que la persona reconoce:
/// el servidor suele ofrecer `doc_8812.pdf`.
String fileNameFor({required String offered, String? preferred}) {
  final wanted = preferred?.trim();
  if (wanted == null || wanted.isEmpty) return offered;
  final offeredExtension = p.extension(offered);
  final wantedExtension = p.extension(wanted);
  if (wantedExtension.isNotEmpty &&
      wantedExtension.toLowerCase() == offeredExtension.toLowerCase()) {
    return wanted;
  }
  return '$wanted$offeredExtension';
}
