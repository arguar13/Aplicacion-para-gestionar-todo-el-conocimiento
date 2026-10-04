import 'dart:async';

import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';

import 'fake_model_download.dart';

/// Un modelo de embeddings de mentira: dice que está listo o no, sin tocar
/// `flutter_gemma` —que no tiene con qué hablar en un test—. Mismo patrón
/// que `FakeChatModelManager`.
class FakeEmbeddingModelManager implements EmbeddingModelManager {
  FakeEmbeddingModelManager({this.ready = false, this.sizeInBytes});

  /// Si el modelo ya está "descargado". Mutable a propósito.
  bool ready;

  /// Lo que devuelve `downloadSizeInBytes()`. `null` simula no haber podido
  /// calcularlo.
  int? sizeInBytes;

  /// El control de la descarga que se pidió más recientemente. `null` hasta
  /// el primer `download()`.
  StreamController<double>? lastDownload;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<int?> downloadSizeInBytes() async => sizeInBytes;

  /// Si hay una descarga en curso a la que engancharse (F29): la que siguió
  /// con la app cerrada. Mutable a propósito.
  bool downloading = false;

  /// Cuántas veces se canceló la descarga.
  int cancelled = 0;

  @override
  Future<bool> isDownloading() async => downloading;

  @override
  Future<void> cancelDownload() async {
    cancelled++;
    downloading = false;
  }

  @override
  Stream<double> download({String? huggingFaceToken}) {
    final controller = StreamController<double>();
    lastDownload = controller;
    return readyWhenDone(controller, () => ready = true);
  }
}
