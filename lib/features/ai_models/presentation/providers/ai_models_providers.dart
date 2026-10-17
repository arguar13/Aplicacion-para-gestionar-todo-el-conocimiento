import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/data/cloud/anthropic_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_model_catalog.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/openai_wire.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_model_settings_store.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/data/repositories/secure_ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_notice_bus.dart';

/// El cliente HTTP de la IA en la nube (F32), aparte del de la app a
/// propósito:
///
/// - **Sin `NetworkLoggingInterceptor`**: el registro de red anota cada URL,
///   y lo que va a la IA no tiene por qué quedar escrito en ningún lado.
/// - **Sin `GlobalErrorInterceptor`**: un 429 de cuota es lo esperado y lo
///   resuelve el motor (cambia de cuenta, espera); el aviso global de error
///   lo mostraría como una falla de la app.
/// - Sin `receiveTimeout` sobre el cuerpo: una respuesta larga llega de a
///   poco durante minutos. El tope de 60 s cubre solo la espera de las
///   cabeceras (dio 5.11), que el proveedor manda enseguida.
final aiDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: const {'User-Agent': 'Sinapsis/0.1'},
    ),
  ),
);

/// Las cuentas de la IA en la nube y sus claves, en el almacén seguro.
final aiAccountRepositoryProvider = Provider<AiAccountRepository>(
  (ref) => SecureAiAccountRepository(
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Las cuentas, a medida que cambian.
final aiAccountsProvider = StreamProvider<List<AiAccount>>(
  (ref) => ref.watch(aiAccountRepositoryProvider).watch(),
);

/// Lo gastado hoy por cada cuenta.
final aiUsageLedgerProvider = Provider<AiUsageLedger>(
  (ref) => PrefsAiUsageLedger(prefs: ref.watch(sharedPreferencesProvider)),
);

/// Avisa cada vez que cambia lo gastado: para redibujar lo que lo muestra.
final aiUsageChangesProvider = StreamProvider<int>((ref) async* {
  var serial = 0;
  yield serial;
  await for (final _ in ref.watch(aiUsageLedgerProvider).changes()) {
    yield ++serial;
  }
});

/// Los avisos de la IA en la nube, uno solo en toda la app.
final aiNoticeBusProvider = Provider<AiNoticeBus>((ref) {
  final bus = AiNoticeBus();
  ref.onDispose(() => unawaited(bus.dispose()));
  return bus;
});

/// Cómo se le habla a cada proveedor en la nube.
final cloudWiresProvider = Provider<Map<AiProvider, CloudWire>>((ref) {
  final dio = ref.watch(aiDioProvider);
  final clock = ref.watch(clockProvider);
  return {
    AiProvider.gemini: GeminiWire(dio: dio, clock: clock),
    AiProvider.openAi: OpenAiWire(dio: dio),
    AiProvider.anthropic: AnthropicWire(dio: dio),
  };
});

/// Sube cada vez que se vuelve a traer una lista de modelos: lo que la
/// muestra la vuelve a leer.
final cloudCatalogRevisionProvider = StateProvider<int>((ref) => 0);

/// Los modelos guardados de [AiProvider], al día con
/// [cloudCatalogRevisionProvider].
final cloudModelsProvider = Provider.autoDispose
    .family<List<CloudModelInfo>, AiProvider>((ref, provider) {
      ref.watch(cloudCatalogRevisionProvider);
      return ref.watch(cloudModelCatalogProvider).cached(provider);
    });

/// La lista de modelos de cada proveedor y cuál usar.
final cloudModelCatalogProvider = Provider<CloudModelCatalog>(
  (ref) => CloudModelCatalog(
    prefs: ref.watch(sharedPreferencesProvider),
    wires: ref.watch(cloudWiresProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Lo elegido para la IA: proveedor, cuenta y modelo de cada uno.
final aiModelSettingsProvider =
    StateNotifierProvider<AiModelSettingsNotifier, AiModelSettings>(
      (ref) => AiModelSettingsNotifier(
        store: PrefsAiModelSettingsStore(
          prefs: ref.watch(sharedPreferencesProvider),
        ),
        usage: ref.watch(aiUsageLedgerProvider),
        clock: ref.watch(clockProvider),
      ),
    );

/// Lo elegido para la IA, guardado al cambiar.
class AiModelSettingsNotifier extends StateNotifier<AiModelSettings> {
  AiModelSettingsNotifier({
    required PrefsAiModelSettingsStore store,
    required AiUsageLedger usage,
    required DateTime Function() clock,
  }) : _store = store,
       _usage = usage,
       _clock = clock,
       super(store.read());

  final PrefsAiModelSettingsStore _store;
  final AiUsageLedger _usage;
  final DateTime Function() _clock;

  /// Deja [settings] como lo elegido (lo usa también el motor, al pasar solo
  /// a otra cuenta).
  Future<void> save(AiModelSettings settings) async {
    if (!mounted || settings == state) return;
    state = settings;
    await _store.write(settings);
  }

  Future<void> chooseProvider(AiProvider provider) =>
      save(state.copyWith(provider: provider));

  /// La persona eligió [accountId] a mano: se usa desde el próximo pedido
  /// aunque la app la tuviera por agotada —quien elige sabe algo que la app
  /// no (que ya se renovó, que pagó)—. Si de verdad no tiene cuota, el
  /// proveedor lo dice y la app sigue como siempre.
  Future<void> chooseAccount(AiProvider provider, String accountId) async {
    await _usage.clearExhausted(accountId, now: _clock());
    await save(state.withActiveAccount(provider, accountId));
  }

  /// Se borró [accountId]: si era la elegida, deja de serlo.
  Future<void> forgetAccount(AiProvider provider, String accountId) async {
    if (state.activeAccountOf(provider) != accountId) return;
    await save(state.withActiveAccount(provider, null));
  }

  /// `null`: el recomendado.
  Future<void> chooseModel(AiProvider provider, String? model) =>
      save(state.withModel(provider, model));

  Future<void> setAutoSwitch({required bool on}) =>
      save(state.copyWith(autoSwitchAccounts: on));

  Future<void> setBackgroundDailyCap(int cap) => save(
    state.copyWith(
      backgroundDailyCap: cap.clamp(0, AiModelSettings.maxDailyCap),
    ),
  );
}

/// Lo que se hace con las cuentas desde la pantalla del modelo.
final aiAccountActionsProvider = Provider<AiAccountActions>(
  (ref) => AiAccountActions(
    accounts: ref.watch(aiAccountRepositoryProvider),
    usage: ref.watch(aiUsageLedgerProvider),
    catalog: ref.watch(cloudModelCatalogProvider),
    settings: ref.watch(aiModelSettingsProvider.notifier),
    currentSettings: () => ref.read(aiModelSettingsProvider),
    clock: ref.watch(clockProvider),
    onCatalogChanged: () =>
        ref.read(cloudCatalogRevisionProvider.notifier).state++,
  ),
);

/// Agregar, probar, renombrar, cambiar la clave y borrar cuentas (F32).
///
/// **Probar una clave es pedirle al proveedor su lista de modelos**: dice si
/// la clave anda sin gastar cuota de respuestas, y de paso deja al día la
/// lista con que se elige el modelo.
class AiAccountActions {
  AiAccountActions({
    required AiAccountRepository accounts,
    required AiUsageLedger usage,
    required CloudModelCatalog catalog,
    required AiModelSettingsNotifier settings,
    required AiModelSettings Function() currentSettings,
    required DateTime Function() clock,
    void Function()? onCatalogChanged,
  }) : _accounts = accounts,
       _currentSettings = currentSettings,
       _usage = usage,
       _catalog = catalog,
       _settings = settings,
       _clock = clock,
       _onCatalogChanged = onCatalogChanged;

  final AiAccountRepository _accounts;
  final AiUsageLedger _usage;
  final CloudModelCatalog _catalog;
  final AiModelSettingsNotifier _settings;
  final AiModelSettings Function() _currentSettings;
  final DateTime Function() _clock;
  final void Function()? _onCatalogChanged;

  /// Cuántos modelos hay con [key]; falla con `CloudModelException` si no
  /// anda.
  Future<int> testKey(AiProvider provider, String key) async {
    final models = await _catalog.refresh(provider, key: key.trim());
    _onCatalogChanged?.call();
    return models.length;
  }

  /// Vuelve a traer la lista de modelos de [provider] con la cuenta elegida
  /// (o la primera).
  Future<void> refreshModels(AiProvider provider) async {
    final accounts = [
      for (final a in await _accounts.list())
        if (a.provider == provider) a,
    ];
    if (accounts.isEmpty) {
      throw const CloudModelException(CloudModelFailure.noAccount);
    }
    final activeId = _currentSettings().activeAccountOf(provider);
    final account = accounts.firstWhere(
      (a) => a.id == activeId,
      orElse: () => accounts.first,
    );
    final key = await _accounts.keyOf(account.id);
    if (key == null) {
      throw const CloudModelException(CloudModelFailure.noAccount);
    }
    await testKey(provider, key);
  }

  /// Prueba [key] y, si anda, guarda la cuenta. La primera de un proveedor
  /// queda como la elegida.
  Future<AiAccount> add({
    required AiProvider provider,
    required String key,
    String? label,
  }) async {
    await testKey(provider, key);
    final hadOne = (await _accounts.list()).any((a) => a.provider == provider);
    final account = await _accounts.add(
      provider: provider,
      key: key.trim(),
      label: label,
    );
    if (!hadOne) await _settings.chooseAccount(provider, account.id);
    return account;
  }

  /// Prueba la clave guardada de [account]. Si anda y estaba rechazada, deja
  /// de estarlo (la cuota agotada no se toca: la lista de modelos anda igual
  /// sin cuota).
  Future<int> test(AiAccount account) async {
    final key = await _accounts.keyOf(account.id);
    if (key == null) {
      throw const CloudModelException(CloudModelFailure.noAccount);
    }
    final count = await testKey(account.provider, key);
    final now = _clock();
    final last = _usage.usageOf(account.id, now: now).lastFailure;
    if (last == CloudModelFailure.invalidKey ||
        last == CloudModelFailure.forbidden) {
      await _usage.clearExhausted(account.id, now: now);
    }
    return count;
  }

  /// Prueba [key] y, si anda, reemplaza la de [account]: lo que se sabía de
  /// la clave vieja (agotada, rechazada) ya no vale.
  Future<void> replaceKey(AiAccount account, String key) async {
    await testKey(account.provider, key);
    await _accounts.replaceKey(account.id, key.trim());
    await _usage.clearExhausted(account.id, now: _clock());
  }

  Future<void> rename(AiAccount account, String label) =>
      _accounts.rename(account.id, label);

  /// Borra [account] y lo que se sabía de ella. Si era la elegida, pasa a
  /// serlo la primera que quede.
  Future<void> remove(AiAccount account) async {
    await _accounts.remove(account.id);
    await _usage.forget(account.id);
    await _settings.forgetAccount(account.provider, account.id);
  }
}
