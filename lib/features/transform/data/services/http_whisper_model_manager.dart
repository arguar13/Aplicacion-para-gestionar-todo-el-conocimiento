import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/resumable_download.dart';
import 'package:sinapsis/features/transform/data/services/whisper_model_spec.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El modelo Whisper multilingüe "small", cuantizado a int8: unos 375 MB en
/// total. Se prefiere a "base" —bastante más liviano, ~160 MB— porque en
/// español, que es el idioma principal de quien usa esta app, la ganancia
/// de precisión de "base" a "small" es notoria, y el dispositivo hace el
/// trabajo una sola vez por transcripción, no en tiempo real. Ver la
/// decisión 8 en docs/arquitectura.md.
///
/// Qué se baja y de dónde lo dice [WhisperModelSpec]: desde F23, la
/// exportación que permite saber cuándo se dice cada palabra. Los archivos
/// se traen sueltos de Hugging Face —no un paquete .tar.bz2— para no tener
/// que descomprimir bzip2 en el dispositivo, y **cada uno se comprueba por
/// su tamaño y su huella SHA-256** antes de usarlo: uno que no coincide se
/// descarta y la descarga falla, en vez de dejar un modelo a medias o
/// distinto del verificado.
class HttpWhisperModelManager implements WhisperModelManager {
  HttpWhisperModelManager({
    required Dio dio,
    required Future<Directory> Function() rootDirectory,
    WhisperModelSpec spec = WhisperModelSpec.smallWithAttention,
    Duration Function(int attempt)? retryDelay,
  }) : _download = ResumableDownload(dio: dio, retryDelay: retryDelay),
       _rootDirectory = rootDirectory,
       _spec = spec;

  final ResumableDownload _download;
  final Future<Directory> Function() _rootDirectory;
  final WhisperModelSpec _spec;

  Future<Directory> _modelsDirectory() async =>
      Directory(p.join((await _rootDirectory()).path, 'modelos'));

  Future<Directory> _modelDirectory() async =>
      Directory(p.join((await _modelsDirectory()).path, _spec.folder));

  /// Un archivo cuenta como bajado si está con su tamaño exacto. La huella
  /// se comprueba al bajarlo, no cada vez: leer 375 MB antes de cada
  /// transcripción costaría segundos.
  static bool _isComplete(File file, WhisperModelFile spec) =>
      file.existsSync() && file.lengthSync() == spec.bytes;

  @override
  Future<bool> isReady() async {
    final dir = await _modelDirectory();
    return _spec.files.every(
      (f) => _isComplete(File(p.join(dir.path, f.name)), f),
    );
  }

  @override
  Future<WhisperModelPaths> paths() async {
    final dir = await _modelDirectory();
    return WhisperModelPaths(
      encoder: p.join(dir.path, _spec.encoder.name),
      decoder: p.join(dir.path, _spec.decoder.name),
      tokens: p.join(dir.path, _spec.tokens.name),
    );
  }

  /// Se sabe de antemano —los tamaños están verificados—: sin preguntarle
  /// nada al servidor, también sin conexión.
  @override
  Future<int?> downloadSizeInBytes() async => _spec.totalBytes;

  @override
  Stream<double> download() {
    final controller = StreamController<double>();
    unawaited(_runDownload(controller));
    return controller.stream;
  }

  Future<void> _runDownload(StreamController<double> controller) async {
    try {
      final dir = await _modelDirectory();
      await dir.create(recursive: true);

      // El total de los tres archivos juntos, para que el progreso avance
      // parejo en vez de saltar de golpe entre uno y el siguiente.
      final total = _spec.totalBytes;
      var completedBytes = 0;
      for (final file in _spec.files) {
        final finalPath = p.join(dir.path, file.name);

        // Un archivo que ya quedó completo de un intento anterior no se
        // vuelve a bajar: reintentar después de un corte retoma desde el
        // archivo que falló, no desde el primero de los tres — ver
        // `isReady()`, que usa el mismo criterio para saber qué falta.
        if (_isComplete(File(finalPath), file)) {
          completedBytes += file.bytes;
          controller.add(completedBytes / total);
          continue;
        }

        final bytesBeforeThisFile = completedBytes;

        // Nombre provisorio: si la app se cierra a mitad de una descarga,
        // isReady() no tiene que confundir un archivo a medio bajar con
        // uno completo. Y no se borra al volver a empezar: lo que ya tiene
        // se retoma por rango —el servidor lo admite, también tras la
        // redirección al CDN (comprobado el 2026-10-03)—. Lo que se pegue
        // mal lo descarta la huella, abajo.
        final tempPath = p.join(dir.path, '.${file.name}.descargando');

        await _download.fetch(
          url: _spec.urlOf(file),
          partial: File(tempPath),
          expectedBytes: file.bytes,
          onProgress: (received, _) =>
              controller.add((bytesBeforeThisFile + received) / total),
        );
        await _verify(File(tempPath), file);

        await File(tempPath).rename(finalPath);
        completedBytes += file.bytes;
      }

      await _deleteReplacedModels();
      controller.add(1);
      await controller.close();
    } on Object catch (e, stackTrace) {
      // Cualquier cosa que salga mal acá —sin conexión, disco lleno, el
      // archivo ya no está en el servidor— tiene que llegar como error del
      // stream, nunca como una excepción sin dueño que tumbe la pantalla que
      // está mirando el progreso.
      controller.addError(e, stackTrace);
      await controller.close();
    }
  }

  /// Que [downloaded] sea exactamente [expected]: tamaño y huella. Si no,
  /// se borra —no queda nada a medias que `isReady()` pudiera aceptar— y
  /// la descarga falla.
  Future<void> _verify(File downloaded, WhisperModelFile expected) async {
    final matches =
        downloaded.lengthSync() == expected.bytes &&
        (await sha256.bind(downloaded.openRead()).first).toString() ==
            expected.sha256;
    if (matches) return;
    await downloaded.delete();
    throw WhisperModelIntegrityException(expected.name);
  }

  /// El modelo de antes, ya reemplazado por uno entero y verificado: sus
  /// 375 MB no sirven más.
  Future<void> _deleteReplacedModels() async {
    final models = await _modelsDirectory();
    for (final folder in _spec.replaces) {
      final old = Directory(p.join(models.path, folder));
      if (old.existsSync()) await old.delete(recursive: true);
    }
  }
}
