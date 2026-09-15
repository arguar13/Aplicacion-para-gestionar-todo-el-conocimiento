import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Firma PNG mínima: ocho bytes alcanzan para que `detectFileFormat`
/// reconozca el formato por magia y no le haga falta el resto del archivo
/// —nada de este archivo se llega a decodificar de verdad en las pruebas—.
final _pngBytes = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpChat(
    WidgetTester tester, {
    bool chatModelReady = false,
    String? chatModelResponse,
    CapturedFile? chosenFile,
  }) async {
    harness = await LibraryHarness.create(
      chatModelReady: chatModelReady,
      chatModelResponse: chatModelResponse,
      chosenFile: chosenFile,
    );
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
  }

  /// Busca solo dentro del panel de historial: mientras está abierto, la
  /// conversación de fondo sigue montada detrás y puede repetir el mismo
  /// texto o tooltip que un elemento del propio panel.
  Finder inDrawer(Finder matching) =>
      find.descendant(of: find.byType(Drawer), matching: matching);

  group('modo con mi bóveda (por defecto)', () {
    testWidgets('arranca en este modo, con su explicación propia', (
      tester,
    ) async {
      await pumpChat(tester);

      expect(find.text(es.chatEmptyExplanation), findsOneWidget);
      expect(find.text(es.chatFreeEmptyExplanation), findsNothing);
    });

    testWidgets('sin el modelo descargado y sin nada guardado, dice que no '
        'encontró nada — es solo un buscador', (tester) async {
      await pumpChat(tester);

      await send(tester, 'algo que no está guardado');

      expect(find.text(es.chatNoSourcesFound), findsOneWidget);
    });

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
        expect(harness.chatModel.vaultConversations.single.sent, [
          'primer mensaje',
          'segundo mensaje',
        ]);
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
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');
      await switchToFreeMode(tester);

      await send(tester, 'primer mensaje');
      await send(tester, 'segundo mensaje');

      expect(harness.chatModel.conversations, hasLength(1));
      expect(harness.chatModel.conversations.single.sent, [
        'primer mensaje',
        'segundo mensaje',
      ]);
    });

    testWidgets('"nueva conversación" cierra la sesión y borra el '
        'historial', (tester) async {
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');
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
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'listo');
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

  group('adjuntos', () {
    Future<void> openAttachMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.attach_file));
      await tester.pumpAndSettle();
    }

    testWidgets('adjuntar una imagen la muestra como chip en el compositor', (
      tester,
    ) async {
      await pumpChat(
        tester,
        chosenFile: CapturedFile(name: 'foto.png', bytes: _pngBytes),
      );

      await openAttachMenu(tester);
      await tester.tap(find.text(es.chatAttachImageAction));
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsOneWidget);
      expect(find.text('foto.png'), findsOneWidget);
    });

    testWidgets(
      'adjuntar un documento le extrae el texto y lo suma al mensaje que '
      've el modelo, sin mostrarlo en lo que escribió la persona',
      (tester) async {
        await pumpChat(
          tester,
          chatModelReady: true,
          chatModelResponse: 'listo',
          chosenFile: CapturedFile(
            name: 'notas.txt',
            bytes: Uint8List.fromList(utf8.encode('contenido del adjunto')),
          ),
        );

        await openAttachMenu(tester);
        await tester.tap(find.text(es.chatAttachDocumentAction));
        await tester.pumpAndSettle();

        expect(find.text('notas.txt'), findsOneWidget);

        await send(tester, 'usá el adjunto');

        expect(find.text('usá el adjunto'), findsOneWidget);
        expect(
          harness.chatModel.vaultConversations.single.sent.single,
          contains('contenido del adjunto'),
        );
      },
    );

    testWidgets('una imagen adjunta se manda como imagen al modelo', (
      tester,
    ) async {
      await pumpChat(
        tester,
        chatModelReady: true,
        chatModelResponse: 'listo',
        chosenFile: CapturedFile(name: 'foto.png', bytes: _pngBytes),
      );

      await openAttachMenu(tester);
      await tester.tap(find.text(es.chatAttachImageAction));
      await tester.pumpAndSettle();

      await send(tester, 'qué ves acá');

      expect(harness.chatModel.vaultConversations.single.sentImages.single, [
        _pngBytes,
      ]);
    });

    testWidgets('se puede quitar un adjunto antes de mandar el mensaje', (
      tester,
    ) async {
      await pumpChat(
        tester,
        chosenFile: CapturedFile(name: 'foto.png', bytes: _pngBytes),
      );

      await openAttachMenu(tester);
      await tester.tap(find.text(es.chatAttachImageAction));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);

      await tester.tap(find.byTooltip(es.chatAttachRemoveTooltip));
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('un documento que no se puede leer avisa y no se adjunta', (
      tester,
    ) async {
      await pumpChat(
        tester,
        chosenFile: CapturedFile(
          name: 'archivo.bin',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      );

      await openAttachMenu(tester);
      await tester.tap(find.text(es.chatAttachDocumentAction));
      await tester.pumpAndSettle();

      expect(find.text(es.chatAttachUnreadable('archivo.bin')), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
    });
  });

  group('historial', () {
    testWidgets('sin conversaciones guardadas, el historial lo dice', (
      tester,
    ) async {
      await pumpChat(tester);

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.text(es.chatHistoryEmpty), findsOneWidget);
    });

    testWidgets('la conversación mandada aparece en el historial, titulada '
        'con el primer mensaje', (tester) async {
      await pumpChat(tester);
      await send(tester, 'mi primera pregunta');

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(inDrawer(find.text('mi primera pregunta')), findsOneWidget);
    });

    testWidgets(
      '"nueva conversación" desde el historial no borra la anterior',
      (tester) async {
        await pumpChat(tester);
        await send(tester, 'mi primera pregunta');

        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();
        await tester.tap(inDrawer(find.byTooltip(es.chatHistoryNewAction)));
        await tester.pumpAndSettle();

        expect(find.text(es.chatEmptyExplanation), findsOneWidget);

        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();

        expect(inDrawer(find.text('mi primera pregunta')), findsOneWidget);
      },
    );

    testWidgets('reabrir una conversación del historial muestra sus '
        'mensajes', (tester) async {
      await pumpChat(tester);
      await send(tester, 'primera conversación');

      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pumpAndSettle();
      await send(tester, 'segunda conversación');

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      await tester.tap(find.text('primera conversación'));
      await tester.pumpAndSettle();

      expect(find.text('primera conversación'), findsOneWidget);
      expect(find.text('segunda conversación'), findsNothing);
    });

    testWidgets('borrar una conversación activa la saca de pantalla y del '
        'historial', (tester) async {
      await pumpChat(tester);
      await send(tester, 'mi primera pregunta');

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.chatHistoryDeleteConfirmAction));
      await tester.pumpAndSettle();

      expect(find.text(es.chatHistoryEmpty), findsOneWidget);
      expect(find.text(es.chatEmptyExplanation), findsOneWidget);
    });
  });
}
