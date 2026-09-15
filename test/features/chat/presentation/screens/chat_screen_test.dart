import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpChat(
    WidgetTester tester, {
    bool chatModelReady = false,
    String? chatModelResponse,
  }) async {
    harness = await LibraryHarness.create(
      chatModelReady: chatModelReady,
      chatModelResponse: chatModelResponse,
    );
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
  }

  group('modo con mi bóveda (por defecto)', () {
    testWidgets('arranca en este modo, con su explicación propia', (
      tester,
    ) async {
      await pumpChat(tester);

      expect(find.text(es.chatEmptyExplanation), findsOneWidget);
      expect(find.text(es.chatFreeEmptyExplanation), findsNothing);
    });

    testWidgets(
      'sin el modelo descargado y sin nada guardado, dice que no '
      'encontró nada — es solo un buscador',
      (tester) async {
        await pumpChat(tester);

        await send(tester, 'algo que no está guardado');

        expect(find.text(es.chatNoSourcesFound), findsOneWidget);
      },
    );

    testWidgets(
      'con el modelo listo, aunque no encuentre nada en la bóveda sigue '
      'charlando en vez de negarse a contestar',
      (tester) async {
        await pumpChat(
          tester,
          chatModelReady: true,
          chatModelResponse: 'listo',
        );

        await send(tester, 'algo que no está guardado');

        expect(find.text('listo'), findsOneWidget);
        expect(find.text(es.chatNoSourcesFound), findsNothing);
      },
    );

    testWidgets('con algo guardado y el modelo listo, redacta una '
        'respuesta citando la fuente', (tester) async {
      await pumpChat(
        tester,
        chatModelReady: true,
        chatModelResponse: 'la respuesta redactada',
      );
      // Título y cuerpo distintos, para que el título de la tarjeta de
      // fuente y su fragmento no sean el mismo texto en pantalla.
      await harness.capture(
        'Un artículo sobre fotosíntesis\n\nhabla del proceso en las plantas',
      );

      await send(tester, 'fotosíntesis');

      expect(find.text('la respuesta redactada'), findsOneWidget);
      expect(find.text('Un artículo sobre fotosíntesis'), findsOneWidget);
    });

    testWidgets(
      'varios mensajes seguidos reusan la misma sesión, con memoria de '
      'lo conversado antes',
      (tester) async {
        await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');

        await send(tester, 'primer mensaje');
        await send(tester, 'segundo mensaje');

        expect(harness.chatModel.vaultConversations, hasLength(1));
        expect(
          harness.chatModel.vaultConversations.single.sent,
          ['primer mensaje', 'segundo mensaje'],
        );
      },
    );

    testWidgets('"nueva conversación" cierra la sesión y borra el '
        'historial', (tester) async {
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');
      await send(tester, 'algo');

      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pumpAndSettle();

      expect(harness.chatModel.vaultConversations.single.closed, isTrue);
      expect(find.text('algo'), findsNothing);
      expect(find.text(es.chatEmptyExplanation), findsOneWidget);
    });
  });

  group('modo conversación libre', () {
    Future<void> switchToFreeMode(WidgetTester tester) async {
      await tester.tap(find.text(es.chatModeFree));
      await tester.pumpAndSettle();
    }

    testWidgets('tiene su propia explicación, sin nada de la bóveda', (
      tester,
    ) async {
      await pumpChat(tester);
      await switchToFreeMode(tester);

      expect(find.text(es.chatFreeEmptyExplanation), findsOneWidget);
      expect(find.text(es.chatEmptyExplanation), findsNothing);
    });

    testWidgets('sin el modelo descargado, no hay red de contención: '
        'avisa en vez de contestar', (tester) async {
      await pumpChat(tester);
      await switchToFreeMode(tester);

      await send(tester, 'hola');

      // Aparece dos veces: el aviso persistente de arriba y el error del
      // propio intercambio.
      expect(find.text(es.chatFreeModelRequired), findsNWidgets(2));
      // Y no le pide nada al modelo: no hay con qué.
      expect(harness.chatModel.conversations, isEmpty);
    });

    testWidgets('con el modelo listo, conversa y muestra la respuesta', (
      tester,
    ) async {
      await pumpChat(
        tester,
        chatModelReady: true,
        chatModelResponse: 'una charla común y corriente',
      );
      await switchToFreeMode(tester);

      await send(tester, 'hola, ¿cómo estás?');

      expect(find.text('hola, ¿cómo estás?'), findsOneWidget);
      expect(find.text('una charla común y corriente'), findsOneWidget);
    });

    testWidgets('varios mensajes seguidos reusan la misma sesión, no abren '
        'una nueva cada vez', (tester) async {
      await pumpChat(
        tester,
        chatModelReady: true,
        chatModelResponse: 'ok',
      );
      await switchToFreeMode(tester);

      await send(tester, 'primer mensaje');
      await send(tester, 'segundo mensaje');

      expect(harness.chatModel.conversations, hasLength(1));
      expect(
        harness.chatModel.conversations.single.sent,
        ['primer mensaje', 'segundo mensaje'],
      );
    });

    testWidgets('"nueva conversación" cierra la sesión y borra el '
        'historial', (tester) async {
      await pumpChat(
        tester,
        chatModelReady: true,
        chatModelResponse: 'ok',
      );
      await switchToFreeMode(tester);
      await send(tester, 'algo');

      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pumpAndSettle();

      expect(harness.chatModel.conversations.single.closed, isTrue);
      expect(find.text('algo'), findsNothing);
      expect(find.text(es.chatFreeEmptyExplanation), findsOneWidget);

      await send(tester, 'otra cosa');

      // La conversación nueva es otra instancia, no la que se cerró.
      expect(harness.chatModel.conversations, hasLength(2));
    });

    testWidgets('cada modo lleva su propio historial, sin mezclarse', (
      tester,
    ) async {
      await pumpChat(
        tester,
        chatModelReady: true,
        chatModelResponse: 'listo',
      );
      await harness.capture('algo guardado sobre gatos');

      await send(tester, 'gatos');
      expect(find.text('listo'), findsOneWidget);

      await switchToFreeMode(tester);
      expect(find.text('listo'), findsNothing);

      await send(tester, 'una pregunta libre');
      expect(find.text('listo'), findsOneWidget);

      await tester.tap(find.text(es.chatModeVault));
      await tester.pumpAndSettle();

      expect(find.text('gatos'), findsOneWidget);
      expect(find.text('una pregunta libre'), findsNothing);
    });
  });
}
