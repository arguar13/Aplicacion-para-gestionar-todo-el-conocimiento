import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:dio/dio.dart';

/// Cuando el backend responde 401 en cualquier request autenticado (no en
/// `/login`: ese caso lo maneja `AuthRemoteDataSource` como credenciales
/// inválidas), significa que el token guardado ya no sirve. `onUnauthorized`
/// desloguea a nivel de sesión — no navega ni conoce a `GoRouter`, el
/// router reacciona solo porque escucha `sessionControllerProvider`.
class UnauthorizedInterceptor extends Interceptor {
  UnauthorizedInterceptor({
    required Future<void> Function() onUnauthorized,
    required AppLogger logger,
  }) : _onUnauthorized = onUnauthorized,
       _logger = logger;

  final Future<void> Function() _onUnauthorized;
  final AppLogger _logger;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 &&
        err.requestOptions.path != '/login') {
      _logger.warning('Token rechazado por el servidor, cerrando sesión.');
      await _onUnauthorized();
    }
    handler.next(err);
  }
}
