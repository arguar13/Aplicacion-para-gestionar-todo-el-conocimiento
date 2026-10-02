import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
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
  }) : _dio = dio,
       _rootDirectory = rootDirectory,
       _spec = spec;

  final Dio _dio;
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

  /// Cuántas veces se reintenta un archivo que falló por algo transitorio
  /// —la conexión se cortó un instante, el servidor contestó 5xx— antes de
  /// rendirse y dejar que el error llegue a la pantalla.
  ///
  /// A quien usa la app no le molesta que la descarga tarde —son tres
  /// archivos que pesan hasta un par de cientos de megas cada uno—, le
  /// molesta que un corte de red de un segundo, de esos que se resuelven
  /// solos, la mande de vuelta a la pantalla de error entera.
  static const _maxAttemptsPerFile = 4;

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
        // uno completo.
        final tempPath = p.join(dir.path, '.${file.name}.descargando');

        await _downloadFileWithRetry(
          url: _spec.urlOf(file),
          tempPath: tempPath,
          onReceiveProgress: (received, _) =>
              controller.add((bytesBeforeThisFile + received) / total),
        );
        await _verify(File(tempPath), file);

        await File(tempPath).rename(finalPath);
        completedBytes += file.bytes;
      }

      await _deleteReplacedModels();
      controller.add(1);
      await controller.close();
      // Catch-all deliberado: cualquier cosa que salga mal acá —sin
      // conexión, disco lleno, el archivo ya no está en el servidor— tiene
      // que llegar como error del stream, nunca como una excepción sin
      // dueño que tumbe la pantalla que está mirando el progreso.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
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

  /// Baja un archivo a [tempPath], reintentando hasta [_maxAttemptsPerFile]
  /// veces si `dio` lo corta por algo transitorio —sin resumir desde donde
  /// se cortó, que reintentar entero sigue siendo mucho más barato que
  /// perder los otros dos archivos que sí llegaron enteros—, con una espera
  /// creciente entre intento e intento: un corte de un segundo no necesita
  /// el mismo respiro que uno de treinta.
  Future<void> _downloadFileWithRetry({
    required String url,
    required String tempPath,
    required void Function(int received, int total) onReceiveProgress,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await _dio.download(
          url,
          tempPath,
          onReceiveProgress: onReceiveProgress,
        );
        return;
      } on DioException {
        if (attempt >= _maxAttemptsPerFile) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }
}
