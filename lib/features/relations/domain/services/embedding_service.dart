/// Calcula vectores de embedding para texto, sobre el mismo modelo que
/// preselecciona candidatos por similitud para el motor de relaciones (F5)
/// — nunca decide él mismo qué está relacionado con qué, solo produce el
/// vector; comparar y ordenar por similitud es responsabilidad de
/// `RelationCandidateSelector`.
abstract interface class EmbeddingService {
  /// El vector de un solo texto.
  Future<List<double>> embed(String text);

  /// Los vectores de varios textos a la vez —más eficiente que llamar
  /// [embed] uno por uno cuando ya se sabe que van a pedirse todos juntos.
  Future<List<List<double>>> embedBatch(List<String> texts);

  /// Saca el modelo de la memoria, si no se está usando (F30): el próximo
  /// pedido lo vuelve a cargar. Con [unusedFor], solo si pasó al menos ese
  /// rato desde el último uso.
  Future<void> release({Duration? unusedFor});
}

/// Se pidió un embedding sin haber descargado el modelo todavía. El
/// llamador debería haber comprobado `EmbeddingModelManager.isReady()`
/// antes.
class EmbeddingModelNotReadyException implements Exception {
  const EmbeddingModelNotReadyException();

  @override
  String toString() => 'El modelo de embeddings todavía no está descargado.';
}
