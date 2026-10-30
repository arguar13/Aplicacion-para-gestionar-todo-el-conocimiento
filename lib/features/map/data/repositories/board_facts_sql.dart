/// El SQL de lo que el Resumen del Mapa lee además del grafo de temas (F44,
/// paso 3). Usa el mismo recorte que el mapa —`mapItemSql`: los documentos
/// procesados vivos— para que las cifras del Resumen y el dibujo del Mapa no
/// puedan contar cosas distintas.
library;

import 'package:sinapsis/features/map/data/repositories/knowledge_map_query_sql.dart';

/// Los documentos procesados vivos, con su título, cuándo se procesaron y sus
/// valores de una categoría. Variable: `?1` la categoría. UNA fila por
/// documento, con los valores juntos en `value_ids` como en `mapItemsSql`, y
/// por la misma razón: lo que cuesta es fabricar cada fila del lado de Dart.
final boardItemsSql =
    '''
SELECT item.id AS id,
       item.title AS title,
       item.created_at AS created_at,
       (SELECT group_concat(ipv.property_value_id, char(31))
          FROM item_property_values ipv
          JOIN property_values pv ON pv.id = ipv.property_value_id
         WHERE ipv.item_id = item.id AND pv.definition_id = ?1) AS value_ids
FROM item
WHERE ${mapItemSql('item')}
''';

/// Lo mismo que [boardItemsSql] cuando el mapa mira los temas (F28): los
/// espacios de cada documento. Sin variables.
final boardSpaceItemsSql =
    '''
SELECT item.id AS id,
       item.title AS title,
       item.created_at AS created_at,
       (SELECT group_concat(s.space_id, char(31))
          FROM item_spaces s
         WHERE s.item_id = item.id) AS value_ids
FROM item
WHERE ${mapItemSql('item')}
''';

/// Las tarjetas de cada documento procesado que tiene alguna: las suyas y las
/// de su fuente, sin las de lo que está en la papelera —lo mismo que deja
/// afuera la cola de estudio—. Variables: `?1` ahora; `?2` el fin del día de
/// estudio.
///
/// «Para hoy» es lo que la cola podría mostrar hoy: ni pausada ni pospuesta, y
/// con su vencimiento antes de que termine el día. No mira los topes del día
/// ni las hermanas: es cuánto hay, no cuánto entra en una sesión.
///
/// Se parte de los documentos procesados y de cada uno se buscan sus tarjetas
/// por el índice de `item_id`: lo que cuesta crece con los documentos, no con
/// las tarjetas de toda la bóveda.
const boardCardsSql = '''
SELECT pd.item_id AS id,
       COUNT(*) AS cards,
       COALESCE(SUM(CASE WHEN f.suspended = 0
                          AND (f.buried_until IS NULL OR f.buried_until <= ?1)
                          AND f.due_at < ?2
                         THEN 1 ELSE 0 END), 0) AS due
FROM processed_documents pd
JOIN flashcards f ON f.item_id IN (pd.item_id, pd.source_item_id)
JOIN item owner ON owner.id = f.item_id
WHERE owner.deleted_at IS NULL
GROUP BY pd.item_id
''';
