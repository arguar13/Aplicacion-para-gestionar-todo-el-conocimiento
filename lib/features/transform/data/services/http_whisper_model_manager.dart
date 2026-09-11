import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El modelo Whisper multilingüe "base", cuantizado a int8: unos 160 MB en
/// total. Se prefiere a "tiny" —bastante más liviano— porque en español,
/// que es el idioma principal de quien usa esta app, "tiny" pierde
/// precisión de forma notoria; "base" sigue siendo chico para lo que es un
/// modelo de reconocimiento de voz. Ver la decisión 8 en
/// docs/arquitectura.md.
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
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main';

  static const _encoderFile = 'base-encoder.int8.onnx';
  static const _decoderFile = 'base-decoder.int8.onnx';
  static const _tokensFile = 'base-tokens.txt';
  static const _files = [_encoderFile, _decoderFile, _tokensFile];

  Future<Directory> _modelDirectory() async {
    final root = await _rootDirectory();
    return Directory(p.join(root.path, 'modelos', 'whisper-base'));
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
        final bytesBeforeThisFile = completedBytes;

        // Nombre provisorio: si la app se cierra a mitad de una descarga,
        // isReady() no tiene que confundir un archivo a medio bajar con
        // uno completo.
        final tempPath = p.join(dir.path, '.$name.descargando');

        await _dio.download(
          '$_baseUrl/$name',
          tempPath,
          onReceiveProgress: (received, _) {
            if (total <= 0) return;
            controller.add((bytesBeforeThisFile + received) / total);
          },
        );

        await File(tempPath).rename(p.join(dir.path, name));
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
}
