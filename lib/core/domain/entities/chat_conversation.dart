import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';

part 'chat_conversation.freezed.dart';

/// Una conversación guardada del chat: cuándo empezó, de qué modo es, y con
/// qué título aparece en el historial.
///
/// Existe para que el chat se sienta como el de cualquier asistente
/// conocido —ChatGPT, por nombrar el que se pidió explícitamente—: un
/// historial de verdad, no una charla que se pierde apenas se cierra la
/// pantalla.
@freezed
sealed class ChatConversation with _$ChatConversation {
  const factory ChatConversation({
    required String id,
    required ChatConversationMode mode,
    required DateTime createdAt,

    /// Cuándo se agregó el último mensaje — lo que decide el orden del
    /// historial: la conversación en la que se sigue escribiendo tiene que
    /// quedar arriba de todas, no la que se creó primero.
    required DateTime updatedAt,

    /// `null` hasta que llega el primer mensaje del usuario: recién ahí hay
    /// algo de qué derivar un título corto, igual que hace ChatGPT con la
    /// primera línea de la charla. Antes de eso, la pantalla muestra algo
    /// como "Nueva conversación" sin necesidad de guardar ese texto.
    String? title,

    /// A qué cuaderno queda acotada (F16, D1). `null` es «toda la bóveda» —
    /// el único valor posible en modo `free`, donde el concepto no aplica.
    String? notebookId,
  }) = _ChatConversation;
}
