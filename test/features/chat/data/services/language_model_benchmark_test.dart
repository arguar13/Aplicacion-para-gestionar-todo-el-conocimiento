import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/data/services/language_model_backend_store.dart';
import 'package:sinapsis/features/chat/data/services/language_model_benchmark.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

import '../../../../support/fake_inference_chat.dart';
import '../../../../support/fake_inference_model.dart';

/// Elegir dónde corre el modelo según lo que mida más rápido (F30).
void main() {
  late LanguageModelBackendStore store;
  late List<GemmaLoadRequest> requests;

  /// Tokens por pedazo según la forma de cargarlo: más es más rápido, con
  /// el mismo tiempo por pedazo.
  late int Function(GemmaLoadRequest request) speedOf;

  /// Dónde queda corriendo de verdad, según lo pedido.
  late PreferredBackend? Function(GemmaLoadRequest request) landsOn;

  GemmaEngine engine() => GemmaEngine(
    ensureReady: () async => true,
    meter: LanguageModelMeter(),
    backends: store,
    load: (request) async {
      requests.add(request);
      final speed = speedOf(request);
      return FakeInferenceModel(
        activeBackend: landsOn(request),
        newChat: (n) => FakeInferenceChat(
          id: n,
          tokensPerPiece: speed,
          pieceDelay: const Duration(milliseconds: 20),
          answer: (_, _) => ['La ', 'escritura ', 'nació ', 'en ', 'Sumeria.'],
        ),
      );
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = LanguageModelBackendStore(
      preferences: await SharedPreferences.getInstance(),
      modelKey: () => 'gemma4E4b',
    );
    requests = [];
    speedOf = (request) =>
        switch ((request.backend, request.speculativeDecoding)) {
          (PreferredBackend.gpu, true) => 20,
          (PreferredBackend.gpu, _) => 10,
          _ => 1,
        };
    landsOn = (request) => request.backend;
  });

  test('prueba GPU, CPU y la especulativa en la más rápida, y se queda con '
      'la mejor', () async {
    final gemma = engine();
    final steps = <int>[];

    final results = await LanguageModelBenchmark(
      gate: LanguageModelGate(),
      engine: gemma,
      store: store,
    ).run(progress: steps.add);

    expect(steps, [1, 2, 3]);
    expect(results.map((r) => (r.backend, r.speculative)), [
      (LanguageModelBackend.gpu, null),
      (LanguageModelBackend.cpu, null),
      (LanguageModelBackend.gpu, true),
    ]);
    expect(results.every((r) => r.worked), isTrue);
    final choice = store.choice!;
    expect(choice.backend, LanguageModelBackend.gpu);
    expect(choice.speculative, isTrue);
    expect(choice.reason, LanguageModelBackendReason.measured);
    expect(store.results, hasLength(3));
    // Soltó el modelo: el próximo uso lo carga con lo elegido.
    expect(gemma.isLoaded, isFalse);
    await gemma.model();
    expect(requests.last.backend, PreferredBackend.gpu);
    expect(requests.last.speculativeDecoding, isTrue);
  });

  test('si la GPU cae a la CPU sola, cuenta como que no anduvo', () async {
    landsOn = (_) => PreferredBackend.cpu;

    final results = await LanguageModelBenchmark(
      gate: LanguageModelGate(),
      engine: engine(),
      store: store,
    ).run();

    expect(results.first.worked, isFalse);
    expect(store.choice!.backend, LanguageModelBackend.cpu);
  });

  group('sin medir', () {
    test(
      'pide la GPU; si no arranca, recuerda la CPU para la próxima',
      () async {
        landsOn = (_) => PreferredBackend.cpu;
        final gemma = engine();

        await gemma.model();
        expect(requests.single.backend, PreferredBackend.gpu);
        expect(store.choice!.reason, LanguageModelBackendReason.gpuFailed);

        await gemma.release();
        await gemma.model();
        expect(requests.last.backend, PreferredBackend.cpu);
      },
    );
  });
}
