import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';

/// Las consultas del Índice (F46, paso 2), escritas a mano: cada una dice qué
/// índice usa, y una prueba de escala —2.000 documentos y 300.000 entradas—
/// comprueba con `EXPLAIN QUERY PLAN` que ninguna recorre las tablas grandes
/// (`processed_headings`, `processed_parts`, `item`, `item_spaces`).
///
/// Todas parten de `processed_documents` —miles de filas, no cientos de
/// miles— o del índice de texto, y llegan a lo demás por clave. El orden de
/// los `CROSS JOIN` es a propósito: en SQLite fija el orden en que se recorren
/// las tablas, y sin él el planificador podía empezar por las asignaciones de
/// temas de toda la Biblioteca para quedarse con las de lo procesado.
///
/// Lo que está en la papelera queda afuera (`kActiveItemSql`).

/// Lo que el Índice lee: cualquier escritura en estas tablas puede cambiarlo.
/// Las partes, las copias del original y las imágenes también —no solo las
/// entradas—: lo que las cambia suelta o escribe entradas por un trigger, que
/// drift no ve, y es la escritura de ellas la que avisa.
List<TableInfo<dynamic, dynamic>> indexTables(AppDatabase db) => [
  db.processedHeadings,
  db.processedDocuments,
  db.processedParts,
  db.processedOriginals,
  db.processedImages,
  db.knowledgeEntries,
  db.itemSpaces,
  db.spaces,
];

/// Que el documento procesado `d` tenga la sección «Texto»: una búsqueda por
/// `idx_processed_parts_document`.
const _hasTextSql =
    'EXISTS (SELECT 1 FROM processed_parts tp '
    "WHERE tp.document_id = d.item_id AND tp.section = 'text')";

/// Que las entradas de texto del documento `d` estén escritas: una búsqueda
/// por `idx_processed_headings_document`.
const _indexedSql =
    'EXISTS (SELECT 1 FROM processed_headings ih '
    "WHERE ih.document_id = d.item_id AND ih.origin <> 'image')";

/// Que el documento procesado `d` sea del Índice: con texto o con imágenes. El
/// resumen, la síntesis, las palabras clave, las notas y los fragmentos no
/// cuentan: el Índice es de los documentos.
const _inIndexSql =
    '($_hasTextSql OR EXISTS (SELECT 1 FROM processed_images ii '
    'WHERE ii.document_id = d.item_id))';

/// Los documentos vivos del Índice, desde `processed_documents` y con su
/// elemento por clave. Se completa con un `AND …` y lo que siga.
const _liveIndexDocumentsSql = '''
FROM processed_documents d
CROSS JOIN item ON item.id = d.item_id
WHERE $kActiveItemSql AND $_inIndexSql''';

/// Los temas con cuántos documentos del Índice tienen, y en una fila con
/// `space_id` nulo cuántos no tienen ninguno: el primer nivel del árbol, en
/// una sola lectura. Cada documento va a sus temas por la clave de
/// `item_spaces`, y a cada tema por la suya.
const indexTopicsSql =
    '''
SELECT isp.space_id AS space_id, s.name AS name, COUNT(*) AS documents
FROM processed_documents d
CROSS JOIN item ON item.id = d.item_id
CROSS JOIN item_spaces isp ON isp.item_id = d.item_id
CROSS JOIN spaces s ON s.id = isp.space_id
WHERE $kActiveItemSql AND $_inIndexSql
GROUP BY isp.space_id
UNION ALL
SELECT NULL AS space_id, '' AS name, COUNT(*) AS documents
$_liveIndexDocumentsSql
  AND NOT EXISTS (SELECT 1 FROM item_spaces ui WHERE ui.item_id = d.item_id)
''';

/// Las columnas de una fila de `IndexDocument`: lo que se ve sin desplegarlo.
/// Los capítulos se cuentan en el índice de las entradas, que lleva el
/// origen —no vuelven a la tabla—; las imágenes, en el de la galería, que son
/// muchas menos.
const _documentColumnsSql =
    '''
SELECT d.item_id AS id,
       item.title AS title,
       d.source_kind AS source_kind,
       d.created_at AS created_at,
       (SELECT COUNT(*) FROM processed_headings ch
         WHERE ch.document_id = d.item_id
           AND ch.origin IN ('bookmark', 'textHeading', 'aiTitle'))
         AS chapters,
       (SELECT COUNT(*) FROM processed_images im
         WHERE im.document_id = d.item_id AND im.title IS NOT NULL) AS images,
       $_hasTextSql AS has_text,
       $_indexedSql AS indexed,
       (SELECT group_concat(ts.space_id, char(31)) FROM item_spaces ts
         WHERE ts.item_id = d.item_id) AS space_ids''';

/// El separador de los temas dentro de `space_ids`: el «separador de
/// unidades» (U+001F), el mismo `char(31)` de la consulta.
const indexSpaceIdSeparator = '\u001f';

/// Todos los documentos del Índice. El orden lo pone quien llama: el de los
/// títulos, sin acentos, no lo sabe SQLite.
const indexDocumentsSql =
    '''
$_documentColumnsSql
$_liveIndexDocumentsSql
''';

/// Los documentos del Índice del tema `?1`: cada documento procesado mira por
/// la clave de `item_spaces` si está en él —tantas búsquedas como documentos
/// procesados, nunca las asignaciones de la Biblioteca entera—.
const indexDocumentsOfTopicSql =
    '''
$_documentColumnsSql
$_liveIndexDocumentsSql
  AND EXISTS (SELECT 1 FROM item_spaces ws
               WHERE ws.item_id = d.item_id AND ws.space_id = ?1)
''';

/// Los documentos del Índice sin ningún tema.
const indexUntopicedDocumentsSql =
    '''
$_documentColumnsSql
$_liveIndexDocumentsSql
  AND NOT EXISTS (SELECT 1 FROM item_spaces ws WHERE ws.item_id = d.item_id)
''';

/// Las columnas de una entrada, con el alias [alias].
String indexEntryColumnsSql(String alias) =>
    '$alias.row_key AS row_key, $alias.document_id AS document_id, '
    '$alias.origin AS origin, $alias.level AS level, '
    '$alias.position AS position, $alias.title AS title, '
    '$alias.text_start AS text_start, $alias.text_end AS text_end, '
    '$alias.text_page AS text_page, $alias.pdf_page AS pdf_page, '
    '$alias.image_id AS image_id';

/// Las entradas de un documento —`?1`— en el orden del índice: su lugar y, a
/// la par, su clave. Sin ordenar nada aparte: el índice ya las trae así.
final indexEntriesSql =
    '''
SELECT ${indexEntryColumnsSql('h')}
FROM processed_headings h
WHERE h.document_id = ?1
ORDER BY h.position, h.row_key
''';

/// Las entradas de varios documentos —[count] claves—, para «Descargar el
/// índice» (F46, paso 4): una búsqueda por documento en
/// `idx_processed_headings_document`, sin recorrer la tabla. El orden de cada
/// documento lo pone quien llama, como en [indexEntriesSql].
String indexEntriesOfSql(int count) =>
    '''
SELECT ${indexEntryColumnsSql('h')}
FROM processed_headings h
WHERE h.document_id IN (${List.filled(count, '?').join(', ')})
''';

/// Las entradas cuyo título tiene lo buscado —`?1`, una consulta de FTS5
/// (`buildSearchQuery`)—, de los documentos vivos, las que mejor coinciden
/// primero, y como mucho `?2`. Del índice de texto a cada entrada, a su
/// documento y a su elemento, por clave; lo de la papelera queda afuera ANTES
/// de cortar en `?2`.
final indexSearchSql =
    '''
SELECT ${indexEntryColumnsSql('h')},
       item.title AS document_title,
       d.source_kind AS source_kind,
       (SELECT group_concat(ts.space_id, char(31)) FROM item_spaces ts
         WHERE ts.item_id = h.document_id) AS space_ids
FROM processed_heading_search
CROSS JOIN processed_headings h ON h.row_key = processed_heading_search.rowid
CROSS JOIN processed_documents d ON d.item_id = h.document_id
CROSS JOIN item ON item.id = h.document_id
WHERE processed_heading_search MATCH ?1 AND $kActiveItemSql
ORDER BY processed_heading_search.rank
LIMIT ?2
''';

/// Los capítulos que contienen a cada entrada de [hits] —claves—: el título
/// anterior de nivel más alto, y el anterior a ese, hasta el nivel 1. Cada
/// paso es una búsqueda hacia atrás en `idx_processed_headings_document`, que
/// lleva el origen y el nivel: se detiene en el primero que sirve, casi
/// siempre unos pocos más atrás. Devuelve, por cada uno, la clave de la
/// entrada buscada (`hit`) y las columnas del capítulo que la contiene.
String indexAncestorsSql(int hits) =>
    '''
WITH RECURSIVE chain(hit, row_key, document_id, position, level) AS (
  SELECT row_key, row_key, document_id, position, level
    FROM processed_headings
   WHERE row_key IN (${List.filled(hits, '?').join(', ')})
     AND origin <> 'image'
  UNION ALL
  SELECT c.hit, p.row_key, p.document_id, p.position, p.level
    FROM chain c
    JOIN processed_headings p ON p.row_key = (
      SELECT q.row_key FROM processed_headings q
       WHERE q.document_id = c.document_id
         AND q.position < c.position
         AND q.level < c.level
         AND q.origin <> 'image'
       ORDER BY q.position DESC
       LIMIT 1)
)
SELECT c.hit AS hit, ${indexEntryColumnsSql('a')}
FROM chain c
CROSS JOIN processed_headings a ON a.row_key = c.row_key
WHERE c.row_key <> c.hit
''';

/// Cuántos documentos vivos con texto hay, cuántos ya tienen sus entradas, y
/// cuántas imágenes no se titularon todavía —por su índice parcial—.
const indexProgressSql =
    '''
SELECT COUNT(*) AS documents,
       COALESCE(SUM($_indexedSql), 0) AS indexed,
       (SELECT COUNT(*) FROM processed_images ui
         WHERE ui.title IS NULL) AS untitled
FROM processed_documents d
CROSS JOIN item ON item.id = d.item_id
WHERE $kActiveItemSql AND $_hasTextSql
''';
