import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/chat_attachment.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/data/repositories/chat_conversation_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: lo que hay que verificar acá es que las
/// conversaciones y sus mensajes sobreviven a una vuelta completa por la
/// base —incluidas las fuentes y los adjuntos, que van codificados como
/// texto—, y no solo que un doble responda lo que se le pida.
void main() {
  late AppDatabase db;
  late ChatConversationRepositoryImpl repository;
  late FakeIdGenerator ids;
  var now = DateTime(2026, 9, 15, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    now = DateTime(2026, 9, 15, 10);
    repository = ChatConversationRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  group('createConversation', () {
    test('crea una conversación vacía del modo pedido', () async {
      final conversation = await repository.createConversation(
        ChatConversationMode.vault,
      );

      expect(conversation.id, 'id-0');
      expect(conversation.mode, ChatConversationMode.vault);
      expect(conversation.title, isNull);
      expect(conversation.createdAt, now);
      expect(conversation.updatedAt, now);
    });
  });

  group('watchConversations', () {
    test('separa las conversaciones por modo', () async {
      await repository.createConversation(ChatConversationMode.vault);
      await repository.createConversation(ChatConversationMode.free);

      final vaultConversations = await repository
          .watchConversations(ChatConversationMode.vault)
          .first;
      final freeConversations = await repository
          .watchConversations(ChatConversationMode.free)
          .first;

      expect(vaultConversations, hasLength(1));
      expect(vaultConversations.single.mode, ChatConversationMode.vault);
      expect(freeConversations, hasLength(1));
      expect(freeConversations.single.mode, ChatConversationMode.free);
    });

    test('ordena las más nuevas primero', () async {
      final first = await repository.createConversation(
        ChatConversationMode.free,
      );
      now = now.add(const Duration(minutes: 5));
      final second = await repository.createConversation(
        ChatConversationMode.free,
      );

      final conversations = await repository
          .watchConversations(ChatConversationMode.free)
          .first;

      expect(conversations.map((c) => c.id), [second.id, first.id]);
    });

    test(
      'agregar un mensaje sube la conversación al principio de la lista',
      () async {
        final older = await repository.createConversation(
          ChatConversationMode.free,
        );
        now = now.add(const Duration(minutes: 1));
        final newer = await repository.createConversation(
          ChatConversationMode.free,
        );

        now = now.add(const Duration(minutes: 5));
        await repository.addMessage(
          PersistedChatMessage(
            id: ids.next(),
            conversationId: older.id,
            isUser: true,
            text: 'Un mensaje tardío',
            createdAt: now,
          ),
        );

        final conversations = await repository
            .watchConversations(ChatConversationMode.free)
            .first;

        expect(conversations.map((c) => c.id), [older.id, newer.id]);
      },
    );
  });

  group('addMessage', () {
    test('guarda el mensaje y lo puede leer watchMessages', () async {
      final conversation = await repository.createConversation(
        ChatConversationMode.vault,
      );

      final message = PersistedChatMessage(
        id: ids.next(),
        conversationId: conversation.id,
        isUser: false,
        text: 'La respuesta, citando la bóveda.',
        createdAt: now,
        sources: const [
          ChatSource(
            itemId: 'item-1',
            itemTitle: 'Un elemento',
            excerpt: 'El fragmento citado.',
          ),
        ],
      );
      await repository.addMessage(message);

      final messages = await repository.watchMessages(conversation.id).first;

      expect(messages, hasLength(1));
      expect(messages.single.text, message.text);
      expect(messages.single.isUser, isFalse);
      expect(messages.single.sources, message.sources);
    });

    test('guarda los adjuntos de un mensaje del usuario', () async {
      final conversation = await repository.createConversation(
        ChatConversationMode.free,
      );

      final message = PersistedChatMessage(
        id: ids.next(),
        conversationId: conversation.id,
        isUser: true,
        text: '¿Qué dice este documento?',
        createdAt: now,
        attachments: const [
          ChatAttachment(
            name: 'informe.pdf',
            kind: ChatAttachmentKind.document,
            relativePath: 'attachments/informe.pdf',
            extractedText: 'Contenido extraído del PDF.',
          ),
        ],
      );
      await repository.addMessage(message);

      final messages = await repository.watchMessages(conversation.id).first;

      expect(messages.single.attachments, message.attachments);
    });

    test('pone título automático con el primer mensaje del usuario', () async {
      final conversation = await repository.createConversation(
        ChatConversationMode.free,
      );

      await repository.addMessage(
        PersistedChatMessage(
          id: ids.next(),
          conversationId: conversation.id,
          isUser: true,
          text: '¿Cuál es la capital de Francia y por qué?',
          createdAt: now,
        ),
      );

      final conversations = await repository
          .watchConversations(ChatConversationMode.free)
          .first;

      expect(conversations.single.title, isNotNull);
      expect(conversations.single.title, startsWith('¿Cuál es la capital'));
    });

    test('no reemplaza un título que ya existe', () async {
      final conversation = await repository.createConversation(
        ChatConversationMode.free,
      );

      await repository.addMessage(
        PersistedChatMessage(
          id: ids.next(),
          conversationId: conversation.id,
          isUser: true,
          text: 'Primera pregunta',
          createdAt: now,
        ),
      );
      await repository.addMessage(
        PersistedChatMessage(
          id: ids.next(),
          conversationId: conversation.id,
          isUser: true,
          text: 'Segunda pregunta',
          createdAt: now,
        ),
      );

      final conversations = await repository
          .watchConversations(ChatConversationMode.free)
          .first;

      expect(conversations.single.title, 'Primera pregunta');
    });

    test('un mensaje del modelo no le pone título a la conversación', () async {
      final conversation = await repository.createConversation(
        ChatConversationMode.free,
      );

      await repository.addMessage(
        PersistedChatMessage(
          id: ids.next(),
          conversationId: conversation.id,
          isUser: false,
          text: 'Una respuesta cualquiera',
          createdAt: now,
        ),
      );

      final conversations = await repository
          .watchConversations(ChatConversationMode.free)
          .first;

      expect(conversations.single.title, isNull);
    });
  });

  group('deleteConversation', () {
    test('borra la conversación y sus mensajes en cascada', () async {
      final conversation = await repository.createConversation(
        ChatConversationMode.vault,
      );
      await repository.addMessage(
        PersistedChatMessage(
          id: ids.next(),
          conversationId: conversation.id,
          isUser: true,
          text: 'Algo',
          createdAt: now,
        ),
      );

      await repository.deleteConversation(conversation.id);

      final conversations = await repository
          .watchConversations(ChatConversationMode.vault)
          .first;
      final messages = await repository.watchMessages(conversation.id).first;

      expect(conversations, isEmpty);
      expect(messages, isEmpty);
    });
  });
}
