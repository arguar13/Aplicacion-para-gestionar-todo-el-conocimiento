import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:cristo_es_el_salvador/core/logging/console_app_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Se sobreescribe en `bootstrap()` con la instancia creada antes de
/// `runApp()`, para poder capturar errores de arranque con el mismo logger.
final appLoggerProvider = Provider<AppLogger>((ref) => ConsoleAppLogger());
