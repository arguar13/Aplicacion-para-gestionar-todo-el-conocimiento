import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_http.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

/// Cómo se le pide una imagen a un proveedor (F43): el formato de sus pedidos
/// y respuestas, nada más, como `CloudWire` para el texto. Qué cuenta, qué
/// se recuerda de ella y cómo se cuenta lo gastado vive arriba, en
/// `IllustrationService`.
///
/// Cada formato traduce sus errores a [ImageGenerationException] con un
/// [ImageFailure] preciso: «sin facturación», «organización sin verificar»,
/// «sin créditos», «rechazado por su contenido»…, no un error genérico.
abstract interface class ImageWire {
  IllustrationProvider get provider;

  /// Los modelos de imagen que ofrece [access], como los lista el proveedor
  /// (o la lista curada, en Hugging Face). Sirve también para probar la
  /// clave sin gastar: falla con [ImageGenerationException] si no anda.
  Future<List<ImageModelInfo>> listImageModels(ImageWireAccess access);

  /// El que la app usa de [models] si la persona no eligió otro; `null` si
  /// [models] está vacía.
  String? recommendedImageModel(List<ImageModelInfo> models);

  /// Dibuja [request].
  Future<GeneratedImage> generate(
    ImageWireRequest request,
    ImageWireAccess access, {
    CancelToken? cancel,
  });
}

/// Con qué se le pide: la clave, si el proveedor la pide (el modelo del
/// teléfono no).
@immutable
class ImageWireAccess {
  const ImageWireAccess({this.key});

  final String? key;
}

/// La falla de imagen que corresponde a una de texto ya traducida por el
/// formato de su proveedor (F32): lo común —la clave, la cuota, la red— se
/// dice igual; lo propio de las imágenes lo afina cada formato antes.
ImageFailure imageFailureOfCloud(CloudModelFailure failure) =>
    switch (failure) {
      CloudModelFailure.invalidKey => ImageFailure.invalidKey,
      CloudModelFailure.forbidden => ImageFailure.forbidden,
      CloudModelFailure.rateLimited => ImageFailure.rateLimited,
      CloudModelFailure.quotaExhausted => ImageFailure.quotaExhausted,
      CloudModelFailure.modelNotFound => ImageFailure.modelNotFound,
      CloudModelFailure.unavailable => ImageFailure.unavailable,
      CloudModelFailure.blocked => ImageFailure.contentRefused,
      CloudModelFailure.network => ImageFailure.network,
      CloudModelFailure.timeout => ImageFailure.timeout,
      // Se cortó a mitad con la conexión andando: de su lado.
      CloudModelFailure.cutOff => ImageFailure.unavailable,
      CloudModelFailure.badRequest ||
      CloudModelFailure.tooLong => ImageFailure.badRequest,
      CloudModelFailure.noAccount => ImageFailure.noAccount,
      CloudModelFailure.backgroundCap ||
      CloudModelFailure.unknown => ImageFailure.unknown,
    };

/// [error] traducido sin más detalle que el que traía.
ImageGenerationException imageExceptionOf(CloudModelException error) =>
    ImageGenerationException(
      imageFailureOfCloud(error.failure),
      detail: error.detail,
      statusCode: error.statusCode,
      retryAfter: error.retryAfter,
    );

/// Si [message] dice que lo pedido se rechazó por su contenido.
bool mentionsContentPolicy(String message) {
  final lower = message.toLowerCase();
  return lower.contains('safety') ||
      lower.contains('content policy') ||
      lower.contains('content_policy') ||
      lower.contains('moderation') ||
      lower.contains('nsfw') ||
      lower.contains('prohibited');
}

/// Manda un pedido de imagen: lo que no llega o vence lo dice
/// [cloudFailureOfError]; un estado que no es 2xx, [failureFrom] con el
/// cuerpo leído. Todo sale como [ImageGenerationException].
Future<Response<T>> sendImageRequest<T>(
  Future<Response<T>> Function() request, {
  required ImageGenerationException Function(
    int status,
    Object? body,
    Headers headers,
  )
  failureFrom,
  ImageFailure Function(CloudModelException error)? connectionFailure,
}) async {
  final Response<T> response;
  try {
    response = await request();
  } on DioException catch (error) {
    if (CancelToken.isCancel(error)) rethrow;
    final cloud = cloudFailureOfError(error)!;
    throw ImageGenerationException(
      connectionFailure?.call(cloud) ?? imageFailureOfCloud(cloud.failure),
      detail: cloud.detail,
    );
  }
  final status = response.statusCode ?? 0;
  if (status >= 200 && status < 300) return response;
  throw failureFrom(
    status,
    await decodeImageErrorBody(response.data),
    response.headers,
  );
}

/// El cuerpo de un error como JSON (venga como texto, bytes o ya leído), o
/// `null` si no lo es.
Future<Object?> decodeImageErrorBody(Object? data) async {
  if (data is List<int>) {
    try {
      return jsonDecode(utf8.decode(data, allowMalformed: true));
    } on FormatException {
      return null;
    }
  }
  return decodeCloudErrorBody(data);
}

/// Las opciones de un pedido de imagen: el error lo traduce el formato, y la
/// espera es la de una respuesta larga —dibujar tarda—.
Options imageOptions(
  Map<String, String> headers, {
  ResponseType type = ResponseType.json,
}) => Options(
  headers: {...headers, 'content-type': 'application/json'},
  responseType: type,
  validateStatus: (_) => true,
  receiveTimeout: kCloudFirstByteTimeout,
);

/// Los bytes de una imagen que viene en base64 (con o sin el prefijo
/// `data:…;base64,`), o `null` si no se entienden.
Uint8List? decodeImageBase64(Object? data) {
  if (data is! String || data.isEmpty) return null;
  final comma = data.startsWith('data:') ? data.indexOf(',') : -1;
  try {
    final bytes = base64Decode(comma >= 0 ? data.substring(comma + 1) : data);
    return bytes.isEmpty ? null : bytes;
  } on FormatException {
    return null;
  }
}

/// El tipo de [bytes] por sus primeros bytes, o [declared] si lo dijo el
/// proveedor y es de imagen.
String imageMimeOf(Uint8List bytes, {String? declared}) {
  final type = declared?.split(';').first.trim().toLowerCase();
  if (type != null && type.startsWith('image/')) return type;
  return imageMimeType(bytes);
}
