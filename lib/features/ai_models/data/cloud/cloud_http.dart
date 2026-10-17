import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';

/// Lo que comparten los formatos de los proveedores en la nube (F32) al hablar
/// por HTTP: mandar, y si el proveedor contestó con un error, traducirlo.

/// Las opciones de un pedido: los errores los lee y traduce el formato, no
/// los tira Dio sin cuerpo.
Options cloudOptions(Map<String, String> headers, ResponseType type) => Options(
  headers: {...headers, 'content-type': 'application/json'},
  responseType: type,
  validateStatus: (_) => true,
);

/// Manda [request]. Sin conexión → `CloudModelFailure.network`; un estado
/// que no es 2xx → lo que diga [failureFrom] con el cuerpo ya leído y las
/// cabeceras. Un corte pedido ([CancelToken]) sale tal cual.
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
    throw CloudModelException(
      CloudModelFailure.network,
      detail: error.type.name,
    );
  }
  final status = response.statusCode ?? 0;
  if (status >= 200 && status < 300) return response;
  throw failureFrom(
    status,
    await decodeCloudErrorBody(response.data),
    response.headers,
  );
}

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
