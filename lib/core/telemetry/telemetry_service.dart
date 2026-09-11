/// Contrato de observabilidad de la app. Cualquier error no manejado
/// (`FlutterError.onError`, `PlatformDispatcher.onError`, la zona de
/// `runZonedGuarded` en `bootstrap.dart`) y cualquier excepción inesperada
/// atrapada en una capa `data` pasa por acá antes de llegar —o no— a un
/// proveedor externo (Sentry/Crashlytics). Ningún feature debe importar el
/// SDK del proveedor directamente: siempre a través de esta interfaz.
abstract interface class TelemetryService {
  /// Debe llamarse una sola vez, antes de `runApp()`. La implementación
  /// decide si esto abre una conexión real con el proveedor externo (p. ej.
  /// nunca en `kDebugMode`) o se queda en un no-op local.
  Future<void> init();

  /// Registra una excepción. Nunca debe lanzar: un fallo al reportar un
  /// error no puede convertirse en un segundo error sin manejar. La
  /// implementación decide si, además de loguearla localmente, la envía al
  /// proveedor externo.
  ///
  /// [hint] es una nota corta para diferenciar el origen del reporte (p.
  /// ej. `'FlutterError.onError'` vs. un catch-all de un repositorio); no
  /// debe contener datos del usuario.
  void recordError(dynamic exception, StackTrace? stackTrace, {String? hint});

  /// Asocia el usuario autenticado a los próximos reportes — únicamente su
  /// id interno, nunca email, nombre u otro dato personal. Pasar `null`
  /// (p. ej. al cerrar sesión) borra la asociación.
  void setUserContext(String? userId);
}
