import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/chat_attachment.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/chat/domain/repositories/chat_conversation_repository.dart';

/// Cuántos caracteres del primer mensaje del usuario se usan como título
/// automático de una conversación nueva.
const _kAutoTitleLength = 48;

class ChatConversationRepositoryImpl implements ChatConversationRepository {
  const ChatConversationRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Stream<List<ChatConversation>> watchConversations(
    ChatConversationMode mode,
  ) {
    return watchQuery(
      db: _db,
      tables: [_db.conversations],
      read: () async {
        final rows =
            await (_db.select(_db.conversations)
                  ..where((c) => c.mode.equalsValue(mode))
                  ..orderBy([
                    (c) => OrderingTerm(
                      expression: c.updatedAt,
                      mode: OrderingMode.desc,
                    ),
                  ]))
                .get();
        return rows.map(_conversationToEntity).toList();
      },
      telemetry: _telemetry,
      hint: 'ChatConversationRepositoryImpl.watchConversations',
    );
  }

  @override
  Stream<List<PersistedChatMessage>> watchMessages(String conversationId) {
    return watchQuery(
      db: _db,
      tables: [_db.chatMessages],
      read: () async {
        final rows =
            await (_db.select(_db.chatMessages)
                  ..where((m) => m.conversationId.equals(conversationId))
                  ..orderBy([(m) => OrderingTerm(expression: m.createdAt)]))
                .get();
        return rows.map(_messageToEntity).toList();
      },
      telemetry: _telemetry,
      hint: 'ChatConversationRepositoryImpl.watchMessages',
    );
  }

  @override
  Future<ChatConversation> createConversation(
    ChatConversationMode mode,
  ) async {
    final now = _clock();
    final conversation = ChatConversation(
      id: _ids.next(),
      mode: mode,
      createdAt: now,
      updatedAt: now,
    );

    await _db
        .into(_db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: conversation.id,
            mode: conversation.mode,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
          ),
        );

    return conversation;
  }

  @override
  Future<void> addMessage(PersistedChatMessage message) async {
    await _db.transaction(() async {
      await _db
          .into(_db.chatMessages)
          .insert(
            ChatMessagesCompanion.insert(
              id: message.id,
              conversationId: message.conversationId,
              isUser: message.isUser,
              content: message.text,
              createdAt: message.createdAt,
              sourcesJson: Value(
                message.sources.isEmpty
                    ? null
                    : encodeChatSources(message.sources),
              ),
              attachmentsJson: Value(
                message.attachments.isEmpty
                    ? null
                    : encodeChatAttachments(message.attachments),
              ),
              error: Value(message.error),
            ),
          );

      final conversationRow = await (_db.select(
        _db.conversations,
      )..where((c) => c.id.equals(message.conversationId))).getSingleOrNull();
      if (conversationRow == null) return;

      final needsTitle =
          message.isUser &&
          conversationRow.title == null &&
          message.text.trim().isNotEmpty;

      await (_db.update(
        _db.conversations,
      )..where((c) => c.id.equals(message.conversationId))).write(
        ConversationsCompanion(
          updatedAt: Value(message.createdAt),
          title: needsTitle
              ? Value(_autoTitle(message.text))
              : const Value.absent(),
        ),
      );
    });
  }

  @override
  Future<void> deleteConversation(String id) async {
    await (_db.delete(_db.conversations)..where((c) => c.id.equals(id))).go();
  }

  String _autoTitle(String text) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length <= _kAutoTitleLength) return trimmed;
    return '${trimmed.substring(0, _kAutoTitleLength).trimRight()}…';
  }

  ChatConversation _conversationToEntity(ConversationRow row) =>
      ChatConversation(
        id: row.id,
        mode: row.mode,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        title: row.title,
      );

  PersistedChatMessage _messageToEntity(ChatMessageRow row) =>
      PersistedChatMessage(
        id: row.id,
        conversationId: row.conversationId,
        isUser: row.isUser,
        text: row.content,
        createdAt: row.createdAt,
        sources: decodeChatSources(row.sourcesJson),
        attachments: decodeChatAttachments(row.attachmentsJson),
        error: row.error,
      );
}
