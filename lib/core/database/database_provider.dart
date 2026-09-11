import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/app_database.dart';

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
  final database = AppDatabase.open();
  ref.onDispose(database.close);
  return database;
});
