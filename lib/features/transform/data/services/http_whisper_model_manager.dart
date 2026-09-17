import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El modelo Whisper multilingüe "small", cuantizado a int8: unos 375 MB en
/// total. Se prefiere a "base" —bastante más liviano, ~160 MB— porque en
/// español, que es el idioma principal de quien usa esta app, la ganancia
/// de precisión de "base" a "small" es notoria, y el dispositivo hace el
/// trabajo una sola vez por transcripción, no en tiempo real. Ver la
/// decisión 8 en docs/arquitectura.md.
///
/// Los archivos se traen sueltos de Hugging Face —no el paquete .tar.bz2 de
/// las release de GitHub— para no tener que descomprimir bzip2 en el
/// dispositivo: es la misma fuente, publicada por quien mantiene
/// sherpa-onnx, solo que sin empaquetar.
class HttpWhisperModelManager implements WhisperModelManager {
  HttpWhisperModelManager({
    required Dio dio,
    required Future<Directory> Function() rootDirectory,
  }) : _dio = dio,
       _rootDirectory = rootDirectory;

  final Dio _dio;
  final Future<Directory> Function() _rootDirectory;

  static const _baseUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main';

  static const _encoderFile = 'small-encoder.int8.onnx';
  static const _decoderFile = 'small-decoder.int8.onnx';
  static const _tokensFile = 'small-tokens.txt';
  static const _files = [_encoderFile, _decoderFile, _tokensFile];

  Future<Directory> _modelDirectory() async {
    final root = await _rootDirectory();
    return Directory(p.join(root.path, 'modelos', 'whisper-small'));
  }

  @override
  Future<bool> isReady() async {
    final dir = await _modelDirectory();
    return _files.every((name) => File(p.join(dir.path, name)).existsSync());
  }

  @override
  Future<WhisperModelPaths> paths() async {
    final dir = await _modelDirectory();
    return WhisperModelPaths(
      encoder: p.join(dir.path, _encoderFile),
      decoder: p.join(dir.path, _decoderFile),
      tokens: p.join(dir.path, _tokensFile),
    );
  }

  @override
  Future<int?> downloadSizeInBytes() async {
    try {
      final sizes = await _fileSizes();
      // Un tamaño en 0 significa que el servidor no contestó con
      // Content-Length para ese archivo: mejor no mostrar ningún número que
      // mostrar uno incompleto.
      if (sizes.any((size) => size <= 0)) return null;

      return sizes.fold<int>(0, (total, size) => total + size);
    } on DioException {
      return null;
    }
  }

  Future<List<int>> _fileSizes() async {
    final sizes = <int>[];
    for (final name in _files) {
      final response = await _dio.head<void>('$_baseUrl/$name');
      final length = response.headers.value(Headers.contentLengthHeader);
      sizes.add(length == null ? 0 : (int.tryParse(length) ?? 0));
    }
    return sizes;
  }

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
  /// A quien usa la app no le molesta que la descarga tarde —son
  /// [_files] con nombres que pesan hasta un par de cientos de megas cada
  /// uno—, le molesta que un corte de red de un segundo, de esos que se
  /// resuelven solos, la mande de vuelta a la pantalla de error entera.
  static const _maxAttemptsPerFile = 4;

  Future<void> _runDownload(StreamController<double> controller) async {
    try {
      final dir = await _modelDirectory();
      await dir.create(recursive: true);

      // El total de los tres archivos juntos, para que el progreso avance
      // parejo en vez de saltar de golpe entre uno y el siguiente.
      final sizes = await _fileSizes();
      final total = sizes.fold(0, (sum, size) => sum + size);

      var completedBytes = 0;
      for (var i = 0; i < _files.length; i++) {
        final name = _files[i];
        final expectedSize = sizes[i];
        final finalPath = p.join(dir.path, name);

        // Un archivo que ya quedó completo de un intento anterior no se
        // vuelve a bajar: reintentar después de un corte retoma desde el
        // archivo que falló, no desde el primero de los tres — ver
        // `isReady()`, que usa el mismo criterio para saber qué falta.
        if (File(finalPath).existsSync()) {
          completedBytes += expectedSize;
          if (total > 0) controller.add(completedBytes / total);
          continue;
        }

        final bytesBeforeThisFile = completedBytes;

        // Nombre provisorio: si la app se cierra a mitad de una descarga,
        // isReady() no tiene que confundir un archivo a medio bajar con
        // uno completo.
        final tempPath = p.join(dir.path, '.$name.descargando');

        await _downloadFileWithRetry(
          url: '$_baseUrl/$name',
          tempPath: tempPath,
          onReceiveProgress: (received, _) {
            if (total <= 0) return;
            controller.add((bytesBeforeThisFile + received) / total);
          },
        );

        await File(tempPath).rename(finalPath);
        completedBytes += expectedSize;
      }

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
