import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:sinapsis/features/transform/data/services/whisper_model_spec.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';
import 'package:web/web.dart' as web;

/// `WhisperModelManager` para la web: el modelo se guarda en el Origin
/// Private File System (OPFS), igual que `OpfsFileStore`, pero en su propia
/// carpeta —`modelos/<carpeta del modelo>/`—, separada de `originales/`: un modelo
/// de reconocimiento de voz no es un archivo original de ningún elemento de
/// la biblioteca, y mezclar los dos en la misma carpeta confundiría a
/// cualquiera que la mirara.
///
/// Qué se baja lo dice [WhisperModelSpec], igual que en el dispositivo, y
/// cada archivo se comprueba por su tamaño y su huella antes de guardarlo
/// (F23).
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
  OpfsWhisperModelManager({
    required Dio dio,
    WhisperModelSpec spec = WhisperModelSpec.smallWithAttention,
  }) : _dio = dio,
       _spec = spec;

  final Dio _dio;
  final WhisperModelSpec _spec;

  /// Rutas sin ningún significado fuera del sistema de archivos virtual de
  /// sherpa-onnx: no hace falta que coincidan con nada de OPFS, alcanza con
  /// que sean siempre las mismas.
  static const _virtualEncoderPath = '/sinapsis-whisper-encoder.onnx';
  static const _virtualDecoderPath = '/sinapsis-whisper-decoder.onnx';
  static const _virtualTokensPath = '/sinapsis-whisper-tokens.txt';

  Future<web.FileSystemDirectoryHandle> _modelsDirectory({
    bool create = false,
  }) async {
    final root = await web.window.navigator.storage.getDirectory().toDart;
    return root
        .getDirectoryHandle(
          'modelos',
          web.FileSystemGetDirectoryOptions(create: create),
        )
        .toDart;
  }

  Future<web.FileSystemDirectoryHandle> _modelDirectory({
    bool create = false,
  }) async => (await _modelsDirectory(create: create))
      .getDirectoryHandle(
        _spec.folder,
        web.FileSystemGetDirectoryOptions(create: create),
      )
      .toDart;

  @override
  Future<bool> isReady() async {
    try {
      final dir = await _modelDirectory();
      for (final spec in _spec.files) {
        final handle = await dir.getFileHandle(spec.name).toDart;
        final file = await handle.getFile().toDart;
        if (file.size != spec.bytes) return false;
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

  /// Se sabe de antemano —los tamaños están verificados—.
  @override
  Future<int?> downloadSizeInBytes() async => _spec.totalBytes;

  /// La descarga en curso, para poder cortarla.
  CancelToken? _cancel;

  /// En la web la descarga vive en la pestaña: cerrada la pestaña, no hay
  /// nada a qué engancharse.
  @override
  Future<bool> isDownloading() async => false;

  /// Lo bajado está en memoria hasta que el archivo entero pasa a OPFS:
  /// cortar la descarga no deja nada que borrar.
  @override
  Future<void> cancelDownload() async => _cancel?.cancel();

  @override
  Stream<double> download() {
    final controller = StreamController<double>();
    unawaited(_runDownload(controller));
    return controller.stream;
  }

  Future<void> _runDownload(StreamController<double> controller) async {
    final cancel = _cancel = CancelToken();
    try {
      final dir = await _modelDirectory(create: true);

      // El total de los tres archivos juntos, para que el progreso avance
      // parejo en vez de saltar de golpe entre uno y el siguiente.
      final total = _spec.totalBytes;

      var completedBytes = 0;
      for (final spec in _spec.files) {
        final bytesBeforeThisFile = completedBytes;

        final response = await _dio.get<List<int>>(
          _spec.urlOf(spec),
          cancelToken: cancel,
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: (received, _) =>
              controller.add((bytesBeforeThisFile + received) / total),
        );
        final bytes = Uint8List.fromList(response.data!);
        // Antes de guardarlo: lo que no coincide no llega a OPFS.
        if (bytes.length != spec.bytes ||
            sha256.convert(bytes).toString() != spec.sha256) {
          throw WhisperModelIntegrityException(spec.name);
        }

        final fileHandle = await dir
            .getFileHandle(
              spec.name,
              web.FileSystemGetFileOptions(create: true),
            )
            .toDart;
        final writable = await fileHandle.createWritable().toDart;
        await writable.write(bytes.toJS).toDart;
        await writable.close().toDart;

        completedBytes += spec.bytes;
      }

      // El modelo de antes, ya reemplazado por uno entero y verificado.
      final models = await _modelsDirectory();
      for (final folder in _spec.replaces) {
        try {
          await models
              .removeEntry(folder, web.FileSystemRemoveOptions(recursive: true))
              .toDart;
          // No estaba: nada que borrar.
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {}
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
    for (final (name, virtualPath) in [
      (_spec.encoder.name, _virtualEncoderPath),
      (_spec.decoder.name, _virtualDecoderPath),
      (_spec.tokens.name, _virtualTokensPath),
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
