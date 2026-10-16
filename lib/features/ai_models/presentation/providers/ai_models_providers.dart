import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_model_catalog.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_wire.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_model_settings_store.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/data/repositories/secure_ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
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
  return {AiProvider.gemini: GeminiWire(dio: dio, clock: clock)};
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
