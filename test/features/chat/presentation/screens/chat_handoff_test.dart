import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_selection.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';

import '../../../../support/library_harness.dart';

/// F43, paso 9: una pregunta que otra pantalla le deja al chat
/// («Preguntarle al chat sobre esto» del mapa mental).
void main() {
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  String fieldText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('chat-composer-field')))
      .controller!
      .text;

  testWidgets('la que esperaba al abrirse el chat: conversación nueva con la '
      'bóveda, y mandada', (tester) async {
    harness.container
        .read(chatHandoffProvider.notifier)
        .state = const ChatHandoff(
      question: 'Contame qué dicen mis fuentes sobre «Moisés».',
    );
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();

    expect(harness.container.read(chatHandoffProvider), isNull);
    final selection = harness.container.read(chatSelectionProvider);
    expect(selection.mode, ChatConversationMode.vault);
    expect(selection.notebookId, isNull);
    expect(
      find.text('Contame qué dicen mis fuentes sobre «Moisés».'),
      findsOneWidget,
    );
    expect(fieldText(tester), isEmpty);
  });

  testWidgets('la que llega con el chat abierto, acotada al cuaderno; sin '
      'mandarse, queda en el campo', (tester) async {
    final notebook = await harness.container
        .read(notebookRepositoryProvider)
        .create(name: 'Pentateuco', mode: NotebookMode.manual);
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
    // Venía en conversación libre: la pregunta vuelve a la bóveda.
    harness.container
        .read(chatSelectionProvider.notifier)
        .changeMode(ChatConversationMode.free);
    await tester.pumpAndSettle();

    harness.container.read(chatHandoffProvider.notifier).state = ChatHandoff(
      question: '¿Qué es la Pascua?',
      notebookId: notebook.id,
      send: false,
    );
    await tester.pumpAndSettle();

    final selection = harness.container.read(chatSelectionProvider);
    expect(selection.mode, ChatConversationMode.vault);
    expect(selection.notebookId, notebook.id);
    expect(fieldText(tester), '¿Qué es la Pascua?');
    expect(harness.container.read(chatHandoffProvider), isNull);
  });
}
