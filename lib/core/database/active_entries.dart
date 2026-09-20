/// Los elementos VIVOS: los que no están en la papelera (F11).
///
/// Borrar un elemento no lo saca de la base: le pone `deleted_at`, y queda ahí
/// hasta que se lo restaure o se vacíe la papelera. Por eso TODA lectura que
/// muestre elementos, o que los use para calcular algo —la lista, la búsqueda,
/// la salud, la línea de tiempo, los vínculos, el grafo, las sugerencias, las
/// tarjetas por vencer— tiene que dejar afuera los que tienen esa marca. Un
/// elemento en la papelera que se sigue viendo, o que se sigue proponiendo como
/// duplicado, es un borrado que no se cumplió.
///
/// Este archivo es el único lugar que dice qué es «vivo»; una prueba recorre
/// `lib` y falla si un archivo lee `item` sin nombrarlo (o sin estar en su
/// lista, con el motivo).
library;

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';

/// La condición SQL de un elemento vivo, para las consultas escritas a mano
/// donde la tabla se llama `item`.
const kActiveItemSql = 'item.deleted_at IS NULL';

/// Lo mismo cuando la tabla `item` tiene otro alias.
String activeItemSql(String alias) => '$alias.deleted_at IS NULL';

/// El índice de lo que está en la papelera: solo las filas de `item` con
/// `deleted_at`.
///
/// PARCIAL a propósito. Un índice común sobre `deleted_at` tendría diez mil
/// entradas, todas nulas, y SQLite —que sin estadísticas cree que preguntar por
/// una igualdad es selectivo— lo usaría para `deleted_at IS NULL`: recorrería
/// el índice entero y volvería a la tabla fila por fila, en vez de buscar los
/// elementos por su clave. Pasó: pedir doscientos elementos por id pasó de 2,8
/// a 9,3 ms, y las búsquedas ganaron entre 10 y 17 ms. Un índice parcial solo
/// sirve para `deleted_at IS NOT NULL` —que es lo que pregunta la papelera— y
/// tiene tantas entradas como elementos borrados: casi ninguna.
const createTrashIndex =
    'CREATE INDEX IF NOT EXISTS idx_item_trashed ON item(deleted_at) '
    'WHERE deleted_at IS NOT NULL';

/// El índice común sobre `deleted_at` que tuvo el esquema v20 mientras se
/// escribía y que [createTrashIndex] reemplaza: se quita si una base lo trae.
const dropSupersededTrashIndex =
    'DROP INDEX IF EXISTS idx_knowledge_entries_deleted_at';

/// La condición SQL para un `WHERE` sobre el índice de chunks (`chunk_search`)
/// que corta en los mejores N: deja afuera los chunks de lo que está en la
/// papelera ANTES del corte.
///
/// Filtrar después no alcanza. La búsqueda por relevancia pide los N mejores
/// chunks al índice y recién entonces los une con `item`: si la papelera
/// acumulara muchas coincidencias —alguien borró todo lo que tenía sobre Roma—
/// ocuparían los N lugares y la búsqueda no encontraría nada de lo que sí
/// sigue guardado, que es el peor fallo de una búsqueda. Con esta condición el
/// corte se hace sobre lo vivo.
///
/// Cuesta lo que cuesta la papelera —se arma una sola vez el conjunto de sus
/// chunks—, no lo que cuesta la bóveda. Se recorre desde `item` por
/// `idx_item_trashed` y se llega a los chunks por su índice de `item_id`: nunca
/// un recorrido de `item` ni de `chunks`.
const kChunkOutsideTrashSql =
    'chunk_search.rowid NOT IN ( '
    'SELECT tc.row_key FROM chunks tc WHERE tc.item_id IN ( '
    'SELECT ti.id FROM item ti WHERE ti.deleted_at IS NOT NULL))';

extension ActiveEntries on $KnowledgeEntriesTable {
  /// El predicado de drift: el elemento no está en la papelera.
  Expression<bool> get isActive => deletedAt.isNull();
}

/// Si el elemento al que apunta [itemId] está vivo: para las tablas que
/// cuelgan de un elemento —tarjetas, enlaces, vínculos, chunks— y no lo unen a
/// `item`.
///
/// Se pregunta por lo que NO está en la papelera —`NOT IN` de los elementos
/// borrados— y no por lo que está vivo (`IN` de todos los demás): la papelera
/// son unos pocos elementos y la bóveda, diez mil. Armar el conjunto de los
/// vivos en cada consulta costaría lo que cuesta la bóveda aunque la consulta
/// mire una docena de filas; el de la papelera cuesta lo que cuesta la
/// papelera, y por fila es una búsqueda en un conjunto que casi siempre está
/// vacío. Con miles de chunks o de vínculos por recorrer es la diferencia entre
/// un filtro que no se nota y uno que sí.
Expression<bool> itemIsActive(AppDatabase db, GeneratedColumn<String> itemId) {
  final entries = db.knowledgeEntries;
  return itemId.isNotInQuery(
    db.selectOnly(entries)
      ..addColumns([entries.id])
      ..where(entries.deletedAt.isNotNull()),
  );
}

/// Los ids de todo lo que está en la papelera.
///
/// Para lo que no se puede filtrar en SQL porque el elemento está DENTRO de un
/// JSON —las sugerencias guardan en su carga útil a qué otro elemento apuntan—:
/// se traen unos pocos ids y se descartan en Dart.
Future<Set<String>> trashedItemIds(AppDatabase db) async {
  final entries = db.knowledgeEntries;
  final rows =
      await (db.selectOnly(entries)
            ..addColumns([entries.id])
            ..where(entries.deletedAt.isNotNull()))
          .get();
  return {for (final row in rows) row.read(entries.id)!};
}
