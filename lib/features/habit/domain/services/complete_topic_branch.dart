import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';

/// Cuántas fuentes tiene que tener una rama, como mínimo, para que «de
/// punta a punta» signifique algo (F17, D7).
///
/// Decisión propia: D7 solo dice «todas las fuentes de esa rama», y sin un
/// piso una hoja de una sola fuente ya citada una vez completaría su
/// propia rama de inmediato —trivializa la insignia, que premia haber
/// trabajado un tema entero, no una cita suelta—.
const kMinSourcesForCompleteBranch = 3;

/// Si alguna rama del Atlas —un valor de Tema con todos sus descendientes,
/// F13— está completa: al menos [kMinSourcesForCompleteBranch] fuentes, y
/// cada una con alguna nota viva madura que la cite.
///
/// Puro: recorre el árbol una sola vez, de las hojas hacia la raíz —una
/// rama grande no repite el trabajo de sus hijos—, en vez de una consulta
/// por cada uno de los miles de valores posibles.
bool hasCompleteTopicBranch({
  required VocabularyTree temaTree,
  required Map<String, Set<String>> sourcesByTema,
  required Set<String> coveredSourceIds,
}) {
  // Cada valor que aparece como asignación directa, o como ancestro de
  // uno: los demás no tienen ninguna fuente en su rama, tampoco a través
  // de sus hijos.
  final candidates = <String>{};
  for (final valueId in sourcesByTema.keys) {
    var current = valueId;
    while (true) {
      if (!candidates.add(current)) break;
      final parent = temaTree.parentOf(current);
      if (parent == null) break;
      current = parent;
    }
  }

  // De las hojas hacia la raíz: la rama de un valor es sus fuentes propias
  // más la unión de las de cada uno de sus hijos, ya resuelta antes.
  final order = candidates.toList()
    ..sort((a, b) => temaTree.depthOf(b).compareTo(temaTree.depthOf(a)));
  final branchSources = <String, Set<String>>{};
  for (final valueId in order) {
    final sources = {...?sourcesByTema[valueId]};
    for (final child in temaTree.childrenOf(valueId)) {
      final childSources = branchSources[child];
      if (childSources != null) sources.addAll(childSources);
    }
    branchSources[valueId] = sources;

    if (sources.length >= kMinSourcesForCompleteBranch &&
        sources.every(coveredSourceIds.contains)) {
      return true;
    }
  }
  return false;
}
