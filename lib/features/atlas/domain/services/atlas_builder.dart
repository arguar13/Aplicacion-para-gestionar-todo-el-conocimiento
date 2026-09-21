import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_gap.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_thresholds.dart';

/// Un valor del vocabulario, con lo justo para armar el árbol.
class AtlasValueRow {
  const AtlasValueRow({required this.id, required this.label, this.parentId});

  final String id;
  final String label;
  final String? parentId;
}

/// Lo que la base cuenta de UNA rama, en cascada. Una rama sin ningún elemento
/// no tiene fila: para el constructor es como si todo valiera cero.
class AtlasBranchCounts {
  const AtlasBranchCounts({
    this.sources = 0,
    this.atomic = 0,
    this.growingLiving = 0,
    this.matureLiving = 0,
    this.maps = 0,
    this.lastTouched,
    this.firstYear,
    this.lastYear,
  });

  final int sources;
  final int atomic;
  final int growingLiving;
  final int matureLiving;
  final int maps;
  final DateTime? lastTouched;
  final int? firstYear;
  final int? lastYear;
}

/// Una nota mapa y el valor al que está asignada directamente.
class AtlasMapNoteRow {
  const AtlasMapNoteRow({
    required this.noteId,
    required this.title,
    required this.valueId,
  });

  final String noteId;
  final String title;
  final String valueId;
}

/// Arma el Atlas de una categoría con lo que la base contó: el árbol en
/// preorden con los agregados de cada rama, las notas mapa que cuelgan de cada
/// una y los vacíos detectados.
///
/// Es pura: la base hace lo que solo ella puede hacer —contar sobre miles de
/// asignaciones— y acá se ordena, se reparte y se juzga. Con [now] se decide
/// qué rama está abandonada.
AtlasSnapshot buildAtlas({
  required String definitionId,
  required String definitionName,
  required List<AtlasValueRow> values,
  required Map<String, AtlasBranchCounts> counts,
  required List<AtlasMapNoteRow> mapNotes,
  required DateTime now,
}) {
  if (values.isEmpty) {
    return AtlasSnapshot.empty(definitionId, name: definitionName);
  }

  // El nombre de cada valor sin mayúsculas ni acentos, UNA vez: normalizar
  // dentro de un comparador lo repite en cada comparación, y con miles de
  // temas era la mayor parte del tiempo de abrir el Atlas.
  final keyOf = {
    for (final value in values) value.id: normalizeVocabularyLabel(value.label),
  };
  // Hermanos por nombre: el árbol se arma en el orden en que llegan los
  // valores.
  final ordered = _sortedByLabel(values, keyOf);
  final byId = {for (final value in ordered) value.id: value};
  final tree = VocabularyTree([
    for (final value in ordered) (id: value.id, parentId: value.parentId),
  ]);

  final mapNotesByBranch = _mapNotesByBranch(mapNotes, tree);

  final nodes = <AtlasNode>[];
  void visit(String id, int depth) {
    final value = byId[id]!;
    final count = counts[id] ?? const AtlasBranchCounts();
    final children = tree.childrenOf(id);
    nodes.add(
      AtlasNode(
        valueId: id,
        label: value.label,
        depth: depth,
        parentId: tree.parentOf(id),
        childCount: children.length,
        sourceCount: count.sources,
        atomicCount: count.atomic,
        growingLivingCount: count.growingLiving,
        matureLivingCount: count.matureLiving,
        mapCount: count.maps,
        lastTouched: count.lastTouched,
        firstYear: count.firstYear,
        lastYear: count.lastYear,
        mapNotes: mapNotesByBranch[id] ?? const [],
      ),
    );
    for (final child in children) {
      visit(child, depth + 1);
    }
  }

  for (final root in tree.roots) {
    visit(root, 0);
  }

  return AtlasSnapshot(
    definitionId: definitionId,
    definitionName: definitionName,
    nodes: nodes,
    gaps: _gapsOf(nodes, now, keyOf),
  );
}

List<AtlasValueRow> _sortedByLabel(
  List<AtlasValueRow> values,
  Map<String, String> keyOf,
) {
  return [...values]..sort((a, b) {
    final byLabel = keyOf[a.id]!.compareTo(keyOf[b.id]!);
    return byLabel != 0 ? byLabel : a.id.compareTo(b.id);
  });
}

/// Las notas mapa de cada rama: las asignadas a ella o a cualquiera de sus
/// descendientes, cada una una vez y por título.
Map<String, List<AtlasMapNote>> _mapNotesByBranch(
  List<AtlasMapNoteRow> rows,
  VocabularyTree tree,
) {
  final byBranch = <String, Map<String, AtlasMapNote>>{};
  // Cada nota mapa se normaliza UNA vez, y cada camino hacia la raíz se arma
  // una vez por valor: son miles de filas y muchas comparten valor.
  final titleKey = <String, String>{};
  final chains = <String, List<String>>{};
  for (final row in rows) {
    final note = AtlasMapNote(id: row.noteId, title: row.title);
    titleKey[row.noteId] ??= normalizeVocabularyLabel(row.title);
    final chain = chains.putIfAbsent(
      row.valueId,
      () => [row.valueId, ...tree.ancestorsOf(row.valueId)],
    );
    for (final branch in chain) {
      (byBranch[branch] ??= {})[row.noteId] = note;
    }
  }
  return {
    for (final entry in byBranch.entries)
      entry.key: [...entry.value.values]
        ..sort((a, b) {
          final byTitle = titleKey[a.id]!.compareTo(titleKey[b.id]!);
          return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
        }),
  };
}

/// Los vacíos de [nodes], que vienen en preorden.
///
/// Cada uno se avisa en la rama MÁS ALTA donde se cumple: si el padre lo
/// cumple, sus descendientes también, y repetirlos sería contar el mismo
/// vacío varias veces.
List<AtlasGap> _gapsOf(
  List<AtlasNode> nodes,
  DateTime now,
  Map<String, String> keyOf,
) {
  final byId = {for (final node in nodes) node.valueId: node};

  bool manySources(AtlasNode node) =>
      node.sourceCount >= kAtlasManySources && node.livingCount == 0;
  bool singleItem(AtlasNode node) => node.itemCount == 1;
  bool stale(AtlasNode node) {
    final touched = node.lastTouched;
    return touched != null && now.difference(touched) >= kAtlasStaleAfter;
  }

  List<AtlasNode> topmost(bool Function(AtlasNode) holds) => [
    for (final node in nodes)
      if (holds(node) &&
          !(node.parentId != null && holds(byId[node.parentId]!)))
        node,
  ];

  int byLabel(AtlasNode a, AtlasNode b) =>
      keyOf[a.valueId]!.compareTo(keyOf[b.valueId]!);

  final many = topmost(manySources)
    ..sort((a, b) {
      final bySources = b.sourceCount.compareTo(a.sourceCount);
      return bySources != 0 ? bySources : byLabel(a, b);
    });
  // Las más abandonadas primero: la fecha más vieja.
  final abandoned = topmost(stale)
    ..sort((a, b) {
      final byAge = a.lastTouched!.compareTo(b.lastTouched!);
      return byAge != 0 ? byAge : byLabel(a, b);
    });
  final single = topmost(singleItem)..sort(byLabel);

  return [
    for (final node in many)
      AtlasGap(
        kind: AtlasGapKind.manySourcesNoLivingNote,
        valueId: node.valueId,
      ),
    for (final node in abandoned)
      AtlasGap(kind: AtlasGapKind.stale, valueId: node.valueId),
    for (final node in single)
      AtlasGap(kind: AtlasGapKind.singleItem, valueId: node.valueId),
  ];
}
