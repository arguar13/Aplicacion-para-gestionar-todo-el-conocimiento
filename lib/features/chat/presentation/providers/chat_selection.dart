import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';

/// Dónde está parado el chat (F42): en qué modo se pregunta, a qué cuaderno
/// queda acotado el modo con la bóveda y qué conversación de cada modo está
/// abierta.
///
/// Hasta F42 vivía suelto en el estado de `ChatScreen`; ahora lo leen y lo
/// cambian piezas que no son la pantalla —la barra de arriba, el panel de
/// conversaciones, el «+» del campo—, así que tiene un solo dueño:
/// [chatSelectionProvider]. Lo que cuesta cerrar (la sesión del modelo, la
/// respuesta que se está escribiendo) lo sigue manejando la pantalla, que
/// escucha este estado y reacciona cuando cambia la conversación abierta.
@immutable
class ChatSelection {
  const ChatSelection({
    this.mode = ChatConversationMode.vault,
    this.notebookId,
    this.vaultConversationId,
    this.freeConversationId,
  });

  /// El modo en que se pregunta ahora.
  final ChatConversationMode mode;

  /// A qué cuaderno queda acotado el modo con la bóveda (F16, D1). `null` es
  /// «toda la bóveda». El modo libre lo ignora.
  final String? notebookId;

  /// La conversación abierta en cada modo; `null` es una nueva, todavía sin
  /// mensajes. Cada modo recuerda la suya: cambiar de modo y volver no la
  /// pierde.
  final String? vaultConversationId;
  final String? freeConversationId;

  bool get isFree => mode == ChatConversationMode.free;

  /// La conversación abierta en el modo de ahora.
  String? get conversationId => conversationIdOf(mode);

  String? conversationIdOf(ChatConversationMode mode) => switch (mode) {
    ChatConversationMode.vault => vaultConversationId,
    ChatConversationMode.free => freeConversationId,
  };

  /// Si [conversationId] es la abierta de alguno de los dos modos.
  bool holds(String conversationId) =>
      vaultConversationId == conversationId ||
      freeConversationId == conversationId;

  ChatSelection _withConversation(ChatConversationMode mode, String? id) =>
      ChatSelection(
        mode: this.mode,
        notebookId: notebookId,
        vaultConversationId: mode == ChatConversationMode.vault
            ? id
            : vaultConversationId,
        freeConversationId: mode == ChatConversationMode.free
            ? id
            : freeConversationId,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatSelection &&
      other.mode == mode &&
      other.notebookId == notebookId &&
      other.vaultConversationId == vaultConversationId &&
      other.freeConversationId == freeConversationId;

  @override
  int get hashCode =>
      Object.hash(mode, notebookId, vaultConversationId, freeConversationId);

  @override
  String toString() =>
      'ChatSelection($mode, cuaderno: $notebookId, '
      'bóveda: $vaultConversationId, libre: $freeConversationId)';
}

/// Cambia [ChatSelection] con las reglas de siempre del chat, en un solo
/// lugar: quien toca el modo o el alcance —la línea debajo del modelo, el
/// «+» del campo— no tiene que saber cuándo eso abre una conversación nueva.
class ChatSelectionNotifier extends StateNotifier<ChatSelection> {
  ChatSelectionNotifier() : super(const ChatSelection());

  /// Pasa a [mode]. La conversación de cada modo queda como estaba.
  void changeMode(ChatConversationMode mode) {
    if (mode == state.mode) return;
    state = ChatSelection(
      mode: mode,
      notebookId: state.notebookId,
      vaultConversationId: state.vaultConversationId,
      freeConversationId: state.freeConversationId,
    );
  }

  /// Acota el modo con la bóveda a [notebookId] —`null`, toda la bóveda—.
  /// Si había una conversación con la bóveda abierta, se arranca una nueva:
  /// el cuaderno de una conversación queda fijo desde que se crea y no
  /// cambia bajo lo ya dicho (F16, D1).
  void selectNotebook(String? notebookId) {
    if (notebookId == state.notebookId) return;
    state = ChatSelection(
      mode: state.mode,
      notebookId: notebookId,
      freeConversationId: state.freeConversationId,
    );
  }

  /// Deja el modo de ahora listo para una conversación nueva, sin borrar
  /// ninguna: la fila del historial se crea con el primer mensaje.
  void startNew() {
    if (state.conversationId == null) return;
    state = state._withConversation(state.mode, null);
  }

  /// Abre [conversation]: pasa a su modo y, si es con la bóveda, vuelve a su
  /// cuaderno.
  void open(ChatConversation conversation) {
    final mode = conversation.mode;
    state = ChatSelection(
      mode: mode,
      notebookId: mode == ChatConversationMode.vault
          ? conversation.notebookId
          : state.notebookId,
      vaultConversationId: mode == ChatConversationMode.vault
          ? conversation.id
          : state.vaultConversationId,
      freeConversationId: mode == ChatConversationMode.free
          ? conversation.id
          : state.freeConversationId,
    );
  }

  /// La conversación [id] de [mode] se acaba de crear con el primer mensaje.
  void started(ChatConversationMode mode, String id) {
    if (state.conversationIdOf(mode) == id) return;
    state = state._withConversation(mode, id);
  }

  /// La conversación [id] se borró (o va a borrarse): si estaba abierta en
  /// algún modo, ese modo queda en una nueva.
  void forget(String id) {
    var next = state;
    if (next.vaultConversationId == id) {
      next = next._withConversation(ChatConversationMode.vault, null);
    }
    if (next.freeConversationId == id) {
      next = next._withConversation(ChatConversationMode.free, null);
    }
    state = next;
  }
}

/// El modo, el alcance y la conversación abierta del chat (F42). Es la API
/// para todo lo que, fuera de la pantalla, muestra o cambia dónde se
/// pregunta: `ref.watch(chatSelectionProvider)` para leerlo y
/// `ref.read(chatSelectionProvider.notifier)` para cambiarlo.
///
/// `autoDispose`: vive lo que la pantalla del chat, igual que cuando era su
/// estado propio.
final chatSelectionProvider =
    StateNotifierProvider.autoDispose<ChatSelectionNotifier, ChatSelection>(
      (ref) => ChatSelectionNotifier(),
    );
