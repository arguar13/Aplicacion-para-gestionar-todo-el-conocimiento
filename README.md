# Cristo es El Salvador

App multiplataforma (Web, Android, iOS) construida con Flutter, Clean
Architecture feature-first y Riverpod.

## Entorno (ya configurado en esta máquina)

- Flutter 3.47.2 (stable) instalado en `C:\src\flutter`, agregado al PATH
  del usuario.
- Carpetas de plataforma (`android/`, `web/`, `ios/`) generadas.
- Dependencias instaladas y código generado (`*.freezed.dart`) al día.
- Android SDK + cmdline-tools + licencias listos (usa el Android Studio /
  emuladores que ya tenías instalados).

Si clonas este repo en otra máquina, instala Flutter
(https://docs.flutter.dev/get-started/install), corre `flutter doctor`,
y luego:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Nota: compilar para Android en esta máquina (Avast)

Este equipo tiene Avast, que intercepta HTTPS instalando su propio
certificado raíz en Windows. `curl`/`git` confían en él (usan el almacén
de Windows), pero el JDK de Android Studio usa su propio almacén
(`cacerts`) y no lo tiene por defecto, así que `flutter build apk` /
`flutter run` en Android pueden fallar al descargar Gradle con
`PKIX path building failed` si Avast está activo con el escudo Web/Mail
Shield habilitado. Web no se ve afectado.

Confirmado: con Avast desactivado, `flutter build apk --debug` compila
sin problema (APK en `build/app/outputs/flutter-apk/app-debug.apk`).
Si vuelves a activar Avast y el build de Android falla con ese error,
dos opciones:

- Desactivar el escudo Web/Mail Shield de Avast mientras compilas, o
- Importar el certificado raíz de Avast (que Windows ya considera de
  confianza) al `cacerts` del JDK, una sola vez, en PowerShell **como
  Administrador**:

```powershell
$cert = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match 'Avast' } | Select-Object -First 1
Export-Certificate -Cert $cert -FilePath "$env:TEMP\avast-root.cer" -Type CERT
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -importcert -alias avast-web-mail-shield -cacerts -storepass changeit -file "$env:TEMP\avast-root.cer" -noprompt
```

## Mock server (backend local para el flavor dev)

`main_dev.dart` habla con un backend local (`json-server`) en vez de un
host remoto. Antes de correr la app en dev:

```bash
cd mock_server
npm install
npm start          # sirve en http://localhost:3000
```

Detalles, endpoints y usuarios de prueba en
[mock_server/README.md](mock_server/README.md). La URL se resuelve sola
por plataforma (`lib/core/config/platform_base_url.dart`): Android
emulator usa `10.0.2.2`, iOS/Web/desktop usan `localhost`.

## Correr la app por flavor

```bash
flutter run -t lib/main_dev.dart          # -d chrome para Web
flutter run -t lib/main_staging.dart
flutter run -t lib/main_prod.dart
```

`lib/main.dart` es un alias de `main_dev.dart` para `flutter run` sin
`--target`. La URL base de la API de cada flavor puede sobreescribirse sin
tocar código con:

```bash
flutter run -t lib/main_dev.dart --dart-define=API_BASE_URL=https://otra-url
```

## Arquitectura

- **Feature-first + Clean Architecture**: cada módulo en `lib/features/`
  separa `presentation` / `domain` / `data`. Ver
  [lib/features/README.md](lib/features/README.md).
- **Estado y DI**: Riverpod (`flutter_riverpod`). Los providers globales
  viven en `lib/core/**` y `lib/app/**`.
- **Routing**: `go_router` centralizado en
  [lib/app/router/app_router.dart](lib/app/router/app_router.dart).
- **Red**: `Dio` configurado en
  [lib/core/network/network_providers.dart](lib/core/network/network_providers.dart)
  con interceptores de auth, logging y manejo global de errores.
- **Modelos**: `freezed` + `json_serializable` para entidades y DTOs.
- **Logging**: `AppLogger` (interfaz) /
  [ConsoleAppLogger](lib/core/logging/console_app_logger.dart) (impl) — nunca
  usar `print()`. Punto de extensión listo para Crashlytics/Sentry.
- **Entornos**: `AppFlavor` + `EnvConfig`
  ([lib/core/config](lib/core/config)), inicializados desde
  `main_dev.dart` / `main_staging.dart` / `main_prod.dart`.
- **Diseño**: `AppColors`/`AppTypography`/`AppTheme` en
  [lib/core/design](lib/core/design) — modo claro/oscuro/sistema
  persistido con `ThemeModeNotifier`.
- **i18n**: Español e inglés vía `.arb` en [lib/l10n](lib/l10n)
  (`flutter gen-l10n`, código generado en `lib/l10n/generated/`, no se
  versiona). `LocaleNotifier` en
  [lib/core/i18n](lib/core/i18n) persiste el idioma elegido; texto en
  pantallas siempre vía `AppLocalizations.of(context)!.xxx`, nunca
  strings sueltos.
- **Observabilidad**: `TelemetryService` ([lib/core/telemetry](lib/core/telemetry))
  abstrae al proveedor externo (`SentryTelemetryService`, con
  `sentry_flutter`); ver la sección dedicada más abajo.

## Observabilidad y manejo de errores

Ningún error no manejado debe crashear la app en silencio, y los que sí
importan deben llegar a un servicio de telemetría en producción.

- **`TelemetryService`** ([lib/core/telemetry/telemetry_service.dart](lib/core/telemetry/telemetry_service.dart)):
  interfaz (`init`, `recordError`, `setUserContext`) que abstrae al
  proveedor externo — ningún feature importa el SDK de Sentry
  directamente. `SentryTelemetryService` es la implementación real; en
  `kDebugMode`, o sin `TELEMETRY_DSN` configurado, `enableRemoteReporting`
  queda en `false` y todo se queda en el logger local (`AppLogger`), sin
  abrir conexión con Sentry.
- **Captura global** ([lib/bootstrap.dart](lib/bootstrap.dart)): un único
  punto conecta `FlutterError.onError`, `PlatformDispatcher.instance.onError`
  y la zona de `runZonedGuarded` a `TelemetryService.recordError`. Es la
  única fuente de verdad de qué pasa con un error no manejado —
  `SentryTelemetryService.init()` no usa el `appRunner` de
  `SentryFlutter.init` para no depender de cómo el SDK encadena sus
  propios manejadores por debajo.
- **Feedback global en la UI**: `GlobalErrorInterceptor`
  ([lib/core/network/interceptors/error_interceptor.dart](lib/core/network/interceptors/error_interceptor.dart))
  mapea cada `DioException` a una excepción de dominio y la publica en
  `GlobalErrorNotifier`
  ([lib/core/error/global_error_bus.dart](lib/core/error/global_error_bus.dart));
  `GlobalErrorListener` ([lib/app/global_error_listener.dart](lib/app/global_error_listener.dart)),
  montado en el `builder` de `MaterialApp.router`, lo traduce a un
  SnackBar amigable sin importar qué pantalla esté activa — así una
  petición que falla nunca deja a la app colgada en un loading infinito
  sin explicación. Solo los fallos que ameritan investigarse
  (`ServerException`, 5xx/respuesta inesperada) además se reportan a
  telemetría; una `NetworkException` (sin conexión) o un 401 esperado no,
  para no generar ruido.
- **Privacidad**: `setUserContext` solo admite un id de usuario — nunca
  email, nombre ni otro dato personal — y se limpia (`null`) en
  `SessionController.logout()`. `sendDefaultPii` queda en `false` en la
  config de Sentry.
- **DSN**: no hay uno por defecto. Se inyecta en build/CI con
  `--dart-define=TELEMETRY_DSN=https://...` para staging/prod (ver
  `EnvConfig.telemetryDsn`); en dev queda vacío = reporte remoto apagado.

## Calidad

```bash
flutter analyze                          # 0 issues (very_good_analysis)
dart format --set-exit-if-changed lib test
flutter test --coverage
dart run build_runner build --delete-conflicting-outputs   # tras tocar freezed/json_serializable
flutter gen-l10n                                            # tras tocar los .arb
```

Estado actual: `flutter analyze` sin incidencias, `flutter test` en
verde, ~82% de cobertura de línea (código de `lib/l10n/generated/`
excluido del cálculo, igual que el resto del código generado),
`flutter build web` compila y corre en Chrome contra el mock server real,
`flutter build apk --debug` compila y genera `app-debug.apk`.

## CI (GitHub Actions)

[.github/workflows/ci.yml](.github/workflows/ci.yml) corre en cada push a
`main` y en cada Pull Request hacia `main`/`develop`: `pub get` →
`build_runner` → formato → `analyze` → tests con cobertura → gate de
cobertura mínima (80%). Ver la sección "Branch Protection Rules" más
abajo para bloquear merges si el pipeline falla.
