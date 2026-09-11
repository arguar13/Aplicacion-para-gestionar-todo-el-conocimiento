import 'dart:async';

import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Implementación de [TelemetryService] con `sentry_flutter`.
///
/// `enableRemoteReporting` es lo que separa dev de producción: en
/// `kDebugMode` (o cuando no hay DSN configurado) debe venir en `false` —
/// [init] entonces nunca llama a `SentryFlutter.init` (no abre conexión con
/// Sentry) y [recordError]/[setUserContext] se quedan en el log local. Así
/// ningún build de desarrollo de ningún miembro del equipo termina
/// contaminando el proyecto de Sentry con ruido.
///
/// Privacidad: [setUserContext] solo admite un id de usuario, nunca email ni
/// nombre (ver la restricción de la firma en [TelemetryService]), y
/// `sendDefaultPii` queda deliberadamente en `false` para que el SDK no
/// adjunte automáticamente IP u otros datos del dispositivo a cada evento.
class SentryTelemetryService implements TelemetryService {
  SentryTelemetryService({
    required AppLogger logger,
    required bool enableRemoteReporting,
    required String dsn,
    required String environment,
  }) : _logger = logger,
       _dsn = dsn,
       _environment = environment,
       // Sin DSN no hay a dónde reportar, sin importar lo que pida el
       // caller: falla cerrado (se queda en modo solo-consola) en vez de
       // arrancar `SentryFlutter.init` con una config inválida.
       _enableRemoteReporting = enableRemoteReporting && dsn.isNotEmpty;

  final AppLogger _logger;
  final String _dsn;
  final String _environment;
  final bool _enableRemoteReporting;

  @override
  Future<void> init() async {
    if (!_enableRemoteReporting) {
      _logger.info(
        'TelemetryService: reporte remoto desactivado '
        '(debug o sin TELEMETRY_DSN); los errores solo se loguean localmente.',
      );
      return;
    }

    await SentryFlutter.init((options) {
      options
        ..dsn = _dsn
        ..environment = _environment
        // No se manda IP/dispositivo por defecto: lo único que este
        // servicio adjunta a un evento es lo que `recordError`/
        // `setUserContext` le pasan explícitamente, ambos ya filtrados de
        // datos sensibles antes de llegar acá (ver
        // AuthRepositoryImpl/DashboardRepositoryImpl y el docstring de
        // setUserContext).
        ..sendDefaultPii = false;
    });
  }

  @override
  void recordError(dynamic exception, StackTrace? stackTrace, {String? hint}) {
    // Local siempre, sin importar el entorno: es la garantía de "ningún
    // error crashea silenciosamente" incluso con el reporte remoto apagado.
    _logger.error(
      hint ?? 'Error capturado por TelemetryService',
      exception,
      stackTrace,
    );

    if (!_enableRemoteReporting) return;

    unawaited(
      Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        withScope: hint == null
            ? null
            : (scope) => scope.setTag('telemetry.hint', hint),
      ),
    );
  }

  @override
  void setUserContext(String? userId) {
    if (!_enableRemoteReporting) return;

    // `configureScope` devuelve `FutureOr<void>`, no un `Future<void>`
    // directo, así que se envuelve para poder pasarla a `unawaited` sin
    // asumir de qué tipo es en runtime.
    unawaited(
      Future.sync(
        () => Sentry.configureScope((scope) {
          scope.setUser(userId == null ? null : SentryUser(id: userId));
        }),
      ),
    );
  }
}
