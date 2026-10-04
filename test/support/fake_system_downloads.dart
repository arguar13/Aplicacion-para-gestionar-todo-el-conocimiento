import 'dart:io';

import 'package:sinapsis/core/network/system_downloads.dart';

/// Una descarga del gestor del sistema de mentira.
class FakeSystemDownload {
  FakeSystemDownload({
    required this.url,
    required this.destination,
    required this.headers,
    this.label,
  });

  final String url;
  final File destination;
  final Map<String, String> headers;
  final String? label;
  SystemDownloadState state = const SystemDownloadState(
    status: SystemDownloadStatus.pending,
  );
}

/// El gestor de descargas del sistema de mentira (F29): las descargas no
/// avanzan solas; la prueba hace de sistema con [progress], [finish] y
/// [fail]. Como el de verdad, sobrevive a "cerrar la app": una prueba puede
/// armar otro `SystemModelFileTransfer` —la app vuelta a abrir— sobre el
/// mismo.
class FakeSystemDownloads implements SystemDownloads {
  FakeSystemDownloads(this.directory);

  @override
  final Directory directory;

  /// Las descargas que el sistema conoce, por número.
  final downloads = <int, FakeSystemDownload>{};

  /// Todas las que se pidieron, en orden.
  final enqueued = <FakeSystemDownload>[];

  /// Los números que se le pidió olvidar.
  final removed = <int>[];

  /// El lugar libre que dice el sistema; `null` si no lo sabe.
  int? free;

  var _nextId = 1;

  @override
  Future<int> enqueue({
    required String url,
    required File destination,
    Map<String, String> headers = const {},
    String? label,
  }) async {
    final id = _nextId++;
    final download = FakeSystemDownload(
      url: url,
      destination: destination,
      headers: headers,
      label: label,
    );
    downloads[id] = download;
    enqueued.add(download);
    return id;
  }

  @override
  Future<SystemDownloadState> query(int id) async =>
      downloads[id]?.state ?? const SystemDownloadState.unknown();

  /// Como `DownloadManager.remove`: la corta, y borra el archivo que
  /// escribía si sigue en su lugar.
  @override
  Future<void> remove(int id) async {
    removed.add(id);
    final download = downloads.remove(id);
    if (download != null && download.destination.existsSync()) {
      download.destination.deleteSync();
    }
  }

  @override
  Future<int?> freeBytes() async => free;

  /// El sistema lleva [bytes] de [total], escritos en el destino.
  void progress(int id, List<int> bytes, int total) {
    final download = downloads[id]!;
    download.destination
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    download.state = SystemDownloadState(
      status: SystemDownloadStatus.running,
      downloadedBytes: bytes.length,
      totalBytes: total,
    );
  }

  /// El sistema terminó de bajar [bytes].
  void finish(int id, List<int> bytes) {
    final download = downloads[id]!;
    download.destination
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    download.state = SystemDownloadState(
      status: SystemDownloadStatus.successful,
      downloadedBytes: bytes.length,
      totalBytes: bytes.length,
    );
  }

  /// El sistema se rindió: como el de verdad, borra lo que había bajado.
  void fail(int id, {int? httpStatus, SystemDownloadError? error}) {
    final download = downloads[id]!;
    if (download.destination.existsSync()) download.destination.deleteSync();
    download.state = SystemDownloadState(
      status: SystemDownloadStatus.failed,
      httpStatus: httpStatus,
      error: error,
    );
  }

  /// El número de la única descarga que el sistema conoce.
  int get onlyId => downloads.keys.single;
}
