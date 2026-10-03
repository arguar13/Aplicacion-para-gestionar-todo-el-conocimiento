/// Un candidato a vincular con el elemento semilla, ya puntuado por
/// similitud —el mismo molde que `RelationCandidate` del grafo
/// (`itemId`/`title`/`excerpt`), más [score]—.
class ScoredRelationCandidate {
  const ScoredRelationCandidate({
    required this.itemId,
    required this.title,
    required this.excerpt,
    required this.score,
  });

  final String itemId;
  final String title;
  final String excerpt;

  /// Similitud coseno entre los centroides del semilla y este candidato,
  /// entre -1.0 y 1.0.
  final double score;
}

/// Preselecciona candidatos a vincular con un elemento semilla por
/// similitud coseno de sus centroides de embeddings —ver la decisión
/// sobre F5, D6—.
///
/// Los embeddings son SOLO preselección: quién de verdad juzga el tipo de
/// vínculo es `RelationSuggestionService`, no este selector — reemplaza
/// el "primeros N en orden de llegada" del diálogo manual del grafo por
/// una preselección real, sin cambiar quién decide el vínculo.
abstract interface class RelationCandidateSelector {
  /// Hasta [limit] candidatos con similitud `>= [minSimilarity]`, de
  /// mayor a menor score. Lista vacía si [seedItemId] no tiene chunks o
  /// embeddings propios todavía, o si ningún otro elemento supera el
  /// umbral — no es un error, es que no hay nada que preseleccionar
  /// todavía.
  Future<List<ScoredRelationCandidate>> selectCandidates({
    required String seedItemId,
    int limit = 15,
    double minSimilarity = 0.5,
  });

  /// Lo mismo que [selectCandidates], pero con el semilla descripto por
  /// [seedVectors] en vez de por sus fragmentos guardados (F27): una nota no
  /// se fragmenta —es texto del usuario que cambia—, así que la IA que la
  /// vincula calcula sus vectores en el momento. [seedItemId] queda afuera
  /// de los candidatos.
  Future<List<ScoredRelationCandidate>> selectCandidatesNear({
    required String seedItemId,
    required List<List<double>> seedVectors,
    int limit = 15,
    double minSimilarity = 0.5,
  });
}
