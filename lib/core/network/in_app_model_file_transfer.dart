import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/core/network/resumable_download.dart';

/// [ModelFileTransfer] en el proceso de la app: el escritorio, las pruebas, y
/// Android si el gestor de descargas del sistema no está (ver
/// `SystemModelFileTransfer`).
///
/// Baja con [ResumableDownload], retomando por rango lo que ya está en el
/// disco, sin límite de tiempo por intento. Mientras dura hay que mantener la
/// app viva —el servicio en primer plano—, y si la app se cierra la descarga
/// se corta y se retoma desde ahí al volver a pedirla.
///
/// **Qué hay en el disco**, junto a `<destino>`:
///
/// - `<destino>.descargando`: lo bajado hasta ahora. El nombre definitivo
///   nunca es un archivo cortado.
/// - `<destino>.source`: de qué dirección es lo que está a medias, y cuánto
///   dijo el servidor que pesa entero; si cambió, se empieza de cero.
class InAppModelFileTransfer implements ModelFileTransfer {
  InAppModelFileTransfer({
    required Dio dio,
    Duration Function(int attempt)? retryDelay,
  }) : _download = ResumableDownload(dio: dio, retryDelay: retryDelay);

  final ResumableDownload _download;

  /// Las descargas en curso, por destino.
  final _running = <String, _Running>{};

  static File partialOf(File target) => File('${target.path}.descargando');
  static File _sourceOf(File target) => File('${target.path}.source');

  @override
  bool get continuesWithAppClosed => false;

  @override
  Future<int> fetch({
    required String url,
    required File target,
    Map<String, String> headers = const {},
    int? expectedBytes,
    String? label,
    Future<void> Function(File whole)? verify,
    void Function(int received, int? total)? onProgress,
  }) {
    final key = target.absolute.path;
    if (_running[key] case final running?) {
      // Otra vez el mismo archivo: se espera la que ya baja.
      if (onProgress != null) running.listeners.add(onProgress);
      return running.done;
    }
    final running = _Running();
    if (onProgress != null) running.listeners.add(onProgress);
    _running[key] = running;
    return running.done = _fetch(
      url: url,
      target: target,
      headers: headers,
      expectedBytes: expectedBytes,
      verify: verify,
      running: running,
    ).whenComplete(() => _running.remove(key));
  }

  @override
  Future<bool> isInFlight(File target) async =>
      _running.containsKey(target.absolute.path);

  @override
  Future<void> cancel(File target) async {
    final running = _running[target.absolute.path];
    if (running != null) {
      running.cancel.cancel();
      // Que termine de cerrar el archivo antes de borrarlo.
      await running.done.then<void>((_) {}, onError: (Object _) {});
    }
    for (final file in [partialOf(target), _sourceOf(target)]) {
      if (file.existsSync()) await file.delete();
    }
  }

  Future<int> _fetch({
    required String url,
    required File target,
    required Map<String, String> headers,
    required int? expectedBytes,
    required Future<void> Function(File whole)? verify,
    required _Running running,
  }) async {
    await target.parent.create(recursive: true);
    final partial = partialOf(target);
    final source = _sourceOf(target);

    // Lo que dejó con el nombre definitivo una versión anterior, sin marca de
    // terminado: entero o cortado, no se sabe. Pasa a ser lo que está a
    // medias —su `.source`, si lo tiene, ya decía de dónde salió— y la
    // descarga lo retoma: si estaba entero, el servidor contesta 416 y no se
    // baja nada.
    if (target.existsSync()) {
      if (partial.existsSync()) await partial.delete();
      await target.rename(partial.path);
    }

    final previous = _SourceRecord.read(source);
    if (previous != null && previous.url != url && partial.existsSync()) {
      // Lo que hay a medias es de otra dirección: seguir agregándole bytes
      // de esta produciría un archivo corrupto.
      await partial.delete();
    }
    final knownTotal =
        (previous?.url == url ? previous?.totalBytes : null) ?? expectedBytes;
    _SourceRecord(url: url, totalBytes: knownTotal).write(source);

    final int total;
    try {
      total = await _download.fetch(
        url: url,
        partial: partial,
        headers: headers,
        expectedBytes: knownTotal,
        // Se anota apenas el servidor lo dice: si la app se cierra a mitad,
        // el próximo intento sabe cuánto tiene que pesar lo que retoma.
        onTotal: (total) =>
            _SourceRecord(url: url, totalBytes: total).write(source),
        onProgress: (received, total) {
          for (final listener in running.listeners) {
            listener(received, total);
          }
        },
        cancelToken: running.cancel,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw const ModelDownloadCancelledException();
      }
      rethrow;
    }

    if (verify != null) {
      try {
        await verify(partial);
      } on Object {
        // Lo que no pasó la comprobación no se retoma: se empieza de cero.
        if (partial.existsSync()) await partial.delete();
        if (source.existsSync()) await source.delete();
        rethrow;
      }
    }

    await partial.rename(target.path);
    if (source.existsSync()) await source.delete();
    return total;
  }
}

/// Una descarga en curso: quiénes esperan su avance y cómo cortarla.
class _Running {
  final listeners = <void Function(int received, int? total)>[];
  final cancel = CancelToken();
  late Future<int> done;
}

/// Lo que dice `<destino>.source`: la dirección de lo que está a medias y,
/// si el servidor ya lo dijo, cuánto pesa entero. Las versiones anteriores
/// escribían solo la dirección.
class _SourceRecord {
  const _SourceRecord({required this.url, this.totalBytes});

  final String url;
  final int? totalBytes;

  static _SourceRecord? read(File file) {
    if (!file.existsSync()) return null;
    final lines = file.readAsLinesSync();
    if (lines.isEmpty) return null;
    return _SourceRecord(
      url: lines.first.trim(),
      totalBytes: lines.length > 1 ? int.tryParse(lines[1].trim()) : null,
    );
  }

  /// Sincrónico: son unos pocos bytes, y se escribe también desde el aviso
  /// del total, que no espera nada.
  void write(File file) =>
      file.writeAsStringSync(totalBytes == null ? url : '$url\n$totalBytes');
}
