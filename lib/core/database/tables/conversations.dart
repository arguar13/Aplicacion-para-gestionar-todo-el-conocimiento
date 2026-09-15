import 'package:drift/drift.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';

/// Una conversación guardada del chat — ver `ChatConversation` en el
/// dominio para el porqué.
@DataClassName('ConversationRow')
@TableIndex(name: 'idx_conversations_mode', columns: {#mode})
@TableIndex(name: 'idx_conversations_updated_at', columns: {#updatedAt})
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get mode => textEnum<ChatConversationMode>()();
  TextColumn get title => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
