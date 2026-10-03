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
  /// mayor a menor score: fuentes y notas (F27), cada una por sus vectores
  /// —los de los fragmentos de una fuente, los de los tramos de una nota—.
  /// Lista vacía si [seedItemId] no tiene vectores propios todavía, o si
  /// ningún otro elemento supera el umbral — no es un error, es que no hay
  /// nada que preseleccionar todavía.
  Future<List<ScoredRelationCandidate>> selectCandidates({
    required String seedItemId,
    int limit = 15,
    double minSimilarity = 0.5,
  });

  /// Lo mismo que [selectCandidates], pero solo fuentes: lo que tiene un
  /// fragmento que citar o donde anclarse, como los distractores de un quiz.
  /// Una nota no tiene fragmentos.
  Future<List<ScoredRelationCandidate>> selectSourceCandidates({
    required String seedItemId,
    int limit = 15,
    double minSimilarity = 0.5,
  });
}
