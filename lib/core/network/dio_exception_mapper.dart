import 'package:cristo_es_el_salvador/core/error/exceptions.dart';
import 'package:dio/dio.dart';

/// Traduce un [DioException] genérico a una excepción de `core/error`.
/// Cada data source que use el `dioProvider` debería pasar por aquí en vez
/// de reinterpretar `DioExceptionType` por su cuenta. Un feature solo debe
/// sobreescribir un caso puntual cuando el mismo código HTTP significa algo
/// distinto en su endpoint (p. ej. Auth mapea 401 en `/login` a
/// `InvalidCredentialsException` —credenciales inválidas— en vez de al
/// genérico [UnauthorizedException] —sesión expirada— que devuelve esta
/// función).
Exception mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.connectionError:
      return const NetworkException(
        message: 'No se pudo conectar. Revisa tu conexión.',
      );
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        return UnauthorizedException(
          message:
              _serverMessageFrom(e) ??
              'Tu sesión expiró. Inicia sesión de nuevo.',
        );
      }
      return ServerException(
        message:
            _serverMessageFrom(e) ?? 'Error del servidor. Intenta más tarde.',
        statusCode: statusCode,
      );
  }
}

String? _serverMessageFrom(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['message'] is String) {
    return data['message'] as String;
  }
  return null;
}
