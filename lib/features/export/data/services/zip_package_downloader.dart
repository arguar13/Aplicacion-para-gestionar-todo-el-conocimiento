import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sinapsis/features/export/domain/services/package_downloader.dart';
import 'package:web/web.dart' as web;

/// `PackageDownloader` para la web: arma un `.zip` en memoria con
/// `package:archive` —ya una dependencia del proyecto, para leer EPUB y
/// DOCX— y lo entrega con el mismo patrón de descarga que
/// `WebDownloadFileOpener`.
class ZipPackageDownloader implements PackageDownloader {
  const ZipPackageDownloader();

  @override
  Future<String> downloadAsZip(
    Map<String, Uint8List> files, {
    required String zipFileName,
  }) async {
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    final zipBytes = ZipEncoder().encodeBytes(archive);

    final blob = web.Blob([zipBytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    try {
      web.HTMLAnchorElement()
        ..href = url
        ..setAttribute('download', zipFileName)
        ..click();
    } finally {
      web.URL.revokeObjectURL(url);
    }

    return zipFileName;
  }
}
