import 'dart:async';

import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';

/// Un modelo de chat de mentira: dice que está listo o no, sin tocar
/// `flutter_gemma` —que no tiene con qué hablar en un test—.
class FakeChatModelManager implements ChatModelManager {
  FakeChatModelManager({this.ready = false});

  /// Si el modelo ya está "descargado". Mutable a propósito.
  bool ready;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<int?> downloadSizeInBytes() async => null;

  @override
  Stream<double> download({String? huggingFaceToken}) => const Stream.empty();
}
