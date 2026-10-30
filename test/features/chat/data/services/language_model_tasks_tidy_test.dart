import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/processed/domain/services/text_tidier.dart';

import '../../../../support/fake_inference_chat.dart';
import '../../../../support/fake_inference_model.dart';

/// Ordenar un pedazo del texto extraído al triar (F45, decisión B), con el
/// modelo de la persona —acá, un Gemma de mentira que contesta lo grabado—.
void main() {
  late FakeInferenceModel model;
  const reply = 'La república romana cayó.';

  GemmaChatModel build({int contextTokens = kGemmaContextTokens}) {
    final meter = LanguageModelMeter();
    return GemmaChatModel(
      gate: LanguageModelGate(),
      engine: GemmaEngine(
        ensureReady: () async => true,
        meter: meter,
        contextTokens: contextTokens,
        load: (_) async => model,
      ),
      meter: meter,
      countTokens: (_, text) async => (text.length / 4).ceil(),
    );
  }

  setUp(() {
    model = FakeInferenceModel(
      newChat: (n) => FakeInferenceChat(id: n, answer: (_, _) => [reply]),
    );
  });

  test('manda el pedazo tal cual, con su instrucción y un tope que alcanza '
      'para devolverlo entero', () async {
    const text = 'La república\nromana cayó.';
    final answer = await build().tidyPart(text);

    expect(answer, reply);
    final opened = model.opened.single;
    expect(opened.maxOutputTokens, tidyReplyTokens(text.length));
    expect(model.chats.single.received.single, text);
    expect(model.chats.single.closed, isTrue);
    // Lo que se le pide: ordenar, nunca reescribir.
    expect(
      opened.instruction,
      contains('ORDENARLO sin cambiar ninguna palabra'),
    );
    expect(opened.instruction, contains('Nunca traduzcas, resumas'));
    expect(opened.instruction, contains('el texto queda en su idioma'));
    // A diferencia de las demás, no pide contestar en español: invitaría a
    // traducir.
    expect(opened.instruction, isNot(contains('Respondé siempre en español')));
  });

  test('lo que se le da por pedido es lo que entra en su ventana', () {
    expect(build().tidyPartChars, tidyPartCharBudget(kGemmaContextTokens));
    expect(build(contextTokens: 200000).tidyPartChars, 8000);
  });

  test('si el pedazo no entra en la ventana, no lo manda: avisa para que se '
      'parta', () async {
    final long = 'palabra ' * 2000;

    await expectLater(build().tidyPart(long), throwsA(isA<TidyPartTooLong>()));
    expect(model.chats.single.received, isEmpty);
    expect(model.chats.single.closed, isTrue);
  });
}
