import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

import '../../../../support/fake_inference_chat.dart';
import '../../../../support/fake_inference_model.dart';

/// `GemmaChatModel` sobre un `flutter_gemma` de mentira (F30).
void main() {
  late FakeInferenceModel model;
  late GemmaChatModel gemma;

  setUp(() {
    model = FakeInferenceModel(
      newChat: (n) => FakeInferenceChat(
        id: n,
        answer: (_, prompt) => [
          if (prompt.contains('Temas:')) 'TEMA: 1 | alta' else 'Un resumen.',
        ],
      ),
    );
    final meter = LanguageModelMeter();
    gemma = GemmaChatModel(
      gate: LanguageModelGate(),
      engine: GemmaEngine(
        ensureReady: () async => true,
        meter: meter,
        load: (_) async => model,
      ),
      meter: meter,
      countTokens: (_, text) async => (text.length / 4).ceil(),
    );
  });

  group('cada uso tiene su tope de largo', () {
    test('elegir un tema: una línea', () async {
      final choice = await gemma.chooseSpace(
        itemTitle: 'El Senado',
        excerpt: 'El Senado romano…',
        spaces: ['Roma', 'Grecia'],
      );

      expect(choice, isNotNull);
      expect(model.opened.single.maxOutputTokens, kChoiceReplyTokens);
      expect(model.chats.single.closed, isTrue);
    });

    test('un resumen: unos párrafos', () async {
      expect(await gemma.summarize(content: 'Texto largo…'), 'Un resumen.');
      expect(model.opened.single.maxOutputTokens, kSummaryReplyTokens);
    });

    test('las tarjetas: según cuántas se piden', () async {
      await gemma.generate(content: 'Texto…', count: 4);

      expect(model.opened.single.maxOutputTokens, draftsReplyTokens(4));
      expect(draftsReplyTokens(4), greaterThan(draftsReplyTokens(1)));
    });

    test('una charla: lo de una respuesta del chat', () async {
      final conversation = await gemma.startConversation();

      expect(model.opened.single.maxOutputTokens, kChatReplyTokens);
      await conversation.close();
    });
  });
}
