import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/on_device_image_engine.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_illustration_store.dart';
import 'package:sinapsis/features/ai_models/data/repositories/secure_ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/data/repositories/secure_image_account_repository.dart';
import 'package:sinapsis/features/ai_models/data/services/illustration_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

import '../../../support/fake_id_generator.dart';

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1]);

/// Un proveedor de imágenes de mentira: devuelve lo programado y anota cada
/// pedido. Nunca sale a internet.
class _FakeImageWire implements ImageWire {
  _FakeImageWire(this.provider);

  @override
  final IllustrationProvider provider;

  List<ImageModelInfo> models = const [
    ImageModelInfo(id: 'modelo-caro', displayName: 'Caro'),
    ImageModelInfo(id: 'gemini-nano-banana-2.1', displayName: 'Nano Banana'),
  ];
  ImageFailure? listFailure;
  final failures = <ImageFailure>[];
  int? inputTokens = 40;
  int? outputTokens = 1120;
  final requests = <ImageWireRequest>[];
  final keys = <String?>[];
  int lists = 0;

  @override
  Future<List<ImageModelInfo>> listImageModels(ImageWireAccess access) async {
    lists++;
    keys.add(access.key);
    if (listFailure case final failure?) {
      throw ImageGenerationException(failure);
    }
    return models;
  }

  @override
  String? recommendedImageModel(List<ImageModelInfo> models) =>
      models.where((m) => m.id == 'gemini-nano-banana-2.1').firstOrNull?.id ??
      models.firstOrNull?.id;

  @override
  Future<GeneratedImage> generate(
    ImageWireRequest request,
    ImageWireAccess access, {
    CancelToken? cancel,
  }) async {
    requests.add(request);
    keys.add(access.key);
    if (failures.isNotEmpty) {
      throw ImageGenerationException(failures.removeAt(0));
    }
    return GeneratedImage(
      bytes: _jpeg,
      mimeType: 'image/jpeg',
      model: request.model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }
}

/// El modelo del teléfono de mentira.
class _FakeEngine extends _FakeImageWire implements OnDeviceImageEngine {
  _FakeEngine() : super(IllustrationProvider.onDevice) {
    models = const [ImageModelInfo(id: 'sdxs-512', displayName: 'SDXS 512')];
    inputTokens = null;
    outputTokens = null;
  }

  OnDeviceImageReadiness ready = const OnDeviceImageReadiness.ready();

  @override
  String get displayName => 'SDXS 512';

  @override
  Future<OnDeviceImageReadiness> readiness() async => ready;

  @override
  Duration estimatedTimePerImage(IllustrationSize size) =>
      const Duration(seconds: 40);
}

void main() {
  final now = DateTime.utc(2026, 10, 28, 15);
  late SecureAiAccountRepository textAccounts;
  late SecureImageAccountRepository imageAccounts;
  late PrefsIllustrationStore store;
  late PrefsAiUsageLedger ledger;
  late _FakeImageWire gemini;
  late _FakeImageWire openAi;
  late _FakeImageWire huggingFace;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    textAccounts = SecureAiAccountRepository(
      ids: FakeIdGenerator(prefix: 'txt'),
      clock: () => now,
    );
    imageAccounts = SecureImageAccountRepository(
      ids: FakeIdGenerator(prefix: 'img'),
      clock: () => now,
    );
    store = PrefsIllustrationStore(prefs: prefs);
    ledger = PrefsAiUsageLedger(prefs: prefs);
    gemini = _FakeImageWire(IllustrationProvider.gemini);
    openAi = _FakeImageWire(IllustrationProvider.openAi);
    huggingFace = _FakeImageWire(IllustrationProvider.huggingFace);
  });

  IllustrationService service({OnDeviceImageEngine? onDevice}) =>
      IllustrationService(
        textAccounts: textAccounts,
        imageAccounts: imageAccounts,
        wires: {
          IllustrationProvider.gemini: gemini,
          IllustrationProvider.openAi: openAi,
          IllustrationProvider.huggingFace: huggingFace,
        },
        store: store,
        usage: ledger,
        clock: () => now,
        onDevice: onDevice,
      );

  Future<IllustrationAccount> addGemini([String key = 'AIza1']) async {
    final account = await textAccounts.add(
      provider: AiProvider.gemini,
      key: key,
      label: 'Trabajo',
    );
    return IllustrationAccount.ofTextAccount(account)!;
  }

  test('las cuentas que dibujan: Gemini y OpenAI de F32, Hugging Face y el '
      'teléfono si hay motor; Claude no', () async {
    await textAccounts.add(provider: AiProvider.anthropic, key: 'sk-ant');
    final g = await addGemini();
    await textAccounts.add(provider: AiProvider.openAi, key: 'sk-1');
    await imageAccounts.add(
      provider: IllustrationProvider.huggingFace,
      key: 'hf_1',
    );

    final withoutEngine = await service().accounts();
    expect(withoutEngine.map((a) => a.provider), [
      IllustrationProvider.gemini,
      IllustrationProvider.openAi,
      IllustrationProvider.huggingFace,
    ]);
    expect(withoutEngine.first, g);

    final withEngine = await service(onDevice: _FakeEngine()).accounts();
    expect(withEngine.last.id, kOnDeviceIllustrationAccountId);
    expect(withEngine.last.label, 'SDXS 512');
  });

  group('dibujar', () {
    test('con la clave de F32, el modelo recomendado, la forma y el estilo; '
        'sin texto en la imagen', () async {
      final account = await addGemini('AIzaSECRETA');

      final result = await service().generate(
        prompt: 'Moisés frente al mar',
        styleHint: 'acuarela suave',
        aspect: IllustrationAspect.wide,
        account: account,
      );

      final request = gemini.requests.single;
      expect(request.model, 'gemini-nano-banana-2.1');
      expect(request.aspect, IllustrationAspect.wide);
      expect(request.size, IllustrationSize.standard);
      expect(
        request.prompt,
        'Moisés frente al mar\n'
        'Estilo: acuarela suave.\n'
        'Sin texto, letras ni números dentro de la imagen.',
      );
      expect(gemini.keys, everyElement('AIzaSECRETA'));
      expect(result.image.bytes, _jpeg);
      expect(result.accountId, account.id);
      expect(result.inputTokens, 40);
      expect(result.outputTokens, 1120);
      // Con los tokens contados y la tabla: 40 × 1,5 + 1120 × 30, por millón.
      expect(result.costUsd, closeTo((40 * 1.5 + 1120 * 30) / 1e6, 1e-12));
      expect(result.costIsEstimate, isFalse);
    });

    test(
      'anota la imagen en lo gastado del día y recuerda que puede',
      () async {
        final account = await addGemini();

        await service().generate(prompt: 'x', account: account);

        final usage = ledger.usageOf(account.id, now: now);
        expect(usage.images, 1);
        expect(usage.requests, 1);
        expect(usage.imageTokens, 1160);
        expect(usage.spentMicroUsd, (40 * 1.5 + 1120 * 30).round());
        final capability = store.capabilityOf(account.id);
        expect(capability.can, isTrue);
        expect(capability.model, 'gemini-nano-banana-2.1');
      },
    );

    test('el elegido manda sobre el recomendado, y la lista se pide una sola '
        'vez', () async {
      final account = await addGemini();
      final images = service();
      await images.chooseImageModel(account, 'modelo-caro');

      await images.generate(prompt: 'a', account: account);
      await images.generate(prompt: 'b', account: account);

      expect(gemini.requests.map((r) => r.model), [
        'modelo-caro',
        'modelo-caro',
      ]);
      expect(gemini.lists, 1);
    });

    test('sin tokens contados: el precio por imagen de la tabla, estimado', () {
      expect(
        imageCostOf(
          IllustrationProvider.gemini,
          model: 'gemini-3.1-flash-image',
          size: IllustrationSize.small,
        ),
        (usd: 0.045, estimate: true),
      );
      expect(
        imageCostOf(
          IllustrationProvider.huggingFace,
          model: 'black-forest-labs/FLUX.1-schnell',
          size: IllustrationSize.standard,
        ),
        (usd: null, estimate: true),
      );
      expect(
        imageCostOf(
          IllustrationProvider.onDevice,
          model: 'sdxs',
          size: IllustrationSize.small,
        ),
        (usd: 0, estimate: false),
      );
    });

    test('sin facturación: lo recuerda como «no puede» con su porqué, y '
        'avisa', () async {
      final account = await addGemini();
      gemini.failures.add(ImageFailure.noBilling);

      await expectLater(
        service().generate(prompt: 'x', account: account),
        throwsA(
          isA<ImageGenerationException>().having(
            (e) => e.failure,
            'failure',
            ImageFailure.noBilling,
          ),
        ),
      );

      final capability = store.capabilityOf(account.id);
      expect(capability.cannot, isTrue);
      expect(capability.reason, ImageFailure.noBilling);
      expect(capability.model, 'gemini-nano-banana-2.1');
      expect(ledger.usageOf(account.id, now: now).images, 0);
    });

    test('sin internet: no cambia lo que se sabía de la cuenta', () async {
      final account = await addGemini();
      final images = service();
      await images.generate(prompt: 'x', account: account);
      gemini.failures.add(ImageFailure.network);

      await expectLater(
        images.generate(prompt: 'x', account: account),
        throwsA(isA<ImageGenerationException>()),
      );

      expect(store.capabilityOf(account.id).can, isTrue);
    });

    test('una cuenta sin modelos de imagen: no puede', () async {
      final account = await addGemini();
      gemini.models = const [];

      await expectLater(
        service().generate(prompt: 'x', account: account),
        throwsA(
          isA<ImageGenerationException>().having(
            (e) => e.failure,
            'failure',
            ImageFailure.noImageModel,
          ),
        ),
      );
      expect(store.capabilityOf(account.id).reason, ImageFailure.noImageModel);
    });

    test('Hugging Face: con su token y su camino; sin precio conocido no '
        'suma dólares', () async {
      final account = await imageAccounts.add(
        provider: IllustrationProvider.huggingFace,
        key: 'hf_TOKEN',
      );
      huggingFace
        ..models = const [
          ImageModelInfo(
            id: 'black-forest-labs/FLUX.1-schnell',
            displayName: 'FLUX',
            route: 'nscale|black-forest-labs/FLUX.1-schnell',
          ),
        ]
        ..inputTokens = null
        ..outputTokens = null;

      final result = await service().generate(prompt: 'x', account: account);

      expect(huggingFace.keys, everyElement('hf_TOKEN'));
      expect(
        huggingFace.requests.single.route,
        'nscale|black-forest-labs/FLUX.1-schnell',
      );
      expect(result.costUsd, isNull);
      final usage = ledger.usageOf(account.id, now: now);
      expect(usage.images, 1);
      expect(usage.spentMicroUsd, 0);
    });
  });

  group('la cuenta por defecto', () {
    test('la primera que puede; si ninguna, la primera sin probar; nunca una '
        'que no puede', () async {
      final a = await addGemini('k1');
      final b = await addGemini('k2');
      final images = service();
      await store.setCapability(
        a.id,
        const ImageCapability(
          state: ImageCapabilityState.cannot,
          reason: ImageFailure.noBilling,
        ),
      );
      expect((await images.defaultAccount())?.id, b.id);

      await store.setCapability(
        b.id,
        const ImageCapability(
          state: ImageCapabilityState.cannot,
          reason: ImageFailure.noBilling,
        ),
      );
      expect(await images.defaultAccount(), isNull);
      await expectLater(
        images.generate(prompt: 'x'),
        throwsA(
          isA<ImageGenerationException>().having(
            (e) => e.failure,
            'failure',
            ImageFailure.noAccount,
          ),
        ),
      );
    });
  });

  group('«Probar ahora»', () {
    test('trae la lista de nuevo y pide una sola imagen chica', () async {
      final account = await addGemini();

      final capability = await service().probe(account);

      expect(capability.can, isTrue);
      expect(gemini.lists, 1);
      final request = gemini.requests.single;
      expect(request.size, IllustrationSize.small);
      expect(request.prompt, startsWith(kImageProbePrompt));
    });

    test(
      'lo que dice de la cuenta queda; lo del momento sale como error',
      () async {
        final account = await addGemini();
        final images = service();
        gemini.failures.add(ImageFailure.orgUnverified);
        final cannot = await images.probe(account);
        expect(cannot.reason, ImageFailure.orgUnverified);

        gemini.failures.add(ImageFailure.rateLimited);
        await expectLater(
          images.probe(account),
          throwsA(isA<ImageGenerationException>()),
        );
      },
    );

    test(
      'una clave que no anda al listar: no puede, sin pedir imagen',
      () async {
        final account = await addGemini();
        gemini.listFailure = ImageFailure.invalidKey;

        final capability = await service().probe(account);

        expect(capability.reason, ImageFailure.invalidKey);
        expect(gemini.requests, isEmpty);
      },
    );
  });

  group('el modelo del teléfono', () {
    test('dibuja sin clave ni costo; puede o no según el motor', () async {
      final engine = _FakeEngine();
      final images = service(onDevice: engine);
      final account = (await images.accounts()).single;

      expect((await images.capabilityOf(account)).can, isTrue);
      final result = await images.generate(prompt: 'x', account: account);
      expect(engine.keys, everyElement(isNull));
      expect(result.costUsd, 0);
      expect(ledger.usageOf(account.id, now: now).images, 1);

      engine.ready = const OnDeviceImageReadiness.notReady(
        ImageFailure.modelNotDownloaded,
        downloadBytes: 600000000,
      );
      final capability = await images.capabilityOf(account);
      expect(capability.reason, ImageFailure.modelNotDownloaded);
      await expectLater(
        images.generate(prompt: 'x', account: account),
        throwsA(
          isA<ImageGenerationException>().having(
            (e) => e.failure,
            'failure',
            ImageFailure.modelNotDownloaded,
          ),
        ),
      );
    });
  });
}
