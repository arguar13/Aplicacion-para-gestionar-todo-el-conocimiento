import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_selection.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_answer_message.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_message_list.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_stage_transition.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_typing_indicator.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_user_bubble.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_welcome.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/chat_actions.dart';
import '../../../../support/library_harness.dart';

/// La conversación del chat nuevo (F42, paso 3), en la pantalla de verdad:
/// burbujas y respuestas, el indicador vivo, las acciones, mantener apretado,
/// «↓», las vibraciones, el paso desde el vacío, y que se lea bien en los
/// nueve temas y con letra grande.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late List<String> platformCalls;
  late List<String> copied;

  Future<void> pumpChat(
    WidgetTester tester, {
    bool chatModelReady = true,
    String? chatModelResponse = 'Una respuesta.',
    CapturedFile? chosenFile,
  }) async {
    harness = await LibraryHarness.create(
      chatModelReady: chatModelReady,
      chatModelResponse: chatModelResponse,
      chosenFile: chosenFile,
    );
    platformCalls = [];
    copied = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          platformCalls.add('vibrar ${call.arguments}');
        }
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
  }

  /// La burbuja misma, no la fila entera en la que se alinea a la derecha.
  final bubbles = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('chat-user-bubble-'),
  );

  Finder answerNamed(String text) => find.descendant(
    of: find.byType(ChatAnswerMessage),
    matching: find.text(text),
  );

  group('burbujas y respuestas', () {
    testWidgets('lo tuyo en una burbuja a la derecha; la respuesta a todo lo '
        'ancho, sin burbuja', (tester) async {
      await pumpChat(tester);
      await sendChatMessage(tester, 'Hola');

      final screen = tester.getRect(find.byType(ChatScreen));
      final bubble = tester.getRect(bubbles);
      expect(screen.right - bubble.right, lessThan(24));
      expect(bubble.width, lessThan(screen.width * 0.5));
      final answer = tester.getRect(find.byType(ChatAnswerMessage));
      expect(answer.width, greaterThanOrEqualTo(screen.width - 40));
      expect(
        find.ancestor(
          of: answerNamed('Una respuesta.'),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    });

    testWidgets('la respuesta se ve con formato: títulos y listas', (
      tester,
    ) async {
      await pumpChat(tester, chatModelResponse: '## Roma\n\n- uno\n- dos');
      await sendChatMessage(tester, 'Contame');

      expect(answerNamed('Roma'), findsOneWidget);
      expect(answerNamed('uno'), findsOneWidget);
      expect(find.textContaining('##'), findsNothing);
    });

    testWidgets('en una pantalla ancha la conversación se centra en una '
        'columna', (tester) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpChat(tester);
      await sendChatMessage(tester, 'Hola');

      final answer = tester.getRect(find.byType(ChatAnswerMessage));
      expect(answer.width, lessThanOrEqualTo(760));
      expect(answer.center.dx, closeTo(800, 2));
    });
  });

  group('mientras escribe', () {
    testWidgets('antes de la primera palabra, el indicador vivo dice qué '
        'hace; después, la respuesta que crece', (tester) async {
      await pumpChat(tester);
      harness.chatModel.manualReplies = true;
      await typeAndSend(tester, 'Hola');
      await tester.pump();
      await tester.pump();

      expect(find.byType(ChatTypingIndicator), findsOneWidget);
      expect(find.text(es.chatThinkingVault), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      final reply = harness.chatModel.vaultConversations.single.replies.single
        ..add('Ya');
      await tester.pump();
      expect(find.byType(ChatTypingIndicator), findsNothing);
      expect(find.byKey(const Key('chat-streaming-reply')), findsOneWidget);
      await reply.close();
      await tester.pumpAndSettle();
    });

    testWidgets('en la conversación libre dice «Pensando…»', (tester) async {
      await pumpChat(tester);
      harness.chatModel.manualReplies = true;
      await setVaultMode(tester, on: false);
      await typeAndSend(tester, 'Hola');
      await tester.pump();
      await tester.pump();
      expect(find.text(es.chatThinkingFree), findsOneWidget);
      await harness.chatModel.conversations.single.replies.single.close();
      await tester.pumpAndSettle();
    });

    testWidgets('con «sin animaciones», el indicador se queda quieto', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpChat(tester);
      harness.chatModel.manualReplies = true;
      await typeAndSend(tester, 'Hola');
      await tester.pump();
      await tester.pump(kChatStageTransition);

      expect(find.text(es.chatThinkingVault), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
      await harness.chatModel.vaultConversations.single.replies.single.close();
      await tester.pumpAndSettle();
    });

    testWidgets('las citas de lo que se escribe ya son chips', (tester) async {
      await pumpChat(tester);
      await harness.capture('Fotosíntesis\n\nel proceso de las plantas');
      harness.chatModel.manualReplies = true;
      await typeAndSend(tester, 'fotosíntesis');
      await tester.pump();
      await tester.pump();

      final reply = harness.chatModel.vaultConversations.single.replies.single
        ..add('Lo dice la fuente [1].');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('chat-streaming-reply')),
          matching: find.byKey(const Key('chat-citation-1')),
        ),
        findsOneWidget,
      );
      await reply.close();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-citation-1')), findsOneWidget);
    });

    testWidgets('vibra corto al mandar y al terminar la respuesta', (
      tester,
    ) async {
      await pumpChat(tester);
      harness.chatModel.manualReplies = true;
      await typeAndSend(tester, 'Hola');
      await tester.pump();
      await tester.pump();
      expect(platformCalls, ['vibrar HapticFeedbackType.lightImpact']);

      await harness.chatModel.vaultConversations.single.replies.single.close();
      await tester.pumpAndSettle();
      expect(platformCalls, [
        'vibrar HapticFeedbackType.lightImpact',
        'vibrar HapticFeedbackType.lightImpact',
      ]);
    });
  });

  group('las acciones de cada respuesta', () {
    testWidgets('«Volver a generar» solo en la última: la reemplaza y '
        'pregunta lo mismo, sin repetir la pregunta', (tester) async {
      await pumpChat(tester, chatModelResponse: 'primera');
      await sendChatMessage(tester, 'Uno');
      await sendChatMessage(tester, 'Dos');
      final conversation = harness.chatModel.vaultConversations.single;

      expect(find.byTooltip(es.chatAnswerRegenerate), findsOneWidget);
      conversation.response = 'otra versión';
      await tester.tap(find.byTooltip(es.chatAnswerRegenerate));
      await tester.pumpAndSettle();

      expect(conversation.sent, ['Uno', 'Dos', 'Dos']);
      final id = harness.container.read(chatSelectionProvider).conversationId!;
      final messages = harness.container
          .read(chatMessagesProvider(id))
          .requireValue;
      expect(
        [for (final m in messages) (m.isUser, m.text)],
        [
          (true, 'Uno'),
          (false, 'primera'),
          (true, 'Dos'),
          (false, 'otra versión'),
        ],
      );
      expect(answerNamed('otra versión'), findsOneWidget);
    });

    group('con una foto', () {
      final png = Uint8List.fromList(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      ]);

      Future<void> sendWithPhoto(WidgetTester tester) async {
        await pumpChat(
          tester,
          chosenFile: CapturedFile(name: 'foto.png', bytes: png),
        );
        await attachFrom(tester, 'chat-add-files');
        await sendChatMessage(tester, 'Qué ves');
      }

      testWidgets('volver a generar la vuelve a mandar', (tester) async {
        await sendWithPhoto(tester);
        await tester.tap(find.byTooltip(es.chatAnswerRegenerate));
        await tester.pumpAndSettle();
        expect(harness.chatModel.vaultConversations.single.sentImages, [
          [png],
          [png],
        ]);
      });

      testWidgets('mientras relee la foto, un segundo toque no pide otra', (
        tester,
      ) async {
        await sendWithPhoto(tester);
        final gate = Completer<void>();
        harness.files.readGate = gate.future;

        await tester.tap(find.byTooltip(es.chatAnswerRegenerate));
        await tester.pump();
        expect(find.byTooltip(es.chatAnswerRegenerate), findsNothing);
        gate.complete();
        await tester.pumpAndSettle();
        expect(harness.chatModel.vaultConversations.single.sent, [
          'Qué ves',
          'Qué ves',
        ]);
      });

      testWidgets('si la foto ya no está, el chat vuelve a quedar libre', (
        tester,
      ) async {
        await sendWithPhoto(tester);
        final id = harness.container
            .read(chatSelectionProvider)
            .conversationId!;
        final question = harness.container
            .read(chatMessagesProvider(id))
            .requireValue
            .first;
        await harness.files.delete(question.attachments.single.relativePath);
        await tester.tap(find.byTooltip(es.chatAnswerRegenerate));
        await tester.pumpAndSettle();
        expect(find.byTooltip(es.chatAnswerRegenerate), findsOneWidget);
      });

      testWidgets('editar y reenviar la manda con el texto nuevo', (
        tester,
      ) async {
        await sendWithPhoto(tester);
        await tester.longPress(bubbles.first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chat-menu-edit')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('chat-user-edit')),
            matching: find.byType(TextField),
          ),
          'Y ahora qué ves',
        );
        await tester.tap(find.byKey(const Key('chat-user-edit-send')));
        await tester.pumpAndSettle();
        final conversation = harness.chatModel.vaultConversations.single;
        expect(conversation.sent, ['Qué ves', 'Y ahora qué ves']);
        expect(conversation.sentImages, [
          [png],
          [png],
        ]);
      });

      testWidgets('si la foto ya no está, lo dice y no toca la respuesta', (
        tester,
      ) async {
        await sendWithPhoto(tester);
        final id = harness.container
            .read(chatSelectionProvider)
            .conversationId!;
        final question = harness.container
            .read(chatMessagesProvider(id))
            .requireValue
            .first;
        await harness.files.delete(question.attachments.single.relativePath);

        await tester.tap(find.byTooltip(es.chatAnswerRegenerate));
        await tester.pumpAndSettle();
        expect(find.text(es.globalErrorUnexpected), findsOneWidget);
        expect(harness.chatModel.vaultConversations.single.sent, ['Qué ves']);
        expect(answerNamed('Una respuesta.'), findsOneWidget);
      });
    });

    testWidgets('dos toques seguidos piden una sola respuesta nueva', (
      tester,
    ) async {
      await pumpChat(tester);
      await sendChatMessage(tester, 'Uno');
      await tester.tap(find.byTooltip(es.chatAnswerRegenerate));
      await tester.tap(find.byTooltip(es.chatAnswerRegenerate));
      await tester.pumpAndSettle();
      expect(harness.chatModel.vaultConversations.single.sent, ['Uno', 'Uno']);
      expect(find.byType(ChatAnswerMessage), findsOneWidget);
    });

    testWidgets('mientras escribe no hay «Volver a generar»', (tester) async {
      await pumpChat(tester);
      await sendChatMessage(tester, 'Uno');
      harness.chatModel.vaultConversations.single.manual = true;
      await typeAndSend(tester, 'Dos');
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip(es.chatAnswerRegenerate), findsNothing);
      await harness.chatModel.vaultConversations.single.replies.single.close();
      await tester.pumpAndSettle();
      expect(find.byTooltip(es.chatAnswerRegenerate), findsOneWidget);
    });

    testWidgets('«Escuchar» lee esa respuesta con el lector, y el mismo botón '
        'la deja de leer', (tester) async {
      // Con formato: el lector no dice los `**`.
      await pumpChat(tester, chatModelResponse: '**Primera** línea.\nSegunda.');
      await sendChatMessage(tester, 'Hola');

      await tester.tap(find.byTooltip(es.chatAnswerListen));
      await tester.pumpAndSettle();
      final reading = harness.container
          .read(readAloudControllerProvider)
          .document!
          .segments;
      expect(reading.map((s) => s.spoken), ['Primera línea.', 'Segunda.']);
      expect(find.byTooltip(es.chatAnswerStopListening), findsOneWidget);

      await tester.tap(find.byTooltip(es.chatAnswerStopListening));
      await tester.pumpAndSettle();
      expect(find.byTooltip(es.chatAnswerListen), findsOneWidget);
    });
  });

  group('mantener apretado un mensaje tuyo', () {
    testWidgets('copiar lo copia', (tester) async {
      await pumpChat(tester);
      await sendChatMessage(tester, 'Mi pregunta');
      await tester.longPress(bubbles.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-menu-copy')));
      await tester.pumpAndSettle();
      expect(copied, ['Mi pregunta']);
    });

    testWidgets('editar y reenviar lo manda corregido al final; lo de antes '
        'queda como pasó', (tester) async {
      await pumpChat(tester);
      await sendChatMessage(tester, 'Cuánto es 2+2');
      await tester.longPress(bubbles.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-menu-edit')));
      await tester.pumpAndSettle();

      final field = find.descendant(
        of: find.byKey(const Key('chat-user-edit')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).controller!.text, 'Cuánto es 2+2');
      await tester.enterText(field, 'Cuánto es 3+3');
      await tester.tap(find.byKey(const Key('chat-user-edit-send')));
      await tester.pumpAndSettle();

      expect(harness.chatModel.vaultConversations.single.sent, [
        'Cuánto es 2+2',
        'Cuánto es 3+3',
      ]);
      expect(find.byKey(const Key('chat-user-edit')), findsNothing);
      expect(find.byType(ChatUserBubble), findsNWidgets(2));
      expect(find.text('Cuánto es 2+2'), findsOneWidget);
      expect(find.text('Cuánto es 3+3'), findsOneWidget);
    });

    testWidgets('«Cancelar» deja todo como estaba', (tester) async {
      await pumpChat(tester);
      await sendChatMessage(tester, 'Hola');
      await tester.longPress(bubbles.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-menu-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-user-edit')), findsNothing);
      expect(harness.chatModel.vaultConversations.single.sent, ['Hola']);
    });

    testWidgets('vacío no se reenvía', (tester) async {
      await pumpChat(tester);
      await sendChatMessage(tester, 'Hola');
      await tester.longPress(bubbles.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-menu-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('chat-user-edit')),
          matching: find.byType(TextField),
        ),
        '   ',
      );
      await tester.tap(find.byKey(const Key('chat-user-edit-send')));
      await tester.pumpAndSettle();
      expect(harness.chatModel.vaultConversations.single.sent, ['Hola']);
      expect(find.byKey(const Key('chat-user-edit')), findsOneWidget);
    });

    testWidgets('seleccionar texto lo ofrece para elegir una parte', (
      tester,
    ) async {
      await pumpChat(tester);
      await sendChatMessage(tester, 'Una pregunta larga');
      await tester.longPress(bubbles.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-menu-select')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const Key('chat-selectable-text')),
            )
            .data,
        'Una pregunta larga',
      );
    });

    testWidgets('mientras espera una respuesta, no se puede reenviar', (
      tester,
    ) async {
      await pumpChat(tester);
      harness.chatModel.manualReplies = true;
      await typeAndSend(tester, 'Hola');
      await tester.pump();
      await tester.pump(kChatStageTransition);
      await tester.longPress(bubbles.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('chat-menu-copy')), findsOneWidget);
      expect(find.byKey(const Key('chat-menu-edit')), findsNothing);
      await tester.tapAt(const Offset(20, 20));
      await harness.chatModel.vaultConversations.single.replies.single.close();
      await tester.pumpAndSettle();
    });
  });

  group('«↓» para volver al final', () {
    Future<void> longConversation(WidgetTester tester) async {
      await pumpChat(tester);
      final repo = harness.container.read(chatConversationRepositoryProvider);
      final conversation = await repo.createConversation(
        ChatConversationMode.vault,
      );
      for (var i = 0; i < 30; i++) {
        await repo.addMessage(
          PersistedChatMessage(
            id: 'm$i',
            conversationId: conversation.id,
            isUser: i.isEven,
            text: 'Mensaje número $i, con bastante texto para ocupar lugar.',
            createdAt: DateTime(2026, 10, 27, 10, i),
          ),
        );
      }
      harness.container.read(chatSelectionProvider.notifier).open(conversation);
      await tester.pumpAndSettle();
    }

    double opacityOfJump(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(const Key('chat-jump-to-end')),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    testWidgets('al subir aparece, y lleva al final', (tester) async {
      await longConversation(tester);
      final list = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(list).position;
      expect(position.pixels, position.maxScrollExtent);
      expect(opacityOfJump(tester), 0);

      await tester.drag(find.byType(ListView), const Offset(0, 1200));
      await tester.pumpAndSettle();
      expect(opacityOfJump(tester), 1);

      await tester.tap(find.byTooltip(es.chatJumpToEnd));
      await tester.pumpAndSettle();
      expect(position.pixels, position.maxScrollExtent);
      expect(opacityOfJump(tester), 0);
    });

    testWidgets('escondido no se puede tocar ni lo anuncia el lector', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await longConversation(tester);
      expect(find.bySemanticsLabel(es.chatJumpToEnd), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 1200));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(const Key('chat-jump-to-end'))),
        isSemantics(tooltip: es.chatJumpToEnd, isButton: true),
      );
      handle.dispose();
    });

    testWidgets('con «sin animaciones», salta de una', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await longConversation(tester);
      await tester.drag(find.byType(ListView), const Offset(0, 1200));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(es.chatJumpToEnd));
      await tester.pump();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(position.pixels, position.maxScrollExtent);
    });
  });

  group('del vacío a la conversación', () {
    testWidgets('el saludo se desvanece mientras la conversación aparece', (
      tester,
    ) async {
      await pumpChat(tester);
      await typeAndSend(tester, 'Hola');
      await tester.pump();
      await tester.pump(kChatStageTransition ~/ 3);

      // Los dos a la vez, a mitad de camino.
      expect(find.byType(ChatWelcome), findsOneWidget);
      expect(find.byType(ChatUserBubble), findsOneWidget);
      final fades = tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: find.byType(ChatUserBubble),
              matching: find.byType(FadeTransition),
            ),
          )
          .map((f) => f.opacity.value);
      expect(fades.any((o) => o > 0 && o < 1), isTrue);

      await tester.pumpAndSettle();
      expect(find.byType(ChatWelcome), findsNothing);
    });

    testWidgets('con «sin animaciones», el cambio es de una', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpChat(tester);
      await typeAndSend(tester, 'Hola');
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChatWelcome), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('pasar de una conversación a otra no se funde: es la misma '
        'lista', (tester) async {
      await pumpChat(tester);
      await sendChatMessage(tester, 'Primera');
      final first = harness.container
          .read(chatSelectionProvider)
          .conversationId!;
      await tester.tap(find.byTooltip(es.chatNewConversationTooltip));
      await tester.pumpAndSettle();
      await sendChatMessage(tester, 'Segunda');

      final repo = harness.container.read(chatConversationRepositoryProvider);
      final saved = await tester.runAsync(
        () => repo.watchConversations(ChatConversationMode.vault).first,
      );
      final firstConversation = saved!.firstWhere((c) => c.id == first);
      harness.container
          .read(chatSelectionProvider.notifier)
          .open(firstConversation);
      // Una sola lista en cada cuadro: la de antes no queda fundiéndose
      // encima de la nueva.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.byType(ChatMessageList), findsOneWidget);
      }
      await tester.pumpAndSettle();
      expect(find.text('Primera'), findsOneWidget);
      expect(find.text('Segunda'), findsNothing);
    });
  });

  group('accesibilidad', () {
    testWidgets('con letra al doble, una respuesta con todo no se desborda', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1080, 2340)
        ..devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpChat(
        tester,
        chatModelResponse:
            '# Un título bastante largo para una pantalla\n\n'
            'Un párrafo con **negrita** y `código` [1].\n\n'
            '1. primero de la lista con texto\n'
            '   - adentro, más metido\n\n'
            '```dart\nfinal unaVariableConNombreLarguisimo = 1;\n```\n\n'
            '| Columna uno | Columna dos | Columna tres |\n'
            '|---|---|---|\n'
            '| un valor | otro valor | y otro más |',
      );
      await harness.capture('Una fuente\n\ncon texto');
      await sendChatMessage(tester, 'Contame de la fuente con texto');
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('chat-sources-toggle')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        bubbles,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(bubbles.first);
      await tester.pumpAndSettle();
      await tester.longPress(bubbles.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-menu-edit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    group('los nueve temas', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final (hi, lo) = la > lb ? (la, lb) : (lb, la);
        return (hi + 0.05) / (lo + 0.05);
      }

      final themes = {
        for (final choice in AppThemeChoice.values)
          for (final theme in choice.previews) theme,
      };

      test('lo que escribe la conversación se lee (AA) en cada tema', () {
        expect(themes, hasLength(AppThemeChoice.values.length - 1));
        for (final theme in themes) {
          final s = theme.colorScheme;
          final back = theme.scaffoldBackgroundColor;
          for (final (fore, bg, what, min) in [
            (s.onSurface, back, 'la respuesta', 4.5),
            (
              s.onSurfaceVariant,
              back,
              'las citas, «Fuentes», el indicador',
              4.5,
            ),
            (s.onSurface, s.surfaceContainerHigh, 'tu burbuja', 4.5),
            (s.onSurface, s.surfaceContainerHighest, 'el código', 4.5),
            (s.onSurfaceVariant, s.surfaceContainerHighest, 'su lenguaje', 4.5),
            (s.onSecondaryContainer, s.secondaryContainer, 'el chip', 4.5),
            (s.onSurface, s.surfaceContainerLow, 'una fuente', 4.5),
            (s.onSurfaceVariant, s.surfaceContainerLow, 'su pasaje', 4.5),
            (s.onErrorContainer, s.errorContainer, 'un aviso de error', 4.5),
            // Íconos y bordes: lo que pide AA para lo que no es texto.
            (s.onSurfaceVariant, back, 'los íconos de las acciones', 3.0),
            (s.onSurface, s.surfaceContainerHigh, 'la flecha de «↓»', 3.0),
          ]) {
            expect(
              contrast(fore, bg),
              greaterThanOrEqualTo(min),
              reason: '$what en ${theme.brightness} ${s.primary}',
            );
          }
        }
      });

      testWidgets('la conversación se dibuja en cada tema', (tester) async {
        await pumpChat(tester, chatModelResponse: '## Hola\n\n- uno\n`x`');
        await sendChatMessage(tester, 'Hola');
        for (final theme in themes) {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: harness.container,
              child: MaterialApp(
                theme: theme,
                locale: const Locale('es'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const ChatScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(answerNamed('uno'), findsOneWidget);
        }
      });
    });
  });
}
