import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';

/// Lo que comparten los formatos de los proveedores en la nube (F32) al hablar
/// por HTTP: mandar, y si el proveedor contestó con un error, traducirlo.

/// Cuánto se espera a que el proveedor empiece a contestar (F39) en un pedido
/// de respuesta larga.
///
/// Acá estaba el «error de conexión» con buena conexión: el cliente tenía un
/// `receiveTimeout` de 60 s y, en dio 5.11, ese tiempo vigila las cabeceras
/// **y también el silencio entre pedazos del cuerpo** (arrancando apenas
/// llegan las cabeceras). Un modelo que razona, o un texto largo, puede
/// callar más de un minuto antes del primer pedazo: dio cortaba con
/// `DioException.receiveTimeout` y el formato de cada proveedor lo tomaba
/// por «sin red». Tres minutos dan margen real sin dejar colgada la pantalla
/// si el servicio no contesta nunca.
const kCloudFirstByteTimeout = Duration(minutes: 3);

/// Cuánto silencio aguanta una respuesta en vivo antes de darla por perdida
/// (F39). Se vigila el silencio, no el total: una respuesta larga que va
/// llegando puede durar lo que dure. Dio ya corta con
/// [kCloudFirstByteTimeout] entre pedazos; esto lo asegura sin depender de
/// cómo lo haga cada versión de dio y deja el valor a mano para las pruebas.
const kCloudIdleTimeout = Duration(minutes: 3);

/// Las opciones de un pedido: los errores los lee y traduce el formato, no
/// los tira Dio sin cuerpo. [receiveTimeout] pisa el del cliente en los
/// pedidos de respuesta larga ([kCloudFirstByteTimeout]).
Options cloudOptions(
  Map<String, String> headers,
  ResponseType type, {
  Duration? receiveTimeout,
}) => Options(
  headers: {...headers, 'content-type': 'application/json'},
  responseType: type,
  validateStatus: (_) => true,
  receiveTimeout: receiveTimeout,
);

/// Manda [request]. Si no llega al proveedor, o no contesta a tiempo, lo
/// dice la clase de falla ([cloudFailureOfError]); un estado que no es 2xx →
/// lo que diga [failureFrom] con el cuerpo ya leído y las cabeceras. Un corte
/// pedido ([CancelToken]) sale tal cual.
Future<Response<T>> sendCloudRequest<T>(
  Future<Response<T>> Function() request, {
  required CloudModelException Function(
    int status,
    Object? body,
    Headers headers,
  )
  failureFrom,
}) async {
  final Response<T> response;
  try {
    response = await request();
  } on DioException catch (error) {
    if (CancelToken.isCancel(error)) rethrow;
    throw cloudFailureOfError(error)!;
  }
  final status = response.statusCode ?? 0;
  if (status >= 200 && status < 300) return response;
  throw failureFrom(
    status,
    await decodeCloudErrorBody(response.data),
    response.headers,
  );
}

/// Traduce un error de la conexión a la falla que le corresponde (F39), o
/// `null` si no es de la conexión —un error del programa no se disfraza—.
///
/// Antes todo `DioException` era «sin red», y el cuerpo en vivo ni se miraba:
/// una espera vencida o una respuesta cortada se mostraban como falta de
/// internet. [inBody] dice que el error vino leyendo la respuesta, cuando ya
/// se había llegado al proveedor: un socket que se cae ahí es una respuesta
/// cortada, no una falta de conexión.
CloudModelException? cloudFailureOfError(Object error, {bool inBody = false}) {
  CloudModelException fail(CloudModelFailure failure, String detail) =>
      CloudModelException(failure, detail: detail);

  if (error is CloudModelException) return error;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return fail(CloudModelFailure.timeout, error.type.name);
      case DioExceptionType.connectionError:
        // El servidor cortó antes de mandar las cabeceras: se llegó a él.
        final inner = error.error;
        if (inner is HttpException &&
            inner.message.contains('Connection closed')) {
          return fail(CloudModelFailure.cutOff, error.type.name);
        }
        return fail(CloudModelFailure.network, error.type.name);
      case DioExceptionType.badCertificate:
        return fail(CloudModelFailure.unknown, error.type.name);
      case DioExceptionType.badResponse:
        return CloudModelException(
          CloudModelFailure.unknown,
          detail: error.type.name,
          statusCode: error.response?.statusCode,
        );
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        final inner = error.error;
        if (inner == null || identical(inner, error)) {
          return fail(CloudModelFailure.unknown, error.type.name);
        }
        return cloudFailureOfError(inner, inBody: inBody) ??
            fail(CloudModelFailure.unknown, error.type.name);
    }
  }
  if (error is TimeoutException) return fail(CloudModelFailure.timeout, 'idle');
  if (error is SocketException) {
    return fail(
      inBody ? CloudModelFailure.cutOff : CloudModelFailure.network,
      'socket',
    );
  }
  if (error is HttpException || error is TlsException) {
    return fail(CloudModelFailure.cutOff, error.runtimeType.toString());
  }
  return null;
}

/// Los bytes del cuerpo de una respuesta en vivo, vigilados (F39):
///
/// - si pasa [idle] sin que llegue nada, es una espera vencida
///   ([CloudModelFailure.timeout]);
/// - si la conexión se cae o el proveedor la corta, es una respuesta cortada
///   ([CloudModelFailure.cutOff]) y no una falta de internet. Esos errores
///   (`HttpException`, `SocketException`) no son `DioException`: salían sin
///   clasificar;
/// - si se cortó a propósito ([cancel]), termina callado.
Stream<Uint8List> guardedCloudBody(
  Stream<Uint8List> bytes, {
  required Duration idle,
  CancelToken? cancel,
}) async* {
  try {
    await for (final chunk in bytes.timeout(idle)) {
      yield chunk;
    }
  } on DioException catch (error) {
    if (CancelToken.isCancel(error) || (cancel?.isCancelled ?? false)) return;
    throw cloudFailureOfError(error, inBody: true)!;
  } on IOException catch (error) {
    if (cancel?.isCancelled ?? false) return;
    throw cloudFailureOfError(error, inBody: true)!;
  } on TimeoutException catch (error) {
    if (cancel?.isCancelled ?? false) return;
    throw cloudFailureOfError(error, inBody: true)!;
  }
}

/// La respuesta en vivo se terminó sin su evento final (F39): se cortó a
/// mitad. Cada formato sabe cuál es su cierre; quien lo detecta tira esto.
const cloudStreamCutOff = CloudModelException(
  CloudModelFailure.cutOff,
  detail: 'sin evento final',
);

/// El cuerpo de un error como JSON, venga entero o como flujo; `null` si no
/// lo es.
Future<Object?> decodeCloudErrorBody(Object? data) async {
  try {
    if (data is ResponseBody) {
      final bytes = await data.stream.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      return jsonDecode(utf8.decode(bytes, allowMalformed: true));
    }
    if (data is String) return jsonDecode(data);
    return data;
  } on FormatException {
    return null;
  }
}

/// Cuánto pide esperar la cabecera `retry-after` (en segundos, como la mandan
/// OpenAI y Anthropic); `null` si no está o no se entiende.
Duration? retryAfterOf(Headers headers) {
  final value = headers.value('retry-after');
  if (value == null) return null;
  final seconds = double.tryParse(value.trim());
  if (seconds == null || seconds < 0) return null;
  return Duration(milliseconds: (seconds * 1000).round());
}

/// Cuánto pide esperar un mensaje como «Please try again in 6m0s» o «in
/// 1.5s» (OpenAI lo dice ahí cuando no manda la cabecera); `null` si no hay.
Duration? retryDelayInMessage(String message) {
  final match = RegExp(
    r'try again in ((?:\d+(?:\.\d+)?(?:ms|h|m|s))+)',
    caseSensitive: false,
  ).firstMatch(message);
  if (match == null) return null;
  var millis = 0.0;
  for (final part in RegExp(
    r'(\d+(?:\.\d+)?)(ms|h|m|s)',
  ).allMatches(match.group(1)!)) {
    final value = double.parse(part.group(1)!);
    millis += switch (part.group(2)) {
      'h' => value * 3600000,
      'm' => value * 60000,
      's' => value * 1000,
      _ => value,
    };
  }
  return Duration(milliseconds: millis.round());
}
