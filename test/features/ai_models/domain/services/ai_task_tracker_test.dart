import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

/// La fuente única de lo que la IA hace ahora (F39, paso 6): las tareas, sus
/// pasos y sus tokens, que salen de lo que el medidor del modelo anota en cada
/// respuesta y no de ninguna estimación.
void main() {
  late DateTime now;
  late AiTaskTracker tracker;
  late LanguageModelMeter meter;

  setUp(() {
    now = DateTime(2026, 10, 24, 10);
    tracker = AiTaskTracker(clock: () => now);
    // Así lo engancha la app (`aiTaskTrackerProvider`).
    meter = LanguageModelMeter()
      ..addTap(
        (reply) => tracker.recordReply(
          inputTokens: reply.inputTokens,
          outputTokens: reply.tokens,
        ),
      );
  });

  tearDown(() => tracker.dispose());

  AiTaskHandle begin(
    String title, {
    AiTaskKind kind = AiTaskKind.studyAnalysis,
  }) => tracker.begin(kind: kind, title: title, itemId: title);

  /// Una respuesta del modelo con los tokens que contó.
  void reply({required int input, required int output}) => meter.recordReply(
    LanguageModelReply(
      kind: LanguageModelReplyKind.task,
      total: const Duration(seconds: 1),
      words: 3,
      inputTokens: input,
      tokens: output,
    ),
  );

  AiTask only() => tracker.tasks.value.single;

  group('las tareas', () {
    test('una tarea abierta se ve con su título, su hora y el modelo; '
        'al cerrarla se va', () {
      final handle = tracker.begin(
        kind: AiTaskKind.organize,
        title: 'Historia',
        itemId: 'h',
        model: 'gemma4E4b',
      );

      expect(only().title, 'Historia');
      expect(only().itemId, 'h');
      expect(only().kind, AiTaskKind.organize);
      expect(only().model, 'gemma4E4b');
      expect(only().startedAt, now);

      handle.end();

      expect(tracker.tasks.value, isEmpty);
    });

    test('las tareas se ven en el orden en que empezaron y cada cambio '
        'avisa', () {
      var notified = 0;
      tracker.tasks.addListener(() => notified++);

      final a = begin('a');
      final b = begin('b');
      a.parts(1, 4);
      b.items(0, 2);

      expect(tracker.tasks.value.map((t) => t.title), ['a', 'b']);
      expect(tracker.tasks.value.first.partProgress?.done, 1);
      expect(tracker.tasks.value.last.batchProgress?.total, 2);
      expect(notified, 4);
    });

    test('un cambio que no cambia nada no avisa', () {
      final handle = begin('a')..parts(1, 4);
      var notified = 0;
      tracker.tasks.addListener(() => notified++);

      handle.parts(1, 4);

      expect(notified, 0);
    });

    test('el tiempo que lleva sale del reloj inyectado', () {
      final handle = begin('a');

      now = now.add(const Duration(minutes: 2, seconds: 14));

      expect(only().elapsed(now), const Duration(minutes: 2, seconds: 14));
      expect(handle.usage.elapsed, const Duration(minutes: 2, seconds: 14));
    });

    test('cerrarla dos veces da lo gastado una sola vez, y lo que le llegue '
        'después no se anota en ninguna parte', () async {
      final handle = begin('a');
      await handle.run(() async => reply(input: 100, output: 20));
      now = now.add(const Duration(seconds: 30));

      final usage = handle.end();

      expect(usage.elapsed, const Duration(seconds: 30));
      expect((usage.inputTokens, usage.outputTokens), (100, 20));
      expect(handle.end(), AiTaskUsage.none);
      expect(handle.isEnded, isTrue);
      // Una respuesta que llega con la tarea ya cerrada no revive nada.
      await handle.run(() async => reply(input: 5, output: 5));
      expect(tracker.tasks.value, isEmpty);
    });

    test('si el reloj va para atrás, lo que lleva es cero y no negativo', () {
      final handle = begin('a');

      now = now.subtract(const Duration(seconds: 5));

      expect(handle.usage.elapsed, Duration.zero);
    });

    test('con el tracker descartado, quien sigue contando no falla', () {
      final handle = begin('a');

      tracker.dispose();

      expect(() => handle.parts(1, 2), returnsNormally);
      expect(handle.end, returnsNormally);
      // `tearDown` lo descarta otra vez.
      tracker = AiTaskTracker(clock: () => now);
    });
  });

  group('los pasos', () {
    AiTaskHandle study() => tracker.begin(
      kind: AiTaskKind.studyAnalysis,
      title: 'Historia',
      steps: const [
        AiTaskStepKind.studySplit,
        AiTaskStepKind.studySend,
        AiTaskStepKind.studyJoin,
      ],
    );

    test('el paso de ahora está en curso, los de antes hechos y los de '
        'después por hacer', () {
      final handle = study();
      expect([
        for (final s in only().steps) only().stateOf(s),
      ], everyElement(AiTaskStepState.pending));

      handle.step(AiTaskStepKind.studySend);

      final task = only();
      expect(task.stateOf(AiTaskStepKind.studySplit), AiTaskStepState.done);
      expect(task.stateOf(AiTaskStepKind.studySend), AiTaskStepState.running);
      expect(task.stateOf(AiTaskStepKind.studyJoin), AiTaskStepState.pending);
    });

    test('volver a mandar la parte siguiente deja el de juntar por hacer '
        'otra vez', () {
      final handle = study()
        ..step(AiTaskStepKind.studySend)
        ..step(AiTaskStepKind.studyJoin);
      expect(only().stateOf(AiTaskStepKind.studySend), AiTaskStepState.done);

      handle.step(AiTaskStepKind.studySend);

      expect(only().stateOf(AiTaskStepKind.studySend), AiTaskStepState.running);
      expect(only().stateOf(AiTaskStepKind.studyJoin), AiTaskStepState.pending);
    });

    test('un paso terminado queda hecho aunque no sea el último, y sin '
        'paso en curso no hay ninguno marcado', () {
      final handle = study()
        ..step(AiTaskStepKind.studySplit)
        ..finishStep(AiTaskStepKind.studySplit);

      final task = only();
      expect(task.currentStep, isNull);
      expect(task.stateOf(AiTaskStepKind.studySplit), AiTaskStepState.done);
      expect(task.stateOf(AiTaskStepKind.studySend), AiTaskStepState.pending);
      expect(handle.isEnded, isFalse);
    });

    test('un paso terminado cuenta para el avance aunque no haya otro en '
        'curso', () {
      tracker
          .begin(
            kind: AiTaskKind.organize,
            title: 'Historia',
            steps: const [
              AiTaskStepKind.organizeProperties,
              AiTaskStepKind.organizeRelations,
              AiTaskStepKind.organizeFlashcards,
            ],
          )
          .finishStep(AiTaskStepKind.organizeProperties);

      final task = only();
      expect(
        task.stateOf(AiTaskStepKind.organizeProperties),
        AiTaskStepState.done,
      );
      expect(task.stepsDone, 1);
      expect(task.progress?.done, 1);
      expect(task.percent, 33);
    });

    test('empezar de nuevo un paso que ya estaba hecho lo vuelve a poner en '
        'curso, y al pasar a uno anterior queda por hacer', () {
      final handle = study()..finishStep(AiTaskStepKind.studyJoin);
      expect(only().stateOf(AiTaskStepKind.studyJoin), AiTaskStepState.done);

      handle.step(AiTaskStepKind.studyJoin);
      expect(only().stateOf(AiTaskStepKind.studyJoin), AiTaskStepState.running);

      handle.step(AiTaskStepKind.studySend);
      expect(only().stateOf(AiTaskStepKind.studyJoin), AiTaskStepState.pending);
    });

    test('un paso que no es de la tarea está por hacer', () {
      study();

      expect(
        only().stateOf(AiTaskStepKind.reviewThings),
        AiTaskStepState.pending,
      );
    });
  });

  group('los tokens salen de lo que el modelo contó', () {
    test('lo que se pide adentro de la tarea se le suma, lo leído y lo '
        'escrito', () async {
      final handle = begin('a');

      await handle.run(() async {
        reply(input: 1200, output: 300);
        await Future<void>.delayed(Duration.zero);
        reply(input: 800, output: 150);
      });

      expect(only().inputTokens, 2000);
      expect(only().outputTokens, 450);
      expect(only().tokens, 2450);
    });

    test(
      'una respuesta sin tokens contados suma cero, no se inventa',
      () async {
        final handle = begin('a');

        await handle.run(() async {
          meter.recordReply(
            const LanguageModelReply(
              kind: LanguageModelReplyKind.task,
              total: Duration(seconds: 1),
              words: 3,
            ),
          );
        });

        expect(only().tokens, 0);
      },
    );

    test('la tarea de otro tracker no se anota en este', () async {
      final other = AiTaskTracker(clock: () => now);
      addTearDown(other.dispose);
      final foreign = other.begin(kind: AiTaskKind.organize, title: 'otra');
      begin('a');

      await foreign.run(() async => reply(input: 10, output: 1));

      expect(only().tokens, 0, reason: 'la respuesta es de la otra tarea');
      expect(foreign.usage.tokens, 0, reason: 'este tracker no la conoce');
    });

    test(
      'una respuesta pedida afuera de toda tarea no es de ninguna',
      () async {
        begin('a');

        reply(input: 100, output: 10);
        await Future<void>.delayed(Duration.zero);

        expect(only().tokens, 0);
      },
    );

    test('dos tareas a la vez no se mezclan, aunque sus respuestas lleguen '
        'intercaladas', () async {
      final a = begin('a');
      final b = begin('b');
      final gateA = Completer<void>();
      final gateB = Completer<void>();

      final futureA = a.run(() async {
        await gateA.future;
        reply(input: 10, output: 1);
        await gateA.future;
      });
      final futureB = b.run(() async {
        await gateB.future;
        reply(input: 200, output: 20);
      });
      // B contesta primero y A después: el orden no es el de empezar.
      gateB.complete();
      await futureB;
      gateA.complete();
      await futureA;

      final byTitle = {for (final t in tracker.tasks.value) t.title: t};
      expect(byTitle['a']!.tokens, 11);
      expect(byTitle['b']!.tokens, 220);
    });

    test('también cuando esperan su turno del modelo: la que se le pide al '
        'turno de la persona y la de la cola de fondo', () async {
      final gate = LanguageModelGate();
      final person = begin('persona');
      final background = begin('fondo', kind: AiTaskKind.organize);
      final release = Completer<void>();

      // La persona tiene el turno; la cola pide el suyo y espera.
      final inPerson = person.run(
        () => gate.runForUser(() async {
          await release.future;
          reply(input: 500, output: 50);
        }),
      );
      final inBackground = background.run(
        () => gate.runInBackground(() async {
          reply(input: 7, output: 3);
        }),
      );
      await pumpEventQueue();
      expect(
        tracker.tasks.value.firstWhere((t) => t.title == 'fondo').tokens,
        0,
        reason: 'la cola espera su turno',
      );
      release.complete();
      await inPerson;
      await inBackground;

      final byTitle = {for (final t in tracker.tasks.value) t.title: t};
      expect(byTitle['persona']!.tokens, 550);
      expect(byTitle['fondo']!.tokens, 10);
    });

    test(
      'también a través de un Stream que se lee adentro de la tarea',
      () async {
        final handle = begin('a');
        Stream<int> pieces() async* {
          yield 1;
          reply(input: 40, output: 4);
          yield 2;
        }

        final read = await handle.run(() => pieces().toList());

        expect(read, [1, 2]);
        expect(only().tokens, 44);
      },
    );

    test(
      'la tarea de quien llama se ve desde adentro, y afuera no hay',
      () async {
        final handle = begin('a');

        expect(AiTaskHandle.current, isNull);
        final inside = await handle.run(() async => AiTaskHandle.current);

        expect(inside, same(handle));
        handle.end();
        expect(await handle.run(() async => AiTaskHandle.current), isNull);
      },
    );

    test('el medidor avisa a cada oyente, en el acto, y deja de avisar a '
        'quien se da de baja', () {
      final seen = <int?>[];
      final stop = meter.addTap((reply) => seen.add(reply.tokens));

      reply(input: 1, output: 2);
      stop();
      reply(input: 1, output: 3);

      expect(seen, [2]);
      // Además de contarlo, lo sigue anotando como siempre.
      expect(meter.performance.value.taskReply?.tokens, 3);
    });
  });

  test('un reintento se ve y se borra', () {
    final handle = begin('a')
      ..retry(
        const AiTaskRetry(
          attempt: 2,
          maxAttempts: 4,
          failure: CloudModelFailure.timeout,
        ),
      );
    expect(only().retry?.attempt, 2);

    handle.retry(null);

    expect(only().retry, isNull);
  });
}
