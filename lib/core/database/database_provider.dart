import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/device_identity.dart';

/// Quién es esta instalación de la app (F11).
///
/// Se resuelve una sola vez en `bootstrap()` —leerla de las preferencias puede
/// tener que crearla, y eso es async— y se sobreescribe ahí. Si algo la lee
/// sin pasar por ese override (un test que se olvidó), falla fuerte: una base
/// abierta sin identidad firmaría sus cambios con un dispositivo inventado.
final deviceIdentityProvider = Provider<DeviceIdentity>((ref) {
  throw UnimplementedError(
    'deviceIdentityProvider debe sobreescribirse en bootstrap() '
    '(o en el test) antes de leerlo.',
  );
});

/// La base de datos de la app, una sola para todo el proceso.
///
/// Deliberadamente NO autoDispose: abrir y cerrar el archivo de SQLite cada
/// vez que una pantalla se desmonta sería costoso y, peor, cortaría los
/// streams de \`watch\` que alimentan las listas abiertas.
///
/// El \`onDispose\` cierra la conexión cuando el contenedor de Riverpod se
/// destruye —al terminar la app, o al final de cada test que use uno propio—
/// para no dejar el archivo tomado.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.open(
    deviceId: ref.watch(deviceIdentityProvider).id,
  );
  ref.onDispose(database.close);
  return database;
});
