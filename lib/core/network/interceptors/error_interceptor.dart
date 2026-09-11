import 'package:dio/dio.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/network/dio_exception_mapper.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';

/// Punto único de manejo global de errores de red: registra el fallo y deja
/// pasar el [DioException] intacto para que cada repositorio lo traduzca a
/// su `Failure` específico (no lo transforma acá para no perder contexto —
/// status code, body— que la capa `data` sí necesita).
///
/// Además de loguear, cumple dos roles transversales que no dependen de qué
/// pantalla esté activa: le avisa a `onDomainError` (normalmente
/// `GlobalErrorNotifier.report`, ver `core/error/global_error_bus.dart`)
/// para que se muestre un mensaje amigable sin importar dónde esté el
/// usuario, y reporta a [TelemetryService] los fallos que sí ameritan
/// investigarse — un [ServerException] (5xx/respuesta inesperada) puede ser
/// un bug real; un [NetworkException] (sin conexión) o un 401 esperado no
/// lo son, y reportarlos solo generaría ruido en Sentry.
class GlobalErrorInterceptor extends Interceptor {
  GlobalErrorInterceptor({
    required AppLogger logger,
    required TelemetryService telemetry,
    required void Function(Exception exception) onDomainError,
  }) : _logger = logger,
       _telemetry = telemetry,
       _onDomainError = onDomainError;

  final AppLogger _logger;
  final TelemetryService _telemetry;
  final void Function(Exception exception) _onDomainError;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.error(
      'HTTP ${err.requestOptions.method} ${err.requestOptions.path} failed: '
      '${err.message}',
      err,
      err.stackTrace,
    );

    final exception = mapDioException(err);
    _onDomainError(exception);
    if (exception is ServerException) {
      _telemetry.recordError(
        exception,
        err.stackTrace,
        hint: '${err.requestOptions.method} ${err.requestOptions.path}',
      );
    }

    handler.next(err);
  }
}
