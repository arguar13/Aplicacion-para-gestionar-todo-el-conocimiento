import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/chat_attachment.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';

part 'persisted_chat_message.freezed.dart';

/// Un mensaje ya guardado del historial: de quién es, qué dice, y con qué
/// fuentes o adjuntos.
///
/// Separado de `ChatAnswer` —que sigue siendo lo que devuelve
/// `AskVaultQuestionUseCase` para una pregunta suelta, sin guardar nada—:
/// acá el mensaje ya tiene una identidad propia (`id`) y un lugar fijo en
/// una conversación (`conversationId`), ninguna de las dos cosas que hacen
/// falta antes de que algo se persista.
@freezed
sealed class PersistedChatMessage with _$PersistedChatMessage {
  const factory PersistedChatMessage({
    required String id,
    required String conversationId,
    required bool isUser,
    required String text,
    required DateTime createdAt,

    /// Las fuentes que citó esta respuesta —solo tiene sentido en el modo
    /// con la bóveda, y solo en un mensaje del modelo—. Vacía en cualquier
    /// otro caso.
    @Default([]) List<ChatSource> sources,

    /// Lo que se adjuntó a este mensaje —solo tiene sentido en uno del
    /// usuario—. Vacía si no se adjuntó nada.
    @Default([]) List<ChatAttachment> attachments,

    /// Si esta vuelta terminó en un error en vez de una respuesta.
    String? error,
  }) = _PersistedChatMessage;
}
