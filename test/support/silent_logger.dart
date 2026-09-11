import 'package:sinapsis/core/logging/app_logger.dart';

/// Un registro que no escribe nada.
///
/// Las pruebas que ejercitan caminos de error hacen que la app registre lo
/// que pasó, y eso es correcto. Pero un test que además imprime media pantalla
/// de rastros por cada fallo esperado convierte la salida en ruido y esconde
/// los fallos de verdad.
class SilentLogger implements AppLogger {
  const SilentLogger();

  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void fatal(String message, [Object? error, StackTrace? stackTrace]) {}
}
