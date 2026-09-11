import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/console_app_logger.dart';

/// Se sobreescribe en `bootstrap()` con la instancia creada antes de
/// `runApp()`, para poder capturar errores de arranque con el mismo logger.
final appLoggerProvider = Provider<AppLogger>((ref) => ConsoleAppLogger());
