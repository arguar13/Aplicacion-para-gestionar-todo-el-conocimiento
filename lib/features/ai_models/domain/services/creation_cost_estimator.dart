import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/daily_quota.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';

/// Lo que se sabe de quien escribe, para estimar (F43): el proveedor
/// elegido, su modelo, la cuenta en uso, lo gastado hoy y su cuota.
@immutable
class TextSide {
  const TextSide({
    required this.provider,
    this.model,
    this.modelLabel,
    this.accountId,
    this.accountLabel,
    this.usage,
    this.quota,
    this.status,
  });

  final AiProvider provider;

  /// El código del modelo («gemini-3.8-flash»), si se sabe.
  final String? model;

  /// Cómo se muestra («Gemini 3.8 Flash»).
  final String? modelLabel;

  /// La cuenta que escribe (`null` con Gemma o sin cuentas).
  final String? accountId;
  final String? accountLabel;

  /// Lo gastado hoy por esa cuenta.
  final AccountUsage? usage;

  /// Su cuota diaria (la de la persona o la estimada); `null` si no hay.
  final DailyQuota? quota;

  /// Si puede contestar ahora; `null` si todavía no se sabe.
  final LanguageModelStatus? status;
}

/// Una cuenta que podría dibujar, con lo que se sabe de ella.
@immutable
class ImageSide {
  const ImageSide({
    required this.account,
    required this.capability,
    this.model,
    this.modelLabel,
    this.usage,
    this.quota,
    this.timePerImage,
  });

  final IllustrationAccount account;
  final ImageCapability capability;

  /// El modelo de imagen con que dibujaría (el elegido o el recomendado).
  final String? model;
  final String? modelLabel;
  final AccountUsage? usage;
  final DailyQuota? quota;

  /// Lo que tarda una imagen, en el modelo del teléfono.
  final Duration? timePerImage;
}

/// Qué tan rápido escribe Gemma en este teléfono: lo medido en la última
/// tarea, o lo estimado si nunca se midió.
@immutable
class LocalSpeed {
  const LocalSpeed({
    required this.readTokensPerSecond,
    required this.writeTokensPerSecond,
    this.measured = false,
  });

  /// Una estimación prudente para un teléfono de gama media con Gemma 4 E4B
  /// en la GPU: lee unos 100 tokens por segundo y escribe unos 8.
  static const estimated = LocalSpeed(
    readTokensPerSecond: 100,
    writeTokensPerSecond: 8,
  );

  final double readTokensPerSecond;
  final double writeTokensPerSecond;

  /// Si sale de una respuesta medida en este teléfono.
  final bool measured;
}

/// Contra qué se mide la cuota.
enum QuotaDimension { requests, tokens, images, usd }

/// Cuánto de la cuota de hoy de una cuenta usaría esta creación, y cuánto ya
/// se usó: «≈ 18 % de tu cuota de hoy · ya usaste 42 %».
@immutable
class QuotaShare {
  const QuotaShare({
    required this.accountId,
    required this.accountLabel,
    this.percentOfQuota,
    this.percentUsed,
    this.dimension,
    this.quotaIsEstimate = false,
  });

  final String accountId;
  final String accountLabel;

  /// Lo que gastaría esta creación, en % de la cuota del día; `null` si la
  /// cuenta no tiene cuota fijada ni estimada.
  final double? percentOfQuota;

  /// Lo ya gastado hoy, en % de la cuota.
  final double? percentUsed;

  /// La cuota que más aprieta, de las que hay.
  final QuotaDimension? dimension;

  /// Si la cuota es la estimada de la tabla, no la de la persona.
  final bool quotaIsEstimate;

  bool get hasQuota => percentOfQuota != null;

  /// Si con esta creación se pasaría de la cuota.
  bool get wouldExceed =>
      hasQuota && (percentUsed ?? 0) + percentOfQuota! > 100;
}

/// Una de las opciones concretas cuando la IA actual no puede dibujar, en el
/// orden de «H en detalle».
@immutable
sealed class IllustrationAlternative {
  const IllustrationAlternative();
}

/// 1. Seguir sin ilustraciones: lo dibujado por la app se ve terminado igual.
final class ContinueWithoutIllustrations extends IllustrationAlternative {
  const ContinueWithoutIllustrations();

  @override
  bool operator ==(Object other) => other is ContinueWithoutIllustrations;

  @override
  int get hashCode => 0;
}

/// 2. Usar otra cuenta ya cargada que puede (o que no se probó todavía):
/// «Usar Gemini (cuenta Trabajo) para las ilustraciones». El texto lo sigue
/// escribiendo la IA elegida.
final class UseOtherImageAccount extends IllustrationAlternative {
  const UseOtherImageAccount({required this.side, this.imagesUsd});

  final ImageSide side;

  /// Lo que costarían las imágenes con esa cuenta; `null` si no se sabe.
  final double? imagesUsd;

  IllustrationAccount get account => side.account;
  bool get untested => side.capability.untested;
}

/// 2b. Usar el modelo del teléfono («Exigente»): sin costo ni cuota, con su
/// tiempo estimado. Si falta descargarlo, [needsDownload].
final class UseOnDeviceModel extends IllustrationAlternative {
  const UseOnDeviceModel({
    required this.side,
    required this.time,
    this.needsDownload = false,
  });

  final ImageSide side;

  /// Lo que tardarían todas las imágenes.
  final Duration time;
  final bool needsDownload;
}

/// 3. Agregar una clave de Gemini u OpenAI (abre la hoja de claves de F32,
/// con las dos líneas de la facturación o la verificación).
final class AddImageKey extends IllustrationAlternative {
  const AddImageKey(this.provider);

  /// `IllustrationProvider.gemini` u `openAi`.
  final IllustrationProvider provider;

  @override
  bool operator ==(Object other) =>
      other is AddImageKey && other.provider == provider;

  @override
  int get hashCode => provider.hashCode;
}

/// 4. Agregar un token de Hugging Face para los modelos abiertos.
final class AddHuggingFaceToken extends IllustrationAlternative {
  const AddHuggingFaceToken();

  @override
  bool operator ==(Object other) => other is AddHuggingFaceToken;

  @override
  int get hashCode => 1;
}

/// Lo que va a poder hacer y cuánto va a consumir una creación (F43): lo que
/// muestra la tarjeta «Con tu IA actual».
@immutable
class CreationEstimate {
  const CreationEstimate({
    required this.text,
    required this.canWriteText,
    required this.inputTokens,
    required this.outputTokens,
    required this.images,
    required this.imageSize,
    required this.canIllustrate,
    required this.quota,
    required this.alternatives,
    this.textProblem,
    this.textUsd,
    this.imageSide,
    this.illustrateReason,
    this.imagesUsd,
    this.imageTokens = 0,
    this.localTime,
    this.localTimeIsEstimate = true,
  });

  /// Quién escribe.
  final TextSide text;

  /// Si la IA elegida puede escribir ahora.
  final bool canWriteText;

  /// Por qué no, si no puede.
  final LanguageModelStatus? textProblem;

  /// Tokens estimados de lectura y de escritura del texto.
  final int inputTokens;
  final int outputTokens;

  /// Cuántas ilustraciones se piden, y de qué tamaño.
  final int images;
  final IllustrationSize imageSize;

  /// Lo que costaría el texto, en dólares (0 en Gemini, que lo hace gratis en
  /// la capa gratuita, y en Gemma); `null` si el precio del modelo no se sabe.
  final double? textUsd;

  /// Si se van a poder dibujar las ilustraciones (con [imageSide]). Con una
  /// cuenta sin probar es `true`: el primer pedido lo dice.
  final bool canIllustrate;

  /// La cuenta que dibujaría.
  final ImageSide? imageSide;

  /// Por qué no se puede dibujar. `ImageFailure.noAccount` sin [imageSide]:
  /// ninguna cuenta cargada dibuja (con Claude o Gemma solos, por ejemplo).
  final ImageFailure? illustrateReason;

  /// Lo que costarían las ilustraciones; `null` si no se sabe (Hugging Face
  /// cobra lo de su proveedor de inferencia).
  final double? imagesUsd;

  /// Tokens de imagen estimados (los que cobra el proveedor).
  final int imageTokens;

  /// Cuánto tardaría en el teléfono (Gemma escribiendo, o el modelo de
  /// imágenes del teléfono dibujando); `null` si todo es en la nube.
  final Duration? localTime;
  final bool localTimeIsEstimate;

  /// La cuota de cada cuenta que se usaría (una, o dos si dibuja otra).
  final List<QuotaShare> quota;

  /// Las opciones, en orden, si no se puede dibujar (vacía si se puede o no
  /// se piden ilustraciones).
  final List<IllustrationAlternative> alternatives;

  /// Si se piden ilustraciones.
  bool get wantsIllustrations => images > 0;

  /// Lo que costaría todo, si se sabe todo.
  double? get totalUsd {
    final text = textUsd;
    if (text == null) return null;
    if (!wantsIllustrations || !canIllustrate) return text;
    final drawn = imagesUsd;
    return drawn == null ? null : text + drawn;
  }

  /// Si el texto se escribe sin internet (Gemma).
  bool get textIsLocal => text.provider == AiProvider.gemma;
}

/// Cuántos tokens lee cada pedido de imagen: la descripción y el estilo.
const kImagePromptTokens = 120;

/// La estimación de «Con tu IA actual» (F43, «H en detalle»): qué va a poder
/// hacer la IA elegida, cuánto consume —tokens, imágenes, dólares y el
/// porcentaje de la cuota de hoy— y, si no puede dibujar, las opciones
/// concretas en el orden aprobado:
///
/// 1. seguir sin ilustraciones;
/// 2. usar otra cuenta ya cargada que puede (las probadas primero, después
///    las sin probar), y el modelo del teléfono si hay uno;
/// 3. agregar una clave de Gemini u OpenAI;
/// 4. Hugging Face.
///
/// No pide nada a nadie: todo sale de lo que ya se sabe (lo gastado, lo
/// recordado de cada cuenta y la tabla fechada de precios).
class CreationCostEstimator {
  const CreationCostEstimator();

  CreationEstimate estimate({
    required TextSide text,
    required int inputTokens,
    required int expectedOutputTokens,
    int textRequests = 1,
    int images = 0,
    IllustrationSize imageSize = IllustrationSize.standard,
    String? imageAccountId,
    List<ImageSide> imageAccounts = const [],
    LocalSpeed localSpeed = LocalSpeed.estimated,
  }) {
    final input = math.max(0, inputTokens);
    final output = math.max(0, expectedOutputTokens);
    final status = text.status;
    final canWrite = status == null || status.isReady;

    final textPrice = textModelPrice(text.provider, text.model);
    final textUsd = textPrice?.usdFor(inputTokens: input, outputTokens: output);

    // Quién dibujaría.
    final wants = images > 0;
    final chosen = wants
        ? _chooseImageSide(text, imageAccountId, imageAccounts)
        : null;
    final canIllustrate = chosen != null && !chosen.capability.cannot;
    final ImageFailure? reason;
    if (!wants) {
      reason = null;
    } else if (chosen == null) {
      reason = ImageFailure.noAccount;
    } else if (chosen.capability.cannot) {
      reason = chosen.capability.reason ?? ImageFailure.unknown;
    } else {
      reason = null;
    }

    final imagesUsd = chosen == null
        ? null
        : _imagesUsd(chosen, images, imageSize);
    final imageTokens = chosen == null
        ? 0
        : images * (_imagePrice(chosen)?.tokensFor(imageSize) ?? 0);

    // Lo que tarda en el teléfono.
    Duration? local;
    if (text.provider == AiProvider.gemma) {
      local = _gemmaTime(input, output, localSpeed);
    }
    if (canIllustrate && chosen.account.provider.isOnDevice) {
      final drawing = (chosen.timePerImage ?? Duration.zero) * images;
      local = (local ?? Duration.zero) + drawing;
    }

    // La cuota de cada cuenta que se usa.
    final quota = <QuotaShare>[];
    final textTokens = input + output;
    final sameAccount = canIllustrate && chosen.account.id == text.accountId;
    if (text.accountId != null && text.provider.isCloud) {
      quota.add(
        quotaShare(
          accountId: text.accountId!,
          label: text.accountLabel ?? '',
          usage: text.usage,
          quota: text.quota,
          requests: textRequests + (sameAccount ? images : 0),
          tokens:
              textTokens +
              (sameAccount ? imageTokens + images * kImagePromptTokens : 0),
          images: sameAccount ? images : 0,
          usd: (textUsd ?? 0) + (sameAccount ? (imagesUsd ?? 0) : 0),
          usedUsd: usedUsdOf(text.usage, textPrice),
        ),
      );
    }
    if (canIllustrate && !sameAccount && !chosen.account.provider.isOnDevice) {
      quota.add(
        quotaShare(
          accountId: chosen.account.id,
          label: chosen.account.label,
          usage: chosen.usage,
          quota: chosen.quota,
          requests: images,
          tokens: imageTokens + images * kImagePromptTokens,
          images: images,
          usd: imagesUsd ?? 0,
          usedUsd: chosen.usage?.spentUsd ?? 0,
        ),
      );
    }

    return CreationEstimate(
      text: text,
      canWriteText: canWrite,
      textProblem: canWrite ? null : status,
      inputTokens: input,
      outputTokens: output,
      images: math.max(0, images),
      imageSize: imageSize,
      textUsd: textUsd,
      canIllustrate: wants && canIllustrate,
      imageSide: chosen,
      illustrateReason: reason,
      imagesUsd: canIllustrate ? imagesUsd : null,
      imageTokens: canIllustrate ? imageTokens : 0,
      localTime: local,
      localTimeIsEstimate: !localSpeed.measured,
      quota: quota,
      alternatives: wants && !canIllustrate
          ? _alternatives(
              chosen: chosen,
              accounts: imageAccounts,
              images: images,
              size: imageSize,
            )
          : const [],
    );
  }

  /// La que dibuja: la que la persona eligió en el aviso ([requested]) o,
  /// si no eligió, **la misma cuenta que escribe** —«con tu IA actual»—, si
  /// es de un proveedor que dibuja. Con Claude o Gemma no hay ninguna: la IA
  /// actual no dibuja, y las demás cuentas van como alternativas, sin
  /// cambiar nada a espaldas de la persona.
  static ImageSide? _chooseImageSide(
    TextSide text,
    String? requested,
    List<ImageSide> accounts,
  ) {
    final id = requested ?? text.accountId;
    if (id == null) return null;
    return accounts.where((s) => s.account.id == id).firstOrNull;
  }

  static ImageModelPrice? _imagePrice(ImageSide side) {
    final model = side.model;
    final known = model == null ? null : imageModelPrice(model);
    return known ?? fallbackImagePrice(side.account.provider);
  }

  /// Lo que cuestan [images] con [side]: la tabla por imagen más lo que lee
  /// cada descripción. 0 en el teléfono; `null` en Hugging Face, que cobra lo
  /// de su proveedor de inferencia.
  static double? _imagesUsd(ImageSide side, int images, IllustrationSize size) {
    final provider = side.account.provider;
    if (provider.isOnDevice) return 0;
    if (provider == IllustrationProvider.huggingFace) return null;
    final price = _imagePrice(side);
    if (price == null) return null;
    return images *
        (price.usdFor(size) +
            kImagePromptTokens * price.inputUsdPerMillion / 1e6);
  }

  /// Lo ya gastado hoy en dólares: las ilustraciones (anotadas) y el texto
  /// (de los tokens, con el precio del modelo de ahora).
  static double usedUsdOf(AccountUsage? usage, TextModelPrice? price) {
    if (usage == null) return 0;
    final drawn = usage.spentUsd;
    if (price == null) return drawn;
    // Los tokens del texto van aparte de los de las ilustraciones, que ya
    // están en lo gastado.
    return drawn +
        price.usdFor(
          inputTokens: usage.inputTokens,
          outputTokens: usage.outputTokens,
        );
  }

  /// Cuánto de [quota] gastaría una creación con estos consumos y cuánto ya
  /// se gastó hoy ([usage], [usedUsd]): la que más aprieta de las cuotas que
  /// hay. Con todo en cero, lo usado hoy (para Ajustes → IA).
  static QuotaShare quotaShare({
    required String accountId,
    required String label,
    required AccountUsage? usage,
    required DailyQuota? quota,
    required int requests,
    required int tokens,
    required int images,
    required double usd,
    required double usedUsd,
  }) {
    if (quota == null || quota.isEmpty) {
      return QuotaShare(accountId: accountId, accountLabel: label);
    }
    final used = usage;
    final candidates =
        <({QuotaDimension dimension, double estimate, double used})>[
          if (quota.requests case final limit?)
            (
              dimension: QuotaDimension.requests,
              estimate: requests / limit * 100,
              used: (used?.requests ?? 0) / limit * 100,
            ),
          if (quota.tokens case final limit?)
            (
              dimension: QuotaDimension.tokens,
              estimate: tokens / limit * 100,
              used: (used?.totalTokens ?? 0) / limit * 100,
            ),
          if (quota.images case final limit?)
            (
              dimension: QuotaDimension.images,
              estimate: images / limit * 100,
              used: (used?.images ?? 0) / limit * 100,
            ),
          if (quota.usd case final limit?)
            (
              dimension: QuotaDimension.usd,
              estimate: usd / limit * 100,
              used: usedUsd / limit * 100,
            ),
        ];
    // La que más aprieta: la que deja menos lugar después de esta creación.
    final tightest = candidates.reduce(
      (a, b) => (b.estimate + b.used) > (a.estimate + a.used) ? b : a,
    );
    return QuotaShare(
      accountId: accountId,
      accountLabel: label,
      percentOfQuota: tightest.estimate,
      percentUsed: tightest.used,
      dimension: tightest.dimension,
      quotaIsEstimate: quota.isEstimate,
    );
  }

  static Duration _gemmaTime(int input, int output, LocalSpeed speed) {
    final seconds =
        input / math.max(1, speed.readTokensPerSecond) +
        output / math.max(0.1, speed.writeTokensPerSecond);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// Las opciones, en el orden aprobado. [chosen] es la que no puede (o
  /// `null` si ninguna dibuja): no se ofrece de nuevo.
  static List<IllustrationAlternative> _alternatives({
    required ImageSide? chosen,
    required List<ImageSide> accounts,
    required int images,
    required IllustrationSize size,
  }) {
    final result = <IllustrationAlternative>[
      const ContinueWithoutIllustrations(),
    ];
    final others = [
      for (final side in accounts)
        if (side.account.id != chosen?.account.id &&
            !side.account.provider.isOnDevice &&
            !side.capability.cannot)
          side,
    ]..sort((a, b) => _stateRank(a).compareTo(_stateRank(b)));
    for (final side in others) {
      result.add(
        UseOtherImageAccount(
          side: side,
          imagesUsd: _imagesUsd(side, images, size),
        ),
      );
    }
    for (final side in accounts) {
      if (!side.account.provider.isOnDevice) continue;
      final reason = side.capability.reason;
      // El teléfono que no alcanza no es una opción; sin descargar, sí.
      if (side.capability.cannot && reason != ImageFailure.modelNotDownloaded) {
        continue;
      }
      result.add(
        UseOnDeviceModel(
          side: side,
          time: (side.timePerImage ?? Duration.zero) * images,
          needsDownload: reason == ImageFailure.modelNotDownloaded,
        ),
      );
    }
    // Agregar una clave del proveedor que todavía no tiene ninguna cuenta que
    // pueda o esté sin probar.
    bool hasUsable(IllustrationProvider provider) => accounts.any(
      (s) => s.account.provider == provider && !s.capability.cannot,
    );
    for (final provider in [
      IllustrationProvider.gemini,
      IllustrationProvider.openAi,
    ]) {
      if (!hasUsable(provider)) result.add(AddImageKey(provider));
    }
    if (!hasUsable(IllustrationProvider.huggingFace)) {
      result.add(const AddHuggingFaceToken());
    }
    return result;
  }

  static int _stateRank(ImageSide side) => side.capability.can ? 0 : 1;
}
