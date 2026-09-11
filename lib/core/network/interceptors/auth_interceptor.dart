import 'package:dio/dio.dart';
import 'package:sinapsis/core/network/token_storage.dart';

/// Inyecta el `Authorization: Bearer <token>` en cada request saliente.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required TokenStorage tokenStorage})
    : _tokenStorage = tokenStorage;

  final TokenStorage _tokenStorage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStorage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
