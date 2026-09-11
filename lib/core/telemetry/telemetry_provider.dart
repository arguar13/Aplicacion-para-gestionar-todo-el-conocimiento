import 'package:cristo_es_el_salvador/core/logging/logger_provider.dart';
import 'package:cristo_es_el_salvador/core/telemetry/sentry_telemetry_service.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Se sobreescribe en `bootstrap()` con la instancia ya inicializada (y con
/// el DSN/flavor reales) antes de `runApp()`. El default de acá nunca
/// reporta nada remoto (`enableRemoteReporting: false`) — es lo que corren
/// los tests y cualquier árbol de widgets que no la sobreescriba a propósito.
final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  return SentryTelemetryService(
    logger: ref.watch(appLoggerProvider),
    enableRemoteReporting: false,
    dsn: '',
    environment: 'test',
  );
});
