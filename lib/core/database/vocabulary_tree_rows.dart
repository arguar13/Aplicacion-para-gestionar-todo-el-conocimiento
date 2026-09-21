import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';

/// Dónde estaba un valor en el árbol: para devolverlo ahí al deshacer (F13).
class ValuePlacement {
  const ValuePlacement({
    required this.id,
    required this.parentId,
    required this.depth,
  });

  final String id;
  final String? parentId;
  final int depth;
}

/// Las filas de [rootIds] y todo lo que cuelga de ellas, cada una una vez, los
/// padres antes que los hijos.
///
/// Son a lo sumo cinco consultas —una por nivel—, no una por valor.
Future<List<PropertyValueRow>> subtreeRows(
  AppDatabase db,
  Iterable<String> rootIds,
) async {
  final found = <String, PropertyValueRow>{};
  var level = await (db.select(
    db.propertyValues,
  )..where((v) => v.id.isIn(rootIds.toList()))).get();
  while (level.isNotEmpty) {
    final fresh = [
      for (final row in level)
        if (!found.containsKey(row.id)) row,
    ];
    for (final row in fresh) {
      found[row.id] = row;
    }
    if (fresh.isEmpty) break;
    level = await (db.select(
      db.propertyValues,
    )..where((v) => v.parentId.isIn(fresh.map((r) => r.id).toList()))).get();
  }
  return found.values.toList();
}

/// La posición actual de [rows], para guardarla antes de moverlas.
List<ValuePlacement> placementsOf(Iterable<PropertyValueRow> rows) => [
  for (final row in rows)
    ValuePlacement(id: row.id, parentId: row.parentId, depth: row.depth),
];

/// Recalcula `depth` de [rootIds] y de todo lo que cuelga de ellos, a partir
/// del padre de cada uno: una raíz vale 0, un hijo vale lo de su padre más 1.
///
/// Solo escribe lo que cambió. Va en la misma transacción que movió la rama:
/// la base rechaza un nivel que pase de `kVocabularyMaxDepth`, y entonces
/// revierte todo el movimiento.
Future<void> recomputeDepths(AppDatabase db, Iterable<String> rootIds) async {
  final rows = await subtreeRows(db, rootIds);
  final byId = {for (final r in rows) r.id: r};
  final depths = <String, int>{};

  Future<int> depthOf(PropertyValueRow row) async {
    final known = depths[row.id];
    if (known != null) return known;
    final parentId = row.parentId;
    if (parentId == null) return depths[row.id] = 0;
    final inBranch = byId[parentId];
    final int parentDepth;
    if (inBranch != null) {
      parentDepth = await depthOf(inBranch);
    } else {
      // El padre es de afuera de la rama: vale lo que tiene guardado.
      final outside = await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals(parentId))).getSingleOrNull();
      parentDepth = outside?.depth ?? -1;
    }
    return depths[row.id] = parentDepth + 1;
  }

  for (final row in rows) {
    final depth = await depthOf(row);
    if (depth != row.depth) {
      await (db.update(db.propertyValues)..where((v) => v.id.equals(row.id)))
          .write(PropertyValuesCompanion(depth: Value(depth)));
    }
  }
}
