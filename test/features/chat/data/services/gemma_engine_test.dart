import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

import '../../../../support/fake_inference_model.dart';

/// El modelo cargado (F30): se carga una vez, se mide la carga y se puede
/// soltar y volver a cargar.
void main() {
  late LanguageModelMeter meter;
  late List<GemmaLoadRequest> requests;
  late List<FakeInferenceModel> models;
  late PreferredBackend activeBackend;
  late bool ready;

  GemmaEngine engine() => GemmaEngine(
    ensureReady: () async => ready,
    meter: meter,
    load: (request) async {
      requests.add(request);
      final model = FakeInferenceModel(activeBackend: activeBackend);
      models.add(model);
      return model;
    },
  );

  setUp(() {
    meter = LanguageModelMeter();
    requests = [];
    models = [];
    activeBackend = PreferredBackend.gpu;
    ready = true;
  });

  test('carga una sola vez y anota cuánto tardó y dónde corre', () async {
    final gemma = engine();

    final first = await gemma.model();
    final again = await gemma.model();

    expect(identical(first, again), isTrue);
    expect(requests, hasLength(1));
    expect(requests.single.maxTokens, kGemmaContextTokens);
    expect(gemma.loadCount, 1);
    final load = meter.performance.value.load!;
    expect(load.backend, LanguageModelBackend.gpu);
    expect(load.fellBackToCpu, isFalse);
  });

  test('si la GPU no arrancó y quedó en la CPU, lo dice', () async {
    activeBackend = PreferredBackend.cpu;

    await engine().model();

    final load = meter.performance.value.load!;
    expect(load.backend, LanguageModelBackend.cpu);
    expect(load.fellBackToCpu, isTrue);
  });

  test('soltarlo lo cierra, y el próximo uso lo vuelve a cargar', () async {
    final gemma = engine();
    await gemma.model();

    await gemma.release();

    expect(models.single.closed, isTrue);
    expect(gemma.isLoaded, isFalse);
    await gemma.model();
    expect(models, hasLength(2));
    expect(gemma.loadCount, 2);
  });

  test('sin el modelo bajado, no intenta cargarlo', () async {
    ready = false;

    await expectLater(
      engine().model(),
      throwsA(isA<ChatModelNotReadyException>()),
    );
    expect(requests, isEmpty);
  });

  group('la parte que mira fotos (F30)', () {
    test('no se carga hasta la primera foto; ahí se vuelve a cargar con '
        'ella, y queda', () async {
      final gemma = engine();
      await gemma.model();
      expect(requests.single.vision, isFalse);

      await gemma.model(vision: true);
      await gemma.model();

      expect(requests.map((r) => r.vision), [false, true]);
      expect(models.first.closed, isTrue);
      expect(gemma.loadCount, 2);
      expect(meter.performance.value.load!.vision, isTrue);
    });

    test('si no se puede, queda cargado sin ella y lo dice', () async {
      final gemma = GemmaEngine(
        ensureReady: () async => true,
        meter: meter,
        load: (request) async {
          requests.add(request);
          if (request.vision) throw StateError('sin codificador de imágenes');
          return FakeInferenceModel();
        },
      );

      await expectLater(
        gemma.model(vision: true),
        throwsA(isA<ChatImagesUnsupportedException>()),
      );

      expect(gemma.isLoaded, isTrue);
      expect(requests.map((r) => r.vision), [true, false]);
    });
  });
}
