import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/hugging_face_image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/on_device_image_engine.dart';
import 'package:sinapsis/features/ai_models/data/cloud/openai_image_wire.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_illustration_store.dart';
import 'package:sinapsis/features/ai_models/data/repositories/secure_image_account_repository.dart';
import 'package:sinapsis/features/ai_models/data/services/illustration_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/daily_quota.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/image_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';

/// Las cuentas propias de imágenes (Hugging Face), en el almacén seguro.
final imageAccountRepositoryProvider = Provider<ImageAccountRepository>(
  (ref) => SecureImageAccountRepository(
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Las cuentas propias de imágenes, a medida que cambian.
final imageAccountsProvider = StreamProvider<List<IllustrationAccount>>(
  (ref) => ref.watch(imageAccountRepositoryProvider).watch(),
);

/// Lo recordado de cada cuenta para dibujar, su cuota y sus modelos.
final illustrationStoreProvider = Provider<PrefsIllustrationStore>(
  (ref) => PrefsIllustrationStore(prefs: ref.watch(sharedPreferencesProvider)),
);

/// Sube cada vez que cambia algo de [illustrationStoreProvider].
final illustrationStoreChangesProvider = StreamProvider<int>((ref) async* {
  var serial = 0;
  yield serial;
  await for (final _ in ref.watch(illustrationStoreProvider).changes()) {
    yield ++serial;
  }
});

/// Cómo se le pide una imagen a cada proveedor en la nube. Sin el
/// registro de red, como el texto (`aiDioProvider`).
final imageWiresProvider = Provider<Map<IllustrationProvider, ImageWire>>((
  ref,
) {
  final dio = ref.watch(aiDioProvider);
  final clock = ref.watch(clockProvider);
  return {
    IllustrationProvider.gemini: GeminiImageWire(
      dio: dio,
      text: GeminiWire(dio: dio, clock: clock),
      clock: clock,
    ),
    IllustrationProvider.openAi: OpenAiImageWire(dio: dio),
    IllustrationProvider.huggingFace: HuggingFaceImageWire(dio: dio),
  };
});

/// El modelo de imágenes del teléfono («Exigente»). Ninguno por ahora: el
/// paso que lo construye sobrescribe este proveedor con su motor, y todo lo
/// demás —la fila y la sección de «¿Qué puede cada IA?», la cuenta que el
/// servicio sabe usar, la alternativa del aviso— aparece solo.
final onDeviceImageEngineProvider = Provider<OnDeviceImageEngine?>(
  (ref) => null,
);

/// Las ilustraciones con IA: a quién se le pide, qué se recuerda y lo
/// gastado.
final illustrationServiceProvider = Provider<IllustrationService>(
  (ref) => IllustrationService(
    textAccounts: ref.watch(aiAccountRepositoryProvider),
    imageAccounts: ref.watch(imageAccountRepositoryProvider),
    wires: ref.watch(imageWiresProvider),
    store: ref.watch(illustrationStoreProvider),
    usage: ref.watch(aiUsageLedgerProvider),
    clock: ref.watch(clockProvider),
    onDevice: ref.watch(onDeviceImageEngineProvider),
  ),
);

/// Si el modelo del teléfono puede dibujar ahora; `null` sin motor.
final onDeviceImageCapabilityProvider =
    FutureProvider.autoDispose<ImageCapability?>((ref) async {
      ref.watch(illustrationStoreChangesProvider);
      final engine = ref.watch(onDeviceImageEngineProvider);
      if (engine == null) return null;
      final service = ref.watch(illustrationServiceProvider);
      return service.capabilityOf(
        IllustrationAccount.onDevice(engine.displayName),
      );
    });

/// La cuota diaria de [accountId] con que se calcula: la que fijó la persona
/// o, si no fijó, la estimada de la capa gratuita de su proveedor de texto
/// ([textProvider]; `null` en las propias de imágenes, que no tienen).
DailyQuota? effectiveDailyQuota(
  PrefsIllustrationStore store,
  String accountId, {
  AiProvider? textProvider,
}) =>
    store.userQuotaOf(accountId) ??
    (textProvider == null ? null : defaultDailyQuota(textProvider));

/// Cada cuenta que podría dibujar, con lo que se sabe de ella: si puede, su
/// modelo, lo gastado hoy y su cuota. En el orden de
/// `IllustrationService.accounts`.
final illustrationSidesProvider = Provider.autoDispose<List<ImageSide>>((ref) {
  ref
    ..watch(illustrationStoreChangesProvider)
    ..watch(aiUsageChangesProvider);
  final text = ref.watch(aiAccountsProvider).valueOrNull ?? const [];
  final own = ref.watch(imageAccountsProvider).valueOrNull ?? const [];
  final engine = ref.watch(onDeviceImageEngineProvider);
  final store = ref.watch(illustrationStoreProvider);
  final service = ref.watch(illustrationServiceProvider);
  final ledger = ref.watch(aiUsageLedgerProvider);
  final now = ref.watch(clockProvider)();

  ImageSide sideOf(IllustrationAccount account, {AiProvider? textProvider}) {
    final model = service.cachedModelOf(account);
    return ImageSide(
      account: account,
      capability: store.capabilityOf(account.id),
      model: model?.id,
      modelLabel: model?.displayName,
      usage: ledger.usageOf(account.id, now: now),
      quota: effectiveDailyQuota(store, account.id, textProvider: textProvider),
    );
  }

  return [
    for (final account in text)
      if (IllustrationAccount.ofTextAccount(account) case final drawing?)
        sideOf(drawing, textProvider: account.provider),
    for (final account in own) sideOf(account),
    if (engine != null)
      ImageSide(
        account: IllustrationAccount.onDevice(engine.displayName),
        capability:
            ref.watch(onDeviceImageCapabilityProvider).valueOrNull ??
            const ImageCapability.untested(),
        model: engine.displayName,
        modelLabel: engine.displayName,
        usage: ledger.usageOf(kOnDeviceIllustrationAccountId, now: now),
        timePerImage: engine.estimatedTimePerImage(IllustrationSize.small),
      ),
  ];
});

/// Lo que se le pregunta al estimador desde una hoja de crear (F43): cuánto
/// lee y escribe, en cuántos pedidos, cuántas ilustraciones y con qué
/// cuenta (si la persona eligió otra en el aviso).
@immutable
class CreationEstimateRequest {
  const CreationEstimateRequest({
    required this.inputTokens,
    required this.expectedOutputTokens,
    this.textRequests = 1,
    this.images = 0,
    this.imageSize = IllustrationSize.standard,
    this.imageAccountId,
  });

  final int inputTokens;
  final int expectedOutputTokens;
  final int textRequests;
  final int images;
  final IllustrationSize imageSize;
  final String? imageAccountId;

  CreationEstimateRequest copyWith({
    int? images,
    IllustrationSize? imageSize,
    String? imageAccountId,
    bool clearImageAccount = false,
  }) => CreationEstimateRequest(
    inputTokens: inputTokens,
    expectedOutputTokens: expectedOutputTokens,
    textRequests: textRequests,
    images: images ?? this.images,
    imageSize: imageSize ?? this.imageSize,
    imageAccountId: clearImageAccount
        ? null
        : (imageAccountId ?? this.imageAccountId),
  );

  @override
  bool operator ==(Object other) =>
      other is CreationEstimateRequest &&
      other.inputTokens == inputTokens &&
      other.expectedOutputTokens == expectedOutputTokens &&
      other.textRequests == textRequests &&
      other.images == images &&
      other.imageSize == imageSize &&
      other.imageAccountId == imageAccountId;

  @override
  int get hashCode => Object.hash(
    inputTokens,
    expectedOutputTokens,
    textRequests,
    images,
    imageSize,
    imageAccountId,
  );
}

/// Quién escribe ahora, para estimar: el proveedor y el modelo elegidos, la
/// cuenta en uso, lo gastado hoy, su cuota y si puede contestar.
final creationTextSideProvider = Provider.autoDispose<TextSide>((ref) {
  ref
    ..watch(illustrationStoreChangesProvider)
    ..watch(aiUsageChangesProvider)
    ..watch(cloudCatalogRevisionProvider);
  final settings = ref.watch(aiModelSettingsProvider);
  final provider = settings.provider;
  final status = ref.watch(languageModelStatusProvider).valueOrNull;
  if (!provider.isCloud) {
    return TextSide(provider: provider, status: status);
  }
  final accounts = [
    for (final a
        in ref.watch(aiAccountsProvider).valueOrNull ?? const <AiAccount>[])
      if (a.provider == provider) a,
  ];
  final chosen = settings.activeAccountOf(provider);
  final account =
      accounts.where((a) => a.id == chosen).firstOrNull ?? accounts.firstOrNull;
  final catalog = ref.watch(cloudModelCatalogProvider);
  final model = settings.modelOf(provider) ?? catalog.recommended(provider);
  final now = ref.watch(clockProvider)();
  return TextSide(
    provider: provider,
    model: model,
    modelLabel: model == null
        ? null
        : catalog.info(provider, model)?.displayName ?? modelLabel(model),
    accountId: account?.id,
    accountLabel: account?.label,
    usage: account == null
        ? null
        : ref.watch(aiUsageLedgerProvider).usageOf(account.id, now: now),
    quota: account == null
        ? null
        : effectiveDailyQuota(
            ref.watch(illustrationStoreProvider),
            account.id,
            textProvider: provider,
          ),
    status: status,
  );
});

/// Qué tan rápido escribe Gemma acá: lo medido en la última tarea (F30), o lo
/// estimado.
final localSpeedProvider = Provider.autoDispose<LocalSpeed>((ref) {
  final reply = ref
      .watch(languageModelMeterProvider)
      .performance
      .value
      .taskReply;
  final write = reply?.tokensPerSecond;
  final first = reply?.firstToken;
  final read = reply?.inputTokens;
  if (write == null || first == null || read == null || first.inSeconds < 1) {
    return LocalSpeed.estimated;
  }
  return LocalSpeed(
    readTokensPerSecond: read / (first.inMilliseconds / 1000),
    writeTokensPerSecond: write,
    measured: true,
  );
});

/// La estimación de «Con tu IA actual» para [CreationEstimateRequest]: lo
/// que usan la hoja común de personalizar, la presentación y la infografía.
final creationEstimateProvider = Provider.autoDispose
    .family<CreationEstimate, CreationEstimateRequest>((ref, request) {
      return const CreationCostEstimator().estimate(
        text: ref.watch(creationTextSideProvider),
        inputTokens: request.inputTokens,
        expectedOutputTokens: request.expectedOutputTokens,
        textRequests: request.textRequests,
        images: request.images,
        imageSize: request.imageSize,
        imageAccountId: request.imageAccountId,
        imageAccounts: ref.watch(illustrationSidesProvider),
        localSpeed: ref.watch(localSpeedProvider),
      );
    });

/// Agregar, probar, renombrar y borrar las cuentas de imágenes, fijar la
/// cuota de cualquier cuenta y elegir su modelo de imagen.
final illustrationActionsProvider = Provider<IllustrationActions>(
  (ref) => IllustrationActions(
    accounts: ref.watch(imageAccountRepositoryProvider),
    service: ref.watch(illustrationServiceProvider),
    store: ref.watch(illustrationStoreProvider),
    wires: ref.watch(imageWiresProvider),
    forgetUsage: (id) => ref.read(aiUsageLedgerProvider).forget(id),
    clock: ref.watch(clockProvider),
  ),
);

class IllustrationActions {
  IllustrationActions({
    required ImageAccountRepository accounts,
    required IllustrationService service,
    required PrefsIllustrationStore store,
    required Map<IllustrationProvider, ImageWire> wires,
    required Future<void> Function(String accountId) forgetUsage,
    required DateTime Function() clock,
  }) : _accounts = accounts,
       _clock = clock,
       _service = service,
       _store = store,
       _wires = wires,
       _forgetUsage = forgetUsage;

  final ImageAccountRepository _accounts;
  final IllustrationService _service;
  final PrefsIllustrationStore _store;
  final Map<IllustrationProvider, ImageWire> _wires;
  final Future<void> Function(String accountId) _forgetUsage;
  final DateTime Function() _clock;

  /// Prueba [key] de Hugging Face (`whoami` y los modelos que hoy dibuja) y,
  /// si anda, guarda la cuenta. Falla con [ImageGenerationException].
  Future<IllustrationAccount> addHuggingFace({
    required String key,
    String? label,
  }) async {
    final wire = _wires[IllustrationProvider.huggingFace]!;
    final models = await wire.listImageModels(ImageWireAccess(key: key.trim()));
    final account = await _accounts.add(
      provider: IllustrationProvider.huggingFace,
      key: key,
      label: label,
    );
    await _store.setImageModels(account.id, models, fetchedAt: _clock());
    return account;
  }

  /// Prueba [key] y, si anda, reemplaza la de [account]: lo que se sabía de
  /// la vieja ya no vale.
  Future<void> replaceKey(IllustrationAccount account, String key) async {
    await _wires[account.provider]!.listImageModels(
      ImageWireAccess(key: key.trim()),
    );
    await _accounts.replaceKey(account.id, key);
    await _service.forgetCapability(account.id);
  }

  Future<void> rename(IllustrationAccount account, String label) =>
      _accounts.rename(account.id, label);

  /// Borra [account] y lo que se sabía de ella.
  Future<void> remove(IllustrationAccount account) async {
    await _accounts.remove(account.id);
    await _store.forget(account.id);
    await _forgetUsage(account.id);
  }

  /// «Probar ahora»: ver `IllustrationService.probe`.
  Future<ImageCapability> probe(IllustrationAccount account) =>
      _service.probe(account);

  /// Vuelve a traer los modelos de imagen de [account].
  Future<List<ImageModelInfo>> refreshModels(IllustrationAccount account) =>
      _service.imageModelsOf(account, refresh: true);

  Future<void> chooseImageModel(IllustrationAccount account, String? model) =>
      _service.chooseImageModel(account, model);

  /// Fija la cuota diaria de [accountId]; vacía, vuelve a la estimada.
  Future<void> setQuota(String accountId, DailyQuota quota) =>
      _store.setUserQuota(accountId, quota);
}
