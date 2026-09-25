import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';

/// Suspende los triggers de `item_search`/`chunk_search` mientras dura
/// [body], y repuebla los índices al terminar (F19, 19.1/19.4, decisión A).
///
/// Genérica y de bajo nivel a propósito: la usa tanto
/// `KnowledgeEntryWriter.runBulk` —que además difiere `field_version`—
/// como `VaultMerger` alrededor de `DerivedRebuild`, que no pasa por el
/// escritor único y por eso no puede usar `runBulk`. Los dos necesitan lo
/// mismo del índice de texto y nada más.
///
/// Con los triggers reales suspendidos, escribir `item`/`renditions`
/// durante [body] no toca `item_search`: queda desactualizado a
/// propósito. Cómo se repuebla al cerrar depende de [touchedItemIds]:
///
/// - `null` (el default): se rehace ENTERO —se tira la tabla y se rearma
///   desde `item`, mismo camino que ya usa
///   `AppDatabase._rebuildItemSearchIndex` en una migración—. Correcto
///   siempre, y lo que conviene cuando [body] toca una fracción grande de
///   la bóveda —`VaultMerger` trayendo miles de elementos a una bóveda
///   vacía, donde el lote y la bóveda son casi lo mismo—.
/// - una función que, llamada DESPUÉS de [body], da los ids que cambiaron:
///   se repuebla solo esas filas —un `DELETE`+`INSERT` acotado, no toda la
///   tabla—. Es lo que usa `KnowledgeEntryWriter.runBulk`, que ya sabe
///   por `field_version` cuáles tocó: medido en un lote chico contra una
///   bóveda de miles de elementos, rehacer la tabla ENTERA por cada
///   importación —por chica que sea— costaba más de lo que ahorraba
///   suspender los triggers (F19, 19.4, hallazgo real de un benchmark, no
///   supuesto).
///
/// [chunks] —en `true` por defecto— decide si `chunk_search` también se
/// suspende y se rehace ENTERO con el comando `rebuild` de FTS5 —no hay
/// forma acotada de pedirle a FTS5 que rehaga solo ciertas filas de
/// contenido externo—. En `false`, sus triggers reales de siempre siguen
/// activos durante todo [body]: correcto para un lote que nunca escribe
/// `chunks` —`KnowledgeEntryWriter` no lo hace, ver su propio doc
/// comment—, y muchísimo más barato que suspenderlo para no tocarlo: el
/// `rebuild` de FTS5 recorre la tabla de chunks ENTERA sin importar
/// cuántos cambiaron, cientos de miles de filas en una bóveda real.
///
/// Si [body] falla, los triggers se recrean y los índices se repueblan
/// IGUAL antes de propagar el error: un índice de texto que queda sin sus
/// triggers, o desincronizado, es peor que el fallo original —una
/// búsqueda que no encuentra algo que sí está guardado, en silencio—.
Future<T> withSuspendedSearchIndexes<T>(
  AppDatabase db,
  Future<T> Function() body, {
  Iterable<String> Function()? touchedItemIds,
  bool chunks = true,
}) async {
  for (final name in searchTriggerNames) {
    await db.customStatement('DROP TRIGGER IF EXISTS $name');
  }
  if (chunks) {
    for (final trigger in chunkSearchTriggers) {
      final name = _triggerNameOf(trigger);
      await db.customStatement('DROP TRIGGER IF EXISTS $name');
    }
  }
  try {
    return await body();
  } finally {
    final scope = touchedItemIds?.call().toList();
    if (scope == null) {
      await db.customStatement('DROP TABLE IF EXISTS item_search');
      await db.customStatement(createSearchTable);
    } else {
      // De a tramos: por debajo del tope de parámetros de SQLite, mismo
      // criterio que `KnowledgeEntryWriter._idsPerQuery`.
      for (var start = 0; start < scope.length; start += _idsPerQuery) {
        final slice = scope.skip(start).take(_idsPerQuery).toList();
        final placeholders = List.filled(slice.length, '?').join(',');
        await db.customStatement(
          'DELETE FROM item_search WHERE item_id IN ($placeholders)',
          slice,
        );
      }
    }
    for (final trigger in searchTriggers) {
      await db.customStatement(trigger);
    }
    if (scope == null) {
      await db.customStatement(populateItemSearch);
    } else {
      for (var start = 0; start < scope.length; start += _idsPerQuery) {
        final slice = scope.skip(start).take(_idsPerQuery).toList();
        final placeholders = List.filled(slice.length, '?').join(',');
        await db.customStatement(populateItemSearchScoped(placeholders), slice);
      }
    }
    if (chunks) {
      for (final trigger in chunkSearchTriggers) {
        await db.customStatement(trigger);
      }
      await db.customStatement(rebuildChunkSearch);
    }
  }
}

/// Cuántos ids entran en una sola consulta: por debajo del tope de
/// parámetros de SQLite. Mismo valor que `KnowledgeEntryWriter._idsPerQuery`
/// —no hay de dónde importarlo compartido sin crear una dependencia nueva
/// entre los dos archivos por una sola constante—.
const _idsPerQuery = 400;

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
