import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/processed_entries.dart';
import 'package:sinapsis/features/library/data/repositories/library_query_sql.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// Lo que el Mapa dibuja (F41, paso 6): los documentos procesados vivos, y
/// nada de la Biblioteca. Lo que las fuentes ya tenían —sus temas, sus
/// vínculos— queda en ellas y no se ve acá: el Mapa se arma con lo que la
/// persona eligió de cada una al triarla. [alias] es el de la tabla `item`.
///
/// Las notas mapa son la excepción, y solo como puntos de entrada del esquema:
/// son el índice que la IA arma de cada tema, con lo procesado.
String mapItemSql(String alias) =>
    '${activeItemSql(alias)} AND ${isProcessedSql('$alias.id')}';

/// Lo vivo de [scope]: lo procesado —lo del Mapa, [mapItemSql]— o la
/// Biblioteca, para quien lee los temas sin ser el Mapa (las preguntas de un
/// cuestionario buscan sus distractores en las fuentes, F20).
String _scopeItemSql(String alias, LibraryScope scope) => switch (scope) {
  LibraryScope.processed => mapItemSql(alias),
  LibraryScope.library =>
    '${activeItemSql(alias)} AND ${notProcessedSql('$alias.id')}',
};

/// Lo que el mapa lee: cualquier escritura en estas tablas puede cambiarlo.
/// `item` también —un elemento que va a la papelera deja de contar— y por eso
/// va junto a las consultas, que son las que dicen qué hacen con lo borrado.
///
/// Alcanza también para un filtro: se resuelve sobre lo procesado (F41, paso
/// 6), que guarda el tipo de su fuente y busca el texto en sus partes.
List<TableInfo<dynamic, dynamic>> mapTables(AppDatabase db) => [
  db.propertyValues,
  db.propertyDefinitions,
  db.itemPropertyValues,
  db.relations,
  db.knowledgeEntries,
  db.knowledgeNotes,
  // Los temas (F28): renombrar uno cambia el mapa que los mira, y poner o
  // sacar uno de un elemento (F37) también.
  db.spaces,
  db.itemSpaces,
  // Lo procesado (F41, paso 6): lo único que el Mapa dibuja, y cuánto se
  // trabajó cada documento sale de sus partes.
  db.processedDocuments,
  db.processedParts,
];

/// El separador de los valores dentro de `value_ids`: el «separador de
/// unidades» (U+001F), el mismo `char(31)` de la consulta.
const mapValueIdSeparator = '\u001f';

/// Los documentos procesados vivos con los valores que tienen de la categoría:
/// UNA fila por documento, con su título, su tipo y cuándo se procesó —lo que
/// el motor necesita para buscarlo, para la burbuja «Sin tema» y para lo nuevo
/// (F44)—. Variable: `?1` la categoría.
///
/// La misma forma que la del Atlas y por la misma razón: lo que cuesta es
/// fabricar cada fila del lado de Dart, no leerla en SQLite, así que los
/// valores de un elemento viajan juntos en `value_ids`, separados por
/// [mapValueIdSeparator]. Un elemento sin ningún valor de la categoría trae
/// `value_ids` nulo y no aporta nada al mapa.
///
/// Lo que está en la papelera queda afuera, y lo que no es procesado también
/// ([mapItemSql]).
final mapItemsSql =
    '''
SELECT item.id AS id,
       item.title AS title,
       item.kind AS kind,
       item.created_at AS created_at,
       (SELECT group_concat(ipv.property_value_id, char(31))
          FROM item_property_values ipv
          JOIN property_values pv ON pv.id = ipv.property_value_id
         WHERE ipv.item_id = item.id AND pv.definition_id = ?1) AS value_ids
FROM item
WHERE ${mapItemSql('item')}
''';

/// Los documentos procesados vivos con sus temas: lo mismo que [mapItemsSql]
/// cuando el mapa mira los temas (F28). Un documento puede estar en varios
/// (F37): vienen juntos en `value_ids`, como los valores de una categoría, o
/// nulo si no tiene ninguno.
final mapSpaceItemsSql =
    '''
SELECT item.id AS id,
       item.title AS title,
       item.kind AS kind,
       item.created_at AS created_at,
       (SELECT group_concat(s.space_id, char(31))
          FROM item_spaces s
         WHERE s.item_id = item.id) AS value_ids
FROM item
WHERE ${mapItemSql('item')}
''';

/// Las relaciones, con lo justo para pesarlas: los extremos, el tipo, si
/// alguien las revisó y cuándo se hicieron (lo nuevo, F44).
///
/// No dice nada de la papelera a propósito: una relación con un extremo en la
/// papelera se descarta del lado de Dart, porque su extremo no está entre los
/// elementos que devolvió [mapItemsSql].
const mapRelationsSql = '''
SELECT from_item_id AS from_id,
       to_item_id AS to_id,
       kind AS kind,
       reviewed_at IS NOT NULL AS reviewed,
       created_at AS created_at
FROM relations
''';

/// Los documentos procesados vivos con lo que el tablero cuenta de cada uno:
/// cuándo se procesó y cuánto se trabajó (`processedDepthSql`). Una fila por
/// documento.
final mapDashboardItemsSql =
    '''
SELECT item.id AS id,
       item.created_at AS created_at,
       ${processedDepthSql('item.id')} AS depth
FROM item
WHERE ${mapItemSql('item')}
''';

/// Las contradicciones sin revisar entre dos documentos procesados vivos.
/// Variable: `?1` el tipo de vínculo `contradicts`.
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
  AND ${mapItemSql('a')}
  AND ${mapItemSql('b')}
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

/// Los documentos procesados vivos vinculados a uno, en los dos sentidos, los
/// vínculos más recientes primero. Variables: `?1` el elemento; `?2` cuántos
/// como mucho.
///
/// Dos búsquedas por clave —por los vínculos que salen y por los que llegan— y
/// no un `OR`, que SQLite resolvería recorriendo todos los vínculos.
final mapItemLinksSql =
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
  WHERE r.from_item_id = ?1 AND ${mapItemSql('item')}
  UNION ALL
  SELECT r.kind AS kind,
         0 AS outgoing,
         item.id AS id,
         item.title AS title,
         item.kind AS item_kind,
         r.created_at AS at
  FROM relations r
  JOIN item ON item.id = r.from_item_id
  WHERE r.to_item_id = ?1 AND ${mapItemSql('item')}
)
ORDER BY at DESC, id
LIMIT ?2
''';

/// Los elementos vivos de [scope] de un tema y de sus subtemas, los tocados
/// más recientemente primero. Variables, en este orden: el valor; cuántos como
/// mucho.
///
/// La jerarquía se resuelve con la misma consulta recursiva sobre los VALORES
/// que usa el filtro de la biblioteca (F13): asignar un subtema no asigna a su
/// padre, y acá se cuenta como suyo. Lo asignado se busca por el índice del
/// valor y cada elemento por su clave.
String mapTopicItemsSql(LibraryScope scope) =>
    '''
SELECT item.id AS id,
       item.title AS title,
       item.kind AS kind
FROM item
WHERE ${_scopeItemSql('item', scope)}
  AND item.id IN (
    SELECT item_id FROM item_property_values
    WHERE property_value_id IN (${valuesWithDescendantsSql(1)}))
ORDER BY item.updated_at DESC, item.id
LIMIT ?
''';

/// Las notas mapa vivas de un tema —un espacio— (F28), las tocadas más
/// recientemente primero. Variables: `?1` el espacio; `?2` cuántas como
/// mucho. Los elementos del tema se buscan por el índice de `item_spaces` y
/// su nota por la clave. `'map'` es `NoteKind.map.name`.
const mapSpaceNotesSql =
    '''
SELECT item.id AS id,
       item.title AS title
FROM item_spaces s
CROSS JOIN item ON item.id = s.item_id
CROSS JOIN note ON note.item_id = item.id
WHERE s.space_id = ?1
  AND note.note_kind = 'map'
  AND $kActiveItemSql
ORDER BY item.updated_at DESC, item.id
LIMIT ?2
''';

/// Los elementos vivos de [scope] de un tema —un espacio— (F28), los tocados
/// más recientemente primero. Variables: `?1` el espacio; `?2` cuántos como
/// mucho. Los temas no tienen subtemas: no hay jerarquía que recorrer.
String mapSpaceTopicItemsSql(LibraryScope scope) =>
    '''
SELECT item.id AS id,
       item.title AS title,
       item.kind AS kind
FROM item_spaces s
CROSS JOIN item ON item.id = s.item_id
WHERE s.space_id = ?1
  AND ${_scopeItemSql('item', scope)}
ORDER BY item.updated_at DESC, item.id
LIMIT ?2
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

/// Los vínculos entre dos documentos procesados vivos, con su fecha: entre
/// ellos elige la vista «Vínculos» qué dibujar (F28).
///
/// A diferencia de [mapRelationsSql], acá la papelera va en la consulta: la
/// vista no parte de una lista de elementos con la que descartar después, y
/// cada extremo se busca por su clave.
final mapLinksSql =
    '''
SELECT r.from_item_id AS from_id,
       r.to_item_id AS to_id,
       r.kind AS kind,
       r.created_at AS created_at,
       r.origin AS origin,
       r.confidence AS confidence,
       r.reviewed_at AS reviewed_at,
       (r.source_char_start IS NOT NULL) AS anchored
FROM relations r
JOIN item a ON a.id = r.from_item_id
JOIN item b ON b.id = r.to_item_id
WHERE ${mapItemSql('a')}
  AND ${mapItemSql('b')}
''';

/// Cuántos documentos procesados vivos hay: lo que la vista «Vínculos»
/// necesita para decir cuántos no tienen ningún vínculo.
final mapLiveItemCountSql =
    'SELECT COUNT(*) AS total FROM item WHERE ${mapItemSql('item')}';

/// El título y el tipo de un grupo de documentos procesados vivos, buscados
/// por su clave.
String mapItemsByIdSql(int count) =>
    'SELECT item.id AS id, item.title AS title, item.kind AS kind '
    'FROM item '
    'WHERE item.id IN (${List.filled(count, '?').join(', ')}) '
    'AND ${mapItemSql('item')}';
