import 'package:sinapsis/core/config/app_flavor.dart';

/// Configuración de entorno resuelta en el arranque de cada entry point
/// (`main_dev.dart`, `main_staging.dart`, `main_prod.dart`).
///
/// Ya no incluye una `apiBaseUrl`: Sinapsis procesa y guarda todo en el
/// dispositivo, así que no hay ningún servidor propio al que apuntar. Las
/// descargas de contenido usan la URL absoluta de cada fuente (ver
/// `core/network/network_providers.dart`).
class EnvConfig {
  const EnvConfig._({
    required this.flavor,
    required this.appName,
    required this.telemetryDsn,
  });

  factory EnvConfig._resolve(AppFlavor flavor) {
    return EnvConfig._(
      flavor: flavor,
      appName: _appNameFor(flavor),
      telemetryDsn: _telemetryDsn,
    );
  }

  // Sin valor por defecto a propósito: el DSN de Sentry no es secreto (va
  // en el bundle del cliente igual), pero sí es específico de cada proyecto
  // de Sentry — se inyecta en build/CI con
  // `--dart-define=TELEMETRY_DSN=https://...` para staging/prod. Vacío acá
  // significa "reporte remoto desactivado", lo mismo que en dev.
  static const _telemetryDsn = String.fromEnvironment('TELEMETRY_DSN');

  static EnvConfig? _instance;

  final AppFlavor flavor;
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

  static String _appNameFor(AppFlavor flavor) {
    return switch (flavor) {
      AppFlavor.dev => 'Sinapsis Dev',
      AppFlavor.staging => 'Sinapsis Staging',
      AppFlavor.prod => 'Sinapsis',
    };
  }
}
