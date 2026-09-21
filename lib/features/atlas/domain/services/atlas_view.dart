import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';

/// Las ramas del Atlas que se ven, en el orden en que se muestran (F13).
///
/// Sin búsqueda: cada raíz y, bajo las de [expanded], sus hijos —un árbol
/// plegado por defecto, que con miles de valores es lo único que se puede
/// recorrer—.
///
/// Con [query]: solo los temas cuyo nombre la contiene, sin distinguir
/// mayúsculas ni acentos, MÁS sus ascendientes: un subtema suelto no dice de
/// qué es subtema. La búsqueda ignora lo plegado —encuentra el tema donde
/// esté— y no despliega nada de lo que no coincide.
List<AtlasNode> visibleAtlasNodes(
  AtlasSnapshot snapshot, {
  required Set<String> expanded,
  String query = '',
}) {
  final needle = normalizeVocabularyLabel(query);
  if (needle.isEmpty) return _collapsed(snapshot.nodes, expanded);

  final byId = {for (final node in snapshot.nodes) node.valueId: node};
  final keep = <String>{};
  for (final node in snapshot.nodes) {
    if (!normalizeVocabularyLabel(node.label).contains(needle)) continue;
    // Se sube hasta la raíz, o hasta el primer ascendiente que ya estaba.
    String? id = node.valueId;
    while (id != null && keep.add(id)) {
      id = byId[id]?.parentId;
    }
  }
  return [
    for (final node in snapshot.nodes)
      if (keep.contains(node.valueId)) node,
  ];
}

/// [nodes], que vienen en preorden, sin lo que cuelga de una rama plegada.
List<AtlasNode> _collapsed(List<AtlasNode> nodes, Set<String> expanded) {
  final rows = <AtlasNode>[];
  // La profundidad de la rama plegada cuyo contenido se está saltando.
  int? collapsedAt;
  for (final node in nodes) {
    final skipping = collapsedAt;
    if (skipping != null) {
      if (node.depth > skipping) continue;
      collapsedAt = null;
    }
    rows.add(node);
    if (node.hasChildren && !expanded.contains(node.valueId)) {
      collapsedAt = node.depth;
    }
  }
  return rows;
}
