import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/data/services/model_memory_keeper.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

import '../../../../support/fake_inference_model.dart';

/// Los modelos se sacan de la memoria cuando no hacen falta (F30).
void main() {
  late DateTime now;
  late LanguageModelGate gate;
  late GemmaEngine gemma;
  late List<FakeInferenceModel> loaded;
  late List<Duration?> embedderReleases;
  late List<Object> errors;
  late ModelMemoryKeeper keeper;

  setUp(() {
    now = DateTime(2026, 10, 4, 12);
    gate = LanguageModelGate(clock: () => now);
    loaded = [];
    gemma = GemmaEngine(
      ensureReady: () async => true,
      meter: LanguageModelMeter(),
      load: (_) async {
        final model = FakeInferenceModel();
        loaded.add(model);
        return model;
      },
    );
    embedderReleases = [];
    errors = [];
    keeper = ModelMemoryKeeper(
      gate: gate,
      gemma: gemma,
      releaseEmbedder: ({unusedFor}) async => embedderReleases.add(unusedFor),
      onError: (error, _) => errors.add(error),
    );
  });

  tearDown(() => keeper.dispose());

  /// Usa el modelo una vez, como lo haría el chat.
  Future<void> use() => gate.runForUser(gemma.model);

  /// Pasa [time] en el reloj del turno y en los temporizadores.
  Future<void> wait(WidgetTester tester, Duration time) async {
    now = now.add(time);
    await tester.pump(time);
  }

  group('cuando Android avisa que falta memoria', () {
    testWidgets('suelta los dos modelos en el acto, y el próximo uso vuelve '
        'a cargar Gemma', (tester) async {
      await use();

      await keeper.memoryPressure();

      expect(gemma.isLoaded, isFalse);
      expect(loaded.single.closed, isTrue);
      expect(embedderReleases, [null]);
      await use();
      expect(loaded, hasLength(2));
    });

    testWidgets('una charla abierta cierra su sesión antes: el próximo '
        'mensaje la reabre', (tester) async {
      await use();
      var closedSessions = 0;
      final hold = gate.holdForUser(onIdle: () async => closedSessions++);

      await keeper.memoryPressure();

      expect(closedSessions, 1);
      expect(hold.isIdle, isTrue);
      expect(gemma.isLoaded, isFalse);
      hold.release();
    });

    testWidgets('lo que se está usando no se toca', (tester) async {
      await use();
      final answering = Completer<void>();
      final answer = gate.runForUser(() => answering.future);

      await keeper.memoryPressure();

      expect(gemma.isLoaded, isTrue);
      answering.complete();
      await answer;
    });
  });

  group('con la app en segundo plano', () {
    testWidgets('pasado el rato sin uso, los suelta', (tester) async {
      await use();
      keeper.appHidden();

      await wait(tester, kModelReleaseAfter - const Duration(seconds: 5));
      expect(gemma.isLoaded, isTrue);

      await wait(tester, const Duration(seconds: 10));
      expect(gemma.isLoaded, isFalse);
      expect(embedderReleases, [kModelReleaseAfter]);
      keeper.appShown();
    });

    testWidgets('si vuelve antes, no los suelta', (tester) async {
      await use();
      keeper.appHidden();

      await wait(tester, const Duration(minutes: 1));
      keeper.appShown();
      await wait(tester, kModelReleaseAfter * 2);

      expect(gemma.isLoaded, isTrue);
      expect(embedderReleases, isEmpty);
    });

    testWidgets('mientras la cola trabaja, espera a que termine y pase el '
        'rato sin uso', (tester) async {
      await use();
      keeper.appHidden();
      final working = Completer<void>();
      final step = gate.runInBackground(() => working.future);

      await wait(tester, kModelReleaseAfter + const Duration(seconds: 1));
      expect(gemma.isLoaded, isTrue);

      working.complete();
      await step;
      await wait(tester, kModelReleaseAfter - const Duration(seconds: 30));
      expect(gemma.isLoaded, isTrue);

      await wait(tester, kModelReleaseAfter);
      expect(gemma.isLoaded, isFalse);
      keeper.appShown();
    });
  });

  testWidgets('si soltar falla, se registra y la app sigue', (tester) async {
    final failing = ModelMemoryKeeper(
      gate: gate,
      gemma: gemma,
      releaseEmbedder: ({unusedFor}) async => throw StateError('no se cerró'),
      onError: (error, _) => errors.add(error),
    );
    await use();

    await failing.memoryPressure();

    expect(errors.single, isA<StateError>());
    expect(gemma.isLoaded, isFalse);
    failing.dispose();
  });
}
