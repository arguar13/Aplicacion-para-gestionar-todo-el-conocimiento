import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_illustration_store.dart';
import 'package:sinapsis/features/ai_models/data/repositories/secure_image_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/daily_quota.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

import '../../../support/fake_id_generator.dart';

/// Lo de las ilustraciones que se guarda (F43): las cuentas de Hugging Face,
/// lo recordado de cada cuenta, su cuota y lo gastado en imágenes.
void main() {
  final now = DateTime.utc(2026, 10, 28, 15);

  group('lo gastado en imágenes', () {
    late PrefsAiUsageLedger ledger;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ledger = PrefsAiUsageLedger(prefs: await SharedPreferences.getInstance());
    });

    test('cada imagen es un pedido más, una imagen más, sus tokens aparte de '
        'los del texto y lo que costó', () async {
      await ledger.recordRequest(
        'a',
        now: now,
        inputTokens: 1000,
        outputTokens: 200,
        background: false,
      );
      await ledger.recordImage(
        'a',
        now: now,
        inputTokens: 40,
        outputTokens: 1120,
        usd: 0.0336,
      );
      await ledger.recordImage(
        'a',
        now: now,
        inputTokens: 40,
        outputTokens: 1120,
        usd: 0.0336,
      );

      final usage = ledger.usageOf('a', now: now);
      expect(usage.requests, 3);
      expect(usage.images, 2);
      expect(usage.inputTokens, 1000);
      expect(usage.outputTokens, 200);
      expect(usage.imageTokens, 2320);
      expect(usage.totalTokens, 3520);
      expect(usage.spentMicroUsd, 67200);
      expect(usage.spentUsd, closeTo(0.0672, 1e-9));
      // Al otro día de cuota, todo vuelve a cero.
      final tomorrow = ledger.usageOf(
        'a',
        now: now.add(const Duration(days: 1)),
      );
      expect(tomorrow.images, 0);
      expect(tomorrow.spentMicroUsd, 0);
    });

    test('lo negativo no resta', () async {
      await ledger.recordImage(
        'a',
        now: now,
        inputTokens: -5,
        outputTokens: -1,
        usd: -1,
      );
      final usage = ledger.usageOf('a', now: now);
      expect(usage.imageTokens, 0);
      expect(usage.spentMicroUsd, 0);
      expect(usage.images, 1);
    });

    test('ida y vuelta por JSON, y lo de antes de F43 se lee sin imágenes', () {
      const usage = AccountUsage(
        accountId: 'a',
        day: '2026-10-28',
        requests: 2,
        images: 1,
        imageTokens: 1160,
        spentMicroUsd: 33600,
      );
      expect(AccountUsage.fromJson(usage.toJson()), usage);
      final old = AccountUsage.fromJson({
        'accountId': 'a',
        'day': '2026-10-28',
        'requests': 4,
      })!;
      expect(old.images, 0);
      expect(old.spentUsd, 0);
    });
  });

  group('las cuentas de Hugging Face, en el almacén seguro', () {
    late SecureImageAccountRepository repository;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      repository = SecureImageAccountRepository(
        ids: FakeIdGenerator(prefix: 'hf'),
        clock: () => now,
      );
    });

    test('el token aparte de la lista; sin nombre, «Hugging Face N»', () async {
      final first = await repository.add(
        provider: IllustrationProvider.huggingFace,
        key: '  hf_Token1 ',
      );
      final second = await repository.add(
        provider: IllustrationProvider.huggingFace,
        key: 'hf_Token2',
        label: 'Personal',
      );

      expect(first.label, 'Hugging Face 1');
      expect(second.label, 'Personal');
      expect(await repository.list(), [first, second]);
      expect(await repository.keyOf(first.id), 'hf_Token1');
      final stored = await const FlutterSecureStorage().readAll();
      expect(stored['ai_image_accounts_v1'], isNot(contains('hf_Token')));
    });

    test('solo Hugging Face se guarda acá, y nunca sin token', () async {
      await expectLater(
        repository.add(provider: IllustrationProvider.gemini, key: 'k'),
        throwsArgumentError,
      );
      await expectLater(
        repository.add(provider: IllustrationProvider.onDevice, key: 'k'),
        throwsArgumentError,
      );
      await expectLater(
        repository.add(provider: IllustrationProvider.huggingFace, key: ' '),
        throwsArgumentError,
      );
      expect(await repository.list(), isEmpty);
    });

    test('renombrar, cambiar el token y borrar (con su token)', () async {
      final account = await repository.add(
        provider: IllustrationProvider.huggingFace,
        key: 'viejo',
      );
      await repository.rename(account.id, '  Trabajo ');
      await repository.replaceKey(account.id, 'nuevo');
      expect((await repository.list()).single.label, 'Trabajo');
      expect(await repository.keyOf(account.id), 'nuevo');

      await repository.remove(account.id);
      expect(await repository.list(), isEmpty);
      expect(await repository.keyOf(account.id), isNull);
    });

    test('una lista ilegible se muestra vacía', () async {
      FlutterSecureStorage.setMockInitialValues({'ai_image_accounts_v1': '{'});
      expect(await repository.list(), isEmpty);
    });
  });

  group('las cuentas que dibujan', () {
    test('una de Gemini u OpenAI es la misma de F32; Claude y Gemma no '
        'dibujan', () {
      AiAccount text(AiProvider provider) => AiAccount(
        id: 'x',
        provider: provider,
        label: 'Trabajo',
        addedAt: now,
      );
      expect(
        IllustrationAccount.ofTextAccount(text(AiProvider.gemini))?.provider,
        IllustrationProvider.gemini,
      );
      expect(
        IllustrationAccount.ofTextAccount(text(AiProvider.openAi))?.provider,
        IllustrationProvider.openAi,
      );
      expect(
        IllustrationAccount.ofTextAccount(text(AiProvider.anthropic)),
        isNull,
      );
      expect(IllustrationAccount.ofTextAccount(text(AiProvider.gemma)), isNull);
    });

    test('lo guardado de una de F32 o del teléfono no se lee como propia', () {
      expect(
        IllustrationAccount.fromJson({
          'id': 'x',
          'provider': 'gemini',
          'label': 'l',
        }),
        isNull,
      );
      expect(
        IllustrationAccount.fromJson({
          'id': 'x',
          'provider': 'on-device',
          'label': 'l',
        }),
        isNull,
      );
    });
  });

  group('lo recordado, la cuota y los modelos de cada cuenta', () {
    late PrefsIllustrationStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = PrefsIllustrationStore(
        prefs: await SharedPreferences.getInstance(),
      );
    });

    test('sin nada: sin probar y sin cuota propia', () {
      expect(store.capabilityOf('a').untested, isTrue);
      expect(store.userQuotaOf('a'), isNull);
      expect(store.imageModelsOf('a'), isNull);
    });

    test('lo que se sabe de la cuenta queda guardado', () async {
      final cannot = ImageCapability.afterFailure(
        const ImageCapability.untested(),
        ImageFailure.noBilling,
        at: now,
        model: 'gemini-nano-banana-2.1',
      );
      await store.setCapability('a', cannot);
      expect(store.capabilityOf('a'), cannot);
      expect(store.capabilityOf('a').reason, ImageFailure.noBilling);
    });

    test('la cuota de la persona; vacía vuelve a la estimada', () async {
      const quota = DailyQuota(requests: 100, images: 10, usd: 1.5);
      await store.setUserQuota('a', quota);
      expect(store.userQuotaOf('a'), quota);
      await store.setUserQuota('a', DailyQuota.none);
      expect(store.userQuotaOf('a'), isNull);
    });

    test('los modelos con su camino, y el elegido', () async {
      await store.setImageModels('a', const [
        ImageModelInfo(
          id: 'black-forest-labs/FLUX.1-schnell',
          displayName: 'FLUX.1 [schnell]',
          route: 'nscale|black-forest-labs/FLUX.1-schnell',
        ),
      ], fetchedAt: now);
      await store.chooseImageModel('a', 'black-forest-labs/FLUX.1-schnell');
      final stored = store.imageModelsOf('a')!;
      expect(stored.fetchedAt, now);
      expect(
        stored.models.single.route,
        'nscale|black-forest-labs/FLUX.1-schnell',
      );
      expect(store.chosenImageModelOf('a'), 'black-forest-labs/FLUX.1-schnell');
    });

    test('olvidar una clave cambiada guarda la cuota; borrar la cuenta, '
        'no', () async {
      await store.setCapability('a', ImageCapability.succeeded('m', now));
      await store.setUserQuota('a', const DailyQuota(requests: 5));
      await store.forget('a', keepQuota: true);
      expect(store.capabilityOf('a').untested, isTrue);
      expect(store.userQuotaOf('a'), isNotNull);
      await store.forget('a');
      expect(store.userQuotaOf('a'), isNull);
    });
  });

  group('lo que se recuerda de un pedido', () {
    test('una imagen que salió: puede', () {
      final can = ImageCapability.succeeded('m', now);
      expect(can.can, isTrue);
      expect(can.model, 'm');
    });

    test('un rechazo de la cuenta: no puede, con el porqué', () {
      for (final failure in [
        ImageFailure.noBilling,
        ImageFailure.orgUnverified,
        ImageFailure.noCredits,
        ImageFailure.invalidKey,
        ImageFailure.forbidden,
        ImageFailure.noImageModel,
      ]) {
        final after = ImageCapability.afterFailure(
          ImageCapability.succeeded('m', now),
          failure,
          at: now,
        );
        expect(after.cannot, isTrue, reason: failure.name);
        expect(after.reason, failure);
      }
    });

    test('lo del momento o del contenido no cambia lo sabido', () {
      final before = ImageCapability.succeeded('m', now);
      for (final failure in [
        ImageFailure.network,
        ImageFailure.timeout,
        ImageFailure.rateLimited,
        ImageFailure.quotaExhausted,
        ImageFailure.contentRefused,
        ImageFailure.unavailable,
        ImageFailure.noImage,
      ]) {
        expect(
          ImageCapability.afterFailure(before, failure, at: now),
          before,
          reason: failure.name,
        );
      }
    });
  });

  test('los píxeles de cada forma, en múltiplos de 64', () {
    expect(pixelsOf(IllustrationAspect.wide, IllustrationSize.standard), (
      width: 1024,
      height: 576,
    ));
    expect(pixelsOf(IllustrationAspect.tall, IllustrationSize.standard), (
      width: 576,
      height: 1024,
    ));
    expect(pixelsOf(IllustrationAspect.classic, IllustrationSize.small), (
      width: 512,
      height: 384,
    ));
    expect(pixelsOf(IllustrationAspect.square, IllustrationSize.large), (
      width: 2048,
      height: 2048,
    ));
  });
}
