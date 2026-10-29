/// Lo que cuesta y lo que puede cada IA (F43, «H en detalle»), en tablas con
/// su fecha: los precios cambian y los nombres de los modelos también, así
/// que lo que se muestra dice «precios al 28/10/2026» y la próxima revisión
/// cambia solo esto.
///
/// Verificado el 2026-10-28 contra la documentación oficial:
///
/// - Gemini, imágenes: https://ai.google.dev/gemini-api/docs/image-generation
///   y precios en https://ai.google.dev/gemini-api/docs/pricing («Free tier:
///   Not available» en todos los modelos de imagen). Límites:
///   https://ai.google.dev/gemini-api/docs/rate-limits (ya no publica la tabla
///   de la capa gratuita: remite a Google AI Studio).
/// - OpenAI: https://developers.openai.com/api/docs/guides/image-generation
///   (organización verificada; tokens por imagen 1024×1024: 272, 1056 y 4160
///   en baja, media y alta) y https://developers.openai.com/api/docs/pricing.
/// - Claude: https://platform.claude.com/docs/en/about-claude/pricing (Claude
///   no genera imágenes).
/// - Hugging Face: https://huggingface.co/docs/inference-providers/pricing
///   (las cuentas gratis no traen créditos; PRO trae US$ 2 por mes) y
///   https://huggingface.co/docs/inference-providers/tasks/text-to-image.
/// - Las fichas y licencias de cada modelo abierto, en su página de Hugging
///   Face (ver [kOpenImageModels]).
library;

import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/daily_quota.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

/// El día en que se verificaron estas tablas.
final kAiPricesVerifiedOn = DateTime.utc(2026, 10, 28);

/// Lo que cuesta un modelo de imagen.
@immutable
class ImageModelPrice {
  const ImageModelPrice({
    required this.provider,
    required this.modelId,
    required this.displayName,
    required this.usdPerImage,
    required this.tokensPerImage,
    this.inputUsdPerMillion = 0,
    this.outputUsdPerMillion = 0,
    this.recommended = false,
    this.cheapest = false,
    this.deprecated = false,
    this.perImageIsEstimate = false,
  });

  final IllustrationProvider provider;

  /// El código del modelo, sin el sufijo de versión de prueba.
  final String modelId;
  final String displayName;

  /// Dólares por imagen, por tamaño. El que falta toma el del tamaño más
  /// cercano que haya (Nano Banana 2 Lite solo hace 1K).
  final Map<IllustrationSize, double> usdPerImage;

  /// Tokens de salida por imagen, por tamaño.
  final Map<IllustrationSize, int> tokensPerImage;

  /// Dólares por millón de tokens de la descripción (lo que se lee).
  final double inputUsdPerMillion;

  /// Dólares por millón de tokens de imagen (lo que se dibuja).
  final double outputUsdPerMillion;

  /// El que recomienda el proveedor para empezar.
  final bool recommended;

  /// El más barato del proveedor.
  final bool cheapest;

  /// El proveedor avisó que lo va a apagar.
  final bool deprecated;

  /// Si el precio por imagen sale de los tokens que se calculan (OpenAI no
  /// publica una tabla por imagen para estos modelos), no de una tabla.
  final bool perImageIsEstimate;

  T _nearest<T>(Map<IllustrationSize, T> table, IllustrationSize size) {
    final exact = table[size];
    if (exact != null) return exact;
    // El más cercano: primero el de arriba (no se dibuja más chico de lo que
    // el modelo puede), después el de abajo.
    const order = IllustrationSize.values;
    for (var i = size.index + 1; i < order.length; i++) {
      final up = table[order[i]];
      if (up != null) return up;
    }
    for (var i = size.index - 1; i >= 0; i--) {
      final down = table[order[i]];
      if (down != null) return down;
    }
    throw StateError('Tabla vacía: $modelId');
  }

  double usdFor(IllustrationSize size) => _nearest(usdPerImage, size);
  int tokensFor(IllustrationSize size) => _nearest(tokensPerImage, size);
}

/// Los modelos de imagen con precio conocido (al [kAiPricesVerifiedOn]).
const kImageModelPrices = <ImageModelPrice>[
  // Gemini: «Free tier: Not available». Salida de imagen a US$ 30 por millón
  // (Nano Banana 2.1 y 2 Lite), 60 (3.1 Flash Image) o 120 (3 Pro Image).
  ImageModelPrice(
    provider: IllustrationProvider.gemini,
    modelId: 'gemini-nano-banana-2.1',
    displayName: 'Nano Banana 2.1',
    usdPerImage: {
      IllustrationSize.standard: 0.0336,
      IllustrationSize.large: 0.0504,
    },
    tokensPerImage: {
      IllustrationSize.standard: 1120,
      IllustrationSize.large: 1680,
    },
    inputUsdPerMillion: 1.5,
    outputUsdPerMillion: 30,
    recommended: true,
  ),
  ImageModelPrice(
    provider: IllustrationProvider.gemini,
    modelId: 'gemini-3.1-flash-lite-image',
    displayName: 'Nano Banana 2 Lite',
    usdPerImage: {IllustrationSize.standard: 0.0336},
    tokensPerImage: {IllustrationSize.standard: 1120},
    inputUsdPerMillion: 0.25,
    outputUsdPerMillion: 30,
    cheapest: true,
  ),
  ImageModelPrice(
    provider: IllustrationProvider.gemini,
    modelId: 'gemini-3.1-flash-image',
    displayName: 'Gemini 3.1 Flash Image',
    usdPerImage: {
      IllustrationSize.small: 0.045,
      IllustrationSize.standard: 0.067,
      IllustrationSize.large: 0.101,
    },
    tokensPerImage: {
      IllustrationSize.small: 747,
      IllustrationSize.standard: 1120,
      IllustrationSize.large: 1680,
    },
    inputUsdPerMillion: 0.5,
    outputUsdPerMillion: 60,
  ),
  ImageModelPrice(
    provider: IllustrationProvider.gemini,
    modelId: 'gemini-3-pro-image',
    displayName: 'Nano Banana Pro',
    usdPerImage: {
      IllustrationSize.standard: 0.134,
      IllustrationSize.large: 0.134,
    },
    tokensPerImage: {
      IllustrationSize.standard: 1120,
      IllustrationSize.large: 1120,
    },
    inputUsdPerMillion: 2,
    outputUsdPerMillion: 120,
  ),
  ImageModelPrice(
    provider: IllustrationProvider.gemini,
    modelId: 'gemini-2.5-flash-image',
    displayName: 'Gemini 2.5 Flash Image',
    usdPerImage: {IllustrationSize.standard: 0.039},
    tokensPerImage: {IllustrationSize.standard: 1290},
    inputUsdPerMillion: 0.3,
    outputUsdPerMillion: 30,
    deprecated: true,
  ),
  // OpenAI: salida de imagen a US$ 30 por millón (GPT Image 2.5) u 8 (GPT
  // Image 1 Mini); la descripción, de texto, a 5 o 2. Los tokens por imagen
  // son los publicados para 1024×1024 (baja 272, media 1056, alta 4160), que
  // la app pide en chica, estándar y grande.
  ImageModelPrice(
    provider: IllustrationProvider.openAi,
    modelId: 'gpt-image-2.5-flare',
    displayName: 'GPT Image 2.5 Flare',
    usdPerImage: {
      IllustrationSize.small: 272 * 30 / 1e6,
      IllustrationSize.standard: 1056 * 30 / 1e6,
      IllustrationSize.large: 4160 * 30 / 1e6,
    },
    tokensPerImage: _openAiTokens,
    inputUsdPerMillion: 5,
    outputUsdPerMillion: 30,
    recommended: true,
    perImageIsEstimate: true,
  ),
  ImageModelPrice(
    provider: IllustrationProvider.openAi,
    modelId: 'gpt-image-2.5-sunburst',
    displayName: 'GPT Image 2.5 Sunburst',
    usdPerImage: {
      IllustrationSize.small: 272 * 30 / 1e6,
      IllustrationSize.standard: 1056 * 30 / 1e6,
      IllustrationSize.large: 4160 * 30 / 1e6,
    },
    tokensPerImage: _openAiTokens,
    inputUsdPerMillion: 5,
    outputUsdPerMillion: 30,
    perImageIsEstimate: true,
  ),
  ImageModelPrice(
    provider: IllustrationProvider.openAi,
    modelId: 'gpt-image-1.5',
    displayName: 'GPT Image 1.5',
    usdPerImage: {
      IllustrationSize.small: 272 * 32 / 1e6,
      IllustrationSize.standard: 1056 * 32 / 1e6,
      IllustrationSize.large: 4160 * 32 / 1e6,
    },
    tokensPerImage: _openAiTokens,
    inputUsdPerMillion: 5,
    outputUsdPerMillion: 32,
    perImageIsEstimate: true,
  ),
  ImageModelPrice(
    provider: IllustrationProvider.openAi,
    modelId: 'gpt-image-1-mini',
    displayName: 'GPT Image 1 Mini',
    usdPerImage: {
      IllustrationSize.small: 272 * 8 / 1e6,
      IllustrationSize.standard: 1056 * 8 / 1e6,
      IllustrationSize.large: 4160 * 8 / 1e6,
    },
    tokensPerImage: _openAiTokens,
    inputUsdPerMillion: 2,
    outputUsdPerMillion: 8,
    cheapest: true,
    perImageIsEstimate: true,
  ),
];

const _openAiTokens = {
  IllustrationSize.small: 272,
  IllustrationSize.standard: 1056,
  IllustrationSize.large: 4160,
};

/// El precio de [modelId], si está en la tabla. Acepta los sufijos de
/// versión que agregan los proveedores («-preview», «-2026-09-08»).
ImageModelPrice? imageModelPrice(String modelId) {
  final id = modelId.trim().toLowerCase();
  ImageModelPrice? best;
  for (final price in kImageModelPrices) {
    if (id == price.modelId) return price;
    // El más largo que sea prefijo: «gemini-3.1-flash-image» no debe ganarle
    // a «gemini-3.1-flash-lite-image».
    if (id.startsWith('${price.modelId}-') &&
        (best == null || price.modelId.length > best.modelId.length)) {
      best = price;
    }
  }
  return best;
}

/// El precio con que se estima un modelo de imagen de [provider] que no está
/// en la tabla (uno nuevo): el más caro de los conocidos del proveedor, para
/// no prometer de menos. `null` si el proveedor no cobra por imagen acá
/// (Hugging Face cobra lo que cobre el proveedor de inferencia; el modelo del
/// teléfono, nada).
ImageModelPrice? fallbackImagePrice(IllustrationProvider provider) {
  ImageModelPrice? worst;
  for (final price in kImageModelPrices) {
    if (price.provider != provider || price.deprecated) continue;
    if (worst == null ||
        price.usdFor(IllustrationSize.standard) >
            worst.usdFor(IllustrationSize.standard)) {
      worst = price;
    }
  }
  return worst;
}

/// Lo que cuesta un modelo de texto, por millón de tokens.
@immutable
class TextModelPrice {
  const TextModelPrice({required this.input, required this.output});

  final double input;
  final double output;

  double usdFor({required int inputTokens, required int outputTokens}) =>
      (inputTokens * input + outputTokens * output) / 1e6;
}

/// Los modelos de texto de OpenAI con precio, por su código exacto (tarifa
/// estándar, contexto de hasta 272 mil tokens).
const _openAiTextPrices = <String, TextModelPrice>{
  'gpt-6-astra': TextModelPrice(input: 10, output: 50),
  'gpt-6.1-sol': TextModelPrice(input: 2, output: 10),
  'gpt-6.1-terra': TextModelPrice(input: 1, output: 5),
  'gpt-6-sol': TextModelPrice(input: 2, output: 10),
  'gpt-6-luna': TextModelPrice(input: 0.1, output: 0.5),
  'gpt-5.6-sol': TextModelPrice(input: 4, output: 20),
  'gpt-5.6-terra': TextModelPrice(input: 2, output: 12),
  'gpt-5.6-luna': TextModelPrice(input: 0.2, output: 1.2),
  'gpt-5.5': TextModelPrice(input: 5, output: 30),
  'gpt-5.4': TextModelPrice(input: 2.5, output: 15),
  'gpt-5.4-mini': TextModelPrice(input: 0.75, output: 4.5),
  'gpt-5.4-nano': TextModelPrice(input: 0.2, output: 1.25),
  'gpt-5.2': TextModelPrice(input: 1.75, output: 14),
  'gpt-5.1': TextModelPrice(input: 1.25, output: 10),
  'gpt-5': TextModelPrice(input: 1.25, output: 10),
  'gpt-5-mini': TextModelPrice(input: 0.25, output: 2),
  'gpt-5-nano': TextModelPrice(input: 0.05, output: 0.4),
};

/// Los de Claude por familia y versión («opus 5.5»). Haiku 5.5, con pedidos
/// de hasta 100 mil tokens: los de crear no pasan de ahí por parte.
const _claudeTextPrices = <String, TextModelPrice>{
  'fable 5.1': TextModelPrice(input: 10, output: 50),
  'fable 5': TextModelPrice(input: 10, output: 50),
  'mythos 5.1': TextModelPrice(input: 10, output: 50),
  'mythos 5': TextModelPrice(input: 10, output: 50),
  'opus 5.5': TextModelPrice(input: 4, output: 20),
  'opus 5': TextModelPrice(input: 5, output: 25),
  'opus 4.8': TextModelPrice(input: 5, output: 25),
  'opus 4.7': TextModelPrice(input: 5, output: 25),
  'opus 4.6': TextModelPrice(input: 5, output: 25),
  'opus 4.5': TextModelPrice(input: 5, output: 25),
  'sonnet 5.5': TextModelPrice(input: 2, output: 10),
  'sonnet 5': TextModelPrice(input: 2, output: 10),
  'sonnet 4.6': TextModelPrice(input: 3, output: 15),
  'sonnet 4.5': TextModelPrice(input: 3, output: 15),
  'haiku 5.5': TextModelPrice(input: 0.1, output: 0.5),
  'haiku 4.5': TextModelPrice(input: 1, output: 5),
};

/// El precio del modelo de texto [model] de [provider], si se conoce. Gemini
/// devuelve cero: la capa gratuita escribe sin costo («Free of charge»), y
/// no hay cómo saber desde acá si la cuenta paga.
TextModelPrice? textModelPrice(AiProvider provider, String? model) {
  switch (provider) {
    case AiProvider.gemma:
    case AiProvider.gemini:
      return const TextModelPrice(input: 0, output: 0);
    case AiProvider.openAi:
      if (model == null) return null;
      final id = model.trim().toLowerCase().replaceFirst(
        RegExp(r'-\d{4}-\d{2}-\d{2}$'),
        '',
      );
      return _openAiTextPrices[id];
    case AiProvider.anthropic:
      if (model == null) return null;
      final match = RegExp(
        r'claude-(fable|mythos|opus|sonnet|haiku)-(\d+)(?:-(\d{1,2}))?(?!\d)',
      ).firstMatch(model.trim().toLowerCase());
      if (match == null) return null;
      final minor = match.group(3);
      final version = minor == null
          ? match.group(2)!
          : '${match.group(2)}.$minor';
      return _claudeTextPrices['${match.group(1)} $version'];
  }
}

/// La cuota diaria con que se calcula el porcentaje hasta que la persona fija
/// la suya: la de la capa gratuita, rotulada «estimado».
///
/// Google ya no publica la tabla de la capa gratuita (la página de límites,
/// al 2026-10-28, remite a Google AI Studio, donde cada proyecto ve la suya),
/// así que para Gemini es una estimación prudente: 250 pedidos por día, lo
/// que rige para los Flash en la mayoría de los proyectos gratuitos. Las
/// imágenes no tienen capa gratuita («Not available»): no hay tope que
/// estimar, se paga cada una.
///
/// OpenAI, Claude y Hugging Face no tienen capa gratuita: sin la cuota de la
/// persona no hay contra qué calcular un porcentaje (`null`), y se muestra
/// el costo. Gemma y el modelo de imágenes del teléfono no tienen cuota.
DailyQuota? defaultDailyQuota(AiProvider provider) => switch (provider) {
  AiProvider.gemini => const DailyQuota(requests: 250, isEstimate: true),
  AiProvider.gemma || AiProvider.openAi || AiProvider.anthropic => null,
};

/// Lo que puede cada IA, para la tabla de «¿Qué puede cada IA?». La fila
/// [AiCapabilityRow.onDevice] («Exigente — en el teléfono») solo se muestra
/// si hay un motor de imágenes del teléfono registrado.
enum AiCapabilityRow { gemma, claude, gemini, openAi, huggingFace, onDevice }

extension AiCapabilityRowFacts on AiCapabilityRow {
  /// Si escribe el contenido (texto, diapositivas, informe…).
  bool get writes => switch (this) {
    AiCapabilityRow.gemma ||
    AiCapabilityRow.claude ||
    AiCapabilityRow.gemini ||
    AiCapabilityRow.openAi => true,
    AiCapabilityRow.huggingFace || AiCapabilityRow.onDevice => false,
  };

  /// Si dibuja ilustraciones.
  bool get illustrates => switch (this) {
    AiCapabilityRow.gemma || AiCapabilityRow.claude => false,
    _ => true,
  };

  /// El de dibujar, si dibuja.
  IllustrationProvider? get illustrationProvider => switch (this) {
    AiCapabilityRow.gemini => IllustrationProvider.gemini,
    AiCapabilityRow.openAi => IllustrationProvider.openAi,
    AiCapabilityRow.huggingFace => IllustrationProvider.huggingFace,
    AiCapabilityRow.onDevice => IllustrationProvider.onDevice,
    AiCapabilityRow.gemma || AiCapabilityRow.claude => null,
  };

  /// El de escribir, si escribe.
  AiProvider? get textProvider => switch (this) {
    AiCapabilityRow.gemma => AiProvider.gemma,
    AiCapabilityRow.claude => AiProvider.anthropic,
    AiCapabilityRow.gemini => AiProvider.gemini,
    AiCapabilityRow.openAi => AiProvider.openAi,
    AiCapabilityRow.huggingFace || AiCapabilityRow.onDevice => null,
  };

  /// Los modelos de imagen de la tabla, del más barato al más caro.
  List<ImageModelPrice> get imagePrices {
    final provider = illustrationProvider;
    return [
      for (final p in kImageModelPrices)
        if (p.provider == provider && !p.deprecated) p,
    ]..sort(
      (a, b) => a
          .usdFor(IllustrationSize.standard)
          .compareTo(b.usdFor(IllustrationSize.standard)),
    );
  }
}

/// La licencia de un modelo abierto, en una línea.
enum OpenModelLicense {
  /// Apache 2.0: uso personal y comercial.
  apache2,

  /// La licencia comunitaria de Stability AI: gratis para uso personal y
  /// para quien factura menos de US$ 1 millón por año; más, licencia de
  /// empresa (https://stability.ai/license).
  stabilityCommunity,
}

/// Un modelo de imágenes de código abierto que se usa por Hugging Face, en
/// la nube (F43, pedido del dueño: «que me los sugiera con su link»). Ninguno
/// de estos corre en un teléfono: piden una placa de video.
@immutable
class OpenImageModel {
  const OpenImageModel({
    required this.key,
    required this.name,
    required this.repoId,
    required this.license,
    required this.billionParameters,
    this.minVideoMemoryGb,
  });

  /// Para los textos y las pruebas.
  final String key;
  final String name;

  /// Su repositorio en Hugging Face.
  final String repoId;
  final OpenModelLicense license;

  /// Miles de millones de parámetros, según los pesos que publica su ficha.
  final double billionParameters;

  /// La memoria de video que dice su ficha para correrlo en una computadora,
  /// si la dice.
  final int? minVideoMemoryGb;

  String get url => 'https://huggingface.co/$repoId';
}

/// Los modelos abiertos que se sugieren, verificados contra su ficha, su
/// licencia y la lista de proveedores de Hugging Face que lo dibujan a partir
/// de texto, el 2026-10-28. Fuera de la lista: Qwen-Image (20 mil millones
/// de parámetros, pedido del dueño) y FLUX.2 klein 4B (en Hugging Face
/// solo se ofrece para editar imágenes, no para dibujar desde texto).
const kOpenImageModels = <OpenImageModel>[
  OpenImageModel(
    key: 'fluxSchnell',
    name: 'FLUX.1 [schnell]',
    repoId: 'black-forest-labs/FLUX.1-schnell',
    license: OpenModelLicense.apache2,
    billionParameters: 11.9,
  ),
  OpenImageModel(
    key: 'zImage',
    name: 'Z-Image Turbo',
    repoId: 'Tongyi-MAI/Z-Image-Turbo',
    license: OpenModelLicense.apache2,
    billionParameters: 6,
    minVideoMemoryGb: 16,
  ),
  OpenImageModel(
    key: 'sd35',
    name: 'Stable Diffusion 3.5 Large',
    repoId: 'stabilityai/stable-diffusion-3.5-large',
    license: OpenModelLicense.stabilityCommunity,
    billionParameters: 8.1,
  ),
  OpenImageModel(
    key: 'sana',
    name: 'Sana Sprint 1.6B',
    repoId: 'Efficient-Large-Model/Sana_Sprint_1.6B_1024px_diffusers',
    license: OpenModelLicense.apache2,
    billionParameters: 1.6,
  ),
];
