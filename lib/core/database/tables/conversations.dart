import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/notebooks.dart';
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

  /// A qué cuaderno queda acotada (F16, D1). `null` es «toda la bóveda» — el
  /// único valor posible en modo `free`, donde el concepto no aplica. Si el
  /// cuaderno se borra, la conversación no se lleva con él: queda sin
  /// acotar, no desaparece su historial.
  TextColumn get notebookId => text().nullable().references(
    Notebooks,
    #id,
    onDelete: KeyAction.setNull,
  )();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
