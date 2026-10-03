import 'dart:async';

import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

import 'fake_model_download.dart';

/// Un modelo de mentira: dice que está listo o no, y deja que la prueba
/// controle a mano el progreso de "la" descarga en curso.
class FakeWhisperModelManager implements WhisperModelManager {
  FakeWhisperModelManager({this.ready = false, this.sizeInBytes})
    : modelPaths = const WhisperModelPaths(
        encoder: '/modelo/encoder.onnx',
        decoder: '/modelo/decoder.onnx',
        tokens: '/modelo/tokens.txt',
      );

  /// Si el modelo ya está "descargado". Mutable a propósito: se puede
  /// arrancar en `false` y ponerlo en `true` a mano, o dejar que lo cambie
  /// la simulación de una descarga completa.
  bool ready;

  final WhisperModelPaths modelPaths;

  /// Lo que devuelve `downloadSizeInBytes()`. `null` simula no haber podido
  /// calcularlo.
  int? sizeInBytes;

  /// El control de la descarga que se pidió más recientemente, para que la
  /// prueba simule su progreso, su error o que termina bien. `download()`
  /// arma uno nuevo en cada llamado, igual que la implementación real:
  /// reintentar después de un error no puede reusar un stream ya cerrado.
  StreamController<double>? lastDownload;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<WhisperModelPaths> paths() async => modelPaths;

  @override
  Future<int?> downloadSizeInBytes() async => sizeInBytes;

  @override
  Stream<double> download() {
    final controller = StreamController<double>();
    lastDownload = controller;
    return readyWhenDone(controller, () => ready = true);
  }
}
