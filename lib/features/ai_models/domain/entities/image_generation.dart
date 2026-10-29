import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';

/// La forma de una ilustración (F43): la de la lámina o la diapositiva donde
/// va.
enum IllustrationAspect {
  /// Horizontal, como una diapositiva.
  wide('16:9', 16, 9),

  /// Vertical, como una infografía de teléfono.
  tall('9:16', 9, 16),

  /// Cuadrada.
  square('1:1', 1, 1),

  /// La diapositiva clásica.
  classic('4:3', 4, 3);

  const IllustrationAspect(this.ratio, this.width, this.height);

  /// Como lo escriben Gemini y la app: «16:9».
  final String ratio;
  final int width;
  final int height;

  static IllustrationAspect? fromRatio(String? ratio) {
    for (final aspect in values) {
      if (aspect.ratio == ratio) return aspect;
    }
    return null;
  }
}

/// El tamaño de una ilustración: el lado largo, más o menos.
enum IllustrationSize {
  /// ~512 px: la prueba de una cuenta, una miniatura.
  small(512),

  /// ~1024 px («1K»): lo de siempre, y lo más barato en casi todos.
  standard(1024),

  /// ~2048 px («2K»): para exportar grande.
  large(2048);

  const IllustrationSize(this.longSide);

  final int longSide;
}

/// El ancho y el alto en píxeles de [aspect] con lado largo [size], en
/// múltiplos de 64 —lo que piden los modelos abiertos y OpenAI—.
({int width, int height}) pixelsOf(
  IllustrationAspect aspect,
  IllustrationSize size,
) {
  int round64(double value) => (value / 64).round().clamp(1, 1 << 10) * 64;
  final long = size.longSide.toDouble();
  if (aspect.width >= aspect.height) {
    return (
      width: round64(long),
      height: round64(long * aspect.height / aspect.width),
    );
  }
  return (
    width: round64(long * aspect.width / aspect.height),
    height: round64(long),
  );
}

/// Un modelo de imagen que ofrece una cuenta, como lo listó su proveedor (o
/// como lo trae la lista curada, en Hugging Face y en el teléfono).
@immutable
class ImageModelInfo {
  const ImageModelInfo({
    required this.id,
    required this.displayName,
    this.route,
  });

  /// El código que se manda: «gemini-nano-banana-2.1», «gpt-image-1-mini»,
  /// «black-forest-labs/FLUX.1-schnell».
  final String id;

  final String displayName;

  /// Por dónde se le pide, si el proveedor lo necesita: en Hugging Face, el
  /// proveedor de inferencia y su código («fal-ai:fal-ai/flux/schnell»).
  final String? route;

  @override
  bool operator ==(Object other) =>
      other is ImageModelInfo &&
      other.id == id &&
      other.displayName == displayName &&
      other.route == route;

  @override
  int get hashCode => Object.hash(id, displayName, route);

  @override
  String toString() => 'ImageModelInfo($id)';
}

/// Un pedido de imagen, ya armado: el modelo, la descripción y la forma.
@immutable
class ImageWireRequest {
  const ImageWireRequest({
    required this.model,
    required this.prompt,
    this.aspect = IllustrationAspect.square,
    this.size = IllustrationSize.standard,
    this.route,
  });

  final String model;
  final String prompt;
  final IllustrationAspect aspect;
  final IllustrationSize size;

  /// Ver [ImageModelInfo.route].
  final String? route;
}

/// Una imagen generada, con lo que contó el proveedor.
@immutable
class GeneratedImage {
  const GeneratedImage({
    required this.bytes,
    required this.mimeType,
    required this.model,
    this.inputTokens,
    this.outputTokens,
  });

  final Uint8List bytes;

  /// «image/png», «image/jpeg» o «image/webp».
  final String mimeType;

  final String model;

  /// Los tokens del pedido y de la imagen, si el proveedor los contó.
  final int? inputTokens;
  final int? outputTokens;
}

/// Lo que devuelve `IllustrationService.generate`: la imagen, quién la hizo y
/// cuánto costó, más o menos.
@immutable
class IllustrationResult {
  const IllustrationResult({
    required this.image,
    required this.accountId,
    required this.provider,
    required this.inputTokens,
    required this.outputTokens,
    required this.costUsd,
    required this.costIsEstimate,
  });

  final GeneratedImage image;
  final String accountId;
  final IllustrationProvider provider;
  final int inputTokens;
  final int outputTokens;

  /// En dólares: con los tokens que contó el proveedor y la tabla de precios
  /// fechada, o con el precio por imagen si no contó nada. 0 en el modelo
  /// del teléfono; `null` en Hugging Face, que cobra lo de su proveedor de
  /// inferencia.
  final double? costUsd;

  /// Si [costUsd] sale del precio por imagen de la tabla (no de lo contado).
  final bool costIsEstimate;
}

/// Por qué no salió una imagen (F43), con las palabras del proveedor
/// traducidas a lo que la persona puede hacer.
enum ImageFailure {
  /// Gemini: la cuenta no tiene facturación activa. La capa gratuita no
  /// incluye los modelos de imagen.
  noBilling,

  /// OpenAI: la organización no está verificada en su consola.
  orgUnverified,

  /// Sin saldo: OpenAI sin créditos, o Hugging Face sin créditos (402).
  noCredits,

  /// Se terminó la cuota del día de esa cuenta.
  quotaExhausted,

  /// Se pasó del tope por minuto: alcanza con esperar.
  rateLimited,

  /// El proveedor no quiso dibujar eso por sus reglas de contenido.
  contentRefused,

  /// La clave no sirve.
  invalidKey,

  /// La clave sirve pero no tiene permiso (el token de Hugging Face sin el
  /// permiso de inferencia, una región).
  forbidden,

  /// El modelo de imagen elegido ya no existe con esa cuenta.
  modelNotFound,

  /// La cuenta no tiene ningún modelo de imagen.
  noImageModel,

  /// Contestó, pero sin ninguna imagen.
  noImage,

  /// El modelo del teléfono («Exigente») todavía no se descargó.
  modelNotDownloaded,

  /// El teléfono no alcanza para el modelo del teléfono: poca memoria o poco
  /// lugar libre.
  deviceTooSmall,

  /// El modelo del teléfono se quedó sin memoria mientras dibujaba, o la app
  /// se cerró la última vez que dibujó: se apaga solo hasta que la persona
  /// lo vuelva a probar.
  notEnoughMemory,

  /// El teléfono no puede correr el modelo del teléfono: no es Android de 64
  /// bits, su procesador no tiene lo que pide, o la app se armó sin el motor.
  unsupportedDevice,

  /// Se canceló a pedido: no es un error que mostrar.
  cancelled,

  /// Sin internet.
  network,

  /// No contestó a tiempo.
  timeout,

  /// Saturado o caído de su lado.
  unavailable,

  /// El pedido no le gustó (y no es nada de lo anterior).
  badRequest,

  /// No hay ninguna cuenta que pueda dibujar.
  noAccount,

  /// Otra cosa: lo que dijo está en el detalle.
  unknown;

  /// Si esto dice algo de la cuenta —que no puede dibujar hasta que la
  /// persona haga algo—, y no del momento o de lo pedido. Es lo que se
  /// recuerda como «no puede».
  bool get isAboutAccount => switch (this) {
    noBilling ||
    orgUnverified ||
    noCredits ||
    invalidKey ||
    forbidden ||
    noImageModel ||
    modelNotDownloaded ||
    deviceTooSmall ||
    notEnoughMemory ||
    unsupportedDevice => true,
    _ => false,
  };
}

/// Un pedido de imagen que no salió.
class ImageGenerationException implements Exception {
  const ImageGenerationException(
    this.failure, {
    this.detail,
    this.statusCode,
    this.retryAfter,
  });

  final ImageFailure failure;

  /// Lo que dijo el proveedor, para el registro; nunca la clave.
  final String? detail;
  final int? statusCode;
  final Duration? retryAfter;

  @override
  String toString() =>
      'ImageGenerationException(${failure.name}'
      '${statusCode == null ? '' : ', $statusCode'}'
      '${detail == null ? '' : ': $detail'})';
}
