import 'dart:async';
import 'dart:io';

import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/core/network/system_downloads.dart';

/// [ModelFileTransfer] con el gestor de descargas del sistema (F29): la
/// descarga sigue aunque se cierre la app o se reinicie el teléfono, retoma
/// sola y tiene su notificación. La app solo la pide, mira cuánto va
/// mientras está abierta, y al final le da su nombre definitivo.
///
/// **Qué hay en el disco**, junto a `<destino>` (dentro de
/// [SystemDownloads.directory], la única carpeta donde el sistema puede
/// escribir por la app):
///
/// - `<destino>.descargando`: lo que el sistema lleva bajado. Es suyo: la
///   app no lo toca hasta que el sistema dice que terminó.
/// - `<destino>.descarga`: el número con que el sistema reconoce la
///   descarga, y su dirección. Es lo que permite, al volver a abrir la app,
///   **engancharse a la descarga en curso** en vez de empezar otra —tocar
///   "Descargar" dos veces, o abrir la app a mitad, nunca baja dos veces—.
///
/// Hugging Face redirige cada archivo a su CDN con una dirección firmada que
/// vence en una hora (medido el 2026-10-03). Por eso al sistema se le da la
/// dirección de Hugging Face y no la del CDN: cada vez que retoma, vuelve a
/// pedirla y recibe una firma nueva. El token del usuario viaja en
/// `Authorization` en cada salto: el CDN lo ignora —contesta igual, con su
/// rango y su ETag fuerte, que es lo que el sistema necesita para retomar—.
class SystemModelFileTransfer implements ModelFileTransfer {
  SystemModelFileTransfer({
    required SystemDownloads downloads,
    this.pollInterval = const Duration(seconds: 1),
  }) : _downloads = downloads;

  final SystemDownloads _downloads;

  /// Cada cuánto se le pregunta al sistema cuánto va, mientras alguien
  /// espera la descarga.
  final Duration pollInterval;

  /// Las descargas que la app está siguiendo ahora, por destino.
  final _following = <String, _Following>{};

  static File partialOf(File target) => File('${target.path}.descargando');
  static File _recordOf(File target) => File('${target.path}.descarga');

  @override
  bool get continuesWithAppClosed => true;

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
    if (_following[key] case final following?) {
      // Ya se la está siguiendo: se espera esa.
      if (onProgress != null) following.listeners.add(onProgress);
      return following.done;
    }
    final following = _Following();
    if (onProgress != null) following.listeners.add(onProgress);
    _following[key] = following;
    return following.done = _fetch(
      url: url,
      target: target,
      headers: headers,
      expectedBytes: expectedBytes,
      label: label,
      verify: verify,
      following: following,
    ).whenComplete(() => _following.remove(key));
  }

  @override
  Future<bool> isInFlight(File target) async {
    if (_following.containsKey(target.absolute.path)) return true;
    final record = _Record.read(_recordOf(target));
    if (record == null) return false;
    final state = await _downloads.query(record.id);
    if (state.status != SystemDownloadStatus.unknown) return true;
    // El sistema ya no la tiene —se borraron los datos del gestor de
    // descargas—: no hay nada a qué engancharse, y engancharse empezaría
    // una descarga nueva que nadie pidió.
    await _recordOf(target).delete();
    return false;
  }

  @override
  Future<void> cancel(File target) async {
    final following = _following[target.absolute.path];
    following?.cancelled = true;
    // Atendido desde ya: el seguimiento puede enterarse de la cancelación
    // mientras se olvida la descarga, y un error sin nadie que lo espere se
    // da por no manejado.
    final settled = following?.done.then<void>((_) {}, onError: (Object _) {});
    final record = _Record.read(_recordOf(target));
    if (record != null) await _forget(record.id, target);
    final partial = partialOf(target);
    if (partial.existsSync()) await partial.delete();
    // Que quien esperaba se entere antes de volver.
    await settled;
  }

  Future<int> _fetch({
    required String url,
    required File target,
    required Map<String, String> headers,
    required int? expectedBytes,
    required String? label,
    required Future<void> Function(File whole)? verify,
    required _Following following,
  }) async {
    await target.parent.create(recursive: true);
    final record = _Record.read(_recordOf(target));
    var id = record?.id;

    if (record != null && record.url != url) {
      // Pedida para otra dirección: lo que baja no es esto.
      await _forget(record.id, target);
      id = null;
    } else if (id != null &&
        (await _downloads.query(id)).status == SystemDownloadStatus.unknown) {
      // El sistema la olvidó: se pide de nuevo.
      await _recordOf(target).delete();
      id = null;
    }

    if (id == null) {
      // Quien llama dice que no está entero: lo que haya con ese nombre no
      // sirve, y el sistema no escribe sobre un archivo que ya existe.
      for (final stale in [target, partialOf(target)]) {
        if (stale.existsSync()) await stale.delete();
      }
      await _ensureSpaceFor(expectedBytes);
      if (following.cancelled) throw const ModelDownloadCancelledException();
      id = await _downloads.enqueue(
        url: url,
        destination: partialOf(target),
        headers: headers,
        label: label,
      );
      if (following.cancelled) {
        // Cancelada mientras se pedía: [cancel] no tenía todavía qué olvidar.
        await _downloads.remove(id);
        throw const ModelDownloadCancelledException();
      }
      _Record(id: id, url: url).write(_recordOf(target));
    }

    return _follow(
      id: id,
      target: target,
      expectedBytes: expectedBytes,
      verify: verify,
      following: following,
    );
  }

  /// Le pregunta al sistema cuánto va hasta que termina o falla.
  Future<int> _follow({
    required int id,
    required File target,
    required int? expectedBytes,
    required Future<void> Function(File whole)? verify,
    required _Following following,
  }) async {
    while (true) {
      if (following.cancelled) throw const ModelDownloadCancelledException();
      final state = await _downloads.query(id);
      if (following.cancelled) throw const ModelDownloadCancelledException();

      switch (state.status) {
        case SystemDownloadStatus.pending:
        case SystemDownloadStatus.running:
        case SystemDownloadStatus.paused:
          following.report(
            state.downloadedBytes,
            state.totalBytes ?? expectedBytes,
          );
          await Future<void>.delayed(pollInterval);
        case SystemDownloadStatus.successful:
          return _finish(id: id, target: target, verify: verify);
        case SystemDownloadStatus.failed:
          // El sistema ya borró lo que había bajado.
          await _forget(id, target);
          throw _errorOf(state, expectedBytes);
        case SystemDownloadStatus.unknown:
          await _forget(id, target);
          throw const ModelDownloadFailedException(
            'el sistema dejó de tener la descarga',
          );
      }
    }
  }

  /// La descarga terminó: se comprueba, toma su nombre definitivo y el
  /// sistema la olvida. En ese orden, para que una app cerrada a mitad de
  /// esto la termine al volver sin perder nada.
  Future<int> _finish({
    required int id,
    required File target,
    required Future<void> Function(File whole)? verify,
  }) async {
    final partial = partialOf(target);
    if (!partial.existsSync()) {
      // Una vuelta anterior ya le dio su nombre y se cerró antes de olvidar
      // la descarga.
      if (target.existsSync()) {
        await _forget(id, target);
        return target.lengthSync();
      }
      await _forget(id, target);
      throw const ModelDownloadFailedException(
        'el sistema la dio por terminada, pero el archivo no está',
      );
    }

    if (verify != null) {
      try {
        await verify(partial);
      } on Object {
        if (partial.existsSync()) await partial.delete();
        await _forget(id, target);
        rethrow;
      }
    }

    final length = partial.lengthSync();
    await partial.rename(target.path);
    // Después del cambio de nombre: el sistema, al olvidarla, borra el
    // archivo que escribía si sigue donde lo dejó, y ya no está ahí.
    await _forget(id, target);
    return length;
  }

  /// Que el sistema olvide [id] y la app también.
  Future<void> _forget(int id, File target) async {
    final record = _recordOf(target);
    if (record.existsSync()) await record.delete();
    await _downloads.remove(id);
  }

  Future<void> _ensureSpaceFor(int? expectedBytes) async {
    if (expectedBytes == null) return;
    final free = await _downloads.freeBytes();
    if (free != null && free < expectedBytes) {
      throw InsufficientStorageException(
        requiredBytes: expectedBytes,
        availableBytes: free,
      );
    }
  }

  static Exception _errorOf(SystemDownloadState state, int? expectedBytes) {
    if (state.httpStatus case final status?) {
      return ModelDownloadHttpException(status);
    }
    return switch (state.error) {
      SystemDownloadError.insufficientSpace => InsufficientStorageException(
        requiredBytes: expectedBytes ?? state.totalBytes,
      ),
      SystemDownloadError.cannotResume => const ModelDownloadFailedException(
        'el servidor no dejó retomarla',
      ),
      _ => ModelDownloadFailedException('$state'),
    };
  }
}

/// Una descarga que la app sigue: quiénes esperan su avance y si se canceló.
class _Following {
  final listeners = <void Function(int received, int? total)>[];
  bool cancelled = false;
  late Future<int> done;

  void report(int received, int? total) {
    for (final listener in listeners) {
      listener(received, total);
    }
  }
}

/// Lo que dice `<destino>.descarga`: el número de la descarga en el sistema
/// y su dirección.
class _Record {
  const _Record({required this.id, required this.url});

  final int id;
  final String url;

  static _Record? read(File file) {
    if (!file.existsSync()) return null;
    final lines = file.readAsLinesSync();
    final id = lines.isEmpty ? null : int.tryParse(lines.first.trim());
    if (id == null || lines.length < 2) return null;
    return _Record(id: id, url: lines[1].trim());
  }

  void write(File file) => file.writeAsStringSync('$id\n$url');
}
