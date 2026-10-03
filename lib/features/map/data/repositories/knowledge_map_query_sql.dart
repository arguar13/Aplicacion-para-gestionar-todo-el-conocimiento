import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/library/data/repositories/library_query_sql.dart';

/// Lo que el mapa lee: cualquier escritura en estas tablas puede cambiarlo.
/// `item` también —un elemento que va a la papelera deja de contar— y por eso
/// va junto a las consultas, que son las que dicen qué hacen con lo borrado.
List<TableInfo<dynamic, dynamic>> mapTables(AppDatabase db) => [
  db.propertyValues,
  db.propertyDefinitions,
  db.itemPropertyValues,
  db.relations,
  db.knowledgeEntries,
  db.knowledgeNotes,
];

/// Lo que se suma cuando el mapa se calcula sobre lo que pasa un filtro: lo que
/// la consulta de la biblioteca mira además de lo anterior —el tipo de la
/// fuente, sus formas y sus chunks, para la búsqueda de texto—.
List<TableInfo<dynamic, dynamic>> mapFilterTables(AppDatabase db) => [
  db.knowledgeSources,
  db.renditions,
  db.chunks,
];

/// El separador de los valores dentro de `value_ids`: el «separador de
/// unidades» (U+001F), el mismo `char(31)` de la consulta.
const mapValueIdSeparator = '\u001f';

/// Los elementos vivos con los valores que tienen de la categoría: UNA fila por
/// elemento. Variable: `?1` la categoría.
///
/// La misma forma que la del Atlas y por la misma razón: lo que cuesta es
/// fabricar cada fila del lado de Dart, no leerla en SQLite, así que los
/// valores de un elemento viajan juntos en `value_ids`, separados por
/// [mapValueIdSeparator]. Un elemento sin ningún valor de la categoría trae
/// `value_ids` nulo y no aporta nada al mapa.
///
/// Lo que está en la papelera queda afuera (`kActiveItemSql`).
const mapItemsSql =
    '''
SELECT item.id AS id,
       (SELECT group_concat(ipv.property_value_id, char(31))
          FROM item_property_values ipv
          JOIN property_values pv ON pv.id = ipv.property_value_id
         WHERE ipv.item_id = item.id AND pv.definition_id = ?1) AS value_ids
FROM item
WHERE $kActiveItemSql
''';

/// Las relaciones, con lo justo para pesarlas: los extremos, el tipo y si
/// alguien las revisó.
///
/// No dice nada de la papelera a propósito: una relación con un extremo en la
/// papelera se descarta del lado de Dart, porque su extremo no está entre los
/// elementos que devolvió [mapItemsSql].
const mapRelationsSql = '''
SELECT from_item_id AS from_id,
       to_item_id AS to_id,
       kind AS kind,
       reviewed_at IS NOT NULL AS reviewed
FROM relations
''';

/// Los elementos vivos con lo que el tablero cuenta de cada uno: qué es, cuándo
/// se guardó y, si es una nota, su madurez. Una fila por elemento.
const mapDashboardItemsSql =
    '''
SELECT item.id AS id,
       item.kind AS kind,
       item.created_at AS created_at,
       note.maturity AS maturity
FROM item
LEFT JOIN note ON note.item_id = item.id
WHERE $kActiveItemSql
''';

/// Las contradicciones sin revisar entre dos elementos vivos. Variable: `?1` el
/// tipo de vínculo `contradicts`.
///
/// Acá la papelera sí va en la consulta y no del lado de Dart: son pocas filas
/// y traer los títulos de lo borrado sería trabajo tirado.
final mapOpenContradictionsSql =
    '''
SELECT r.id AS id,
       r.from_item_id AS from_id,
       r.to_item_id AS to_id,
       r.created_at AS created_at,
       a.title AS from_title,
       b.title AS to_title
FROM relations r
JOIN item a ON a.id = r.from_item_id
JOIN item b ON b.id = r.to_item_id
WHERE r.kind = ?1
  AND r.reviewed_at IS NULL
  AND ${activeItemSql('a')}
  AND ${activeItemSql('b')}
''';

/// Las notas mapa vivas asignadas a un tema, las tocadas más recientemente
/// primero. Variables: `?1` el valor; `?2` cuántas como mucho. El orden por
/// título lo pone quien llama: `COLLATE NOCASE` de SQLite solo entiende ASCII y
/// pondría «Ágora» después de «Zama».
///
/// Se parte de las asignaciones del valor, por su índice, y de cada una se va,
/// por su clave, al elemento y a su nota: nunca se recorren las notas mapa de
/// toda la bóveda para quedarse con las de un tema. `'map'` es
/// `NoteKind.map.name`: un `const` no admite `.name`.
const mapTopicNotesSql =
    '''
SELECT item.id AS id,
       item.title AS title
FROM item_property_values ipv
CROSS JOIN item ON item.id = ipv.item_id
CROSS JOIN note ON note.item_id = item.id
WHERE ipv.property_value_id = ?1
  AND note.note_kind = 'map'
  AND $kActiveItemSql
ORDER BY item.updated_at DESC, item.id
LIMIT ?2
''';

/// Los elementos vivos vinculados a uno, en los dos sentidos, los vínculos
/// más recientes primero. Variables: `?1` el elemento; `?2` cuántos como
/// mucho.
///
/// Dos búsquedas por clave —por los vínculos que salen y por los que llegan— y
/// no un `OR`, que SQLite resolvería recorriendo todos los vínculos.
const mapItemLinksSql =
    '''
SELECT * FROM (
  SELECT r.kind AS kind,
         1 AS outgoing,
         item.id AS id,
         item.title AS title,
         item.kind AS item_kind,
         r.created_at AS at
  FROM relations r
  JOIN item ON item.id = r.to_item_id
  WHERE r.from_item_id = ?1 AND $kActiveItemSql
  UNION ALL
  SELECT r.kind AS kind,
         0 AS outgoing,
         item.id AS id,
         item.title AS title,
         item.kind AS item_kind,
         r.created_at AS at
  FROM relations r
  JOIN item ON item.id = r.from_item_id
  WHERE r.to_item_id = ?1 AND $kActiveItemSql
)
ORDER BY at DESC, id
LIMIT ?2
''';

/// Los elementos vivos de un tema y de sus subtemas, los tocados más
/// recientemente primero. Variables, en este orden: el valor; cuántos como
/// mucho.
///
/// La jerarquía se resuelve con la misma consulta recursiva sobre los VALORES
/// que usa el filtro de la biblioteca (F13): asignar un subtema no asigna a su
/// padre, y acá se cuenta como suyo. Lo asignado se busca por el índice del
/// valor y cada elemento por su clave.
final mapTopicItemsSql =
    '''
SELECT item.id AS id,
       item.title AS title,
       item.kind AS kind
FROM item
WHERE $kActiveItemSql
  AND item.id IN (
    SELECT item_id FROM item_property_values
    WHERE property_value_id IN (${valuesWithDescendantsSql(1)}))
ORDER BY item.updated_at DESC, item.id
LIMIT ?
''';

/// Los vínculos que salen de un grupo de elementos: se buscan por el índice del
/// origen, y quien llama se queda con los que llegan a otro del grupo.
String mapItemsRelationsSql(int count) =>
    'SELECT from_item_id AS from_id, to_item_id AS to_id, kind AS kind '
    'FROM relations '
    'WHERE from_item_id IN (${List.filled(count, '?').join(', ')})';

/// Las notas mapa vivas de toda la bóveda, las tocadas más recientemente
/// primero. Variable: `?1` cuántas como mucho. Es el punto de entrada del
/// esquema: una nota mapa reúne lo que otra persona ya ordenó.
///
/// Se parte de las notas y se va a cada elemento por su clave. `'map'` es
/// `NoteKind.map.name`: un `const` no admite `.name`.
const mapNotesSql =
    '''
SELECT item.id AS id,
       item.title AS title
FROM note
CROSS JOIN item ON item.id = note.item_id
WHERE note.note_kind = 'map'
  AND $kActiveItemSql
ORDER BY item.updated_at DESC, item.id
LIMIT ?
''';

/// Los vínculos entre dos elementos vivos, con su fecha: entre ellos elige la
/// vista «Vínculos» qué dibujar (F28).
///
/// A diferencia de [mapRelationsSql], acá la papelera va en la consulta: la
/// vista no parte de una lista de elementos con la que descartar después, y
/// cada extremo se busca por su clave.
final mapLinksSql =
    '''
SELECT r.from_item_id AS from_id,
       r.to_item_id AS to_id,
       r.kind AS kind,
       r.created_at AS created_at
FROM relations r
JOIN item a ON a.id = r.from_item_id
JOIN item b ON b.id = r.to_item_id
WHERE ${activeItemSql('a')}
  AND ${activeItemSql('b')}
''';

/// Cuántos elementos vivos hay: lo que la vista «Vínculos» necesita para
/// decir cuántos no tienen ningún vínculo.
const mapLiveItemCountSql =
    'SELECT COUNT(*) AS total FROM item WHERE $kActiveItemSql';

/// El título y el tipo de un grupo de elementos vivos, buscados por su clave.
String mapItemsByIdSql(int count) =>
    'SELECT item.id AS id, item.title AS title, item.kind AS kind '
    'FROM item '
    'WHERE item.id IN (${List.filled(count, '?').join(', ')}) '
    'AND $kActiveItemSql';
