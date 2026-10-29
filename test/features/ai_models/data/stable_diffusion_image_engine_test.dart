import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/data/on_device/prefs_on_device_image_store.dart';
import 'package:sinapsis/features/ai_models/data/on_device/stable_diffusion_image_engine.dart';
import 'package:sinapsis/features/ai_models/data/on_device/stable_diffusion_runtime.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/ai_models/domain/services/on_device_verdict.dart';

import '../../../support/on_device_harness.dart';

const _sdxs = OnDeviceImageModel.sdxs;
const _turbo = OnDeviceImageModel.sdTurbo;
final _now = DateTime.utc(2026, 10, 28, 15);

void main() {
  late Directory root;
  late OnDeviceFakes fakes;
  late PrefsOnDeviceImageStore store;
  late SharedPreferences prefs;
  late StreamController<void> chosenChanges;
  String? chosen;
  late StableDiffusionImageEngine engine;

  Future<StableDiffusionImageEngine> build({
    Duration releaseAfter = const Duration(minutes: 2),
  }) async {
    final built = StableDiffusionImageEngine(
      runtime: fakes.runtime,
      files: fakes.files,
      probe: fakes.probe,
      store: store,
      chosenModel: () => chosen,
      chosenChanges: chosenChanges.stream,
      clock: () => _now,
      releaseAfter: releaseAfter,
    );
    await built.start();
    addTearDown(built.dispose);
    return built;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = PrefsOnDeviceImageStore(prefs: prefs);
    root = Directory.systemTemp.createTempSync('motor_imagen_');
    fakes = OnDeviceFakes(root: root);
    chosenChanges = StreamController<void>.broadcast();
    chosen = null;
    engine = await build();
  });

  tearDown(() async {
    await chosenChanges.close();
    root.deleteSync(recursive: true);
  });

  group('con qué modelo dibuja', () {
    test('sin ninguno bajado, el que habría que bajar primero: SDXS', () {
      expect(engine.provider, IllustrationProvider.onDevice);
      expect(engine.activeModel, _sdxs);
      expect(engine.displayName, 'SDXS-512');
    });

    test('con los dos bajados y 12 GB, SD-Turbo; con 8 GB, SDXS', () async {
      fakes
        ..placeDownloaded(_sdxs)
        ..placeDownloaded(_turbo);
      expect(engine.activeModel, _turbo);
      fakes.probe.profile = phoneWith(ramGb: 8);
      await engine.profile(refresh: true);
      expect(engine.activeModel, _sdxs);
    });

    test('solo uno bajado: ese, aunque sea justo', () async {
      fakes.placeDownloaded(_turbo);
      fakes.probe.profile = phoneWith(ramGb: 8);
      await engine.profile(refresh: true);
      expect(engine.activeModel, _turbo);
    });

    test('el elegido manda si está bajado y el teléfono puede', () async {
      fakes
        ..placeDownloaded(_sdxs)
        ..placeDownloaded(_turbo);
      chosen = _sdxs.spec.id;
      expect(engine.activeModel, _sdxs);
      // SD-Turbo elegido en un teléfono de 6 GB: no alcanza, dibuja SDXS.
      chosen = _turbo.spec.id;
      fakes.probe.profile = phoneWith(ramGb: 6);
      await engine.profile(refresh: true);
      expect(engine.activeModel, _sdxs);
    });

    test(
      'los modelos que ofrece son los bajados que el teléfono puede',
      () async {
        expect(await engine.listImageModels(const ImageWireAccess()), isEmpty);
        fakes
          ..placeDownloaded(_sdxs)
          ..placeDownloaded(_turbo);
        fakes.probe.profile = phoneWith(ramGb: 6);
        final models = await engine.listImageModels(const ImageWireAccess());
        expect(models.map((m) => m.id), [_sdxs.spec.id]);
        expect(engine.recommendedImageModel(models), _sdxs.spec.id);
        expect(engine.recommendedImageModel(const []), isNull);
      },
    );
  });

  group('si puede dibujar', () {
    test('sin bajar: falta descargarlo, con cuánto pesa', () async {
      final readiness = await engine.readiness();
      expect(readiness.isReady, isFalse);
      expect(readiness.reason, ImageFailure.modelNotDownloaded);
      expect(readiness.downloadBytes, _sdxs.spec.bytes);
    });

    test('bajado: listo', () async {
      fakes.placeDownloaded(_sdxs);
      expect((await engine.readiness()).isReady, isTrue);
    });

    test('con 4 GB: no alcanza; fuera de Android: no puede', () async {
      fakes.probe.profile = phoneWith(ramGb: 4);
      expect((await engine.readiness()).reason, ImageFailure.deviceTooSmall);
      fakes.probe.profile = phoneWith(android: false);
      expect((await engine.readiness()).reason, ImageFailure.unsupportedDevice);
    });

    test('lee el teléfono de nuevo cada vez (el lugar libre cambia)', () async {
      final before = fakes.probe.reads;
      await engine.readiness();
      await engine.readiness();
      expect(fakes.probe.reads, before + 2);
    });
  });

  group('cuánto tarda', () {
    test('hasta medirlo, lo estimado de su ficha', () {
      expect(engine.timeMeasured, isFalse);
      expect(
        engine.estimatedTimePerImage(IllustrationSize.standard),
        Duration(seconds: _sdxs.spec.estimatedSecondsPerImage),
      );
      expect(
        engine.timePerImageOf(_turbo),
        Duration(seconds: _turbo.spec.estimatedSecondsPerImage),
      );
    });

    test('«Medir en mi teléfono» carga de cero, dibuja 512 × 512 y guarda lo '
        'que tardó', () async {
      fakes.placeDownloaded(_sdxs);
      final changes = <void>[];
      final sub = engine.changes().listen(changes.add);
      addTearDown(sub.cancel);

      final measured = await engine.measure(_sdxs);

      expect(fakes.runtime.releases, 1);
      final job = fakes.runtime.jobs.single;
      expect(job.prompt, kOnDeviceMeasurePrompt);
      expect((job.width, job.height), (512, 512));
      expect(measured.perImage, const Duration(seconds: 17));
      expect(measured.load, const Duration(seconds: 4));
      expect(measured.measuredAt, _now);
      expect(engine.measurementOf(_sdxs), measured);
      expect(engine.timeMeasured, isTrue);
      expect(
        engine.estimatedTimePerImage(IllustrationSize.small),
        const Duration(seconds: 17),
      );
      await pumpEventQueue();
      expect(changes, isNotEmpty);
      // Lo medido sobrevive: está en las preferencias.
      expect(
        PrefsOnDeviceImageStore(prefs: prefs).measurementOf(_sdxs)?.perImage,
        const Duration(seconds: 17),
      );
    });

    test('medir sin bajarlo falla con «falta descargarlo»', () async {
      await expectLater(
        engine.measure(_turbo),
        throwsA(
          isA<ImageGenerationException>().having(
            (e) => e.failure,
            'falla',
            ImageFailure.modelNotDownloaded,
          ),
        ),
      );
      expect(fakes.runtime.jobs, isEmpty);
    });
  });

  group('dibujar', () {
    test(
      'a 512 px con la forma pedida, un paso y sin guía, y devuelve un PNG',
      () async {
        fakes.placeDownloaded(_sdxs);
        final image = await engine.generate(
          ImageWireRequest(
            model: _sdxs.spec.id,
            prompt: 'un árbol',
            aspect: IllustrationAspect.wide,
            size: IllustrationSize.large,
          ),
          const ImageWireAccess(),
        );
        expect(image.mimeType, 'image/png');
        expect(image.model, _sdxs.spec.id);
        expect(image.bytes.take(4), [0x89, 0x50, 0x4E, 0x47]);
        final job = fakes.runtime.jobs.single;
        expect((job.width, job.height), (512, 320));
        expect(job.steps, 1);
        expect(job.cfg, 1);
        expect(job.prompt, 'un árbol');
        expect(job.modelPath, fakes.fileOf(_sdxs).path);
        // La marca de «dibujando» ya no está: no se cerró.
        expect(prefs.getString('ai_device_image_drawing'), isNull);
      },
    );

    test(
      'un modelo que no existe o no está bajado no llega al motor',
      () async {
        await expectLater(
          engine.generate(
            const ImageWireRequest(model: 'flux', prompt: 'x'),
            const ImageWireAccess(),
          ),
          throwsA(
            isA<ImageGenerationException>().having(
              (e) => e.failure,
              'falla',
              ImageFailure.modelNotFound,
            ),
          ),
        );
        await expectLater(
          engine.generate(
            ImageWireRequest(model: _turbo.spec.id, prompt: 'x'),
            const ImageWireAccess(),
          ),
          throwsA(
            isA<ImageGenerationException>().having(
              (e) => e.failure,
              'falla',
              ImageFailure.modelNotDownloaded,
            ),
          ),
        );
        expect(fakes.runtime.jobs, isEmpty);
      },
    );

    test('mientras dibuja deja la marca; si la app se cierra, al volver ese '
        'modelo queda apagado y lo dice', () async {
      fakes.placeDownloaded(_sdxs);
      final gate = fakes.runtime.gate = Completer<void>();
      final drawing = engine.generate(
        ImageWireRequest(model: _sdxs.spec.id, prompt: 'x'),
        const ImageWireAccess(),
      );
      await pumpEventQueue();
      expect(prefs.getString('ai_device_image_drawing'), contains('sdxs-512'));

      // La app «se cierra» acá: otro motor arranca con las mismas
      // preferencias.
      final restarted = await build();
      expect(restarted.isClosed(_sdxs), isTrue);
      expect(restarted.isClosed(_turbo), isFalse);
      expect(restarted.verdictOf(_sdxs).reasons.first, isA<ClosedLastTime>());
      expect(
        (await restarted.readiness()).reason,
        isNot(ImageFailure.notEnoughMemory),
        reason: 'con SDXS apagado dibujaría SD-Turbo (sin bajar)',
      );
      gate.complete();
      await drawing;
    });

    test('sin memoria: falla precisa, se apaga solo y suelta el modelo; '
        '«Probar de nuevo» lo vuelve a encender', () async {
      fakes.placeDownloaded(_sdxs);
      fakes.runtime.failure = StableDiffusionFailure.memory;
      await expectLater(
        engine.generate(
          ImageWireRequest(model: _sdxs.spec.id, prompt: 'x'),
          const ImageWireAccess(),
        ),
        throwsA(
          isA<ImageGenerationException>().having(
            (e) => e.failure,
            'falla',
            ImageFailure.notEnoughMemory,
          ),
        ),
      );
      expect(engine.isClosed(_sdxs), isTrue);
      expect(fakes.runtime.releases, 1);
      expect(prefs.getString('ai_device_image_drawing'), isNull);
      final readiness = await engine.readiness();
      expect(readiness.isReady, isFalse);

      fakes.runtime.failure = null;
      await engine.measure(_sdxs);
      expect(engine.isClosed(_sdxs), isFalse);
      expect((await engine.readiness()).isReady, isTrue);
    });

    test(
      'cancelar corta el motor y llega como «cancelado», no como error',
      () async {
        fakes.placeDownloaded(_sdxs);
        fakes.runtime.gate = Completer<void>();
        final cancel = CancelToken();
        final drawing = engine.generate(
          ImageWireRequest(model: _sdxs.spec.id, prompt: 'x'),
          const ImageWireAccess(),
          cancel: cancel,
        );
        await pumpEventQueue();
        cancel.cancel();
        await expectLater(
          drawing,
          throwsA(
            isA<ImageGenerationException>().having(
              (e) => e.failure,
              'falla',
              ImageFailure.cancelled,
            ),
          ),
        );
        expect(fakes.runtime.cancels, 1);
        expect(engine.isClosed(_sdxs), isFalse);

        // Ya cancelado antes de empezar: ni llega al motor.
        final before = fakes.runtime.jobs.length;
        await expectLater(
          engine.generate(
            ImageWireRequest(model: _sdxs.spec.id, prompt: 'x'),
            const ImageWireAccess(),
            cancel: cancel,
          ),
          throwsA(isA<ImageGenerationException>()),
        );
        expect(fakes.runtime.jobs.length, before);
      },
    );

    test('de a una imagen: la segunda espera a la primera', () async {
      fakes.placeDownloaded(_sdxs);
      final gate = fakes.runtime.gate = Completer<void>();
      final first = engine.generate(
        ImageWireRequest(model: _sdxs.spec.id, prompt: 'uno'),
        const ImageWireAccess(),
      );
      final second = engine.generate(
        ImageWireRequest(model: _sdxs.spec.id, prompt: 'dos'),
        const ImageWireAccess(),
      );
      await pumpEventQueue();
      expect(fakes.runtime.jobs.map((j) => j.prompt), ['uno']);
      gate.complete();
      await first;
      await second;
      expect(fakes.runtime.jobs.map((j) => j.prompt), ['uno', 'dos']);
    });

    test('cada falla del motor tiene la suya', () {
      expect(
        {
          for (final failure in StableDiffusionFailure.values)
            failure: imageFailureOfRuntime(failure),
        },
        {
          StableDiffusionFailure.unavailable: ImageFailure.unsupportedDevice,
          StableDiffusionFailure.load: ImageFailure.unknown,
          StableDiffusionFailure.memory: ImageFailure.notEnoughMemory,
          StableDiffusionFailure.generate: ImageFailure.noImage,
          StableDiffusionFailure.cancelled: ImageFailure.cancelled,
          StableDiffusionFailure.arguments: ImageFailure.badRequest,
        },
      );
    });
  });

  test('suelta el modelo pasado un rato sin dibujar, y ya si se lo piden', () {
    fakeAsync((async) {
      late StableDiffusionImageEngine idle;
      unawaited(
        build(releaseAfter: const Duration(minutes: 1)).then((e) => idle = e),
      );
      async.flushMicrotasks();
      fakes.placeDownloaded(_sdxs);
      unawaited(
        idle.generate(
          ImageWireRequest(model: _sdxs.spec.id, prompt: 'x'),
          const ImageWireAccess(),
        ),
      );
      async.flushMicrotasks();
      expect(fakes.runtime.isLoaded, isTrue);
      async.elapse(const Duration(seconds: 59));
      expect(fakes.runtime.releases, 0);
      async.elapse(const Duration(seconds: 2));
      expect(fakes.runtime.releases, 1);
      expect(fakes.runtime.isLoaded, isFalse);
    });
  });

  test(
    'releaseNow suelta el cargado, y sin nada cargado no hace nada',
    () async {
      await engine.releaseNow();
      expect(fakes.runtime.releases, 0);
      fakes.placeDownloaded(_sdxs);
      await engine.generate(
        ImageWireRequest(model: _sdxs.spec.id, prompt: 'x'),
        const ImageWireAccess(),
      );
      await engine.releaseNow();
      expect(fakes.runtime.releases, 1);
    },
  );

  test('avisa cuando cambia lo elegido, lo bajado o lo medido', () async {
    final changes = <void>[];
    final sub = engine.changes().listen(changes.add);
    addTearDown(sub.cancel);
    chosenChanges.add(null);
    await store.markClosed(_turbo, _now);
    await pumpEventQueue();
    expect(changes, hasLength(2));
  });
}
