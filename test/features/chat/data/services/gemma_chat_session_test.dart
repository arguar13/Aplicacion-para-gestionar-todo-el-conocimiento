import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_session.dart';
import 'package:sinapsis/features/chat/data/services/gemma_reply.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

import '../../../../support/fake_inference_chat.dart';

/// La sesión de una charla (F27): retiene el modelo mientras se usa, lo
/// suelta sola tras un rato sin uso y, al volver a escribir, se retoma con lo
/// conversado.
void main() {
  late LanguageModelGate gate;
  late List<FakeInferenceChat> opened;

  setUp(() {
    gate = LanguageModelGate();
    opened = [];
  });

  Future<GemmaChatSession> open() async {
    final meter = LanguageModelMeter();
    final session = GemmaChatSession(
      gate,
      () async {
        final chat = FakeInferenceChat(id: opened.length + 1);
        opened.add(chat);
        return chat;
      },
      reply: (chat) =>
          collectReply(chat, meter: meter, kind: LanguageModelReplyKind.chat),
    );
    await session.openFirst();
    return session;
  }

  testWidgets('mientras se usa, una sola sesión con todo lo dicho', (
    tester,
  ) async {
    final session = await open();

    await session.send(prompt: 'Hola', said: 'Hola');
    await tester.pump(kChatIdleRelease - const Duration(seconds: 5));
    await session.send(prompt: '¿Y Roma?', said: '¿Y Roma?');

    expect(opened, hasLength(1));
    expect(opened.single.received, ['Hola', '¿Y Roma?']);
    expect(gate.isUserActive, isTrue);
    await session.close();
    expect(gate.isUserActive, isFalse);
  });

  testWidgets('sin uso, cierra su sesión y suelta el modelo; al volver a '
      'escribir, la reabre con lo conversado', (tester) async {
    final session = await open();
    final first = await session.send(
      prompt: 'Fuentes: …\n\n¿Qué es el Senado?',
      said: '¿Qué es el Senado?',
    );

    final ai = <String>[];
    final background = gate.runInBackground(() async => ai.add('IA'));
    await tester.pump(kChatIdleRelease + const Duration(seconds: 1));
    await background;
    expect(opened.single.closed, isTrue);
    expect(ai, ['IA']);

    final again = await session.send(
      prompt: '¿Y el pueblo?',
      said: '¿Y el pueblo?',
    );

    expect(opened, hasLength(2));
    final resumed = opened.last.received.single;
    // Lo que escribió la persona, sin el contexto de la bóveda de aquella
    // vuelta, y lo que le contestó el modelo.
    expect(resumed, contains('Persona: ¿Qué es el Senado?'));
    expect(resumed, contains('Asistente: $first'));
    expect(resumed, isNot(contains('Fuentes: …')));
    expect(resumed, endsWith('¿Y el pueblo?'));
    expect(again, isNotEmpty);

    // Ya retomada, lo siguiente va solo.
    await session.send(prompt: 'Gracias', said: 'Gracias');
    expect(opened.last.received.last, 'Gracias');
    await session.close();
  });

  testWidgets('lo conversado que se retoma entra en la ventana', (
    tester,
  ) async {
    final session = await open();
    for (var i = 0; i < 20; i++) {
      final long = 'Pregunta $i ${'larga ' * 40}';
      await session.send(prompt: long, said: long);
    }
    await tester.pump(kChatIdleRelease + const Duration(seconds: 1));

    await session.send(prompt: 'Última', said: 'Última');

    final resumed = opened.last.received.single;
    expect(
      resumed.length,
      lessThan(kResumedTranscriptChars + 'Última'.length + 100),
    );
    // Lo más reciente es lo que queda.
    expect(resumed, contains('Pregunta 19'));
    expect(resumed, isNot(contains('Pregunta 0 ')));
    await session.close();
  });
}
