import 'package:sinapsis/core/domain/entities/chat_source.dart';

/// Redacta una respuesta en lenguaje natural a partir de una pregunta y las
/// fuentes que `VaultRetriever` encontró.
///
/// Es la mitad "G" de RAG. Corre enteramente en el dispositivo —Gemma vía
/// `flutter_gemma`, ver la decisión 20—: nunca se manda la pregunta ni el
/// contenido de la bóveda a ningún servidor, el mismo principio 1 de
/// siempre.
// ignore: one_member_abstracts
abstract interface class ChatModel {
  /// La respuesta a [question], basada solo en [sources] —nunca en
  /// conocimiento general del modelo—: citarlas es lo que permite confiar en
  /// de dónde sale cada dato.
  Future<String> answer({
    required String question,
    required List<ChatSource> sources,
  });
}

/// Se pidió una respuesta sin haber descargado el modelo todavía. El
/// llamador debería haber comprobado `ChatModelManager.isReady()` antes.
class ChatModelNotReadyException implements Exception {
  const ChatModelNotReadyException();

  @override
  String toString() => 'El modelo de chat todavía no está descargado.';
}
