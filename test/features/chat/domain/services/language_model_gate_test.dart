import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';

void main() {
  late LanguageModelGate gate;

  setUp(() => gate = LanguageModelGate());

  test(
    'corre de a uno: el segundo empieza cuando termina el primero',
    () async {
      final log = <String>[];
      final first = Completer<void>();

      final a = gate.runForUser(() async {
        log.add('a empieza');
        await first.future;
        log.add('a termina');
      });
      final b = gate.runForUser(() async => log.add('b empieza'));

      await pumpEventQueue();
      expect(log, ['a empieza']);

      first.complete();
      await Future.wait([a, b]);
      expect(log, ['a empieza', 'a termina', 'b empieza']);
    },
  );

  test('al liberarse, la persona pasa antes que la cola de la IA', () async {
    final log = <String>[];
    final running = Completer<void>();

    final current = gate.runInBackground(() => running.future);
    final background = gate.runInBackground(() async => log.add('IA'));
    await pumpEventQueue();
    final user = gate.runForUser(() async => log.add('persona'));

    running.complete();
    await Future.wait([current, background, user]);
    expect(log, ['persona', 'IA']);
  });

  group('la persona primero, de verdad (F30)', () {
    test('si la cola está escribiendo cuando la persona pide el modelo, se '
        'la corta, y la persona va en cuanto la cola suelta', () async {
      final log = <String>[];
      final running = Completer<void>();
      var cuts = 0;
      final background = gate.runInBackground(
        () => running.future,
        onPreempt: () {
          cuts++;
          log.add('cortada');
          running.complete();
        },
      );
      await pumpEventQueue();

      final user = gate.runForUser(() async => log.add('persona'));
      // Una segunda llamada no la vuelve a cortar.
      final again = gate.runForUser(() async => log.add('otra vez'));
      await Future.wait([background, user, again]);

      expect(cuts, 1);
      expect(log, ['cortada', 'persona', 'otra vez']);
    });

    test('lo que no apura —cerrar una charla, cargar de antemano— espera sin '
        'cortar', () async {
      final running = Completer<void>();
      var cuts = 0;
      final background = gate.runInBackground(
        () => running.future,
        onPreempt: () => cuts++,
      );
      await pumpEventQueue();

      final user = gate.runForUser(() async {}, preempt: false);
      running.complete();
      await Future.wait([background, user]);

      expect(cuts, 0);
    });

    test('con el chat a la vista, la cola no empieza aunque todavía no haya '
        'ninguna charla; al dejar de verse, sigue', () async {
      final log = <String>[];
      gate.chatVisible = true;
      expect(gate.isUserActive, isTrue);

      final background = gate.runInBackground(() async => log.add('IA'));
      await pumpEventQueue();
      expect(log, isEmpty);

      gate.chatVisible = false;
      await background;
      expect(log, ['IA']);
    });

    test('los vínculos esperan a que la persona suelte el modelo', () async {
      final log = <String>[];
      gate.chatVisible = true;
      final idle = gate.whenUserIdle().then((_) => log.add('vínculos'));
      await pumpEventQueue();
      expect(log, isEmpty);

      final answering = Completer<void>();
      final user = gate.runForUser(() => answering.future);
      gate.chatVisible = false;
      await pumpEventQueue();
      // Sin el chat a la vista, pero con una respuesta en curso.
      expect(log, isEmpty);

      answering.complete();
      await user;
      await idle;
      expect(log, ['vínculos']);
      expect(gate.isIdle, isTrue);
    });
  });

  group('para soltar la memoria (F30)', () {
    test('runIfFree corre solo si nadie usa ni espera el modelo', () async {
      final running = Completer<void>();
      final current = gate.runInBackground(() => running.future);

      expect(await gate.runIfFree(() async {}), isFalse);
      running.complete();
      await current;
      var ran = false;
      expect(await gate.runIfFree(() async => ran = true), isTrue);
      expect(ran, isTrue);
    });

    test('cuánto hace que nadie lo usa', () async {
      var now = DateTime(2026, 10, 4, 12);
      final timed = LanguageModelGate(clock: () => now);
      expect(timed.unusedFor, isNull);

      await timed.runForUser(() async {});
      now = now.add(const Duration(minutes: 2));
      expect(timed.unusedFor, const Duration(minutes: 2));

      timed.chatVisible = true;
      expect(timed.unusedFor, isNull);
    });
  });

  test('la persona cuenta como activa mientras espera su turno', () async {
    final running = Completer<void>();
    final current = gate.runInBackground(() => running.future);
    expect(gate.isUserActive, isFalse);

    final user = gate.runForUser(() async {});
    expect(gate.isUserActive, isTrue);

    running.complete();
    await Future.wait([current, user]);
    expect(gate.isUserActive, isFalse);
  });

  test('con una charla abierta, la cola de la IA espera a que se cierre; '
      'los mensajes de la charla no', () async {
    final log = <String>[];
    final hold = gate.holdForUser();

    final background = gate.runInBackground(() async => log.add('IA'));
    await gate.runForUser(() async => log.add('mensaje'));
    await pumpEventQueue();
    expect(log, ['mensaje']);
    expect(gate.isUserActive, isTrue);

    hold.release();
    await background;
    expect(log, ['mensaje', 'IA']);
    expect(gate.isUserActive, isFalse);
  });

  test('soltar una charla dos veces no suelta la de otra', () async {
    final log = <String>[];
    final first = gate.holdForUser();
    final second = gate.holdForUser();

    final background = gate.runInBackground(() async => log.add('IA'));
    first
      ..release()
      ..release();
    await pumpEventQueue();
    expect(log, isEmpty);

    second.release();
    await background;
    expect(log, ['IA']);
  });

  test('un trabajo que falla suelta el turno igual', () async {
    final failing = gate.runForUser<void>(() async => throw StateError('x'));
    await expectLater(failing, throwsStateError);

    expect(await gate.runInBackground(() async => 'sigue'), 'sigue');
  });

  group('una charla que deja de usarse suelta el modelo (F27)', () {
    late List<String> log;

    setUp(() => log = []);

    /// Una charla abierta que anota cuándo cierra su sesión por falta de uso.
    LanguageModelHold chat(LanguageModelGate gate) =>
        gate.holdForUser(onIdle: () async => log.add('cierra su sesión'));

    testWidgets('pasado el rato sin uso y sin la pantalla a la vista, cierra '
        'su sesión y la cola sigue', (tester) async {
      final gate = LanguageModelGate();
      final hold = chat(gate);
      final background = gate.runInBackground(() async => log.add('IA'));

      await tester.pump(kChatIdleRelease - const Duration(seconds: 1));
      expect(log, isEmpty);
      expect(gate.isUserActive, isTrue);

      await tester.pump(const Duration(seconds: 2));
      await background;
      expect(log, ['cierra su sesión', 'IA']);
      expect(hold.isIdle, isTrue);
      expect(gate.isUserActive, isFalse);
    });

    testWidgets('con la pantalla a la vista no se suelta nunca; al dejar de '
        'verse, el rato cuenta desde ahí', (tester) async {
      final gate = LanguageModelGate()..chatVisible = true;
      chat(gate);
      final background = gate.runInBackground(() async => log.add('IA'));

      await tester.pump(const Duration(hours: 3));
      expect(log, isEmpty);

      gate.chatVisible = false;
      await tester.pump(kChatIdleRelease - const Duration(seconds: 1));
      expect(log, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await background;
      expect(log, ['cierra su sesión', 'IA']);
    });

    testWidgets('cada mensaje vuelve a empezar el rato', (tester) async {
      final gate = LanguageModelGate();
      final hold = chat(gate);

      for (var i = 0; i < 5; i++) {
        await tester.pump(kChatIdleRelease - const Duration(seconds: 10));
        hold.touch();
      }
      expect(log, isEmpty);
      expect(gate.isUserActive, isTrue);
      hold.release();
    });

    testWidgets('volver a escribir retiene el modelo otra vez', (tester) async {
      final gate = LanguageModelGate();
      final hold = chat(gate);
      await tester.pump(kChatIdleRelease + const Duration(seconds: 1));
      expect(hold.isIdle, isTrue);

      hold.touch();
      expect(hold.isIdle, isFalse);
      final background = gate.runInBackground(() async => log.add('IA'));
      await tester.pump(const Duration(seconds: 30));
      expect(log, ['cierra su sesión']);

      hold.release();
      await background;
      expect(log, ['cierra su sesión', 'IA']);
    });

    testWidgets('un mensaje que llega mientras la sesión se cierra espera el '
        'cierre, y la charla sigue en uso', (tester) async {
      final gate = LanguageModelGate();
      final closing = Completer<void>();
      final hold = gate.holdForUser(
        onIdle: () async {
          log.add('empieza a cerrar');
          await closing.future;
          log.add('cerrada');
        },
      );
      await tester.pump(kChatIdleRelease + const Duration(seconds: 1));
      expect(log, ['empieza a cerrar']);

      hold.touch();
      final message = gate.runForUser(() async => log.add('mensaje'));
      final background = gate.runInBackground(() async => log.add('IA'));
      closing.complete();
      await message;
      await tester.pump();
      expect(log, ['empieza a cerrar', 'cerrada', 'mensaje']);
      expect(hold.isIdle, isFalse);

      hold.release();
      await background;
      expect(log.last, 'IA');
    });

    testWidgets('si cerrar falla, se registra y el modelo se suelta igual', (
      tester,
    ) async {
      final errors = <Object>[];
      final gate = LanguageModelGate(onError: (e, _) => errors.add(e))
        ..holdForUser(onIdle: () async => throw StateError('no cerró'));
      final background = gate.runInBackground(() async => log.add('IA'));

      await tester.pump(kChatIdleRelease + const Duration(seconds: 1));
      await background;

      expect(errors.single, isA<StateError>());
      expect(log, ['IA']);
    });

    testWidgets('cerrada a mano, no hay nada que soltar después', (
      tester,
    ) async {
      final gate = LanguageModelGate();
      chat(gate).release();

      await tester.pump(kChatIdleRelease * 2);
      expect(log, isEmpty);
    });
  });
}
