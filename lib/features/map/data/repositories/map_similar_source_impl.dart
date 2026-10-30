import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_query_sql.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/services/map_similar_source.dart';
import 'package:sinapsis/features/relations/domain/services/item_vector_index.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';

/// [MapSimilarSource] con los vectores de F30 ([vectors]) y los vínculos de la
/// base (F44, paso 5).
///
/// Los vínculos se leen acá y no se toman de lo que dibuja el lienzo: con
/// «Más fuertes», lo vinculado no dibuja los vínculos más flojos, y un par
/// unido por uno de esos no es un parecido «sin vincular». Se dejan afuera
/// antes de comparar, para que el tope se llene con lo que sí se propone.
MapSimilarSource mapSimilarSource({
  required AppDatabase database,
  required ItemVectorIndex vectors,
}) => (itemIds) async {
  final ids = itemIds.toSet().take(kMaxGraphItems).toList();
  if (ids.length < 2) return const [];
  return vectors.similarPairs(
    ids,
    minSimilarity: kMapSimilarMinScore,
    perItem: kMapSimilarPerDocument,
    limit: kMapSimilarPairs,
    except: await _linkedPairs(database, ids),
  );
};

/// Los pares de [ids] que ya tienen algún vínculo, en cualquier sentido
/// (`similarPairKey`): una sola consulta por el índice de `from_item_id`, la de
/// los documentos de un tema. Son a lo sumo `kMaxGraphItems`, lejos del tope
/// de variables de SQLite.
Future<Set<String>> _linkedPairs(AppDatabase db, List<String> ids) async {
  final inside = ids.toSet();
  final rows = await db
      .customSelect(
        mapItemsRelationsSql(ids.length),
        variables: [for (final id in ids) Variable.withString(id)],
        readsFrom: {db.relations},
      )
      .get();
  return {
    for (final row in rows)
      if (row.data['from_id'] case final String from)
        if (row.data['to_id'] case final String to)
          if (from != to && inside.contains(to)) similarPairKey(from, to),
  };
}
