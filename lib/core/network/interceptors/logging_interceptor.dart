import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:dio/dio.dart';

/// Registra cada request/response saliente a través de [AppLogger] en vez
/// de `print()`, para que los logs de red respeten el mismo sink que el
/// resto de la app (y puedan filtrarse o desactivarse en `prod`).
class NetworkLoggingInterceptor extends Interceptor {
  NetworkLoggingInterceptor({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.debug('--> ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _logger.debug('<-- ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.debug('<-x ${err.response?.statusCode} ${err.requestOptions.uri}');
    handler.next(err);
  }
}
