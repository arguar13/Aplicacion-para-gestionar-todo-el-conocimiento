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
}
