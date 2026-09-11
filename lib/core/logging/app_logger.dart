/// Contrato de logging de la app. Ningún feature debe usar `print()` ni
/// `debugPrint()` directamente: siempre se inyecta un [AppLogger].
abstract interface class AppLogger {
  void debug(String message, [Object? error, StackTrace? stackTrace]);
  void info(String message, [Object? error, StackTrace? stackTrace]);
  void warning(String message, [Object? error, StackTrace? stackTrace]);
  void error(String message, [Object? error, StackTrace? stackTrace]);
  void fatal(String message, [Object? error, StackTrace? stackTrace]);
}
