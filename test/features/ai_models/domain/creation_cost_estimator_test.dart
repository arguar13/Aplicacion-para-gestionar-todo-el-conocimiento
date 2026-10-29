import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/daily_quota.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';

final _at = DateTime.utc(2026, 10, 28);
const _estimator = CreationCostEstimator();

ImageSide _side(
  String id,
  IllustrationProvider provider, {
  ImageCapabilityState state = ImageCapabilityState.can,
  ImageFailure? reason,
  String? model,
  AccountUsage? usage,
  DailyQuota? quota,
  Duration? timePerImage,
}) => ImageSide(
  account: provider.isOnDevice
      ? IllustrationAccount.onDevice('SDXS 512')
      : IllustrationAccount(
          id: id,
          provider: provider,
          label: 'Cuenta $id',
          addedAt: _at,
        ),
  capability: ImageCapability(state: state, reason: reason),
  model: model,
  usage: usage,
  quota: quota,
  timePerImage: timePerImage,
);

TextSide _text(
  AiProvider provider, {
  String? accountId,
  String? model,
  AccountUsage? usage,
  DailyQuota? quota,
  LanguageModelStatus? status,
}) => TextSide(
  provider: provider,
  model: model,
  accountId: accountId,
  accountLabel: accountId == null ? null : 'Cuenta $accountId',
  usage: usage,
  quota: quota,
  status: status,
);

void main() {
  group('Gemma', () {
    test('escribe sin cuota: dice cuánto tarda; no dibuja, y las opciones '
        'son agregar quien dibuje', () {
      final estimate = _estimator.estimate(
        text: _text(AiProvider.gemma),
        inputTokens: 1000,
        expectedOutputTokens: 80,
        images: 3,
      );

      expect(estimate.canWriteText, isTrue);
      expect(estimate.textUsd, 0);
      expect(estimate.quota, isEmpty);
      // 1000 / 100 + 80 / 8 = 20 s, estimado (nunca se midió).
      expect(estimate.localTime, const Duration(seconds: 20));
      expect(estimate.localTimeIsEstimate, isTrue);
      expect(estimate.canIllustrate, isFalse);
      expect(estimate.illustrateReason, ImageFailure.noAccount);
      expect(estimate.alternatives, const [
        ContinueWithoutIllustrations(),
        AddImageKey(IllustrationProvider.gemini),
        AddImageKey(IllustrationProvider.openAi),
        AddHuggingFaceToken(),
      ]);
    });

    test('con lo medido en el teléfono, no es estimado', () {
      final estimate = _estimator.estimate(
        text: _text(AiProvider.gemma),
        inputTokens: 300,
        expectedOutputTokens: 100,
        localSpeed: const LocalSpeed(
          readTokensPerSecond: 300,
          writeTokensPerSecond: 20,
          measured: true,
        ),
      );
      expect(estimate.localTime, const Duration(seconds: 6));
      expect(estimate.localTimeIsEstimate, isFalse);
      expect(estimate.alternatives, isEmpty);
    });
  });

  test('Claude solo: escribe con su precio y sin cuota fijada; las '
      'ilustraciones no, porque Claude no dibuja', () {
    final estimate = _estimator.estimate(
      text: _text(
        AiProvider.anthropic,
        accountId: 'c',
        model: 'claude-sonnet-5-5',
        usage: const AccountUsage(accountId: 'c', day: '2026-10-28'),
      ),
      inputTokens: 100000,
      expectedOutputTokens: 10000,
      images: 2,
    );

    // 100 mil × US$ 2 + 10 mil × US$ 10, por millón.
    expect(estimate.textUsd, closeTo(0.3, 1e-9));
    expect(estimate.quota.single.hasQuota, isFalse);
    expect(estimate.canIllustrate, isFalse);
    expect(estimate.illustrateReason, ImageFailure.noAccount);
    expect(estimate.imageSide, isNull);
    expect(estimate.alternatives.first, const ContinueWithoutIllustrations());
    expect(estimate.alternatives.whereType<AddImageKey>(), hasLength(2));
  });

  test('Gemini sin facturación: lo dice con el nombre de la cuenta, y vuelve '
      'a ofrecer una clave de Gemini (con facturación)', () {
    final estimate = _estimator.estimate(
      text: _text(AiProvider.gemini, accountId: 'g'),
      inputTokens: 500,
      expectedOutputTokens: 100,
      images: 4,
      imageAccounts: [
        _side(
          'g',
          IllustrationProvider.gemini,
          state: ImageCapabilityState.cannot,
          reason: ImageFailure.noBilling,
        ),
      ],
    );

    expect(estimate.canWriteText, isTrue);
    expect(estimate.textUsd, 0);
    expect(estimate.canIllustrate, isFalse);
    expect(estimate.illustrateReason, ImageFailure.noBilling);
    expect(estimate.imageSide?.account.id, 'g');
    expect(estimate.imagesUsd, isNull);
    expect(estimate.alternatives, const [
      ContinueWithoutIllustrations(),
      AddImageKey(IllustrationProvider.gemini),
      AddImageKey(IllustrationProvider.openAi),
      AddHuggingFaceToken(),
    ]);
  });

  test('Gemini que puede: las imágenes con su precio de la tabla, y el '
      'porcentaje de la cuota estimada de hoy', () {
    final estimate = _estimator.estimate(
      text: _text(
        AiProvider.gemini,
        accountId: 'g',
        usage: const AccountUsage(
          accountId: 'g',
          day: '2026-10-28',
          requests: 105,
        ),
        quota: defaultDailyQuota(AiProvider.gemini),
      ),
      inputTokens: 500,
      expectedOutputTokens: 100,
      images: 4,
      imageAccounts: [
        _side(
          'g',
          IllustrationProvider.gemini,
          model: 'gemini-nano-banana-2.1',
        ),
      ],
    );

    expect(estimate.canIllustrate, isTrue);
    expect(estimate.alternatives, isEmpty);
    // Cuatro imágenes 1K a US$ 0,0336 más lo que lee cada descripción.
    expect(
      estimate.imagesUsd,
      closeTo(4 * (0.0336 + kImagePromptTokens * 1.5 / 1e6), 1e-9),
    );
    expect(estimate.imageTokens, 4 * 1120);
    expect(estimate.totalUsd, closeTo(estimate.imagesUsd!, 1e-9));
    final share = estimate.quota.single;
    // Un pedido de texto y cuatro de imagen, de 250 estimados; 105 usados.
    expect(share.dimension, QuotaDimension.requests);
    expect(share.percentOfQuota, closeTo(2, 1e-9));
    expect(share.percentUsed, closeTo(42, 1e-9));
    expect(share.quotaIsEstimate, isTrue);
    expect(share.wouldExceed, isFalse);
  });

  test('OpenAI con la organización sin verificar', () {
    final estimate = _estimator.estimate(
      text: _text(AiProvider.openAi, accountId: 'o', model: 'gpt-5.2'),
      inputTokens: 1000,
      expectedOutputTokens: 1000,
      images: 1,
      imageAccounts: [
        _side(
          'o',
          IllustrationProvider.openAi,
          state: ImageCapabilityState.cannot,
          reason: ImageFailure.orgUnverified,
        ),
      ],
    );

    expect(estimate.textUsd, closeTo((1000 * 1.75 + 1000 * 14) / 1e6, 1e-12));
    expect(estimate.illustrateReason, ImageFailure.orgUnverified);
    expect(estimate.alternatives, const [
      ContinueWithoutIllustrations(),
      AddImageKey(IllustrationProvider.gemini),
      AddImageKey(IllustrationProvider.openAi),
      AddHuggingFaceToken(),
    ]);
  });

  group('dos cuentas, y la segunda puede', () {
    final accounts = [
      _side(
        'a',
        IllustrationProvider.gemini,
        state: ImageCapabilityState.cannot,
        reason: ImageFailure.noBilling,
      ),
      _side(
        'u',
        IllustrationProvider.openAi,
        state: ImageCapabilityState.untested,
        model: 'gpt-image-1-mini',
      ),
      _side('b', IllustrationProvider.gemini, model: 'gemini-nano-banana-2.1'),
    ];

    test('no se cambia sola: se ofrece por su nombre, primero la que puede '
        'y después la sin probar, y ya no hace falta otra clave de esos '
        'proveedores', () {
      final estimate = _estimator.estimate(
        text: _text(AiProvider.gemini, accountId: 'a'),
        inputTokens: 10,
        expectedOutputTokens: 10,
        images: 2,
        imageAccounts: accounts,
      );

      expect(estimate.canIllustrate, isFalse);
      expect(estimate.illustrateReason, ImageFailure.noBilling);
      final alternatives = estimate.alternatives;
      expect(alternatives.first, const ContinueWithoutIllustrations());
      expect(
        alternatives.whereType<UseOtherImageAccount>().map((a) => a.account.id),
        ['b', 'u'],
      );
      expect(alternatives[1], isA<UseOtherImageAccount>());
      expect((alternatives[2] as UseOtherImageAccount).untested, isTrue);
      expect(
        (alternatives[1] as UseOtherImageAccount).imagesUsd,
        closeTo(2 * (0.0336 + kImagePromptTokens * 1.5 / 1e6), 1e-9),
      );
      expect(alternatives.whereType<AddImageKey>(), isEmpty);
      expect(alternatives.last, const AddHuggingFaceToken());
    });

    test('elegida en el aviso, dibuja la otra y su cuota va aparte', () {
      final estimate = _estimator.estimate(
        text: _text(
          AiProvider.gemini,
          accountId: 'a',
          quota: const DailyQuota(requests: 100),
        ),
        inputTokens: 10,
        expectedOutputTokens: 10,
        images: 2,
        imageAccountId: 'b',
        imageAccounts: [
          ...accounts.take(2),
          _side(
            'b',
            IllustrationProvider.gemini,
            model: 'gemini-nano-banana-2.1',
            quota: const DailyQuota(images: 10),
            usage: const AccountUsage(
              accountId: 'b',
              day: '2026-10-28',
              images: 3,
            ),
          ),
        ],
      );

      expect(estimate.canIllustrate, isTrue);
      expect(estimate.imageSide?.account.id, 'b');
      expect(estimate.quota.map((s) => s.accountId), ['a', 'b']);
      expect(estimate.quota.first.percentOfQuota, closeTo(1, 1e-9));
      expect(estimate.quota.last.dimension, QuotaDimension.images);
      expect(estimate.quota.last.percentOfQuota, closeTo(20, 1e-9));
      expect(estimate.quota.last.percentUsed, closeTo(30, 1e-9));
    });
  });

  test(
    'con Hugging Face no se inventa un precio: cobra lo de su proveedor',
    () {
      final estimate = _estimator.estimate(
        text: _text(AiProvider.anthropic, accountId: 'c'),
        inputTokens: 10,
        expectedOutputTokens: 10,
        images: 2,
        imageAccountId: 'h',
        imageAccounts: [
          _side(
            'h',
            IllustrationProvider.huggingFace,
            model: 'black-forest-labs/FLUX.1-schnell',
          ),
        ],
      );
      expect(estimate.canIllustrate, isTrue);
      expect(estimate.imagesUsd, isNull);
      expect(estimate.totalUsd, isNull);
    },
  );

  test('la cuenta que escribe sin probar: se intenta, y lo dice', () {
    final estimate = _estimator.estimate(
      text: _text(AiProvider.gemini, accountId: 'g'),
      inputTokens: 10,
      expectedOutputTokens: 10,
      images: 1,
      imageAccounts: [
        _side(
          'g',
          IllustrationProvider.gemini,
          state: ImageCapabilityState.untested,
        ),
      ],
    );
    expect(estimate.canIllustrate, isTrue);
    expect(estimate.imageSide!.capability.untested, isTrue);
    // Sin modelo conocido, el precio del más caro de Gemini: no promete de
    // menos.
    expect(
      estimate.imagesUsd,
      closeTo(0.134 + kImagePromptTokens * 2 / 1e6, 1e-9),
    );
  });

  group('el modelo del teléfono («Exigente»)', () {
    final device = _side(
      'on-device',
      IllustrationProvider.onDevice,
      timePerImage: const Duration(seconds: 50),
    );

    test('es una opción con su tiempo, después de las cuentas y antes de '
        'agregar claves', () {
      final estimate = _estimator.estimate(
        text: _text(AiProvider.anthropic, accountId: 'c'),
        inputTokens: 10,
        expectedOutputTokens: 10,
        images: 3,
        imageAccounts: [_side('b', IllustrationProvider.gemini), device],
      );
      final alternatives = estimate.alternatives;
      expect(alternatives[1], isA<UseOtherImageAccount>());
      final onDevice = alternatives[2] as UseOnDeviceModel;
      expect(onDevice.time, const Duration(seconds: 150));
      expect(onDevice.needsDownload, isFalse);
      expect(alternatives[3], const AddImageKey(IllustrationProvider.openAi));
    });

    test('sin descargar se ofrece igual; sin memoria, no', () {
      List<IllustrationAlternative> alternativesWith(ImageFailure reason) =>
          _estimator
              .estimate(
                text: _text(AiProvider.gemma),
                inputTokens: 10,
                expectedOutputTokens: 10,
                images: 1,
                imageAccounts: [
                  _side(
                    'on-device',
                    IllustrationProvider.onDevice,
                    state: ImageCapabilityState.cannot,
                    reason: reason,
                  ),
                ],
              )
              .alternatives;
      expect(
        alternativesWith(
          ImageFailure.modelNotDownloaded,
        ).whereType<UseOnDeviceModel>().single.needsDownload,
        isTrue,
      );
      expect(
        alternativesWith(
          ImageFailure.deviceTooSmall,
        ).whereType<UseOnDeviceModel>(),
        isEmpty,
      );
    });

    test('elegido: sin costo ni cuota, con el tiempo de dibujar sumado', () {
      final estimate = _estimator.estimate(
        text: _text(AiProvider.gemma),
        inputTokens: 1000,
        expectedOutputTokens: 80,
        images: 2,
        imageAccountId: kOnDeviceIllustrationAccountId,
        imageAccounts: [device],
      );
      expect(estimate.canIllustrate, isTrue);
      expect(estimate.imagesUsd, 0);
      expect(estimate.quota, isEmpty);
      expect(estimate.localTime, const Duration(seconds: 120));
    });
  });

  group('la cuota', () {
    test('la que más aprieta, contando lo usado; y si se pasaría', () {
      final estimate = _estimator.estimate(
        text: _text(
          AiProvider.openAi,
          accountId: 'o',
          model: 'gpt-5-mini',
          usage: const AccountUsage(
            accountId: 'o',
            day: '2026-10-28',
            requests: 1,
            spentMicroUsd: 900000,
          ),
          quota: const DailyQuota(requests: 100, usd: 1),
        ),
        inputTokens: 100000,
        expectedOutputTokens: 50000,
        images: 2,
        imageAccounts: [
          _side('o', IllustrationProvider.openAi, model: 'gpt-image-1-mini'),
        ],
      );
      final share = estimate.quota.single;
      expect(share.dimension, QuotaDimension.usd);
      expect(share.quotaIsEstimate, isFalse);
      // Lo usado: US$ 0,90 de imágenes de antes (el texto de hoy, sin
      // tokens). Lo de ahora: texto US$ 0,125 + dos imágenes Mini.
      expect(share.percentUsed, closeTo(90, 1e-9));
      const imagesUsd = 2 * (1056 * 8 / 1e6 + kImagePromptTokens * 2 / 1e6);
      expect(share.percentOfQuota, closeTo((0.125 + imagesUsd) * 100, 1e-6));
      expect(share.wouldExceed, isTrue);
    });

    test('lo usado del día en tokens cuenta texto e imágenes', () {
      final share = CreationCostEstimator.quotaShare(
        accountId: 'a',
        label: 'A',
        usage: const AccountUsage(
          accountId: 'a',
          day: 'd',
          inputTokens: 300,
          outputTokens: 200,
          imageTokens: 500,
        ),
        quota: const DailyQuota(tokens: 2000),
        requests: 0,
        tokens: 0,
        images: 0,
        usd: 0,
        usedUsd: 0,
      );
      expect(share.percentUsed, closeTo(50, 1e-9));
      expect(share.percentOfQuota, 0);
    });
  });

  test('la IA que escribe sin cuota ahora: no puede escribir, y dice por '
      'qué', () {
    const status = LanguageModelOutOfQuota(
      provider: AiProvider.gemini,
      accounts: 1,
    );
    final estimate = _estimator.estimate(
      text: _text(AiProvider.gemini, accountId: 'g', status: status),
      inputTokens: 1,
      expectedOutputTokens: 1,
    );
    expect(estimate.canWriteText, isFalse);
    expect(estimate.textProblem, status);
    expect(estimate.wantsIllustrations, isFalse);
    expect(estimate.alternatives, isEmpty);
  });

  group('la tabla de precios', () {
    test('los nombres con sufijo de versión encuentran su precio, y el '
        'Lite no se confunde con el Flash', () {
      expect(
        imageModelPrice('gemini-3.1-flash-lite-image-preview')?.modelId,
        'gemini-3.1-flash-lite-image',
      );
      expect(
        imageModelPrice('gemini-3.1-flash-image-preview')?.modelId,
        'gemini-3.1-flash-image',
      );
      expect(
        imageModelPrice('gpt-image-2.5-flare-2026-09-08')?.modelId,
        'gpt-image-2.5-flare',
      );
      expect(imageModelPrice('otro'), isNull);
    });

    test('un tamaño que el modelo no hace toma el más cercano de arriba', () {
      final lite = imageModelPrice('gemini-3.1-flash-lite-image')!;
      expect(lite.usdFor(IllustrationSize.small), 0.0336);
      expect(lite.usdFor(IllustrationSize.large), 0.0336);
      final banana = imageModelPrice('gemini-nano-banana-2.1')!;
      expect(banana.usdFor(IllustrationSize.small), 0.0336);
      expect(banana.tokensFor(IllustrationSize.large), 1680);
    });

    test('el texto: Claude por familia y versión, OpenAI por código, Gemini '
        'gratis', () {
      expect(textModelPrice(AiProvider.anthropic, 'claude-opus-5-5')?.input, 4);
      expect(
        textModelPrice(
          AiProvider.anthropic,
          'claude-sonnet-4-5-20250929',
        )?.output,
        15,
      );
      expect(textModelPrice(AiProvider.anthropic, 'claude-opus-5')?.input, 5);
      expect(
        textModelPrice(AiProvider.openAi, 'gpt-5.4-mini-2026-03-01')?.input,
        0.75,
      );
      expect(textModelPrice(AiProvider.openAi, 'gpt-99'), isNull);
      expect(textModelPrice(AiProvider.gemini, 'gemini-3.8-flash')?.output, 0);
    });

    test(
      'la cuota estimada: Gemini con la capa gratis; los pagos, ninguna',
      () {
        expect(defaultDailyQuota(AiProvider.gemini)?.isEstimate, isTrue);
        expect(defaultDailyQuota(AiProvider.openAi), isNull);
        expect(defaultDailyQuota(AiProvider.anthropic), isNull);
      },
    );

    test('los modelos abiertos, sin Qwen-Image, con su ficha', () {
      expect(kOpenImageModels.map((m) => m.key), [
        'fluxSchnell',
        'zImage',
        'sd35',
        'sana',
      ]);
      expect(
        kOpenImageModels.first.url,
        'https://huggingface.co/black-forest-labs/FLUX.1-schnell',
      );
      expect(
        kOpenImageModels.firstWhere((m) => m.key == 'sd35').license,
        OpenModelLicense.stabilityCommunity,
      );
    });
  });
}
