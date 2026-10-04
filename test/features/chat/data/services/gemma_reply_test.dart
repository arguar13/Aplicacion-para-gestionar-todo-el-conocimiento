import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_reply.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

import '../../../../support/fake_inference_chat.dart';

/// La respuesta del modelo de a pedazos, medida (F30).
void main() {
  late LanguageModelMeter meter;

  setUp(() => meter = LanguageModelMeter());

  test('da cada pedazo a medida que llega y anota la respuesta', () async {
    final chat = FakeInferenceChat(
      answer: (_, _) => ['Roma ', 'fue ', 'una ', 'república.'],
      tokensPerPiece: 2,
    );

    final pieces = await measuredReply(
      chat,
      meter: meter,
      kind: LanguageModelReplyKind.chat,
    ).toList();

    expect(pieces, ['Roma ', 'fue ', 'una ', 'república.']);
    final reply = meter.performance.value.chatReply!;
    expect(reply.firstToken, isNotNull);
    expect(reply.tokens, 8);
    expect(reply.words, 4);
    expect(meter.performance.value.taskReply, isNull);
  });

  test('una tarea queda aparte del chat, y su texto sale limpio', () async {
    final chat = FakeInferenceChat(
      answer: (_, _) => ['  TEMA: 2 | alta', '\n'],
    );

    final text = await collectReply(chat, meter: meter);

    expect(text, 'TEMA: 2 | alta');
    expect(meter.performance.value.taskReply, isNotNull);
    expect(meter.performance.value.chatReply, isNull);
  });

  test('una respuesta sin texto no tiene primera palabra', () async {
    final chat = FakeInferenceChat(answer: (_, _) => []);

    expect(await collectReply(chat, meter: meter), isEmpty);
    final reply = meter.performance.value.taskReply!;
    expect(reply.firstToken, isNull);
    expect(reply.tokens, isNull);
    expect(reply.wordsPerSecond, isNull);
  });
}
