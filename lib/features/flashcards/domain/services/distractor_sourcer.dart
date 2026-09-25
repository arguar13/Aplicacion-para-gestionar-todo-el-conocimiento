/// Un distractor real de la bóveda para una pregunta de quiz (F20): nunca
/// inventado por el modelo, siempre anclado a un chunk real de un elemento
/// —no necesariamente el mismo que la pregunta—.
class DistractorCandidate {
  const DistractorCandidate({
    required this.itemId,
    required this.content,
    required this.sourceChunkId,
    required this.sourceCharStart,
    required this.sourceCharEnd,
  });

  final String itemId;
  final String content;
  final String sourceChunkId;
  final int sourceCharStart;
  final int sourceCharEnd;
}

/// Busca distractores reales para la respuesta correcta de una pregunta de
/// quiz (F20, decisión C): nunca los inventa, salen de material que ya está
/// en la bóveda, cada uno anclado a su propio chunk.
///
/// Orden de las fuentes, de la decisión C: hermanos del elemento semilla en
/// la jerarquía del Atlas (tema de vocabulario), el otro lado de una
/// relación `contradicts`, cercanía por embedding. «Misma comunidad del
/// Mapa» queda deliberadamente afuera: hoy no hay forma de leerla sin forzar
/// un cálculo completo del Mapa (investigado, `KnowledgeMapEngine` no
/// expone un `peek` de solo lectura), y el propio plan la deja como cuarta
/// fuente opcional, solo si las otras tres no alcanzan.
// ignore: one_member_abstracts
abstract interface class DistractorSourcer {
  /// Hasta [count] distractores para una pregunta cuya respuesta correcta
  /// sale de [seedItemId], sin repetir elemento entre sí ni citar
  /// [seedItemId], y descartando cualquier candidato cuyo texto coincida con
  /// [excludeContent] —la respuesta correcta: un distractor nunca puede ser
  /// también correcto—.
  ///
  /// Lista más corta que [count], o vacía, si la bóveda no tiene suficiente
  /// material real: nunca se completa con nada inventado. Decidir qué hacer
  /// con una lista corta —degradar a verdadero/falso o descartar la
  /// pregunta— es de quien guarda, no de acá.
  Future<List<DistractorCandidate>> sourceDistractors({
    required String seedItemId,
    required String excludeContent,
    int count = 3,
  });
}
