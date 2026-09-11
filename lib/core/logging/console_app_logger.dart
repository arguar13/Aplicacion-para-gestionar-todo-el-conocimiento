import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:logger/logger.dart';

/// Implementación por defecto: imprime en consola vía el paquete `logger`.
///
/// Punto de extensión futuro: reenviar `error`/`fatal` a Crashlytics o Sentry
/// (p. ej. `FirebaseCrashlytics.instance.recordError(...)`) sin cambiar el
/// contrato [AppLogger] ni los call sites en el resto de la app.
class ConsoleAppLogger implements AppLogger {
  ConsoleAppLogger({Logger? logger})
    : _logger =
          logger ??
          Logger(printer: PrettyPrinter(methodCount: 1, errorMethodCount: 5));

  final Logger _logger;

  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.d(message, error: error, stackTrace: stackTrace);

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.i(message, error: error, stackTrace: stackTrace);

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.w(message, error: error, stackTrace: stackTrace);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.e(message, error: error, stackTrace: stackTrace);

  @override
  void fatal(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.f(message, error: error, stackTrace: stackTrace);
}
