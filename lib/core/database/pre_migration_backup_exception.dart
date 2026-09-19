/// No se pudo respaldar la base antes de migrarla, así que NO se migra.
///
/// Una migración sin red de seguridad es exactamente lo que el respaldo
/// existe para evitar: ante la duda, se corta acá —la app avisa que no
/// pudo abrir la bóveda— en vez de arriesgar datos.
///
/// Vive en su propio archivo porque las dos implementaciones del respaldo
/// (nativa y web) tienen que compartirla: quien la atrape no debería
/// depender de cuál se compiló.
class PreMigrationBackupException implements Exception {
  const PreMigrationBackupException(this.message, this.cause);

  final String message;
  final Object cause;

  @override
  String toString() => 'PreMigrationBackupException: $message ($cause)';
}
