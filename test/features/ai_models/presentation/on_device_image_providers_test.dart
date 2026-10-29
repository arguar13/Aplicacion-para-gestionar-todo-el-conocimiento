import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/on_device_image_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';

import '../../../support/illustration_harness.dart';
import '../../../support/on_device_harness.dart';

const _sdxs = OnDeviceImageModel.sdxs;
const _turbo = OnDeviceImageModel.sdTurbo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late OnDeviceFakes fakes;
  late IllustrationHarness harness;

  Future<void> create({AiProvider provider = AiProvider.anthropic}) async {
    harness = await IllustrationHarness.create(
      provider: provider,
      realOnDeviceEngine: true,
      overrides: fakes.overrides,
    );
    addTearDown(harness.container.dispose);
    // Que el motor arranque: la carpeta, lo que quedó de antes y el teléfono.
    final engine = harness.container.read(stableDiffusionImageEngineProvider)!;
    await engine.start();
  }

  /// Lo que se sabe del teléfono para dibujar, escuchándolo mientras dure la
  /// prueba (se descarta si nadie lo mira).
  Future<ImageCapability?> capabilityOf(ProviderContainer container) {
    final sub = container.listen(
      onDeviceImageCapabilityProvider.future,
      (_, _) {},
    );
    addTearDown(sub.close);
    return sub.read();
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('imagenes_telefono_');
    fakes = OnDeviceFakes(root: root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'sin la biblioteca nativa no hay motor ni cuenta del teléfono',
    () async {
      harness = await IllustrationHarness.create(realOnDeviceEngine: true);
      addTearDown(harness.container.dispose);
      // En las pruebas no es Android: no se busca la biblioteca.
      expect(harness.container.read(sdNativeLibraryProvider), isNull);
      expect(harness.container.read(onDeviceImageEngineProvider), isNull);
      expect(
        await harness.container.read(illustrationServiceProvider).accounts(),
        isNot(
          contains(
            predicate<IllustrationAccount>((a) => a.provider.isOnDevice),
          ),
        ),
      );
    },
  );

  test(
    'con el motor, el teléfono es una cuenta más que el servicio sabe usar',
    () async {
      await create();
      final container = harness.container;
      expect(
        container.read(onDeviceImageEngineProvider),
        same(container.read(stableDiffusionImageEngineProvider)),
      );
      final accounts = await container
          .read(illustrationServiceProvider)
          .accounts();
      expect(accounts.last.id, kOnDeviceIllustrationAccountId);
      expect(accounts.last.label, 'SDXS-512');

      // Bajado, dibuja de verdad por el servicio, sin costo.
      fakes.placeDownloaded(_sdxs);
      final result = await container
          .read(illustrationServiceProvider)
          .generate(prompt: 'un faro', account: accounts.last);
      expect(result.costUsd, 0);
      expect(result.image.mimeType, 'image/png');
      expect(fakes.runtime.jobs.single.prompt, contains('un faro'));
      expect(
        fakes.runtime.jobs.single.prompt,
        contains('Sin texto'),
        reason: 'el texto lo pone siempre la app',
      );
    },
  );

  test('los modelos del teléfono se le preguntan al motor cada vez: uno '
      'recién bajado aparece en el acto', () async {
    await create();
    final service = harness.container.read(illustrationServiceProvider);
    final phone = (await service.accounts()).last;
    expect(await service.imageModelsOf(phone), isEmpty);
    fakes.placeDownloaded(_turbo);
    expect((await service.imageModelsOf(phone)).map((m) => m.id), [
      _turbo.spec.id,
    ]);
    expect((await service.resolveModel(phone)).id, _turbo.spec.id);
  });

  group('«Con tu IA actual» con el modelo del teléfono', () {
    const request = CreationEstimateRequest(
      inputTokens: 1000,
      expectedOutputTokens: 200,
      images: 3,
    );

    test(
      'sin bajar, se ofrece con «hay que descargarlo» y el tiempo estimado',
      () async {
        await create();
        final container = harness.container;
        final sub = container.listen(
          creationEstimateProvider(request),
          (_, _) {},
        );
        addTearDown(sub.close);
        final capability = await capabilityOf(container);
        expect(capability?.reason, ImageFailure.modelNotDownloaded);
        final onDevice = sub
            .read()
            .alternatives
            .whereType<UseOnDeviceModel>()
            .single;
        expect(onDevice.needsDownload, isTrue);
        expect(onDevice.timeMeasured, isFalse);
        expect(
          onDevice.time,
          Duration(seconds: _sdxs.spec.estimatedSecondsPerImage * 3),
        );
      },
    );

    test('bajado y medido: dibuja sin costo ni cuota, con lo medido sumado al '
        'tiempo', () async {
      await create();
      final container = harness.container;
      fakes.placeDownloaded(_sdxs);
      await container.read(onDeviceImageActionsProvider)!.measure(_sdxs);
      await capabilityOf(container);

      final sub = container.listen(
        creationEstimateProvider(
          request.copyWith(imageAccountId: kOnDeviceIllustrationAccountId),
        ),
        (_, _) {},
      );
      addTearDown(sub.close);
      // Lo que se recalcula al saberse que puede.
      await capabilityOf(container);
      final estimate = sub.read();
      expect(estimate.canIllustrate, isTrue);
      expect(estimate.imageSide!.account.provider.isOnDevice, isTrue);
      expect(estimate.imageSide!.timeMeasured, isTrue);
      expect(estimate.imagesUsd, 0);
      expect(
        estimate.quota.where(
          (q) => q.accountId == kOnDeviceIllustrationAccountId,
        ),
        isEmpty,
      );
      expect(estimate.localTime, const Duration(seconds: 17 * 3));
    });

    test('en un teléfono de 4 GB no se ofrece', () async {
      fakes.probe.profile = phoneWith(ramGb: 4);
      await create();
      final container = harness.container;
      expect(
        (await capabilityOf(container))?.reason,
        ImageFailure.deviceTooSmall,
      );
      final sub = container.listen(
        creationEstimateProvider(request),
        (_, _) {},
      );
      addTearDown(sub.close);
      expect(sub.read().alternatives.whereType<UseOnDeviceModel>(), isEmpty);
    });
  });

  group('las acciones', () {
    test(
      'bajar, pausar, seguir y terminar, con el estado de cada uno',
      () async {
        await create();
        final container = harness.container;
        final actions = container.read(onDeviceImageActionsProvider)!;
        final state = container.listen(
          onDeviceModelDownloadProvider(_turbo),
          (_, _) {},
        );
        addTearDown(state.close);

        expect(actions.download(_turbo), isTrue);
        expect(actions.download(_turbo), isFalse, reason: 'una sola descarga');
        await pumpEventQueue();
        fakes.transfer.progress(_turbo.spec.fileName, 10);
        await pumpEventQueue();
        expect(state.read(), isA<ModelDownloadRunning>());

        await actions.pause(_turbo);
        await pumpEventQueue();
        expect(state.read(), isA<ModelDownloadPaused>());
        expect(await actions.pausedProgress(_turbo), greaterThan(0));

        actions.download(_turbo);
        await pumpEventQueue();
        await fakes.transfer.finish(
          _turbo.spec.fileName,
          fakeModelContent(_turbo),
        );
        await pumpEventQueue();
        expect(state.read(), isA<ModelDownloadIdle>());
        expect(
          container
              .read(stableDiffusionImageEngineProvider)!
              .isDownloaded(_turbo),
          isTrue,
        );
      },
    );

    test('cancelar una en curso la corta y borra lo bajado', () async {
      await create();
      final actions = harness.container.read(onDeviceImageActionsProvider)!
        ..download(_sdxs);
      await pumpEventQueue();
      fakes.transfer.progress(_sdxs.spec.fileName, 3);
      await actions.cancel(_sdxs).timeout(const Duration(seconds: 5));
      expect(await actions.pausedProgress(_sdxs), isNull);
      expect(
        harness.container.read(onDeviceModelDownloadProvider(_sdxs)),
        isA<ModelDownloadIdle>(),
      );
    });

    test('cancelar una pausada borra lo bajado a medias', () async {
      await create();
      final actions = harness.container.read(onDeviceImageActionsProvider)!
        ..download(_sdxs);
      await pumpEventQueue();
      fakes.transfer.progress(_sdxs.spec.fileName, 3);
      await actions.pause(_sdxs);
      await pumpEventQueue();
      await actions.cancel(_sdxs);
      expect(await actions.pausedProgress(_sdxs), isNull);
      expect(
        harness.container.read(onDeviceModelDownloadProvider(_sdxs)),
        isA<ModelDownloadIdle>(),
      );
    });

    test(
      '«Usar este» lo elige; borrar el elegido vuelve a elegir solo',
      () async {
        await create();
        final container = harness.container;
        final engine = container.read(stableDiffusionImageEngineProvider)!;
        final actions = container.read(onDeviceImageActionsProvider)!;
        fakes
          ..placeDownloaded(_sdxs)
          ..placeDownloaded(_turbo);
        expect(engine.activeModel, _turbo);

        await actions.use(_sdxs);
        expect(engine.activeModel, _sdxs);
        expect(engine.displayName, 'SDXS-512');

        await actions.delete(_sdxs);
        expect(engine.chosenModel, isNull);
        expect(engine.activeModel, _turbo);
        expect(fakes.fileOf(_sdxs).existsSync(), isFalse);
        expect(fakes.fileOf(_turbo).existsSync(), isTrue);
      },
    );
  });
}
