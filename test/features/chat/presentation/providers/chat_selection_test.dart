import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_selection.dart';

/// Las reglas de dónde está parado el chat (F42): las mismas que tenía la
/// pantalla, ahora en un solo dueño que pueden tocar la barra, el panel y el
/// «+» del campo.
void main() {
  late ChatSelectionNotifier selector;

  setUp(() => selector = ChatSelectionNotifier());
  tearDown(() => selector.dispose());

  ChatConversation conversation(
    String id,
    ChatConversationMode mode, {
    String? notebookId,
  }) => ChatConversation(
    id: id,
    mode: mode,
    createdAt: DateTime(2026, 9, 11),
    updatedAt: DateTime(2026, 9, 11),
    notebookId: notebookId,
  );

  test('arranca con la bóveda, toda la bóveda y sin conversación', () {
    expect(selector.state, const ChatSelection());
    expect(selector.state.mode, ChatConversationMode.vault);
    expect(selector.state.isFree, isFalse);
    expect(selector.state.notebookId, isNull);
    expect(selector.state.conversationId, isNull);
  });

  test('cada modo recuerda su conversación al ir y volver', () {
    selector
      ..started(ChatConversationMode.vault, 'b1')
      ..changeMode(ChatConversationMode.free);
    expect(selector.state.isFree, isTrue);
    expect(selector.state.conversationId, isNull);

    selector.started(ChatConversationMode.free, 'l1');
    expect(selector.state.conversationId, 'l1');

    selector.changeMode(ChatConversationMode.vault);
    expect(selector.state.conversationId, 'b1');
    expect(selector.state.freeConversationId, 'l1');
  });

  test('cambiar al mismo modo no avisa a nadie', () {
    final seen = <ChatSelection>[];
    selector
      ..addListener(seen.add, fireImmediately: false)
      ..changeMode(ChatConversationMode.vault);
    expect(seen, isEmpty);
  });

  group('elegir un cuaderno', () {
    test('con una conversación de la bóveda abierta, arranca una nueva; la '
        'libre no se toca', () {
      selector
        ..started(ChatConversationMode.vault, 'b1')
        ..started(ChatConversationMode.free, 'l1')
        ..selectNotebook('tesis');

      expect(selector.state.notebookId, 'tesis');
      expect(selector.state.vaultConversationId, isNull);
      expect(selector.state.freeConversationId, 'l1');
    });

    test('elegir el mismo no cambia nada', () {
      selector
        ..selectNotebook('tesis')
        ..started(ChatConversationMode.vault, 'b1')
        ..selectNotebook('tesis');
      expect(selector.state.vaultConversationId, 'b1');
    });

    test('se puede elegir estando en la conversación libre', () {
      selector
        ..changeMode(ChatConversationMode.free)
        ..selectNotebook('tesis');
      expect(selector.state.isFree, isTrue);
      expect(selector.state.notebookId, 'tesis');
    });
  });

  test('una nueva deja atrás solo la del modo de ahora', () {
    selector
      ..started(ChatConversationMode.vault, 'b1')
      ..started(ChatConversationMode.free, 'l1')
      ..startNew();
    expect(selector.state.vaultConversationId, isNull);
    expect(selector.state.freeConversationId, 'l1');

    final before = selector.state;
    selector.startNew();
    expect(identical(selector.state, before), isTrue);
  });

  group('abrir una conversación', () {
    test('con la bóveda: pasa a ese modo y vuelve a su cuaderno', () {
      selector
        ..changeMode(ChatConversationMode.free)
        ..open(
          conversation('b1', ChatConversationMode.vault, notebookId: 'tesis'),
        );
      expect(selector.state.mode, ChatConversationMode.vault);
      expect(selector.state.vaultConversationId, 'b1');
      expect(selector.state.notebookId, 'tesis');
    });

    test('con la bóveda entera: vuelve a toda la bóveda', () {
      selector
        ..selectNotebook('tesis')
        ..open(conversation('b1', ChatConversationMode.vault));
      expect(selector.state.notebookId, isNull);
    });

    test('libre: pasa a ese modo y el cuaderno de la bóveda queda', () {
      selector
        ..selectNotebook('tesis')
        ..started(ChatConversationMode.vault, 'b1')
        ..open(conversation('l1', ChatConversationMode.free));
      expect(selector.state.isFree, isTrue);
      expect(selector.state.freeConversationId, 'l1');
      expect(selector.state.vaultConversationId, 'b1');
      expect(selector.state.notebookId, 'tesis');
    });
  });

  test('«started» con la misma no avisa', () {
    selector.started(ChatConversationMode.vault, 'b1');
    final before = selector.state;
    selector.started(ChatConversationMode.vault, 'b1');
    expect(identical(selector.state, before), isTrue);
  });

  test('olvidar una borrada deja su modo en una nueva', () {
    selector
      ..started(ChatConversationMode.vault, 'b1')
      ..started(ChatConversationMode.free, 'l1')
      ..forget('l1');
    expect(selector.state.freeConversationId, isNull);
    expect(selector.state.vaultConversationId, 'b1');

    selector
      ..forget('otra')
      ..forget('b1');
    expect(selector.state.vaultConversationId, isNull);
  });

  test('holds dice si una conversación está abierta en algún modo', () {
    const selection = ChatSelection(
      vaultConversationId: 'b1',
      freeConversationId: 'l1',
    );
    expect(selection.holds('b1'), isTrue);
    expect(selection.holds('l1'), isTrue);
    expect(selection.holds('otra'), isFalse);
  });

  test('dos selecciones iguales son iguales', () {
    expect(
      const ChatSelection(notebookId: 'a', vaultConversationId: 'b'),
      const ChatSelection(notebookId: 'a', vaultConversationId: 'b'),
    );
    expect(
      const ChatSelection(notebookId: 'a').hashCode,
      const ChatSelection(notebookId: 'a').hashCode,
    );
    for (final other in const [
      ChatSelection(mode: ChatConversationMode.free, notebookId: 'a'),
      ChatSelection(notebookId: 'b'),
      ChatSelection(notebookId: 'a', vaultConversationId: 'x'),
      ChatSelection(notebookId: 'a', freeConversationId: 'x'),
    ]) {
      expect(other, isNot(const ChatSelection(notebookId: 'a')));
    }
  });
}
