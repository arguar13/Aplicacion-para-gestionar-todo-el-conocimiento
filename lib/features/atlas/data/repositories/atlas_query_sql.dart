import 'package:sinapsis/core/database/active_entries.dart';

/// Los agregados en cascada de TODAS las ramas de una categoría, en una sola
/// consulta (F13). Variables: `?1` la categoría; `?2` el nombre de la categoría
/// de fechas del hecho (la de sistema).
///
/// Cómo se cuenta:
/// 1. `closure`: para cada valor de la categoría, todos sus descendientes —él
///    mismo incluido—, con una CTE recursiva sobre los valores, que son
///    miles, no sobre los elementos. `UNION` y no `UNION ALL`: una jerarquía
///    dañada con un ciclo terminaría igual en vez de dar vueltas para siempre.
/// 2. `pairs`: cada par (rama, elemento vivo) UNA vez. Un elemento asignado a
///    dos valores de la misma rama cuenta una sola vez en ella: por eso el
///    `DISTINCT` va ANTES de contar y no dentro de cada conteo.
/// 3. `dated`: el rango de años de «Fecha del hecho» de cada elemento, una fila
///    por elemento. Va aparte y no unida a las asignaciones de la rama: un
///    elemento con tres temas y dos fechas daría seis filas por rama.
///
/// Se llega a las asignaciones por el índice del valor y a cada elemento y
/// nota por su clave: nunca un recorrido de `item` ni de las asignaciones de
/// otras categorías. El `CROSS JOIN` de `pairs` fija ese orden —la rama, sus
/// asignaciones, el elemento—: sin él SQLite, que no sabe cuántas filas tiene
/// una CTE, recorría TODAS las asignaciones de la base y buscaba cada
/// elemento y cada rama en el camino. Lo que está en la papelera queda afuera
/// desde `pairs`.
///
/// Una rama sin ningún elemento no devuelve fila.
const atlasAggregatesSql =
    '''
WITH RECURSIVE closure(descendant, branch) AS (
  SELECT id, id FROM property_values WHERE definition_id = ?1
  UNION
  SELECT pv.id, closure.branch
  FROM property_values pv JOIN closure ON pv.parent_id = closure.descendant
),
pairs AS (
  SELECT DISTINCT closure.branch AS branch, ipv.item_id AS item_id
  FROM closure
  CROSS JOIN item_property_values ipv
    ON ipv.property_value_id = closure.descendant
  CROSS JOIN item ON item.id = ipv.item_id
  WHERE $kActiveItemSql
),
dated AS (
  SELECT ipv.item_id AS item_id,
         MIN(dv.date_from_year) AS year_from,
         MAX(dv.date_to_year) AS year_to
  FROM property_values dv
  JOIN item_property_values ipv ON ipv.property_value_id = dv.id
  WHERE dv.definition_id = (
          SELECT id FROM property_definitions
          WHERE is_system = 1 AND name = ?2 COLLATE NOCASE)
    AND dv.date_from_year IS NOT NULL
  GROUP BY ipv.item_id
)
SELECT pairs.branch AS value_id,
       COALESCE(SUM(item.kind = 'source'), 0) AS sources,
       COALESCE(SUM(note.note_kind = 'atomic'), 0) AS atomic,
       COALESCE(SUM(note.note_kind = 'living'
                    AND note.maturity <> 'mature'), 0) AS growing_living,
       COALESCE(SUM(note.note_kind = 'living'
                    AND note.maturity = 'mature'), 0) AS mature_living,
       COALESCE(SUM(note.note_kind = 'map'), 0) AS maps,
       MAX(item.updated_at) AS last_touched,
       MIN(dated.year_from) AS first_year,
       MAX(dated.year_to) AS last_year
FROM pairs
JOIN item ON item.id = pairs.item_id
LEFT JOIN note ON note.item_id = item.id
LEFT JOIN dated ON dated.item_id = item.id
GROUP BY pairs.branch
''';
