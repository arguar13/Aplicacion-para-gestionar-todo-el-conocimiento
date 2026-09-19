import '../generated_migrations/schema.dart';

/// La versión con la que las pruebas de migración validan la forma FINAL de
/// la base: el snapshot más reciente.
///
/// `SchemaVerifier.migrateAndValidate` compara el esquema al que llegó la
/// base contra el snapshot de la versión que se le pasa, y `AppDatabase`
/// siempre migra hasta su propio `schemaVersion`. Por eso el número que hay que
/// pasarle no es la versión que da nombre a cada archivo de prueba sino la
/// última con snapshot —una versión sin cambio de forma, como la 14, no tiene
/// snapshot y la última sigue siendo la que vale—. Escribirlo a mano en cada
/// prueba obligaba a tocarlas todas cada vez que el esquema cambia de forma.
final int latestSchemaSnapshot = GeneratedHelper.versions.last;
