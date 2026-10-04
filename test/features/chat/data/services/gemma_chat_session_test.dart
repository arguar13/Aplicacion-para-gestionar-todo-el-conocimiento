import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_session.dart';
import 'package:sinapsis/features/chat/data/services/gemma_reply.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

import '../../../../support/fake_inference_chat.dart';

/// Un token cada cuatro caracteres: el tokenizador de mentira.
Future<int> _fourCharsPerToken(InferenceChat _, String text) async =>
    (text.length / 4).ceil();

/// La sesión de una charla (F27, F30): retiene el modelo mientras se usa, da
/// la respuesta de a pedazos, nunca se pasa de la ventana y, si se cerró por
/// falta de uso, se retoma con lo conversado.
void main() {
  late LanguageModelGate gate;
  late List<FakeInferenceChat> opened;

  /// Cuántas veces se "cargó" el modelo, y si con la parte de las fotos.
  late int loads;
  late bool vision;

  setUp(() {
    gate = LanguageModelGate();
    opened = [];
    loads = 1;
    vision = false;
  });

  Future<GemmaChatSession> open({
    int window = 2048,
    int replyTokens = 512,
    FakeInferenceChat Function(int n)? chat,
  }) async {
    final meter = LanguageModelMeter();
    final session = GemmaChatSession(
      gate,
      () async {
        final next =
            chat?.call(opened.length + 1) ??
            FakeInferenceChat(id: opened.length + 1);
        opened.add(next);
        return next;
      },
      reply: (chat) =>
          measuredReply(chat, meter: meter, kind: LanguageModelReplyKind.chat),
      clean: cleanReply,
      instruction: 'Sos un asistente.',
      window: window,
      replyTokens: replyTokens,
      prepareImages: () async {
        if (vision) return;
        vision = true;
        loads++;
      },
      loadCount: () => loads,
      countTokens: _fourCharsPerToken,
    );
    await session.openFirst();
    return session;
  }

  testWidgets('la respuesta llega de a pedazos, cada vez más larga', (
    tester,
  ) async {
    final session = await open(
      chat: (n) => FakeInferenceChat(
        id: n,
        answer: (_, _) => ['  Roma ', 'fue ', 'grande.'],
      ),
    );

    final texts = await session.send(prompt: 'Hola', said: 'Hola').toList();

    expect(texts, ['Roma ', 'Roma fue ', 'Roma fue grande.']);
    await session.close();
  });

  testWidgets('mientras se usa, una sola sesión con todo lo dicho', (
    tester,
  ) async {
    final session = await open();

    await session.send(prompt: 'Hola', said: 'Hola').last;
    await tester.pump(kChatIdleRelease - const Duration(seconds: 5));
    await session.send(prompt: '¿Y Roma?', said: '¿Y Roma?').last;

    expect(opened, hasLength(1));
    expect(opened.single.received, ['Hola', '¿Y Roma?']);
    expect(gate.isUserActive, isTrue);
    await session.close();
    expect(gate.isUserActive, isFalse);
    expect(opened.single.closed, isTrue);
  });

  testWidgets('sin uso, cierra su sesión y suelta el modelo; al volver a '
      'escribir, la reabre con lo conversado', (tester) async {
    final session = await open();
    final first = await session
        .send(
          prompt: 'Fuentes: …\n\n¿Qué es el Senado?',
          said: '¿Qué es el Senado?',
        )
        .last;

    final ai = <String>[];
    final background = gate.runInBackground(() async => ai.add('IA'));
    await tester.pump(kChatIdleRelease + const Duration(seconds: 1));
    await background;
    expect(opened.single.closed, isTrue);
    expect(ai, ['IA']);

    final again = await session
        .send(prompt: '¿Y el pueblo?', said: '¿Y el pueblo?')
        .last;

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
    await session.send(prompt: 'Gracias', said: 'Gracias').last;
    expect(opened.last.received.last, 'Gracias');
    await session.close();
  });

  testWidgets('cuando el mensaje no entra con lo ya conversado, sigue en '
      'una sesión nueva con lo conversado que entre', (tester) async {
    // 400 tokens de ventana, 50 de respuesta: cada mensaje de 240
    // caracteres ocupa 60.
    final session = await open(window: 400, replyTokens: 50);
    final long = 'pregunta ${'larga ' * 38}';

    for (var i = 0; i < 6; i++) {
      await session.send(prompt: '$i $long', said: 'Pregunta $i').last;
    }

    expect(opened.length, greaterThan(1));
    for (final chat in opened) {
      // Antes del último mensaje de cada sesión, la instrucción, lo
      // mandado, lo respondido —tres tokens por respuesta— y la respuesta
      // más larga posible entraban en la ventana.
      final prompts = chat.received.fold<int>(
        0,
        (sum, prompt) => sum + (prompt.length / 4).ceil(),
      );
      final turns = chat.received.length;
      final used =
          ('Sos un asistente.'.length / 4).ceil() +
          prompts +
          (turns - 1) * (kTurnTemplateTokens + 3) +
          kTurnTemplateTokens +
          50 +
          kWindowSafetyTokens;
      expect(used, lessThanOrEqualTo(400));
    }
    for (final chat in opened.skip(1)) {
      final resumed = chat.received.first;
      expect(resumed, startsWith('Lo que veníamos conversando'));
      expect(resumed, contains('Persona: Pregunta'));
      expect(resumed, endsWith(long));
    }
    await session.close();
  });

  testWidgets('un mensaje que no entra ni en una sesión nueva falla claro, '
      'y la charla sigue', (tester) async {
    final session = await open(window: 300, replyTokens: 100);

    await expectLater(
      session.send(prompt: 'x' * 2000, said: 'Un libro pegado').toList(),
      throwsA(isA<ChatMessageTooLongException>()),
    );

    expect(await session.send(prompt: 'Hola', said: 'Hola').last, isNotEmpty);
    // Sin cerrar ni reabrir la sesión por un mensaje que no iba a entrar.
    expect(opened, hasLength(1));
    expect(opened.single.received, ['Hola']);
    await session.close();
  });

  testWidgets('cortar la respuesta para al modelo, y la charla sigue con lo '
      'que alcanzó a escribir', (tester) async {
    final session = await open(
      chat: (n) => FakeInferenceChat(
        id: n,
        gated: true,
        answer: (turn, _) =>
            turn == 1 ? ['Roma ', 'fue ', 'una ', 'república.'] : ['Sí.'],
      ),
    );
    final texts = <String>[];
    final subscription = session
        .send(prompt: 'Contame de Roma', said: 'Contame de Roma')
        .listen(texts.add);
    await tester.pump();
    opened.single.releasePiece();
    await tester.pump();
    expect(texts, ['Roma ']);

    await subscription.cancel();
    expect(opened.single.stopRequests, 1);
    opened.single.releasePiece();
    await tester.pump();

    // El turno quedó libre: el próximo mensaje va, en la misma sesión, y
    // retomada más tarde lleva lo que se alcanzó a escribir.
    final next = session.send(prompt: '¿Seguro?', said: '¿Seguro?').last;
    await tester.pump();
    opened.single.releasePiece();
    expect(await next, 'Sí.');
    expect(opened, hasLength(1));
    await session.close();
  });

  testWidgets('si el motor falla a mitad, lo escrito llega y después el '
      'error', (tester) async {
    final session = await open(
      chat: (n) => FakeInferenceChat(
        id: n,
        failAfter: 1,
        answer: (_, _) => ['Roma ', 'fue…'],
      ),
    );
    final texts = <String>[];
    Object? error;
    final done = Completer<void>();
    session
        .send(prompt: 'Roma', said: 'Roma')
        .listen(
          texts.add,
          onError: (Object e) => error = e,
          onDone: done.complete,
        );
    await done.future;

    expect(texts, ['Roma ']);
    expect(error, isA<StateError>());
    // El turno no quedó tomado.
    expect(await gate.runForUser(() async => 'libre'), 'libre');
    await session.close();
  });

  testWidgets('una foto llega al modelo: si hay que volver a cargarlo para '
      'mirarla, sigue en una sesión nueva con lo conversado (F30)', (
    tester,
  ) async {
    final session = await open();
    await session.send(prompt: 'Hola', said: 'Hola').last;

    await session
        .send(
          prompt: '¿Qué es esto?',
          said: '¿Qué es esto?',
          images: [
            Uint8List.fromList(const [1, 2, 3]),
          ],
        )
        .last;

    expect(vision, isTrue);
    expect(opened, hasLength(2));
    expect(opened.last.imagesReceived, 1);
    expect(opened.last.received.single, contains('Persona: Hola'));
    expect(opened.last.received.single, endsWith('¿Qué es esto?'));

    // Con el modelo ya listo para fotos, la siguiente va en la misma sesión.
    await session
        .send(
          prompt: '¿Y esta?',
          said: '¿Y esta?',
          images: [
            Uint8List.fromList(const [4]),
          ],
        )
        .last;
    expect(opened, hasLength(2));
    expect(opened.last.imagesReceived, 2);
    await session.close();
  });
}
