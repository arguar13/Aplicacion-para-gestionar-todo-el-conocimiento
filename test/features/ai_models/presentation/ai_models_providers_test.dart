import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_model_backend.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_model_settings_store.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/chat/data/services/gemma_backend.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';

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
      ],
    );
    addTearDown(container.dispose);
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
}
