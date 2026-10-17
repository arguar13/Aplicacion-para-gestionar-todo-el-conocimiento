import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/data/cloud/anthropic_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_model_backend.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/openai_wire.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_model_settings_store.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/chat/data/services/gemma_backend.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';

/// La clave «buena…» anda; cualquier otra, no.
class _KeyWire implements CloudWire {
  @override
  AiProvider get provider => AiProvider.gemini;

  @override
  Future<List<CloudModelInfo>> listModels(String key) async {
    if (!key.startsWith('buena')) {
      throw const CloudModelException(CloudModelFailure.invalidKey);
    }
    return const [CloudModelInfo(id: 'gemini-3.8-flash', displayName: 'F')];
  }

  @override
  String? recommendedModel(List<CloudModelInfo> models) =>
      models.firstOrNull?.id;

  @override
  Stream<CloudDelta> stream(
    CloudRequest request, {
    required String key,
    CancelToken? cancel,
  }) => const Stream.empty();
}

void main() {
  late ProviderContainer container;
  late SharedPreferences prefs;
  final now = DateTime.utc(2026, 10, 16, 15);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
        cloudWiresProvider.overrideWithValue({AiProvider.gemini: _KeyWire()}),
      ],
    );
    addTearDown(container.dispose);
  });

  test('la app sabe hablarles a Gemini, OpenAI y Claude, cada uno con su '
      'formato', () {
    final real = ProviderContainer();
    addTearDown(real.dispose);
    final wires = real.read(cloudWiresProvider);

    expect(
      wires.keys,
      unorderedEquals(AiProvider.values.where((p) => p.isCloud)),
    );
    expect(wires[AiProvider.gemini], isA<GeminiWire>());
    expect(wires[AiProvider.openAi], isA<OpenAiWire>());
    expect(wires[AiProvider.anthropic], isA<AnthropicWire>());
    for (final MapEntry(:key, :value) in wires.entries) {
      expect(value.provider, key);
    }
  });

  test('por defecto escribe Gemini, en la nube', () {
    expect(container.read(aiModelSettingsProvider).provider, AiProvider.gemini);
    expect(container.read(modelBackendProvider), isA<CloudModelBackend>());
  });

  test('elegir Gemma cambia el motor de todo, y queda guardado', () async {
    final before = container.read(modelBackendProvider);
    await container
        .read(aiModelSettingsProvider.notifier)
        .chooseProvider(AiProvider.gemma);

    expect(container.read(modelBackendProvider), isA<GemmaBackend>());
    expect(before, isNot(same(container.read(modelBackendProvider))));
    expect(
      PrefsAiModelSettingsStore(prefs: prefs).read().provider,
      AiProvider.gemma,
    );
  });

  test('cambiar de cuenta no rearma el motor: vale desde el próximo '
      'pedido', () async {
    final accounts = container.read(aiAccountRepositoryProvider);
    await accounts.add(provider: AiProvider.gemini, key: 'clave-1');
    final second = await accounts.add(
      provider: AiProvider.gemini,
      key: 'clave-2',
    );
    final backend = container.read(modelBackendProvider);

    await container
        .read(aiModelSettingsProvider.notifier)
        .chooseAccount(AiProvider.gemini, second.id);

    expect(container.read(modelBackendProvider), same(backend));
    expect(
      container
          .read(aiModelSettingsProvider)
          .activeAccountOf(AiProvider.gemini),
      second.id,
    );
  });

  test('elegir a mano una cuenta agotada la vuelve a probar', () async {
    final accounts = container.read(aiAccountRepositoryProvider);
    final only = await accounts.add(provider: AiProvider.gemini, key: 'c');
    final usage = container.read(aiUsageLedgerProvider);
    await usage.markExhausted(
      only.id,
      now: now,
      until: now.add(const Duration(hours: 5)),
      failure: CloudModelFailure.quotaExhausted,
    );
    final check = container.read(languageModelStatusCheckProvider);
    expect(await check(), isA<LanguageModelOutOfQuota>());

    await container
        .read(aiModelSettingsProvider.notifier)
        .chooseAccount(AiProvider.gemini, only.id);

    expect(usage.usageOf(only.id, now: now).isExhaustedAt(now), isFalse);
    expect(await check(), isA<LanguageModelReady>());
  });

  test('sin cuentas, la nube dice que falta cargar una', () async {
    final check = container.read(languageModelStatusCheckProvider);
    expect(await check(), isA<LanguageModelNeedsAccount>());
  });

  group('las acciones sobre las cuentas', () {
    test('agregar prueba la clave: una mala no se guarda; la primera queda '
        'elegida y la segunda no', () async {
      final actions = container.read(aiAccountActionsProvider);
      await expectLater(
        actions.add(provider: AiProvider.gemini, key: 'mala'),
        throwsA(isA<CloudModelException>()),
      );
      expect(await container.read(aiAccountRepositoryProvider).list(), isEmpty);

      final first = await actions.add(
        provider: AiProvider.gemini,
        key: 'buena-1',
      );
      await actions.add(provider: AiProvider.gemini, key: 'buena-2');
      expect(
        container
            .read(aiModelSettingsProvider)
            .activeAccountOf(AiProvider.gemini),
        first.id,
      );
      // Y la prueba dejó la lista de modelos guardada.
      expect(
        container.read(cloudModelsProvider(AiProvider.gemini)).single.id,
        'gemini-3.8-flash',
      );
    });

    test('probar una cuenta le saca la marca de clave rechazada, pero no la '
        'de cuota agotada', () async {
      final actions = container.read(aiAccountActionsProvider);
      final usage = container.read(aiUsageLedgerProvider);
      final account = await actions.add(
        provider: AiProvider.gemini,
        key: 'buena-1',
      );
      Future<void> mark(CloudModelFailure failure) => usage.markExhausted(
        account.id,
        now: now,
        until: now.add(const Duration(hours: 1)),
        failure: failure,
      );

      await mark(CloudModelFailure.quotaExhausted);
      await actions.test(account);
      expect(usage.usageOf(account.id, now: now).isExhaustedAt(now), isTrue);

      await mark(CloudModelFailure.invalidKey);
      expect(await actions.test(account), 1);
      expect(usage.usageOf(account.id, now: now).isExhaustedAt(now), isFalse);
    });

    test('cambiar la clave la prueba antes, y con la nueva se olvida lo de '
        'la vieja', () async {
      final actions = container.read(aiAccountActionsProvider);
      final repo = container.read(aiAccountRepositoryProvider);
      final usage = container.read(aiUsageLedgerProvider);
      final account = await actions.add(
        provider: AiProvider.gemini,
        key: 'buena-1',
      );
      await usage.markExhausted(
        account.id,
        now: now,
        until: now.add(const Duration(hours: 1)),
        failure: CloudModelFailure.invalidKey,
      );

      await expectLater(
        actions.replaceKey(account, 'mala'),
        throwsA(isA<CloudModelException>()),
      );
      expect(await repo.keyOf(account.id), 'buena-1');

      await actions.replaceKey(account, 'buena-2');
      expect(await repo.keyOf(account.id), 'buena-2');
      expect(usage.usageOf(account.id, now: now).isExhaustedAt(now), isFalse);
    });

    test('borrar la elegida la deja de elegir y olvida lo gastado', () async {
      final actions = container.read(aiAccountActionsProvider);
      final usage = container.read(aiUsageLedgerProvider);
      final account = await actions.add(
        provider: AiProvider.gemini,
        key: 'buena-1',
      );
      await usage.recordRequest(
        account.id,
        now: now,
        inputTokens: 5,
        outputTokens: 5,
        background: false,
      );

      await actions.remove(account);

      expect(
        container
            .read(aiModelSettingsProvider)
            .activeAccountOf(AiProvider.gemini),
        isNull,
      );
      expect(usage.usageOf(account.id, now: now).requests, 0);
      expect(await container.read(aiAccountRepositoryProvider).list(), isEmpty);
    });
  });
}
