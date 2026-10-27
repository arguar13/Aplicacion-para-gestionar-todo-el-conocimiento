import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/data/repositories/chat_conversation_repository_impl.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_history.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';

import '../../../../support/fake_id_generator.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

void main() {
  /// Viernes 11 de septiembre de 2026, 10:00.
  final now = DateTime(2026, 9, 11, 10);

  ChatConversation at(String id, DateTime updatedAt, {String? title}) =>
      ChatConversation(
        id: id,
        mode: ChatConversationMode.vault,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        title: title ?? id,
      );

  group('groupChatHistory', () {
    test('sin conversaciones, sin secciones', () {
      expect(groupChatHistory(const [], pinned: const {}, now: now), isEmpty);
    });

    test('las fijadas primero; después hoy, ayer y cada día anterior, '
        'manteniendo el orden de llegada dentro de cada uno', () {
      final sections = groupChatHistory(
        [
          at('hoy-2', DateTime(2026, 9, 11, 9)),
          at('hoy-1', DateTime(2026, 9, 11, 0, 5)),
          at('fijada', DateTime(2026, 9, 10, 20)),
          at('anoche', DateTime(2026, 9, 10, 23, 50)),
          at('domingo', DateTime(2026, 9, 6, 12)),
          at('fin-de-mes', DateTime(2026, 8, 31, 23)),
        ],
        pinned: {'fijada'},
        now: now,
      );

      expect(sections.map((s) => s.kind), [
        ChatHistorySectionKind.pinned,
        ChatHistorySectionKind.today,
        ChatHistorySectionKind.yesterday,
        ChatHistorySectionKind.day,
        ChatHistorySectionKind.day,
      ]);
      expect(sections.map((s) => s.conversations.map((c) => c.id).toList()), [
        ['fijada'],
        ['hoy-2', 'hoy-1'],
        ['anoche'],
        ['domingo'],
        ['fin-de-mes'],
      ]);
      expect(sections[0].day, isNull);
      expect(sections[1].day, DateTime(2026, 9, 11));
      expect(sections[2].day, DateTime(2026, 9, 10));
      expect(sections[3].day, DateTime(2026, 9, 6));
      expect(sections[4].day, DateTime(2026, 8, 31));
    });

    test('«ayer» del primero del mes es el último del mes anterior', () {
      final sections = groupChatHistory(
        [at('a', DateTime(2026, 8, 31, 22))],
        pinned: const {},
        now: DateTime(2026, 9, 1, 8),
      );
      expect(sections.single.kind, ChatHistorySectionKind.yesterday);
    });

    test('un fijado que ya no existe no arma una sección vacía', () {
      final sections = groupChatHistory(
        [at('a', now)],
        pinned: {'borrada'},
        now: now,
      );
      expect(sections.single.kind, ChatHistorySectionKind.today);
    });

    test('el buscador mira el título sin acentos ni mayúsculas, también en '
        'las fijadas, y deja afuera las sin título', () {
      final sections = groupChatHistory(
        [
          at('a', now, title: 'La Revolución Francesa'),
          at('b', now, title: 'Recetas'),
          at('c', DateTime(2026, 9, 2), title: 'revolución rusa'),
          ChatConversation(
            id: 'd',
            mode: ChatConversationMode.free,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        pinned: {'c'},
        now: now,
        query: '  REVOLUCION ',
      );
      expect(
        [
          for (final s in sections)
            for (final c in s.conversations) c.id,
        ],
        ['c', 'a'],
      );
    });

    test('un buscador vacío o de puros espacios no filtra', () {
      final all = [
        at('a', now),
        ChatConversation(
          id: 'sin-titulo',
          mode: ChatConversationMode.free,
          createdAt: now,
          updatedAt: now,
        ),
      ];
      for (final query in ['', '   ']) {
        expect(
          groupChatHistory(
            all,
            pinned: const {},
            now: now,
            query: query,
          ).single.conversations,
          hasLength(2),
        );
      }
    });
  });

  group('foldForSearch', () {
    test('minúsculas, sin acentos y un solo espacio entre palabras', () {
      expect(foldForSearch('  Él   CANTÓ,  señor!  '), 'el canto senor');
      expect(foldForSearch(''), '');
      expect(foldForSearch('¿?'), '');
    });
  });

  group('las fijadas', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('fijar, desfijar y alternar se guardan en el teléfono', () async {
      final pins = ChatPinsNotifier(prefs: prefs);
      addTearDown(pins.dispose);

      await pins.pin('a');
      await pins.pin('a');
      await pins.toggle('b');
      expect(pins.state, {'a', 'b'});
      expect(prefs.getStringList(ChatPinsNotifier.prefsKey), ['a', 'b']);

      await pins.toggle('a');
      await pins.unpin('nunca');
      expect(pins.state, {'b'});
      expect(pins.isPinned('b'), isTrue);
      expect(pins.isPinned('a'), isFalse);
      expect(prefs.getStringList(ChatPinsNotifier.prefsKey), ['b']);

      final again = ChatPinsNotifier(prefs: prefs);
      addTearDown(again.dispose);
      expect(again.state, {'b'});
    });
  });

  group('chatHistoryProvider', () {
    test('junta las de los dos modos, la última usada primero', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var clock = DateTime(2026, 9, 11, 8);
      final repository = ChatConversationRepositoryImpl(
        database: db,
        telemetry: _MockTelemetry(),
        ids: FakeIdGenerator(),
        clock: () => clock,
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          chatConversationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      Future<void> say(ChatConversationMode mode, String text) async {
        final c = await repository.createConversation(mode);
        await repository.addMessage(
          PersistedChatMessage(
            id: 'm-$text',
            conversationId: c.id,
            isUser: true,
            text: text,
            createdAt: clock,
          ),
        );
        clock = clock.add(const Duration(minutes: 5));
      }

      await say(ChatConversationMode.vault, 'primera');
      await say(ChatConversationMode.free, 'segunda');
      await say(ChatConversationMode.vault, 'tercera');

      final sub = container.listen(chatHistoryProvider, (_, _) {});
      addTearDown(sub.close);
      expect(sub.read(), isA<AsyncLoading<List<ChatConversation>>>());
      for (var i = 0; i < 20 && !sub.read().hasValue; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(sub.read().requireValue.map((c) => c.title), [
        'tercera',
        'segunda',
        'primera',
      ]);
    });
  });
}
