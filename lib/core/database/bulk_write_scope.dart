import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';

/// Suspende los triggers de `item_search`/`chunk_search` mientras dura
/// [body], y repuebla los dos índices de una sola vez al terminar (F19,
/// 19.1, decisión A).
///
/// Genérica y de bajo nivel a propósito: la usa tanto
/// `KnowledgeEntryWriter.runBulk` —que además difiere `field_version`—
/// como `VaultMerger` alrededor de `DerivedRebuild`, que no pasa por el
/// escritor único y por eso no puede usar `runBulk`. Los dos necesitan lo
/// mismo del índice de texto y nada más.
///
/// Con los triggers reales suspendidos, escribir `item`/`renditions`/
/// `chunks` durante [body] no toca `item_search`/`chunk_search`: quedan
/// desactualizados a propósito, y por eso `item_search` se rehace ENTERO
/// —se tira la tabla y se rearma desde `item`, mismo camino que ya usa
/// `AppDatabase._rebuildItemSearchIndex` en una migración— en vez de
/// confiar en que las filas tocadas por [body] alcancen para saber qué
/// actualizar. `chunk_search`, al ser de contenido externo, se arregla
/// solo con el comando `rebuild` de FTS5 —no hace falta tirar la tabla—.
///
/// Si [body] falla, los triggers se recrean y los dos índices se
/// repueblan IGUAL antes de propagar el error: un índice de texto que
/// queda sin sus triggers, o desincronizado, es peor que el fallo
/// original —una búsqueda que no encuentra algo que sí está guardado, en
/// silencio—.
Future<T> withSuspendedSearchIndexes<T>(
  AppDatabase db,
  Future<T> Function() body,
) async {
  for (final name in searchTriggerNames) {
    await db.customStatement('DROP TRIGGER IF EXISTS $name');
  }
  for (final trigger in chunkSearchTriggers) {
    final name = _triggerNameOf(trigger);
    await db.customStatement('DROP TRIGGER IF EXISTS $name');
  }
  try {
    return await body();
  } finally {
    await db.customStatement('DROP TABLE IF EXISTS item_search');
    await db.customStatement(createSearchTable);
    for (final trigger in searchTriggers) {
      await db.customStatement(trigger);
    }
    await db.customStatement(populateItemSearch);
    for (final trigger in chunkSearchTriggers) {
      await db.customStatement(trigger);
    }
    await db.customStatement(rebuildChunkSearch);
  }
}

/// El nombre de un trigger de `CREATE TRIGGER IF NOT EXISTS <nombre> ...`:
/// para no mantener una segunda lista de nombres de los de `chunks`,
/// paralela a `chunkSearchTriggers`, que ya trae el SQL completo.
String _triggerNameOf(String createTriggerSql) => createTriggerSql
    .trim()
    .split('\n')
    .first
    .replaceFirst('CREATE TRIGGER IF NOT EXISTS ', '')
    .split(' ')
    .first;
