import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';
import 'package:web/web.dart' as web;

/// `WhisperModelManager` para la web: el modelo se guarda en el Origin
/// Private File System (OPFS), igual que `OpfsFileStore`, pero en su propia
/// carpeta —`modelos/whisper-base/`—, separada de `originales/`: un modelo
/// de reconocimiento de voz no es un archivo original de ningún elemento de
/// la biblioteca, y mezclar los dos en la misma carpeta confundiría a
/// cualquiera que la mirara.
///
/// Ver la decisión 10 en docs/arquitectura.md. `paths()` no devuelve rutas
/// reales —OPFS no las tiene— sino las que entiende el propio sistema de
/// archivos virtual de sherpa-onnx: constantes fijas, sin relación con
/// dónde vive nada en OPFS. Para que esas rutas signifiquen algo hace falta
/// [loadIntoEngine], que copia los bytes ya descargados al motor: se separa
/// de `paths()` porque solo tiene sentido llamarlo una vez, después de que
/// el motor de sherpa-onnx ya esté cargado.
///
/// Sin pruebas propias: habla con OPFS y con el motor de WebAssembly de
/// sherpa-onnx, ninguno de los dos disponible bajo `flutter test`.
/// Verificado a mano en un Chromium real (ver la fase 8 en
/// docs/arquitectura.md).
class OpfsWhisperModelManager implements WhisperModelManager {
  OpfsWhisperModelManager({required Dio dio}) : _dio = dio;

  final Dio _dio;

  static const _baseUrl =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main';

  static const _encoderFile = 'base-encoder.int8.onnx';
  static const _decoderFile = 'base-decoder.int8.onnx';
  static const _tokensFile = 'base-tokens.txt';
  static const _files = [_encoderFile, _decoderFile, _tokensFile];

  static const _folder = ['modelos', 'whisper-base'];

  /// Rutas sin ningún significado fuera del sistema de archivos virtual de
  /// sherpa-onnx: no hace falta que coincidan con nada de OPFS, alcanza con
  /// que sean siempre las mismas.
  static const _virtualEncoderPath = '/sinapsis-whisper-encoder.onnx';
  static const _virtualDecoderPath = '/sinapsis-whisper-decoder.onnx';
  static const _virtualTokensPath = '/sinapsis-whisper-tokens.txt';

  Future<web.FileSystemDirectoryHandle> _modelDirectory({
    bool create = false,
  }) async {
    var current = await web.window.navigator.storage.getDirectory().toDart;
    for (final segment in _folder) {
      current = await current
          .getDirectoryHandle(
            segment,
            web.FileSystemGetDirectoryOptions(create: create),
          )
          .toDart;
    }
    return current;
  }

  @override
  Future<bool> isReady() async {
    try {
      final dir = await _modelDirectory();
      for (final name in _files) {
        await dir.getFileHandle(name).toDart;
      }
      return true;
      // La carpeta o alguno de los archivos no existen todavía: OPFS no
      // ofrece otra forma de comprobarlo que intentar abrirlos.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return false;
    }
  }

  @override
  Future<WhisperModelPaths> paths() async {
    return const WhisperModelPaths(
      encoder: _virtualEncoderPath,
      decoder: _virtualDecoderPath,
      tokens: _virtualTokensPath,
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
      final dir = await _modelDirectory(create: true);

      // El total de los tres archivos juntos, para que el progreso avance
      // parejo en vez de saltar de golpe entre uno y el siguiente.
      final sizes = await _fileSizes();
      final total = sizes.fold(0, (sum, size) => sum + size);

      var completedBytes = 0;
      for (var i = 0; i < _files.length; i++) {
        final name = _files[i];
        final expectedSize = sizes[i];
        final bytesBeforeThisFile = completedBytes;

        final response = await _dio.get<List<int>>(
          '$_baseUrl/$name',
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: (received, _) {
            if (total <= 0) return;
            controller.add((bytesBeforeThisFile + received) / total);
          },
        );

        final fileHandle = await dir
            .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
            .toDart;
        final writable = await fileHandle.createWritable().toDart;
        await writable.write(Uint8List.fromList(response.data!).toJS).toDart;
        await writable.close().toDart;

        completedBytes += expectedSize;
      }

      controller.add(1);
      await controller.close();
      // Catch-all deliberado: cualquier cosa que salga mal acá —sin
      // conexión, OPFS lleno, el archivo ya no está en el servidor— tiene
      // que llegar como error del stream, nunca como una excepción sin
      // dueño que tumbe la pantalla que está mirando el progreso.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      controller.addError(e, stackTrace);
      await controller.close();
    }
  }

  /// Copia los tres archivos ya descargados al sistema de archivos virtual
  /// del módulo de WebAssembly de sherpa-onnx, en las rutas que devuelve
  /// [paths]: es la única forma que tiene ese motor de leer algo, no existe
  /// un `fetch()` de por medio. Solo tiene sentido llamarlo después de que
  /// `sherpa_onnx.initBindingsAsync()` haya terminado.
  Future<void> loadIntoEngine() async {
    final module = globalContext.getProperty<JSObject>('Module'.toJS);
    final fs = module.getProperty<JSObject>('FS'.toJS);
    final writeFile = fs.getProperty<JSFunction>('writeFile'.toJS);

    final dir = await _modelDirectory();
    for (final (name, virtualPath) in const [
      (_encoderFile, _virtualEncoderPath),
      (_decoderFile, _virtualDecoderPath),
      (_tokensFile, _virtualTokensPath),
    ]) {
      final fileHandle = await dir.getFileHandle(name).toDart;
      final file = await fileHandle.getFile().toDart;
      final buffer = await file.arrayBuffer().toDart;
      writeFile.callAsFunction(
        fs,
        virtualPath.toJS,
        buffer.toDart.asUint8List().toJS,
      );
    }
  }
}
