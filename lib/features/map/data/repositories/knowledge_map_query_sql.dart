import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';

/// Lo que el grafo de temas lee: cualquier escritura en estas tablas puede
/// cambiarlo. `item` también —un elemento que va a la papelera deja de
/// contar— y por eso va junto a las consultas, que son las que dicen qué hacen
/// con lo borrado.
List<TableInfo<dynamic, dynamic>> mapTables(AppDatabase db) => [
  db.propertyValues,
  db.propertyDefinitions,
  db.itemPropertyValues,
  db.relations,
  db.knowledgeEntries,
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
