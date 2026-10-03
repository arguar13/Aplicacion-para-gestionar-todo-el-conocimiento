import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/resumable_download.dart';

/// Baja el archivo de un modelo de Hugging Face con reanudación de verdad,
/// en vez de dejar la descarga en manos de `background_downloader` (lo que
/// usa `flutter_gemma` por dentro para `fromHuggingFace`/`fromNetwork`).
///
/// Ese camino pasa por WorkManager en Android, que corta cualquier tarea a
/// los ~9 minutos; retoma sola si el servidor lo permite, pero Hugging Face
/// sirve ETags débiles y no cumple lo que `background_downloader` necesita
/// para confiar en una reanudación, así que ahí la tarea "falla derecho" en
/// vez de pausarse. En una conexión que no alcance a bajar el archivo
/// entero —varios cientos de megas, a veces unos pocos gigas— en esos 9
/// minutos, la descarga nunca llega a terminar por más reintentos que haga.
///
/// Acá, en cambio, la descarga corre en el propio proceso de la app —con el
/// servicio en primer plano mientras dura, para que siga con la app
/// minimizada—, sin ningún límite de tiempo por intento, y si se corta
/// retoma desde el byte donde se quedó (`ResumableDownload`).
///
/// **Qué hay en el disco**, dentro de `modelos/gemma/`:
///
/// - `<nombre>.descargando`: lo bajado hasta ahora. El nombre definitivo
///   nunca es un archivo cortado.
/// - `<nombre>.source`: de qué dirección es lo que está a medias, y cuánto
///   dijo el servidor que pesa entero; si cambió, se empieza de cero.
/// - `<nombre>`: el archivo entero.
/// - `<nombre>.completo`: la marca de que `<nombre>` quedó entero, con su
///   tamaño. Es lo que mira [isComplete] —sin red— cada vez que la app
///   arranca, para saber si el modelo está en el dispositivo.
class HttpGemmaModelDownloader {
  HttpGemmaModelDownloader({
    required Dio dio,
    required Future<Directory> Function() rootDirectory,
    Duration Function(int attempt)? retryDelay,
  }) : _download = ResumableDownload(dio: dio, retryDelay: retryDelay),
       _rootDirectory = rootDirectory;

  final ResumableDownload _download;
  final Future<Directory> Function() _rootDirectory;

  /// Dónde queda el archivo entero, para instalarlo con `fromFile()`.
  Future<File> targetFile(String fileName) async {
    final root = await _rootDirectory();
    return File(p.join(root.path, 'modelos', 'gemma', fileName));
  }

  static File _partialOf(File target) => File('${target.path}.descargando');
  static File _sourceOf(File target) => File('${target.path}.source');
  static File _markOf(File target) => File('${target.path}.completo');

  /// Si [fileName] está entero en el dispositivo. Sin red: lo dice la marca
  /// que deja la descarga al terminar.
  ///
  /// [publishedBytes] es para lo que se bajó **antes** de que existiera la
  /// marca: esas versiones escribían directo sobre el nombre definitivo, así
  /// que un archivo con ese nombre podía estar entero o cortado. Si mide
  /// exactamente lo que Hugging Face publica para ese archivo, está entero:
  /// se marca y no se vuelve a bajar. Si mide otra cosa, no se da por bueno
  /// —la próxima descarga lo retoma, y si ya estaba entero el servidor lo
  /// dice con un 416 sin mandar un byte—.
  Future<bool> isComplete(String fileName, {int? publishedBytes}) async {
    final target = await targetFile(fileName);
    if (!target.existsSync()) return false;
    final length = target.lengthSync();

    final mark = _markOf(target);
    if (mark.existsSync()) {
      return int.tryParse(mark.readAsStringSync().trim()) == length;
    }
    if (publishedBytes != null && length == publishedBytes) {
      await mark.writeAsString('$length');
      return true;
    }
    return false;
  }

  /// Baja [url] a [targetFile]`(fileName)` y reporta el progreso como una
  /// fracción de 0 a 1. Emite un error del stream si se agotan los
  /// reintentos —nunca una excepción sin dueño— y cierra el stream al
  /// terminar.
  ///
  /// Si el archivo ya está entero ([isComplete]) no se baja de nuevo: el
  /// stream emite 1 y cierra, sin tocar la red.
  Stream<double> download({
    required String url,
    required String fileName,
    String? token,
    int? publishedBytes,
  }) {
    final controller = StreamController<double>();
    unawaited(_run(controller, url, fileName, token, publishedBytes));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<double> controller,
    String url,
    String fileName,
    String? token,
    int? publishedBytes,
  ) async {
    try {
      if (!await isComplete(fileName, publishedBytes: publishedBytes)) {
        await _fetch(controller, url, fileName, token);
      }
      controller.add(1);
      await controller.close();
    } on Object catch (e, stackTrace) {
      // Cualquier fallo —la red, el disco— llega como error del stream,
      // nunca como una excepción sin dueño que tumbe la pantalla.
      controller.addError(e, stackTrace);
      await controller.close();
    }
  }

  Future<void> _fetch(
    StreamController<double> controller,
    String url,
    String fileName,
    String? token,
  ) async {
    final target = await targetFile(fileName);
    await target.parent.create(recursive: true);
    final partial = _partialOf(target);
    final source = _sourceOf(target);

    // Lo que dejó con el nombre definitivo una versión anterior, sin marca y
    // sin el tamaño publicado: entero o cortado, no se sabe. Pasa a ser lo
    // que está a medias —su `.source`, si lo tiene, ya decía de dónde
    // salió— y la descarga lo retoma: si estaba entero, el servidor contesta
    // 416 y no se baja nada.
    if (target.existsSync()) {
      if (partial.existsSync()) await partial.delete();
      final mark = _markOf(target);
      if (mark.existsSync()) await mark.delete();
      await target.rename(partial.path);
    }

    final previous = _SourceRecord.read(source);
    if (previous != null && previous.url != url && partial.existsSync()) {
      // Lo que hay a medias es de otra dirección: seguir agregándole bytes
      // de esta produciría un archivo corrupto.
      await partial.delete();
    }
    final knownTotal = previous?.url == url ? previous?.totalBytes : null;
    _SourceRecord(url: url, totalBytes: knownTotal).write(source);

    final total = await _download.fetch(
      url: url,
      partial: partial,
      headers: {
        if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
      },
      expectedBytes: knownTotal,
      // Se anota apenas el servidor lo dice: si la app se cierra a mitad, el
      // próximo intento sabe cuánto tiene que pesar lo que retoma.
      onTotal: (total) =>
          _SourceRecord(url: url, totalBytes: total).write(source),
      onProgress: (received, total) {
        if (total != null && total > 0 && !controller.isClosed) {
          controller.add((received / total).clamp(0, 1));
        }
      },
    );

    await partial.rename(target.path);
    await _markOf(target).writeAsString('$total');
    if (source.existsSync()) await source.delete();
  }
}

/// Lo que dice `<nombre>.source`: la dirección de lo que está a medias y,
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

  /// Sincrónico: son unos pocos bytes, y [HttpGemmaModelDownloader] lo
  /// escribe también desde el aviso del total, que no espera nada.
  void write(File file) =>
      file.writeAsStringSync(totalBytes == null ? url : '$url\n$totalBytes');
}
