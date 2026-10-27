import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/language_model_tasks.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/model_backend.dart';

/// Un motor que anota con qué «Pensar más» se mandó cada mensaje.
class _Backend implements ModelBackend {
  final conversation = _Conversation();

  @override
  ModelBackend get forBackground => this;

  @override
  int get contextTokens => 1000000;

  @override
  bool get isWarm => true;

  @override
  Future<void> warmUp() async {}

  @override
  Future<ModelExchange> openExchange({
    required String instruction,
    required int maxOutputTokens,
  }) => throw UnimplementedError();

  @override
  Future<ModelConversation> openConversation({
    required String instruction,
    required int maxOutputTokens,
  }) async => conversation;
}

class _Conversation implements ModelConversation {
  final thinkMore = <bool>[];

  @override
  ChatReplyStream send({
    required String prompt,
    required String said,
    List<Uint8List> images = const [],
    bool thinkMore = false,
  }) {
    this.thinkMore.add(thinkMore);
    return Stream.value('ok');
  }

  @override
  Future<void> close() async {}
}

/// «Pensar más» (F42) pasa por las dos charlas del chat hasta el motor, que es
/// quien sabe si su modelo lo permite.
void main() {
  late _Backend backend;
  late LanguageModelTasks tasks;

  setUp(() {
    backend = _Backend();
    tasks = LanguageModelTasks(gate: LanguageModelGate(), backend: backend);
  });

  test('la conversación libre lo pasa tal cual', () async {
    final chat = await tasks.startConversation();
    await chat.send('a', thinkMore: true).toList();
    await chat.send('b').toList();

    expect(backend.conversation.thinkMore, [true, false]);
  });

  test('la de la bóveda también', () async {
    final chat = await tasks.startVaultConversation();
    await chat.send(message: 'a', sources: const [], thinkMore: true).toList();
    await chat.send(message: 'b', sources: const []).toList();

    expect(backend.conversation.thinkMore, [true, false]);
  });
}
