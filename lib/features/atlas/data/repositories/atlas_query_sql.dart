import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';

/// Lo que el Atlas lee: cualquier escritura en estas tablas puede cambiarlo.
/// `item` también —un elemento que va a la papelera deja de contar— y por eso
/// va junto a las consultas, que son las que dicen qué hacen con lo borrado.
List<TableInfo<dynamic, dynamic>> atlasTables(AppDatabase db) => [
  db.propertyValues,
  db.propertyDefinitions,
  db.itemPropertyValues,
  db.knowledgeEntries,
  db.knowledgeNotes,
  // Los temas (F28): crear, renombrar o borrar uno cambia su Atlas.
  db.spaces,
];

/// El separador de los valores dentro de `value_ids`: el «separador de
/// unidades» (U+001F), el mismo `char(31)` de la consulta.
const atlasValueIdSeparator = '\u001f';

/// Lo que el Atlas necesita de cada elemento vivo, en UNA fila por elemento:
/// qué es, cuándo se tocó, qué años cubre y qué valores de la categoría tiene.
/// Variables: `?1` la categoría; `?2` el nombre de la categoría de fechas del
/// hecho (la de sistema).
///
/// Una fila por elemento —10.000, y no las 42.000 que salían de traer aparte
/// cada asignación y cada dato—: lo que cuesta es fabricar cada fila del lado
/// de Dart, no leerla en SQLite. Los valores de la categoría vienen juntos en
/// `value_ids`, separados por [atlasValueIdSeparator] —un carácter de control
/// que ningún identificador lleva—; la cascada por la jerarquía y el no contar
/// dos veces un elemento dentro de una rama las hace `aggregateBranches`, en
/// Dart. Un elemento sin ningún valor de la categoría trae `value_ids` nulo.
///
/// `dated` es el rango de años de «Fecha del hecho» de cada elemento, una fila
/// por elemento: va aparte para no multiplicar las filas por temas × fechas.
///
/// Lo que está en la papelera queda afuera (`kActiveItemSql`): sin fila, el
/// elemento no cuenta en ninguna rama.
final atlasItemsSql = _atlasItemsSql(
  valueIds: '''
(SELECT group_concat(ipv.property_value_id, char(31))
          FROM item_property_values ipv
          JOIN property_values pv ON pv.id = ipv.property_value_id
         WHERE ipv.item_id = item.id AND pv.definition_id = ?1)''',
  datesCategory: '?2',
);

/// Lo mismo que [atlasItemsSql] cuando el Atlas mira los temas (F28): el
/// «valor» de cada elemento es su espacio, uno o ninguno. Variable: `?1` el
/// nombre de la categoría de fechas del hecho.
final atlasSpaceItemsSql = _atlasItemsSql(
  valueIds: 'item.space_id',
  datesCategory: '?1',
);

/// La forma común de [atlasItemsSql] y [atlasSpaceItemsSql]: [valueIds] es la
/// expresión de los valores de cada elemento, y [datesCategory] la variable
/// con el nombre de la categoría de fechas.
String _atlasItemsSql({
  required String valueIds,
  required String datesCategory,
}) =>
    '''
WITH dated AS (
  SELECT ipv.item_id AS item_id,
         MIN(dv.date_from_year) AS year_from,
         MAX(dv.date_to_year) AS year_to
  FROM property_values dv
  JOIN item_property_values ipv ON ipv.property_value_id = dv.id
  WHERE dv.definition_id = (
          SELECT id FROM property_definitions
          WHERE is_system = 1 AND name = $datesCategory COLLATE NOCASE)
    AND dv.date_from_year IS NOT NULL
  GROUP BY ipv.item_id
)
SELECT item.kind AS kind,
       item.updated_at AS updated_at,
       note.note_kind AS note_kind,
       note.maturity AS maturity,
       dated.year_from AS year_from,
       dated.year_to AS year_to,
       $valueIds AS value_ids
FROM item
LEFT JOIN note ON note.item_id = item.id
LEFT JOIN dated ON dated.item_id = item.id
WHERE $kActiveItemSql
''';

/// Las notas mapa vivas asignadas a un valor de la categoría: una fila por
/// cada asignación, con el título de la nota. Variable: `?1` la categoría.
///
/// Como la anterior, se lee en crudo: con 10.000 elementos son unas 3.000
/// filas, y leerlas por la API tipada de drift costaba 200 ms —más que la
/// consulta—. `'map'` es `NoteKind.map.name`: un `const` no admite `.name`.
///
/// Los `CROSS JOIN` fijan el orden: las notas mapa (un millar), su elemento,
/// sus asignaciones por la clave del elemento y el valor por la suya. Sin
/// ellos SQLite empezaba por las asignaciones de la categoría —32.000— y
/// descartaba casi todas al mirar el subtipo de la nota: 200 ms contra 15.
const atlasMapNotesSql =
    '''
SELECT item.id AS note_id,
       item.title AS title,
       ipv.property_value_id AS value_id
FROM note
CROSS JOIN item ON item.id = note.item_id
CROSS JOIN item_property_values ipv ON ipv.item_id = item.id
CROSS JOIN property_values pv ON pv.id = ipv.property_value_id
WHERE note.note_kind = 'map'
  AND pv.definition_id = ?1
  AND $kActiveItemSql
''';

/// Las notas mapa vivas que están en un tema —un espacio— (F28): una fila por
/// nota, con su espacio como «valor». Se parte de las notas mapa, como en
/// [atlasMapNotesSql], y cada una va a su elemento por la clave. `'map'` es
/// `NoteKind.map.name`.
const atlasSpaceMapNotesSql =
    '''
SELECT item.id AS note_id,
       item.title AS title,
       item.space_id AS value_id
FROM note
CROSS JOIN item ON item.id = note.item_id
WHERE note.note_kind = 'map'
  AND item.space_id IS NOT NULL
  AND $kActiveItemSql
''';
