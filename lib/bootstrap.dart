import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/app.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/device_identity.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/logging/console_app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/telemetry/sentry_telemetry_service.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';

/// Arranque compartido por los 3 entry points de flavor. Centraliza los
/// tres puntos de captura de errores no manejados — `FlutterError.onError`
/// (errores del framework de widgets), `PlatformDispatcher.instance.onError`
/// (errores de plataforma/async que escapan del ciclo de vida normal) y la
/// zona de `runZonedGuarded` (red de seguridad final, cualquier excepción
/// async no atrapada en ningún otro lado) — y los reenvía todos a
/// `TelemetryService.recordError`. Es la única fuente de verdad de qué pasa
/// con un error no manejado: `SentryTelemetryService.init()` deliberadamente
/// no usa el `appRunner` de `SentryFlutter.init` para no depender de cómo el
/// SDK encadena sus propios manejadores por debajo.
Future<void> bootstrap() async {
  final logger = ConsoleAppLogger();
  final telemetry = SentryTelemetryService(
    logger: logger,
    // `kDebugMode` es la señal de "estoy corriendo en la máquina de un
    // dev" — ahí el reporte remoto queda apagado sin importar el flavor,
    // así un `flutter run` local nunca contamina el proyecto de Sentry.
    enableRemoteReporting: !kDebugMode,
    dsn: EnvConfig.current.telemetryDsn,
    environment: EnvConfig.current.flavor.name,
  );

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await telemetry.init();

      FlutterError.onError = (details) {
        logger.error(
          details.exceptionAsString(),
          details.exception,
          details.stack,
        );
        telemetry.recordError(
          details.exception,
          details.stack,
          hint: 'FlutterError.onError',
        );
      };

      PlatformDispatcher.instance.onError = (error, stackTrace) {
        logger.fatal('Unhandled platform error', error, stackTrace);
        telemetry.recordError(
          error,
          stackTrace,
          hint: 'PlatformDispatcher.onError',
        );
        // `true` = ya está manejado, no debe además tumbar la app.
        return true;
      };

      // `SharedPreferences.getInstance()` es async: se resuelve acá, una
      // sola vez, para que `ThemeModeNotifier` pueda leer/guardar la
      // preferencia de tema de forma síncrona el resto del tiempo.
      final prefs = await SharedPreferences.getInstance();
      // Quién es esta instalación: lo que firma cada cambio que se guarda.
      final device = await DeviceIdentity.loadOrCreate(prefs);

      // Requisito del propio paquete: ninguna otra API de `flutter_gemma`
      // —`installModel`, `hasActiveModel`, `getActiveModel`— funciona sin
      // esto. Sin inicializar, cualquier llamada revienta con un
      // `StateError` interno del paquete que no tiene nada que ver con la
      // red ni con el token, y termina mostrándose como el mismo error
      // genérico de "no se pudo descargar" sin importar la causa real —el
      // bug real detrás de una falla que se probó en un dispositivo real y
      // persistía con cualquier token. `LiteRtLmEngine` es el motor que
      // entiende el formato `.litertlm` que usa Gemma acá (ver la decisión
      // 20 en docs/arquitectura.md); sin registrarlo, `installModel`
      // tampoco sabría qué hacer con la descarga.
      await FlutterGemma.initialize(inferenceEngines: [const LiteRtLmEngine()]);

      runApp(
        ProviderScope(
          overrides: [
            appLoggerProvider.overrideWithValue(logger),
            telemetryServiceProvider.overrideWithValue(telemetry),
            sharedPreferencesProvider.overrideWithValue(prefs),
            deviceIdentityProvider.overrideWithValue(device),
          ],
          child: const App(),
        ),
      );
    },
    (error, stackTrace) {
      logger.fatal('Uncaught zone error', error, stackTrace);
      telemetry.recordError(error, stackTrace, hint: 'runZonedGuarded');
    },
  );
}
