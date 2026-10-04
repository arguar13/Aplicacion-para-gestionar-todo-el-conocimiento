import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';

/// Baja los archivos de los modelos de Gemma de Hugging Face, en vez de
/// dejar la descarga en manos de `background_downloader` (lo que usa
/// `flutter_gemma` por dentro para `fromHuggingFace`/`fromNetwork`).
///
/// Ese camino pasa por WorkManager en Android, que corta cualquier tarea a
/// los ~9 minutos, y ahí la tarea "falla derecho" en vez de pausarse: en
/// una conexión que no alcance a bajar el archivo entero —varios cientos de
/// megas, a veces unos pocos gigas— en esos 9 minutos, la descarga nunca
/// llega a terminar por más reintentos que haga.
///
/// Acá la descarga la hace un [ModelFileTransfer]: en Android, el gestor de
/// descargas del sistema, que sigue con la app cerrada (F29); en el
/// escritorio, la propia app, retomando por rango.
///
/// **Qué hay en el disco**, dentro de `modelos/gemma/`:
///
/// - `<nombre>`: el archivo entero.
/// - `<nombre>.completo`: la marca de que `<nombre>` quedó entero, con su
///   tamaño. Es lo que mira [isComplete] —sin red— cada vez que la app
///   arranca, para saber si el modelo está en el dispositivo.
/// - Lo que deje la transferencia mientras baja (ver cada una).
///
/// **Dónde**: en `rootDirectory`; y lo que quedó entero en `earlierRoots`
/// —antes de F29 los modelos se bajaban a la carpeta interna de la app, y
/// el gestor del sistema no puede escribir ahí— se sigue reconociendo y
/// usando donde está, sin volver a bajarlo.
class HttpGemmaModelDownloader {
  HttpGemmaModelDownloader({
    required ModelFileTransfer transfer,
    required Future<Directory> Function() rootDirectory,
    List<Future<Directory> Function()> earlierRoots = const [],
  }) : _transfer = transfer,
       _rootDirectory = rootDirectory,
       _earlierRoots = earlierRoots;

  final ModelFileTransfer _transfer;
  final Future<Directory> Function() _rootDirectory;
  final List<Future<Directory> Function()> _earlierRoots;

  /// Si la descarga sigue con la app cerrada (ver
  /// [ModelFileTransfer.continuesWithAppClosed]).
  bool get continuesWithAppClosed => _transfer.continuesWithAppClosed;

  static File _fileIn(Directory root, String fileName) =>
      File(p.join(root.path, 'modelos', 'gemma', fileName));

  /// Dónde se baja [fileName] ahora.
  Future<File> targetFile(String fileName) async =>
      _fileIn(await _rootDirectory(), fileName);

  static File _markOf(File target) => File('${target.path}.completo');

  /// Dónde está [fileName] entero, para instalarlo con `fromFile()`; `null`
  /// si no está en el dispositivo. Sin red: lo dice la marca que deja la
  /// descarga al terminar.
  ///
  /// [publishedBytes] es para lo que se bajó **antes** de que existiera la
  /// marca: esas versiones escribían directo sobre el nombre definitivo, así
  /// que un archivo con ese nombre podía estar entero o cortado. Si mide
  /// exactamente lo que Hugging Face publica para ese archivo, está entero:
  /// se marca y no se vuelve a bajar. Si mide otra cosa, no se da por bueno.
  Future<File?> completeFile(String fileName, {int? publishedBytes}) async {
    for (final root in [_rootDirectory, ..._earlierRoots]) {
      final file = _fileIn(await root(), fileName);
      if (await _isComplete(file, publishedBytes)) return file;
    }
    return null;
  }

  /// Si [fileName] está entero en el dispositivo (ver [completeFile]).
  Future<bool> isComplete(String fileName, {int? publishedBytes}) async =>
      await completeFile(fileName, publishedBytes: publishedBytes) != null;

  static Future<bool> _isComplete(File target, int? publishedBytes) async {
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

  /// Si hay una descarga de [fileName] en curso: de esta sesión o, con el
  /// gestor del sistema, una que siguió con la app cerrada y la app todavía
  /// no recogió.
  Future<bool> isDownloading(String fileName) async =>
      _transfer.isInFlight(await targetFile(fileName));

  /// Corta la descarga de [fileName] y borra lo bajado.
  Future<void> cancel(String fileName) async =>
      _transfer.cancel(await targetFile(fileName));

  /// Borra [fileName] del lugar de ahora aunque haya quedado entero, con su
  /// marca: para un modelo de varios archivos que se canceló a medias. Lo
  /// del lugar de antes no se toca.
  Future<void> discard(String fileName) async {
    final target = await targetFile(fileName);
    for (final file in [target, _markOf(target)]) {
      if (file.existsSync()) await file.delete();
    }
  }

  /// Baja [url] a [targetFile]`(fileName)` y reporta el progreso como una
  /// fracción de 0 a 1. Emite un error del stream si falla —nunca una
  /// excepción sin dueño— y cierra el stream al terminar.
  ///
  /// Si el archivo ya está entero ([isComplete]) no se baja de nuevo: el
  /// stream emite 1 y cierra, sin tocar la red. Si hay una descarga en curso
  /// —también de antes de cerrar la app—, se engancha a esa.
  ///
  /// [label] dice qué modelo es, para la notificación del sistema.
  Stream<double> download({
    required String url,
    required String fileName,
    String? token,
    int? publishedBytes,
    String? label,
  }) {
    final controller = StreamController<double>();
    unawaited(_run(controller, url, fileName, token, publishedBytes, label));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<double> controller,
    String url,
    String fileName,
    String? token,
    int? publishedBytes,
    String? label,
  ) async {
    try {
      if (!await isComplete(fileName, publishedBytes: publishedBytes)) {
        await _fetch(controller, url, fileName, token, publishedBytes, label);
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
    int? publishedBytes,
    String? label,
  ) async {
    final target = await targetFile(fileName);
    // La marca de un archivo que no está entero ya no dice nada.
    final mark = _markOf(target);
    if (mark.existsSync()) await mark.delete();
    await _discardEarlierPartials(fileName);

    final total = await _transfer.fetch(
      url: url,
      target: target,
      headers: {
        if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
      },
      expectedBytes: publishedBytes,
      label: label,
      onProgress: (received, total) {
        if (total != null && total > 0 && !controller.isClosed) {
          controller.add((received / total).clamp(0, 1));
        }
      },
    );
    await mark.writeAsString('$total');
  }

  /// Lo que quedó a medias en el lugar de antes no se puede seguir desde el
  /// lugar nuevo: se borra para no ocupar lugar de más.
  Future<void> _discardEarlierPartials(String fileName) async {
    for (final root in _earlierRoots) {
      final earlier = _fileIn(await root(), fileName);
      for (final file in [
        earlier,
        _markOf(earlier),
        InAppModelFileTransfer.partialOf(earlier),
        File('${earlier.path}.source'),
      ]) {
        if (file.existsSync()) await file.delete();
      }
    }
  }
}
