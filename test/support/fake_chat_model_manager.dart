import 'dart:async';

import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';

/// Un modelo de chat de mentira: dice que está listo o no, sin tocar
/// `flutter_gemma` —que no tiene con qué hablar en un test—.
class FakeChatModelManager implements ChatModelManager {
  FakeChatModelManager({this.ready = false, this.sizeInBytes});

  /// Si el modelo ya está "descargado". Mutable a propósito.
  bool ready;

  /// Lo que devuelve `downloadSizeInBytes()`. `null` simula no haber podido
  /// calcularlo.
  int? sizeInBytes;

  /// El control de la descarga que se pidió más recientemente, para que la
  /// prueba simule su progreso, su error o que termina bien. `download()`
  /// arma uno nuevo en cada llamado, igual que la implementación real:
  /// reintentar después de un error no puede reusar un stream ya cerrado.
  /// `null` hasta el primer `download()`.
  StreamController<double>? lastDownload;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<int?> downloadSizeInBytes() async => sizeInBytes;

  @override
  Stream<double> download({String? huggingFaceToken}) {
    final controller = StreamController<double>();
    lastDownload = controller;
    return controller.stream;
  }
}
