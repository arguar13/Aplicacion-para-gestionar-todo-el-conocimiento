import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_inference_chat.dart';

/// Un modelo de `flutter_gemma` de mentira: abre sesiones de
/// [FakeInferenceChat] y anota con qué se abrieron y si se cerró.
class FakeInferenceModel extends Fake implements InferenceModel {
  FakeInferenceModel({
    this.activeBackend = PreferredBackend.gpu,
    this.maxTokens = 2048,
    this.newChat,
  });

  @override
  final PreferredBackend? activeBackend;

  @override
  final int maxTokens;

  /// Arma la sesión número N; por defecto, una [FakeInferenceChat] común.
  final FakeInferenceChat Function(int n)? newChat;

  /// Las sesiones abiertas, en orden.
  final chats = <FakeInferenceChat>[];

  /// Con qué instrucción y qué tope de salida se abrió cada sesión.
  final opened = <({String? instruction, int? maxOutputTokens, bool? image})>[];

  bool closed = false;

  @override
  Future<InferenceChat> createChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    int tokenBuffer = 256,
    String? loraPath,
    bool? supportImage,
    bool? supportAudio,
    List<Tool> tools = const [],
    bool? supportsFunctionCalls,
    bool isThinking = false,
    ModelType? modelType,
    ToolChoice toolChoice = ToolChoice.auto,
    int? maxFunctionBufferLength,
    String? systemInstruction,
    int? maxOutputTokens,
  }) async {
    if (closed) throw StateError('modelo cerrado');
    final chat =
        newChat?.call(chats.length + 1) ??
        FakeInferenceChat(id: chats.length + 1);
    chats.add(chat);
    opened.add((
      instruction: systemInstruction,
      maxOutputTokens: maxOutputTokens,
      image: supportImage,
    ));
    return chat;
  }

  @override
  Future<void> close() async => closed = true;
}
