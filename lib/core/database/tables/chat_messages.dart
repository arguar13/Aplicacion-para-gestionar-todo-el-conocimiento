import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/conversations.dart';

/// Un mensaje de una conversación guardada — ver `PersistedChatMessage` en
/// el dominio.
///
/// `sourcesJson`/`attachmentsJson` son texto y no una tabla aparte cada
/// uno: son listas chicas, propias de un solo mensaje, que nunca se
/// consultan por su cuenta —nadie busca "todos los mensajes que citan tal
/// fuente"—, así que separarlas en tablas relacionadas sería más
/// complejidad de la que compra ninguna consulta real. Mismo criterio que
/// ya usa `Rendition.text` para los bloques de una nota (ver
/// `encodeContentBlocks`).
@DataClassName('ChatMessageRow')
@TableIndex(name: 'idx_chat_messages_conversation', columns: {#conversationId})
class ChatMessages extends Table {
  TextColumn get id => text()();

  TextColumn get conversationId =>
      text().references(Conversations, #id, onDelete: KeyAction.cascade)();

  BoolColumn get isUser => boolean()();
  TextColumn get content => text()();
  TextColumn get sourcesJson => text().nullable()();
  TextColumn get attachmentsJson => text().nullable()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
