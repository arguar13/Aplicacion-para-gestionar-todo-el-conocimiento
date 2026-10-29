import 'package:dio/dio.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/on_device_image_engine.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_illustration_store.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/image_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';

/// Cuánto se confía en la lista de modelos de imagen guardada de una cuenta.
const kImageModelListMaxAge = Duration(days: 3);

/// La descripción de «Probar ahora»: lo más chico y barato que se puede
/// pedir, para saber si la cuenta dibuja.
const kImageProbePrompt =
    'Un círculo azul sobre fondo blanco, ilustración mínima.';

/// Las ilustraciones con IA (F43, decisión H): a qué cuenta se le pide, con
/// qué modelo, qué se recuerda de cada cuenta y cuánto se gastó. No guarda
/// las imágenes: devuelve los bytes, y lo guardan los pasos que las usan.
///
/// - **Cuentas**: las de Gemini y OpenAI de F32 (la misma clave), las de
///   Hugging Face y, si hay un motor registrado, el modelo del teléfono.
/// - **Modelos**: de la lista del propio proveedor (o la curada de Hugging
///   Face), guardada unos días; el elegido o el recomendado.
/// - **Lo que se recuerda**: el primer pedido de verdad dice si la cuenta
///   puede; un rechazo de la cuenta (sin facturación, sin verificar, sin
///   créditos, la clave) queda como «no puede» con su porqué, hasta que una
///   imagen salga o se pruebe de nuevo.
/// - **Lo gastado**: cada imagen, con sus tokens y su costo estimado, en lo
///   gastado del día de esa cuenta.
class IllustrationService {
  IllustrationService({
    required AiAccountRepository textAccounts,
    required ImageAccountRepository imageAccounts,
    required Map<IllustrationProvider, ImageWire> wires,
    required PrefsIllustrationStore store,
    required AiUsageLedger usage,
    required Clock clock,
    OnDeviceImageEngine? onDevice,
  }) : _textAccounts = textAccounts,
       _imageAccounts = imageAccounts,
       _wires = wires,
       _store = store,
       _usage = usage,
       _clock = clock,
       _onDevice = onDevice;

  final AiAccountRepository _textAccounts;
  final ImageAccountRepository _imageAccounts;
  final Map<IllustrationProvider, ImageWire> _wires;
  final PrefsIllustrationStore _store;
  final AiUsageLedger _usage;
  final Clock _clock;
  final OnDeviceImageEngine? _onDevice;

  /// Si hay un modelo de imágenes del teléfono registrado.
  bool get hasOnDeviceEngine => _onDevice != null;

  ImageWire _wire(IllustrationProvider provider) {
    if (provider.isOnDevice) {
      final engine = _onDevice;
      if (engine == null) {
        throw const ImageGenerationException(ImageFailure.noAccount);
      }
      return engine;
    }
    final wire = _wires[provider];
    if (wire == null) {
      throw ImageGenerationException(
        ImageFailure.noAccount,
        detail: 'Sin formato para ${provider.storageKey}',
      );
    }
    return wire;
  }

  /// Todas las cuentas que podrían dibujar: las de Gemini y OpenAI de F32 en
  /// el orden en que se agregaron, las de Hugging Face y el teléfono.
  Future<List<IllustrationAccount>> accounts() async => [
    for (final account in await _textAccounts.list())
      ?IllustrationAccount.ofTextAccount(account),
    ...await _imageAccounts.list(),
    if (_onDevice case final engine?)
      IllustrationAccount.onDevice(engine.displayName),
  ];

  /// Lo que se sabe de [account] para dibujar. El teléfono se pregunta al
  /// motor: depende de la memoria, el lugar y si se descargó.
  Future<ImageCapability> capabilityOf(IllustrationAccount account) async {
    if (account.provider.isOnDevice) return _onDeviceCapability();
    return _store.capabilityOf(account.id);
  }

  Future<ImageCapability> _onDeviceCapability() async {
    final engine = _onDevice;
    if (engine == null) {
      return const ImageCapability(
        state: ImageCapabilityState.cannot,
        reason: ImageFailure.noAccount,
      );
    }
    final readiness = await engine.readiness();
    return readiness.isReady
        ? ImageCapability(state: ImageCapabilityState.can, checkedAt: _clock())
        : ImageCapability(
            state: ImageCapabilityState.cannot,
            reason: readiness.reason,
            checkedAt: _clock().toUtc(),
          );
  }

  Future<String?> _keyOf(IllustrationAccount account) async {
    if (account.provider.isOnDevice) return null;
    final key = account.isTextAccount
        ? await _textAccounts.keyOf(account.id)
        : await _imageAccounts.keyOf(account.id);
    if (key == null) {
      throw const ImageGenerationException(ImageFailure.noAccount);
    }
    return key;
  }

  /// Los modelos de imagen de [account]: los guardados, o los del proveedor
  /// si son viejos, no están o se pide [refresh]. Si la lista no se puede
  /// traer pero había una guardada, sirve la guardada. Una lista vacía deja
  /// la cuenta como «no puede: sin modelos de imagen».
  Future<List<ImageModelInfo>> imageModelsOf(
    IllustrationAccount account, {
    bool refresh = false,
  }) async {
    final stored = _store.imageModelsOf(account.id);
    final stale =
        stored == null ||
        _clock().toUtc().difference(stored.fetchedAt) > kImageModelListMaxAge;
    if (!refresh && !stale) return stored.models;
    final List<ImageModelInfo> models;
    try {
      models = await _wire(
        account.provider,
      ).listImageModels(ImageWireAccess(key: await _keyOf(account)));
    } on ImageGenerationException catch (error) {
      await _remember(account, error.failure);
      if (stored != null && !refresh && !error.failure.isAboutAccount) {
        return stored.models;
      }
      rethrow;
    }
    await _store.setImageModels(account.id, models, fetchedAt: _clock());
    if (models.isEmpty) await _remember(account, ImageFailure.noImageModel);
    return models;
  }

  /// Los modelos guardados de [accountId], sin pedir nada (vacía si nunca).
  List<ImageModelInfo> cachedImageModelsOf(String accountId) =>
      _store.imageModelsOf(accountId)?.models ?? const [];

  /// El modelo con que dibuja [account]: el elegido o el recomendado.
  Future<ImageModelInfo> resolveModel(IllustrationAccount account) async {
    final models = await imageModelsOf(account);
    if (models.isEmpty) {
      throw const ImageGenerationException(ImageFailure.noImageModel);
    }
    final chosen = _store.chosenImageModelOf(account.id);
    final match = models.where((m) => m.id == chosen).firstOrNull;
    if (match != null) return match;
    final recommended = _wire(account.provider).recommendedImageModel(models);
    return models.firstWhere(
      (m) => m.id == recommended,
      orElse: () => models.first,
    );
  }

  /// El modelo que usaría [account] según lo guardado, sin pedir nada; `null`
  /// si no hay lista todavía.
  ImageModelInfo? cachedModelOf(IllustrationAccount account) {
    final models = cachedImageModelsOf(account.id);
    if (models.isEmpty) return null;
    final chosen = _store.chosenImageModelOf(account.id);
    final match = models.where((m) => m.id == chosen).firstOrNull;
    if (match != null) return match;
    final wire = account.provider.isOnDevice
        ? _onDevice
        : _wires[account.provider];
    final recommended = wire?.recommendedImageModel(models);
    return models.where((m) => m.id == recommended).firstOrNull ?? models.first;
  }

  /// Elige el modelo de imagen de [account] (`null`: el recomendado).
  Future<void> chooseImageModel(IllustrationAccount account, String? model) =>
      _store.chooseImageModel(account.id, model);

  /// La cuenta con que se dibuja si no se pide una: la primera que puede; si
  /// ninguna, la primera sin probar. `null` si ninguna dibuja.
  Future<IllustrationAccount?> defaultAccount() async {
    final all = await accounts();
    IllustrationAccount? untested;
    for (final account in all) {
      final capability = await capabilityOf(account);
      if (capability.can) return account;
      if (capability.untested) untested ??= account;
    }
    return untested;
  }

  /// Dibuja [prompt] en el estilo [styleHint], con la forma [aspect] y el
  /// tamaño [size], con [account] (o la de [defaultAccount]).
  ///
  /// Devuelve los bytes, el tipo, los tokens y el costo; anota la imagen en
  /// lo gastado del día de la cuenta y lo que se supo de ella. Si falla, tira
  /// [ImageGenerationException] con el porqué preciso (y lo recuerda si es de
  /// la cuenta).
  Future<IllustrationResult> generate({
    required String prompt,
    String? styleHint,
    IllustrationAspect aspect = IllustrationAspect.square,
    IllustrationSize size = IllustrationSize.standard,
    IllustrationAccount? account,
    CancelToken? cancel,
  }) async {
    final target = account ?? await defaultAccount();
    if (target == null) {
      throw const ImageGenerationException(ImageFailure.noAccount);
    }
    if (target.provider.isOnDevice) {
      final capability = await _onDeviceCapability();
      if (capability.cannot) {
        throw ImageGenerationException(
          capability.reason ?? ImageFailure.unknown,
        );
      }
    }
    final model = await resolveModel(target);
    final key = await _keyOf(target);
    final request = ImageWireRequest(
      model: model.id,
      prompt: composeImagePrompt(prompt, styleHint: styleHint),
      aspect: aspect,
      size: size,
      route: model.route,
    );
    final GeneratedImage image;
    try {
      image = await _wire(
        target.provider,
      ).generate(request, ImageWireAccess(key: key), cancel: cancel);
    } on ImageGenerationException catch (error) {
      await _remember(target, error.failure, model: model.id);
      rethrow;
    }
    final now = _clock();
    final cost = imageCostOf(
      target.provider,
      model: model.id,
      size: size,
      inputTokens: image.inputTokens,
      outputTokens: image.outputTokens,
    );
    final input = image.inputTokens ?? 0;
    final output = image.outputTokens ?? 0;
    await _usage.recordImage(
      target.id,
      now: now,
      inputTokens: input,
      outputTokens: output,
      usd: cost.usd ?? 0,
    );
    if (!target.provider.isOnDevice) {
      await _store.setCapability(
        target.id,
        ImageCapability.succeeded(model.id, now),
      );
    }
    return IllustrationResult(
      image: image,
      accountId: target.id,
      provider: target.provider,
      inputTokens: input,
      outputTokens: output,
      costUsd: cost.usd,
      costIsEstimate: cost.estimate,
    );
  }

  /// «Probar ahora»: un solo pedido, el más chico, para saber si [account]
  /// dibuja. Lo hace solo quien lo toca (cuesta una imagen chica). Devuelve
  /// lo que quedó sabido; un problema del momento (sin internet, el tope por
  /// minuto) sale como [ImageGenerationException].
  Future<ImageCapability> probe(IllustrationAccount account) async {
    try {
      await imageModelsOf(account, refresh: true);
      await generate(
        prompt: kImageProbePrompt,
        size: IllustrationSize.small,
        account: account,
      );
    } on ImageGenerationException catch (error) {
      if (!error.failure.isAboutAccount) rethrow;
    }
    return capabilityOf(account);
  }

  /// Olvida lo que se sabía de [accountId] para dibujar (se le cambió la
  /// clave: la nueva puede andar distinto). La cuota y el modelo elegido se
  /// quedan.
  Future<void> forgetCapability(String accountId) =>
      _store.forget(accountId, keepQuota: true);

  Future<void> _remember(
    IllustrationAccount account,
    ImageFailure failure, {
    String? model,
  }) async {
    if (account.provider.isOnDevice || !failure.isAboutAccount) return;
    final before = _store.capabilityOf(account.id);
    await _store.setCapability(
      account.id,
      ImageCapability.afterFailure(before, failure, at: _clock(), model: model),
    );
  }
}

/// La descripción que se manda: lo pedido, el estilo, y que no lleve texto
/// —el texto lo pone siempre la app encima, sin faltas de ortografía
/// dibujadas (decisión G)—.
String composeImagePrompt(String prompt, {String? styleHint}) {
  final style = styleHint?.trim() ?? '';
  return [
    prompt.trim(),
    if (style.isNotEmpty) 'Estilo: $style.',
    'Sin texto, letras ni números dentro de la imagen.',
  ].join('\n');
}

/// Lo que costó (o cuesta) una imagen de [provider] con [model]: con los
/// tokens que contó el proveedor si los contó, o con el precio por imagen de
/// la tabla fechada. Hugging Face: `null` (cobra lo de su proveedor de
/// inferencia); el teléfono: 0.
({double? usd, bool estimate}) imageCostOf(
  IllustrationProvider provider, {
  required String model,
  required IllustrationSize size,
  int? inputTokens,
  int? outputTokens,
}) {
  if (provider.isOnDevice) return (usd: 0, estimate: false);
  if (provider == IllustrationProvider.huggingFace) {
    return (usd: null, estimate: true);
  }
  final price = imageModelPrice(model) ?? fallbackImagePrice(provider);
  if (price == null) return (usd: null, estimate: true);
  if (outputTokens != null && outputTokens > 0) {
    return (
      usd:
          ((inputTokens ?? 0) * price.inputUsdPerMillion +
              outputTokens * price.outputUsdPerMillion) /
          1e6,
      estimate: false,
    );
  }
  return (usd: price.usdFor(size), estimate: true);
}
