import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_conversations_panel.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/chat_actions.dart';
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

  Future<void> send(WidgetTester tester, String text) =>
      sendChatMessage(tester, text);

  /// Busca solo dentro del panel de conversaciones: mientras está abierto, la
  /// conversación de fondo sigue montada detrás y puede repetir el mismo
  /// texto que una fila del propio panel.
  Finder inPanel(Finder matching) => find.descendant(
    of: find.byKey(const Key('chat-panel')),
    matching: matching,
  );

  /// ☰, arriba a la izquierda (F42).
  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byTooltip(es.chatPanelOpenTooltip));
    await tester.pumpAndSettle();
  }

  /// ✎, arriba a la derecha (F42).
  Future<void> startNew(WidgetTester tester) async {
    await tester.tap(find.byTooltip(es.chatNewConversationTooltip));
    await tester.pumpAndSettle();
  }

  /// Elige [label] —un modo o un cuaderno— en la hoja «Dónde pregunto», que
  /// se abre tocando la línea debajo del modelo (F42).
  Future<void> chooseScope(WidgetTester tester, String label) =>
      chooseChatScope(tester, label);

  group('la pantalla a la vista retiene el modelo para la charla (F27)', () {
    testWidgets('lo dice mientras se ve, deja de decirlo si otra pantalla la '
        'tapa o la app pasa a segundo plano, y al cerrarse', (tester) async {
      await pumpChat(tester);
      final gate = harness.container.read(languageModelGateProvider);
      expect(gate.chatVisible, isTrue);

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Text('Encima')),
        ),
      );
      await tester.pumpAndSettle();
      expect(gate.chatVisible, isFalse);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(gate.chatVisible, isTrue);

      // Como lo hace el sistema: de a un paso.
      Future<void> go(List<AppLifecycleState> states) async {
        for (final state in states) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump();
      }

      await go(const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      expect(gate.chatVisible, isFalse);
      await go(const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      expect(gate.chatVisible, isTrue);

      await tester.pumpWidget(harness.wrap(const SizedBox()));
      expect(gate.chatVisible, isFalse);
    });
  });

  group('con la IA en la nube (F32)', () {
    testWidgets('sin clave, dice que falta la clave —no que falta bajar '
        'Gemma— y que mientras se ven las fuentes; al cargarla, se va sin '
        'salir del chat', (tester) async {
      harness = await LibraryHarness.create(
        languageModelProvider: AiProvider.gemini,
      );
      await tester.pumpWidget(harness.wrap(const ChatScreen()));
      await tester.pumpAndSettle();

      final banner =
          '${es.lmMissingAccount(es.lmProviderGemini)} '
          '${es.chatSourcesMeanwhile}';
      expect(find.text(banner), findsOneWidget);
      expect(find.text(es.chatModelNotReadyBanner), findsNothing);
      expect(find.text(es.lmActionAddKey), findsOneWidget);

      await harness.container
          .read(aiAccountRepositoryProvider)
          .add(provider: AiProvider.gemini, key: 'una-clave', label: 'Mía');
      await tester.pumpAndSettle();

      expect(find.text(banner), findsNothing);
      expect(find.text(es.lmActionAddKey), findsNothing);
    });
  });

  group('modo con mi bóveda (por defecto)', () {
    testWidgets('arranca en este modo, con su saludo propio', (tester) async {
      await pumpChat(tester);

      expect(find.text(es.chatGreetingVaultQuestion), findsOneWidget);
      expect(find.text(es.chatGreetingFreeQuestion), findsNothing);
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
      // Las tarjetas de las fuentes, debajo, en «Fuentes» plegado (F42).
      expect(find.text('Un artículo sobre fotosíntesis'), findsNothing);
      await tester.tap(find.text(es.chatSourcesHeader(1)));
      await tester.pumpAndSettle();
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

      await startNew(tester);

      expect(harness.chatModel.vaultConversations.single.closed, isTrue);
      expect(find.text('algo'), findsNothing);
      expect(find.text(es.chatGreetingVaultQuestion), findsOneWidget);
    });
  });

  group('modo conversación libre', () {
    Future<void> switchToFreeMode(WidgetTester tester) =>
        chooseScope(tester, es.chatModeFree);

    testWidgets('tiene su propio saludo, sin nada de la bóveda', (
      tester,
    ) async {
      await pumpChat(tester);
      await switchToFreeMode(tester);

      expect(find.text(es.chatGreetingFreeQuestion), findsOneWidget);
      expect(find.text(es.chatGreetingVaultQuestion), findsNothing);
    });

    testWidgets('sin el modelo descargado, no hay red de contención: '
        'avisa en vez de contestar', (tester) async {
      await pumpChat(tester);
      await switchToFreeMode(tester);

      await send(tester, 'hola');

      // Aparece dos veces: el aviso que sigue a la vista arriba del campo y
      // el error del propio intercambio.
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

      await startNew(tester);

      expect(harness.chatModel.conversations.single.closed, isTrue);
      expect(find.text('algo'), findsNothing);
      expect(find.text(es.chatGreetingFreeQuestion), findsOneWidget);

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

      await chooseScope(tester, es.chatModeVault);

      expect(find.text('gatos'), findsOneWidget);
      expect(find.text('una pregunta libre'), findsNothing);
    });
  });

  testWidgets('con el modelo bajado, lo carga al abrir el chat, antes del '
      'primer mensaje (F30)', (tester) async {
    await pumpChat(tester, chatModelReady: true);

    expect(harness.chatModel.warmUps, 1);
  });

  testWidgets('sin el modelo bajado, no intenta cargarlo', (tester) async {
    await pumpChat(tester);

    expect(harness.chatModel.warmUps, 0);
  });

  testWidgets('una foto por mensaje: la segunda no se adjunta y lo dice '
      '(F30)', (tester) async {
    await pumpChat(
      tester,
      chosenFile: CapturedFile(name: 'foto.png', bytes: _pngBytes),
    );

    await attachFrom(tester, 'chat-add-files');
    expect(find.byKey(const Key('chat-pending-attachment')), findsOneWidget);

    // Con una foto ya adjunta, las tarjetas de fotos se apagan y lo dicen.
    await openAddToChat(tester);
    expect(find.text(es.chatAttachOneImage), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-add-photos')));
    await tester.pumpAndSettle();
    expect(harness.photoLibraryChooser.timesOpened, 0);

    // Y si llega otra imagen por «Archivos», no se adjunta y lo dice.
    await tester.tap(find.byKey(const Key('chat-add-files')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-pending-attachment')), findsOneWidget);
    expect(find.text(es.chatAttachOneImage), findsOneWidget);
  });

  group('la respuesta mientras se escribe (F30)', () {
    Future<StreamController<String>> sendLive(
      WidgetTester tester,
      String text,
    ) async {
      await pumpChat(tester, chatModelReady: true);
      harness.chatModel.manualReplies = true;
      await chooseScope(tester, es.chatModeFree);
      await typeAndSend(tester, text);
      await tester.pump();
      await tester.pump();
      return harness.chatModel.conversations.single.replies.single;
    }

    Finder growing(String text) => find.descendant(
      of: find.byKey(const Key('chat-streaming-reply')),
      matching: find.text(text),
    );

    testWidgets('se ve a medida que llega y queda guardada al terminar', (
      tester,
    ) async {
      final reply = await sendLive(tester, 'Contame de Roma');

      reply.add('Roma fue');
      await tester.pump();
      expect(growing('Roma fue'), findsOneWidget);

      reply.add('Roma fue una república.');
      await tester.pump();
      expect(growing('Roma fue una república.'), findsOneWidget);

      await reply.close();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-streaming-reply')), findsNothing);
      expect(find.text('Roma fue una república.'), findsOneWidget);
      expect(find.byTooltip(es.chatSendTooltip), findsOneWidget);
    });

    testWidgets('detenerla corta al modelo y guarda lo que alcanzó a '
        'escribir', (tester) async {
      final reply = await sendLive(tester, 'Contame de Roma');
      reply.add('Roma fue');
      await tester.pump();

      await tester.tap(find.byTooltip(es.chatStopTooltip));
      await tester.pumpAndSettle();

      expect(reply.hasListener, isFalse);
      expect(find.text('Roma fue'), findsOneWidget);
      expect(find.byKey(const Key('chat-streaming-reply')), findsNothing);
      expect(find.byTooltip(es.chatStopTooltip), findsNothing);
    });

    testWidgets('empezar una conversación nueva la corta y guarda lo escrito '
        '(F42)', (tester) async {
      final reply = await sendLive(tester, 'Contame de Roma');
      reply.add('Roma fue');
      await tester.pump();

      await startNew(tester);

      expect(reply.hasListener, isFalse);
      expect(find.text(es.chatGreetingFreeQuestion), findsOneWidget);
      await openPanel(tester);
      await tester.tap(inPanel(find.text('Contame de Roma')));
      await tester.pumpAndSettle();
      expect(find.text('Roma fue'), findsOneWidget);
    });

    testWidgets('cambiar de modo no la corta: sigue en su conversación (F42)', (
      tester,
    ) async {
      final reply = await sendLive(tester, 'Contame de Roma');
      reply.add('Roma fue');
      await tester.pump();

      await chooseScope(tester, es.chatModeVault);
      expect(reply.hasListener, isTrue);
      await chooseScope(tester, es.chatModeFree);
      expect(growing('Roma fue'), findsOneWidget);

      await reply.close();
      await tester.pumpAndSettle();
      expect(find.text('Roma fue'), findsOneWidget);
    });

    testWidgets('detenerla antes de que escriba nada lo dice', (tester) async {
      await sendLive(tester, 'Hola');

      await tester.tap(find.byTooltip(es.chatStopTooltip));
      await tester.pumpAndSettle();

      expect(find.text(es.chatReplyStoppedEmpty), findsOneWidget);
    });

    testWidgets('un error a mitad deja lo escrito y avisa', (tester) async {
      final reply = await sendLive(tester, 'Contame de Roma');
      reply
        ..add('Roma fue')
        ..addError(StateError('falla del motor'));
      await tester.pumpAndSettle();

      expect(find.text('Roma fue'), findsOneWidget);
      expect(find.text(es.chatReplyInterrupted), findsOneWidget);
    });
  });

  group('adjuntos', () {
    Future<void> attachFile(WidgetTester tester) =>
        attachFrom(tester, 'chat-add-files');

    final pendingAttachment = find.byKey(const Key('chat-pending-attachment'));

    testWidgets('adjuntar una imagen la muestra en miniatura en el campo', (
      tester,
    ) async {
      await pumpChat(
        tester,
        chosenFile: CapturedFile(name: 'foto.png', bytes: _pngBytes),
      );

      await attachFile(tester);

      expect(pendingAttachment, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.semanticLabel == 'foto.png',
        ),
        findsOneWidget,
      );
    });

    // Una foto adjunta son millones de píxeles; la miniatura es de 64×64
    // puntos.
    testWidgets('la miniatura de la imagen la decodifica al tamaño de su '
        'recuadro, no entera', (tester) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpChat(
        tester,
        chosenFile: CapturedFile(name: 'foto.png', bytes: _pngBytes),
      );

      await attachFile(tester);

      final thumbnail = find.descendant(
        of: pendingAttachment,
        matching: find.byType(Image),
      );
      final image = tester.widget<Image>(thumbnail).image;
      expect(image, isA<ResizeImage>());
      // 64 puntos × 3 de densidad × 2.
      expect((image as ResizeImage).width, 384);
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

        await attachFile(tester);

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

      await attachFile(tester);

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

      await attachFile(tester);
      expect(pendingAttachment, findsOneWidget);

      await tester.tap(find.byTooltip(es.chatAttachRemoveTooltip));
      await tester.pumpAndSettle();

      expect(pendingAttachment, findsNothing);
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

      await attachFile(tester);

      expect(find.text(es.chatAttachUnreadable('archivo.bin')), findsOneWidget);
      expect(pendingAttachment, findsNothing);
    });
  });

  group('el panel de conversaciones (F42)', () {
    testWidgets('sin conversaciones guardadas, lo dice', (tester) async {
      await pumpChat(tester);

      await openPanel(tester);

      expect(inPanel(find.text(es.chatPanelEmpty)), findsOneWidget);
    });

    testWidgets('la conversación mandada aparece en «Hoy», titulada con el '
        'primer mensaje', (tester) async {
      await pumpChat(tester);
      await send(tester, 'mi primera pregunta');

      await openPanel(tester);

      expect(inPanel(find.text(es.chatPanelToday)), findsOneWidget);
      expect(inPanel(find.text('mi primera pregunta')), findsOneWidget);
    });

    testWidgets('«Nueva» desde el panel lo cierra y no borra la anterior', (
      tester,
    ) async {
      await pumpChat(tester);
      await send(tester, 'mi primera pregunta');

      await openPanel(tester);
      await tester.tap(inPanel(find.text(es.chatPanelNew)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat-panel')), findsNothing);
      expect(find.text(es.chatGreetingVaultQuestion), findsOneWidget);

      await openPanel(tester);
      expect(inPanel(find.text('mi primera pregunta')), findsOneWidget);
    });

    testWidgets('✎ solo se puede tocar con una conversación empezada', (
      tester,
    ) async {
      await pumpChat(tester);
      IconButton pencil() => tester.widget<IconButton>(
        find.byKey(const Key('chat-new-conversation')),
      );
      expect(pencil().onPressed, isNull);

      await send(tester, 'algo');

      expect(pencil().onPressed, isNotNull);
    });

    testWidgets('reabrir una conversación muestra sus mensajes y cierra el '
        'panel', (tester) async {
      await pumpChat(tester);
      await send(tester, 'primera conversación');
      await startNew(tester);
      await send(tester, 'segunda conversación');

      await openPanel(tester);
      await tester.tap(inPanel(find.text('primera conversación')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat-panel')), findsNothing);
      expect(find.text('primera conversación'), findsOneWidget);
      expect(find.text('segunda conversación'), findsNothing);
    });

    testWidgets('muestra las de los dos modos; abrir una libre desde el modo '
        'con la bóveda pasa a la conversación libre', (tester) async {
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');
      await chooseScope(tester, es.chatModeFree);
      await send(tester, 'una charla libre');
      await chooseScope(tester, es.chatModeVault);
      await send(tester, 'una con la bóveda');

      await openPanel(tester);
      expect(inPanel(find.text('una con la bóveda')), findsOneWidget);
      await tester.tap(inPanel(find.text('una charla libre')));
      await tester.pumpAndSettle();

      expect(find.text('una charla libre'), findsOneWidget);
      expect(find.text('una con la bóveda'), findsNothing);
      // La línea debajo del modelo lo dice.
      expect(
        find.descendant(
          of: find.byKey(const Key('chat-scope-line')),
          matching: find.text(es.chatModeFree),
        ),
        findsOneWidget,
      );

      // Y el próximo mensaje sigue la charla libre, con su propia sesión.
      await send(tester, 'sigo charlando');
      expect(harness.chatModel.conversations.last.sent.last, 'sigo charlando');
    });

    testWidgets('borrar la conversación abierta la saca de la pantalla al '
        'instante; «Deshacer» la recupera, abierta', (tester) async {
      await pumpChat(tester);
      await send(tester, 'mi primera pregunta');

      await openPanel(tester);
      await tester.tap(
        find.byTooltip(es.chatPanelRowMenu('mi primera pregunta')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.chatHistoryDeleteTooltip));
      await tester.pumpAndSettle();

      expect(
        inPanel(find.text(es.chatPanelDeleted('mi primera pregunta'))),
        findsOneWidget,
      );
      expect(find.text(es.chatGreetingVaultQuestion), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat-panel-undo')));
      await tester.pumpAndSettle();

      expect(inPanel(find.text('mi primera pregunta')), findsOneWidget);
      expect(find.text(es.chatGreetingVaultQuestion), findsNothing);

      // Pasado el tiempo del «Deshacer», sigue ahí: no se borró.
      await tester.pump(kChatDeleteUndoWindow * 2);
      await tester.pumpAndSettle();
      expect(inPanel(find.text('mi primera pregunta')), findsOneWidget);
    });

    testWidgets('pasado el «Deshacer», se borra de verdad', (tester) async {
      await pumpChat(tester);
      await send(tester, 'mi primera pregunta');

      await openPanel(tester);
      await tester.tap(
        find.byTooltip(es.chatPanelRowMenu('mi primera pregunta')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.chatHistoryDeleteTooltip));
      await tester.pumpAndSettle();
      await tester.pump(kChatDeleteUndoWindow);
      await tester.pumpAndSettle();

      expect(inPanel(find.text(es.chatPanelEmpty)), findsOneWidget);
      expect(find.text(es.chatGreetingVaultQuestion), findsOneWidget);
    });

    testWidgets('cerrar el panel con un borrado pendiente lo confirma', (
      tester,
    ) async {
      await pumpChat(tester);
      await send(tester, 'mi primera pregunta');

      await openPanel(tester);
      await tester.tap(
        find.byTooltip(es.chatPanelRowMenu('mi primera pregunta')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.chatHistoryDeleteTooltip));
      await tester.pumpAndSettle();
      // Afuera del panel, sobre el fondo oscuro.
      await tester.tapAt(const Offset(780, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-panel')), findsNothing);

      await openPanel(tester);
      expect(inPanel(find.text(es.chatPanelEmpty)), findsOneWidget);
    });

    testWidgets('borrar una que no está abierta no toca la de la pantalla', (
      tester,
    ) async {
      await pumpChat(tester);
      await send(tester, 'la vieja');
      await startNew(tester);
      await send(tester, 'la de ahora');

      await openPanel(tester);
      await tester.tap(find.byTooltip(es.chatPanelRowMenu('la vieja')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.chatHistoryDeleteTooltip));
      await tester.pumpAndSettle();
      await tester.pump(kChatDeleteUndoWindow);
      await tester.pumpAndSettle();

      expect(inPanel(find.text('la vieja')), findsNothing);
      expect(inPanel(find.text('la de ahora')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListView).first,
          matching: find.text('la de ahora'),
        ),
        findsOneWidget,
      );
    });
  });

  group('acotar a un cuaderno (F16, D1)', () {
    Future<void> selectScope(WidgetTester tester, String label) =>
        chooseScope(tester, label);

    /// Dos elementos que la búsqueda de texto encuentra a los dos —los
    /// títulos comparten la palabra "cuaderno"—, y un cuaderno manual que
    /// solo tiene el primero: lo que distingue "encontrado por texto" de
    /// "adentro del alcance".
    Future<String> seedScopedNotebook(WidgetTester tester) async {
      await harness.capture('Adentro del cuaderno');
      await harness.capture('Afuera del cuaderno');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final inside = items.firstWhere((i) => i.title == 'Adentro del cuaderno');

      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Mi cuaderno', mode: NotebookMode.manual);
      await harness.container
          .read(notebookRepositoryProvider)
          .addItem(notebookId: notebook.id, itemId: inside.id);
      await tester.pumpAndSettle();
      return notebook.id;
    }

    testWidgets('en modo libre no hay cuadernos para elegir', (tester) async {
      await pumpChat(tester);
      await chooseScope(tester, es.chatModeFree);

      await tester.tap(find.byKey(const Key('chat-scope-line')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat-scope-notebook-all')), findsNothing);
    });

    testWidgets('la línea debajo del modelo dice el cuaderno elegido', (
      tester,
    ) async {
      await pumpChat(tester);
      await seedScopedNotebook(tester);
      Finder line(String text) => find.descendant(
        of: find.byKey(const Key('chat-scope-line')),
        matching: find.text(text),
      );
      expect(
        line('${es.chatScopeLineVault} · ${es.chatNotebookScopeAll}'),
        findsOneWidget,
      );

      await selectScope(tester, 'Mi cuaderno');

      expect(line('${es.chatScopeLineVault} · Mi cuaderno'), findsOneWidget);
    });

    testWidgets('elegir un cuaderno acota qué fuentes llegan al modelo', (
      tester,
    ) async {
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');
      await seedScopedNotebook(tester);

      await selectScope(tester, 'Mi cuaderno');
      await send(tester, 'cuaderno');

      final sent =
          harness.chatModel.vaultConversations.single.sentSources.single;
      expect(sent.map((s) => s.itemTitle), ['Adentro del cuaderno']);
    });

    testWidgets(
      'cambiar de cuaderno con la conversación en curso arranca una nueva',
      (tester) async {
        await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');
        await seedScopedNotebook(tester);

        await selectScope(tester, 'Mi cuaderno');
        await send(tester, 'cuaderno');
        await selectScope(tester, es.chatNotebookScopeAll);
        await send(tester, 'cuaderno');

        expect(harness.chatModel.vaultConversations, hasLength(2));
        expect(harness.chatModel.vaultConversations.first.closed, isTrue);
        // Sin acotar, la segunda alcanza a las dos fuentes.
        expect(
          harness.chatModel.vaultConversations.last.sentSources.single.map(
            (s) => s.itemTitle,
          ),
          containsAll(['Adentro del cuaderno', 'Afuera del cuaderno']),
        );
      },
    );

    testWidgets('reabrir una conversación restablece su cuaderno', (
      tester,
    ) async {
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');
      await seedScopedNotebook(tester);

      await selectScope(tester, 'Mi cuaderno');
      await send(tester, 'primera conversación con cuaderno');

      await selectScope(tester, es.chatNotebookScopeAll);
      await send(tester, 'segunda conversación sin acotar');

      await openPanel(tester);
      await tester.tap(inPanel(find.text('primera conversación con cuaderno')));
      await tester.pumpAndSettle();

      await send(tester, 'cuaderno de nuevo');

      final lastSent = harness.chatModel.vaultConversations.last.sentSources;
      expect(lastSent.last.map((s) => s.itemTitle), ['Adentro del cuaderno']);
    });
  });
}
