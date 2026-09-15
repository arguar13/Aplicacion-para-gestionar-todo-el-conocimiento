import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/chat_source.dart';

/// Redacta una respuesta en lenguaje natural a partir de una pregunta y las
/// fuentes que `VaultRetriever` encontró.
///
/// Es la mitad "G" de RAG. Corre enteramente en el dispositivo —Gemma vía
/// `flutter_gemma`, ver la decisión 20—: nunca se manda la pregunta ni el
/// contenido de la bóveda a ningún servidor, el mismo principio 1 de
/// siempre.
abstract interface class ChatModel {
  /// La respuesta a [question], basada solo en [sources] —nunca en
  /// conocimiento general del modelo—: citarlas es lo que permite confiar en
  /// de dónde sale cada dato.
  Future<String> answer({
    required String question,
    required List<ChatSource> sources,
  });

  /// Arranca una charla libre, sin restringirla al contenido de la bóveda:
  /// el modo "conversación libre" del chat, para hablar con el modelo como
  /// con cualquier asistente de lenguaje general.
  ///
  /// Separada de [answer] a propósito: ahí cada pregunta abre y cierra su
  /// propia sesión porque no tiene sentido que arrastre el historial de la
  /// anterior —cada una busca sus propias fuentes—. Acá es al revés: una
  /// charla libre **es** su historial, así que la sesión vive mientras dure
  /// la conversación y no se cierra pregunta a pregunta.
  Future<FreeConversation> startConversation();

  /// Arranca una charla **sobre la bóveda**, pero conversacional: a
  /// diferencia de [answer] —una pregunta, una respuesta, sesión nueva cada
  /// vez—, acá el historial se mantiene entre mensajes, como en cualquier
  /// chat de verdad. Es lo que permite pedir "resumime esto" después de
  /// haber preguntado por un tema, sin repetir el contexto a mano.
  ///
  /// Las fuentes se buscan por fuera —`VaultRetriever` sigue siendo quien
  /// sabe buscar— y se le pasan a cada [VaultConversation.send] como
  /// contexto nuevo; lo que esta sesión aporta es la memoria de lo
  /// conversado antes, no la búsqueda en sí.
  Future<VaultConversation> startVaultConversation();
}

/// Una conversación libre en curso, con su propio historial en memoria
/// mientras dura.
abstract interface class FreeConversation {
  /// Manda [message] y espera la respuesta, con todo lo dicho antes en esta
  /// misma conversación como contexto.
  ///
  /// [images] son fotos adjuntas al mensaje —vacío si no se adjuntó
  /// ninguna—: Gemma 3n E4B y Gemma 4 E4B son multimodales, así que
  /// mandarlas junto con el texto deja que el modelo las describa o
  /// responda preguntas sobre ellas, no solo sobre lo escrito.
  Future<String> send(String message, {List<Uint8List> images = const []});

  /// Libera lo que haya quedado abierto. Después de esto, [send] no vuelve
  /// a llamarse sobre esta instancia.
  Future<void> close();
}

/// Una charla sobre la bóveda en curso, con memoria de lo conversado.
abstract interface class VaultConversation {
  /// Manda [message] junto con las fuentes que `VaultRetriever` encontró
  /// para él —puede ser una lista vacía, si nada de la bóveda coincide— y
  /// espera la respuesta. A diferencia de [ChatModel.answer], una lista
  /// vacía no corta la conversación en seco: el modelo puede decir
  /// honestamente que no encontró nada específico y seguir charlando, en
  /// vez de negarse a contestar.
  ///
  /// [images] son fotos adjuntas al mensaje —ver [FreeConversation.send]—.
  Future<String> send({
    required String message,
    required List<ChatSource> sources,
    List<Uint8List> images = const [],
  });

  /// Libera lo que haya quedado abierto.
  Future<void> close();
}

/// Se pidió una respuesta sin haber descargado el modelo todavía. El
/// llamador debería haber comprobado `ChatModelManager.isReady()` antes.
class ChatModelNotReadyException implements Exception {
  const ChatModelNotReadyException();

  @override
  String toString() => 'El modelo de chat todavía no está descargado.';
}
