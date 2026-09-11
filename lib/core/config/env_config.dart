import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/platform_base_url.dart';

/// Configuración de entorno resuelta en el arranque de cada entry point
/// (`main_dev.dart`, `main_staging.dart`, `main_prod.dart`).
///
/// El valor de `apiBaseUrl` puede sobreescribirse en tiempo de build con
/// `--dart-define=API_BASE_URL=https://...` sin tocar el código fuente.
class EnvConfig {
  const EnvConfig._({
    required this.flavor,
    required this.apiBaseUrl,
    required this.appName,
    required this.telemetryDsn,
  });

  factory EnvConfig._resolve(AppFlavor flavor) {
    return EnvConfig._(
      flavor: flavor,
      apiBaseUrl: _apiBaseUrlOverride.isNotEmpty
          ? _apiBaseUrlOverride
          : _defaultApiBaseUrlFor(flavor),
      appName: _appNameFor(flavor),
      telemetryDsn: _telemetryDsn,
    );
  }

  static const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  // Sin valor por defecto a propósito: el DSN de Sentry no es secreto (va
  // en el bundle del cliente igual), pero sí es específico de cada proyecto
  // de Sentry — se inyecta en build/CI con
  // `--dart-define=TELEMETRY_DSN=https://...` para staging/prod. Vacío acá
  // significa "reporte remoto desactivado", lo mismo que en dev.
  static const _telemetryDsn = String.fromEnvironment('TELEMETRY_DSN');

  static EnvConfig? _instance;

  final AppFlavor flavor;
  final String apiBaseUrl;
  final String appName;
  final String telemetryDsn;

  // Accede al singleton ya resuelto; no es una fábrica de instancias nuevas,
  // por eso se queda como getter y no como constructor.
  // ignore: prefer_constructors_over_static_methods
  static EnvConfig get current {
    final instance = _instance;
    assert(
      instance != null,
      'EnvConfig.initialize() debe llamarse antes de runApp(). '
      'Usa uno de los entry points main_dev.dart / main_staging.dart / main_prod.dart.',
    );
    return instance ?? EnvConfig._resolve(AppFlavor.dev);
  }

  static void initialize(AppFlavor flavor) {
    _instance = EnvConfig._resolve(flavor);
  }

  static String _defaultApiBaseUrlFor(AppFlavor flavor) {
    return switch (flavor) {
      // dev apunta al mock server local (`mock_server/`), no a un host
      // fijo: la URL depende de la plataforma (ver platform_base_url.dart).
      AppFlavor.dev => resolveLocalBaseUrl(),
      AppFlavor.staging => 'https://staging.api.cristoeselsalvador.org',
      AppFlavor.prod => 'https://api.cristoeselsalvador.org',
    };
  }

  static String _appNameFor(AppFlavor flavor) {
    return switch (flavor) {
      AppFlavor.dev => 'Sinapsis (Dev)',
      AppFlavor.staging => 'Sinapsis (Staging)',
      AppFlavor.prod => 'Sinapsis',
    };
  }
}
