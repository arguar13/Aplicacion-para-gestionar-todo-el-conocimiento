import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';

/// El historial del chat: las conversaciones guardadas y sus mensajes.
///
/// Devuelve `Stream`, no `Future`, para lo que se lista — mismo criterio
/// que `LibraryRepository` (ver la decisión 1 en docs/arquitectura.md):
/// la pantalla del historial y la de una conversación abierta se actualizan
/// solas cuando algo cambia, sin que nadie tenga que acordarse de volver a
/// pedirlo.
abstract interface class ChatConversationRepository {
  /// Las conversaciones de [mode], más nueva primero por
  /// [ChatConversation.updatedAt].
  Stream<List<ChatConversation>> watchConversations(ChatConversationMode mode);

  /// Los mensajes de una conversación, en el orden en que se escribieron.
  Stream<List<PersistedChatMessage>> watchMessages(String conversationId);

  /// Arranca una conversación nueva y vacía, del modo que corresponda.
  ///
  /// [notebookId] la acota a ese cuaderno (F16, D1) — solo tiene sentido en
  /// [ChatConversationMode.vault]; en [ChatConversationMode.free] se ignora.
  Future<ChatConversation> createConversation(
    ChatConversationMode mode, {
    String? notebookId,
  });

  /// Agrega un mensaje al final de su conversación.
  ///
  /// Si es el primer mensaje del usuario y la conversación todavía no
  /// tiene título, también le pone uno —derivado del propio mensaje—: es
  /// lo que hace que el historial muestre algo más útil que "Nueva
  /// conversación" para siempre.
  Future<void> addMessage(PersistedChatMessage message);

  /// Borra una conversación entera, con todos sus mensajes.
  Future<void> deleteConversation(String id);
}
