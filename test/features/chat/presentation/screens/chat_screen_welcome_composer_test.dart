import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/camera_chooser.dart';
import 'package:sinapsis/features/chat/domain/services/dictation.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_ambient_glow.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/settings/presentation/providers/owner_name.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/chat_actions.dart';
import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';

/// Firma PNG mínima: alcanza para que el formato se reconozca por los bytes.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

/// F42, paso 2: el vacío que recibe y el campo flotante. Ninguna función de
/// antes se pierde (decisión D): adjuntar, mandar, detener, el modo y el
/// alcance siguen, ahora desde el «+»; y lo nuevo —el saludo, las
/// sugerencias, el aviso del modelo en su lugar, dictar, «Pensar más», Enter
/// en la computadora— se fija acá.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpChat(
    WidgetTester tester, {
    bool chatModelReady = false,
    String? chatModelResponse,
    CapturedFile? chosenFile,
    CapturedFile? chosenPhoto,
    CapturedFile? chosenGalleryPhoto,
    Object? cameraChooserError,
    bool dictationAvailable = false,
  }) async {
    harness = await LibraryHarness.create(
      chatModelReady: chatModelReady,
      chatModelResponse: chatModelResponse,
      chosenFile: chosenFile,
      chosenPhoto: chosenPhoto,
      chosenGalleryPhoto: chosenGalleryPhoto,
      cameraChooserError: cameraChooserError,
      dictationAvailable: dictationAvailable,
    );
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
  }

  /// Con Gemini, una clave cargada y [model] elegido: el modelo está listo.
  Future<void> pumpCloudChat(WidgetTester tester, String model) async {
    harness = await LibraryHarness.create(
      languageModelProvider: AiProvider.gemini,
      chatModelResponse: 'ok',
    );
    await harness.container
        .read(aiAccountRepositoryProvider)
        .add(provider: AiProvider.gemini, key: 'una-clave', label: 'Mía');
    await harness.container
        .read(aiModelSettingsProvider.notifier)
        .chooseModel(AiProvider.gemini, model);
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('chat-composer-field')))
      .controller!
      .text;

  IconButton sendButton(WidgetTester tester) => tester.widget<IconButton>(
    find.ancestor(
      of: find.byIcon(Icons.arrow_upward_rounded),
      matching: find.byType(IconButton),
    ),
  );

  group('el saludo', () {
    testWidgets('sin nombre, según la hora —a las 10, «Buen día»— y la '
        'pregunta de la bóveda', (tester) async {
      await pumpChat(tester);

      expect(find.text(es.chatGreetingMorning), findsOneWidget);
      expect(find.text(es.chatGreetingVaultQuestion), findsOneWidget);
      // Para el lector de pantalla, una sola frase y un encabezado.
      expect(
        find.bySemanticsLabel(
          '${es.chatGreetingMorning} ${es.chatGreetingVaultQuestion}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con el nombre de «Cómo te llamo», «Hola, Armando.», al día '
        'con Ajustes; sin nombre, vuelve a la hora', (tester) async {
      await pumpChat(tester);
      final owner = harness.container.read(ownerNameProvider.notifier);

      await owner.rename(' Armando ');
      await tester.pumpAndSettle();
      expect(find.text(es.chatGreetingNamed('Armando')), findsOneWidget);
      expect(find.text(es.chatGreetingMorning), findsNothing);

      await owner.rename('   ');
      await tester.pumpAndSettle();
      expect(find.text(es.chatGreetingMorning), findsOneWidget);
    });

    testWidgets('en conversación libre, su pregunta y lo que dice el campo', (
      tester,
    ) async {
      await pumpChat(tester);
      expect(find.text(es.chatComposerVaultHint), findsOneWidget);

      await setVaultMode(tester, on: false);

      expect(find.text(es.chatGreetingFreeQuestion), findsOneWidget);
      expect(find.text(es.chatComposerFreeHint), findsOneWidget);
      expect(find.text(es.chatComposerVaultHint), findsNothing);
    });

    testWidgets('el brillo está en el vacío y se va con la conversación', (
      tester,
    ) async {
      await pumpChat(tester);
      expect(find.byKey(const Key('chat-ambient-glow')), findsOneWidget);

      await sendChatMessage(tester, 'hola');

      expect(find.byKey(const Key('chat-ambient-glow')), findsNothing);
    });
  });

  group('el brillo, que respira', () {
    Future<void> pumpBreathing(WidgetTester tester) async {
      harness = await LibraryHarness.create(chatGlowBreaths: 2);
      await tester.pumpWidget(harness.wrap(const ChatScreen()));
      await tester.pump();
    }

    testWidgets('respira y después queda quieto: no gasta cuadros para '
        'siempre', (tester) async {
      await pumpBreathing(tester);
      expect(tester.hasRunningAnimations, isTrue);

      final fade = find
          .ancestor(
            of: find.byKey(const Key('chat-ambient-glow')),
            matching: find.byType(FadeTransition),
          )
          .first;
      double opacity() => tester.widget<FadeTransition>(fade).opacity.value;
      final atRest = opacity();
      await tester.pump(kChatGlowBreath ~/ 2);
      expect(opacity(), greaterThan(atRest));

      await tester.pump(kChatGlowBreath * 2);
      expect(tester.hasRunningAnimations, isFalse);
      // Termina exhalado, como empezó: no en su pico.
      expect(opacity(), closeTo(atRest, 0.001));
    });

    testWidgets('con «sin animaciones» del sistema, quieto desde el '
        'principio', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpBreathing(tester);

      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byKey(const Key('chat-ambient-glow')), findsOneWidget);
    });

    testWidgets('con «alto contraste», el fondo queda liso', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpChat(tester);

      expect(find.byKey(const Key('chat-ambient-glow')), findsNothing);
      // Y el saludo, sin el degradé.
      expect(
        find.ancestor(
          of: find.byKey(const Key('chat-greeting')),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
    });
  });

  group('las sugerencias', () {
    testWidgets('con la bóveda vacía, dice que van a aparecer', (tester) async {
      await pumpChat(tester);

      expect(find.text(es.chatSuggestionsEmptyVault), findsOneWidget);
    });

    testWidgets('con algo guardado, tocar «Resumime…» la manda al modelo', (
      tester,
    ) async {
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'listo');
      await harness.capture('Don Quijote\n\nun hidalgo de la Mancha');
      await tester.pumpAndSettle();

      final summarize = es.chatSuggestionSummarize('Don Quijote');
      expect(find.text(summarize), findsOneWidget);
      expect(find.text(es.chatSuggestionQuizMe('Don Quijote')), findsOneWidget);
      expect(find.text(es.chatSuggestionsEmptyVault), findsNothing);

      await tester.tap(find.text(summarize));
      await tester.pumpAndSettle();

      expect(harness.chatModel.vaultConversations.single.sent, [summarize]);
      expect(find.text('listo'), findsOneWidget);
    });

    testWidgets('lo que todavía se está procesando no se sugiere: no tiene '
        'texto que resumir', (tester) async {
      await pumpChat(tester);
      await harness.capture('https://example.com/un-articulo');
      await tester.pumpAndSettle();

      expect(find.textContaining('Resumime'), findsNothing);
      expect(find.text(es.chatSuggestionsEmptyVault), findsOneWidget);
    });

    testWidgets('la que hay que completar queda en el campo, sin mandarse', (
      tester,
    ) async {
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'listo');
      for (final title in ['Roma', 'Grecia', 'Egipto']) {
        await harness.capture('$title\n\nuna civilización');
      }
      await tester.pumpAndSettle();

      final ask = find.textContaining('¿Qué dice «');
      expect(ask, findsOneWidget);
      await tester.tap(ask);
      await tester.pumpAndSettle();

      expect(fieldText(tester), startsWith('¿Qué dice «'));
      expect(fieldText(tester), endsWith(' sobre '));
      expect(harness.chatModel.vaultConversations, isEmpty);
    });

    testWidgets('en conversación libre, tres comienzos que se completan', (
      tester,
    ) async {
      await pumpChat(tester, chatModelReady: true);
      await setVaultMode(tester, on: false);

      expect(find.text(es.chatSuggestionsEmptyVault), findsNothing);
      await tester.tap(find.text('${es.chatSuggestionFreeExplain.trim()}…'));
      await tester.pumpAndSettle();

      expect(fieldText(tester), es.chatSuggestionFreeExplain);
      expect(harness.chatModel.conversations, isEmpty);
    });

    testWidgets('acotadas a un cuaderno, sale el cuaderno', (tester) async {
      await pumpChat(tester);
      // Lo último de la Biblioteca no cuenta: un cuaderno tiene solo
      // documentos procesados (F41, paso 5).
      await harness.capture('De la Biblioteca\n\nalgo');
      await insertProcessedRows(
        harness.database,
        id: 'adentro',
        title: 'Adentro',
      );
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Tesis', mode: NotebookMode.manual);
      await harness.container
          .read(notebookRepositoryProvider)
          .addItem(notebookId: notebook.id, itemId: 'adentro');
      await tester.pumpAndSettle();

      await chooseChatScope(tester, 'Tesis');

      expect(
        find.text(es.chatSuggestionNotebookThemes('Tesis')),
        findsOneWidget,
      );
      expect(find.text(es.chatSuggestionSummarize('Adentro')), findsOneWidget);
      expect(
        find.text(es.chatSuggestionSummarize('De la Biblioteca')),
        findsNothing,
      );
    });
  });

  group('el aviso del modelo', () {
    testWidgets('sin el modelo, en el vacío con su botón, y en la '
        'conversación arriba del campo', (tester) async {
      await pumpChat(tester);

      final notice = find.byKey(const Key('chat-model-notice'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(
          of: notice,
          matching: find.text(es.chatModelNotReadyBanner),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: notice,
          matching: find.text(es.chatModelDownloadAction),
        ),
        findsOneWidget,
      );

      await sendChatMessage(tester, 'algo');

      expect(notice, findsOneWidget);
      expect(find.text(es.chatModelNotReadyBanner), findsOneWidget);
    });

    testWidgets('con el modelo listo, no hay aviso', (tester) async {
      await pumpChat(tester, chatModelReady: true);

      expect(find.byKey(const Key('chat-model-notice')), findsNothing);
    });
  });

  group('el campo', () {
    testWidgets('enviar está apagado sin nada que mandar y se prende al '
        'escribir', (tester) async {
      await pumpChat(tester);
      expect(sendButton(tester).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('chat-composer-field')),
        '   ',
      );
      await tester.pump();
      expect(sendButton(tester).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('chat-composer-field')),
        'hola',
      );
      await tester.pump();
      expect(sendButton(tester).onPressed, isNotNull);
    });

    testWidgets('mientras el modelo escribe se puede ir escribiendo lo '
        'próximo, pero no mandarlo', (tester) async {
      await pumpChat(tester, chatModelReady: true);
      harness.chatModel.manualReplies = true;
      await typeAndSend(tester, 'primero');
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('chat-composer-field')),
        'segundo',
      );
      // Lo que tarda enviar en volverse «Detener».
      await tester.pump(const Duration(milliseconds: 300));
      expect(fieldText(tester), 'segundo');
      expect(find.byTooltip(es.chatStopTooltip), findsOneWidget);
      expect(find.byTooltip(es.chatSendTooltip), findsNothing);

      final reply = harness.chatModel.vaultConversations.single.replies.single;
      await reply.close();
      await tester.pumpAndSettle();
      expect(harness.chatModel.vaultConversations.single.sent, ['primero']);
      expect(fieldText(tester), 'segundo');
    });

    testWidgets('cada botón dice qué hace, para el lector de pantalla', (
      tester,
    ) async {
      await pumpChat(tester, dictationAvailable: true);

      expect(find.byTooltip(es.chatAddTooltip), findsOneWidget);
      expect(find.byTooltip(es.chatSendTooltip), findsOneWidget);
      expect(find.byTooltip(es.chatDictateTooltip), findsOneWidget);
    });
  });

  group('Enter en la computadora', () {
    Future<void> typeInField(WidgetTester tester, String text) async {
      await tester.tap(find.byKey(const Key('chat-composer-field')));
      await tester.enterText(
        find.byKey(const Key('chat-composer-field')),
        text,
      );
      await tester.pump();
    }

    testWidgets('Enter manda; Shift+Enter, no', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');

      await typeInField(tester, 'con shift');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(harness.chatModel.vaultConversations, isEmpty);

      await typeInField(tester, 'con enter');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.chatModel.vaultConversations.single.sent, ['con enter']);
      expect(fieldText(tester), isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Enter sin nada escrito no manda nada', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpChat(tester, chatModelReady: true);

      await typeInField(tester, '');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(harness.chatModel.vaultConversations, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('en el teléfono, Enter no manda: es el salto de línea', (
      tester,
    ) async {
      await pumpChat(tester, chatModelReady: true);

      await typeInField(tester, 'en el teléfono');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(harness.chatModel.vaultConversations, isEmpty);
    });

    testWidgets('en la computadora no hay tarjeta de cámara', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpChat(tester);
      await openAddToChat(tester);

      expect(find.byKey(const Key('chat-add-camera')), findsNothing);
      expect(find.byKey(const Key('chat-add-photos')), findsOneWidget);
      expect(find.byKey(const Key('chat-add-files')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('«Agregar al chat»', () {
    final pending = find.byKey(const Key('chat-pending-attachment'));

    testWidgets('«Cámara» saca una foto y la adjunta', (tester) async {
      await pumpChat(
        tester,
        chatModelReady: true,
        chatModelResponse: 'ok',
        chosenPhoto: CapturedFile(name: 'foto.png', bytes: _png),
      );

      await attachFrom(tester, 'chat-add-camera');

      expect(harness.cameraChooser.timesOpened, 1);
      expect(pending, findsOneWidget);
      await sendChatMessage(tester, 'qué es esto');
      expect(harness.chatModel.vaultConversations.single.sentImages.single, [
        _png,
      ]);
    });

    testWidgets('sin permiso para la cámara, lo dice', (tester) async {
      await pumpChat(
        tester,
        cameraChooserError: const CameraAccessDeniedException(),
      );

      await attachFrom(tester, 'chat-add-camera');

      expect(find.text(es.captureCameraAccessDenied), findsOneWidget);
      expect(pending, findsNothing);
    });

    testWidgets('«Fotos» trae una de la galería', (tester) async {
      await pumpChat(
        tester,
        chosenGalleryPhoto: CapturedFile(name: 'galeria.png', bytes: _png),
      );

      await attachFrom(tester, 'chat-add-photos');

      expect(harness.photoLibraryChooser.timesOpened, 1);
      expect(pending, findsOneWidget);
    });

    testWidgets('cerrar la galería sin elegir no adjunta nada', (tester) async {
      await pumpChat(tester);

      await attachFrom(tester, 'chat-add-photos');

      expect(harness.photoLibraryChooser.timesOpened, 1);
      expect(pending, findsNothing);
    });

    testWidgets('«Dónde pregunto» del «+» abre la misma hoja que la línea de '
        'arriba: el modo cambia desde ahí y la fila lo dice', (tester) async {
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');
      final scopeRow = find.byKey(const Key('chat-add-scope'));
      Finder rowSays(String text) =>
          find.descendant(of: scopeRow, matching: find.text(text));

      await openAddToChat(tester);
      expect(
        rowSays('${es.chatScopeLineVault} · ${es.chatNotebookScopeAll}'),
        findsOneWidget,
      );
      await tester.tap(scopeRow);
      await tester.pumpAndSettle();
      // La hoja «Dónde pregunto» del paso 1, la misma de la línea de arriba.
      expect(find.byKey(const Key('chat-scope-free')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat-scope-free')));
      await tester.pumpAndSettle();
      // Elegir la conversación libre la cierra; el «+» queda, al día.
      expect(rowSays(es.chatModeFree), findsOneWidget);
      await closeChatSheets(tester);

      await sendChatMessage(tester, 'libre');
      expect(harness.chatModel.conversations.single.sent, ['libre']);
      expect(harness.chatModel.vaultConversations, isEmpty);

      await setVaultMode(tester, on: true, fromAddSheet: true);
      await sendChatMessage(tester, 'con la bóveda');
      expect(harness.chatModel.vaultConversations.single.sent, [
        'con la bóveda',
      ]);
    });

    testWidgets('el cuaderno elegido desde el «+» se ve en la fila y acota '
        'lo que llega al modelo', (tester) async {
      await pumpChat(tester, chatModelReady: true, chatModelResponse: 'ok');
      await insertProcessedRows(
        harness.database,
        id: 'adentro',
        title: 'Adentro del cuaderno',
        parts: {
          ProcessedSection.notes: ['algo de adentro'],
        },
      );
      await harness.capture('Afuera del cuaderno\n\nalgo de afuera');
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Mi cuaderno', mode: NotebookMode.manual);
      await harness.container
          .read(notebookRepositoryProvider)
          .addItem(notebookId: notebook.id, itemId: 'adentro');
      await tester.pumpAndSettle();

      await chooseChatScope(tester, 'Mi cuaderno', fromAddSheet: true);
      await openAddToChat(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('chat-add-scope')),
          matching: find.text('${es.chatScopeLineVault} · Mi cuaderno'),
        ),
        findsOneWidget,
      );
      await closeChatSheets(tester);

      await sendChatMessage(tester, 'cuaderno');
      expect(
        harness.chatModel.vaultConversations.single.sentSources.single.map(
          (s) => s.itemTitle,
        ),
        ['Adentro del cuaderno'],
      );
    });

    group('«Pensar más»', () {
      testWidgets('con Gemma se ve apagado y dice por qué', (tester) async {
        await pumpChat(tester, chatModelReady: true);
        await openAddToChat(tester);

        final toggle = tester.widget<SwitchListTile>(
          find.byKey(const Key('chat-add-think-more')),
        );
        expect(toggle.onChanged, isNull);
        expect(toggle.value, isFalse);
        expect(find.text(es.chatAddThinkMoreOnDevice), findsOneWidget);
      });

      testWidgets('si después se elige un modelo que no razona, deja de '
          'valer: ni la pastilla ni el pedido', (tester) async {
        await pumpCloudChat(tester, 'gemini-3.8-flash');
        await openAddToChat(tester);
        await tester.tap(find.byKey(const Key('chat-add-think-more')));
        await tester.pumpAndSettle();
        await closeChatSheets(tester);
        expect(find.byKey(const Key('chat-think-more-pill')), findsOneWidget);

        await harness.container
            .read(aiModelSettingsProvider.notifier)
            .chooseModel(AiProvider.gemini, 'gemini-2.0-flash');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chat-think-more-pill')), findsNothing);

        await sendChatMessage(tester, 'hola');
        expect(harness.chatModel.vaultConversations.single.sentThinkMore, [
          false,
        ]);
      });

      testWidgets('con un modelo en la nube que no razona, también, con su '
          'nombre', (tester) async {
        await pumpCloudChat(tester, 'gemini-2.0-flash');
        await openAddToChat(tester);

        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('chat-add-think-more')),
              )
              .onChanged,
          isNull,
        );
        expect(
          find.text(es.chatAddThinkMoreNotThisModel('Gemini 2.0 Flash')),
          findsOneWidget,
        );
      });

      testWidgets('con uno que razona se prende, se ve en el campo, llega al '
          'modelo y se apaga tocando la pastilla', (tester) async {
        await pumpCloudChat(tester, 'gemini-3.8-flash');
        await openAddToChat(tester);
        expect(find.text(es.chatAddThinkMoreAvailable), findsOneWidget);

        await tester.tap(find.byKey(const Key('chat-add-think-more')));
        await tester.pumpAndSettle();
        await closeChatSheets(tester);

        final pill = find.byKey(const Key('chat-think-more-pill'));
        expect(pill, findsOneWidget);
        await sendChatMessage(tester, 'pensalo bien');

        await tester.tap(pill);
        await tester.pumpAndSettle();
        expect(pill, findsNothing);
        await sendChatMessage(tester, 'rápido');

        expect(harness.chatModel.vaultConversations.single.sentThinkMore, [
          true,
          false,
        ]);
      });
    });
  });

  group('dictar', () {
    final mic = find.byTooltip(es.chatDictateTooltip);
    final micListening = find.byTooltip(es.chatDictateStopTooltip);

    testWidgets('sin reconocimiento de voz en el dispositivo, no hay 🎤', (
      tester,
    ) async {
      await pumpChat(tester);

      expect(mic, findsNothing);
      expect(micListening, findsNothing);
    });

    testWidgets('lo dicho se escribe mientras se dice, después de lo que ya '
        'había, y al terminar la frase el 🎤 vuelve', (tester) async {
      await pumpChat(tester, dictationAvailable: true);
      await tester.enterText(
        find.byKey(const Key('chat-composer-field')),
        'Hola',
      );

      await tester.tap(mic);
      await tester.pump();
      expect(micListening, findsOneWidget);
      expect(harness.dictation.listenedIn.single, startsWith('es'));

      harness.dictation
        ..level(0.8)
        ..say('qué tal');
      await tester.pump();
      expect(fieldText(tester), 'Hola qué tal');

      await harness.dictation.finish('qué tal, che');
      await tester.pumpAndSettle();
      expect(fieldText(tester), 'Hola qué tal, che');
      expect(mic, findsOneWidget);
      expect(micListening, findsNothing);
    });

    testWidgets('con el campo vacío, dice que escucha; tocarlo de nuevo '
        'corta', (tester) async {
      await pumpChat(tester, dictationAvailable: true);

      await tester.tap(mic);
      await tester.pump();
      expect(find.text(es.chatComposerListeningHint), findsOneWidget);

      await tester.tap(micListening);
      await tester.pumpAndSettle();
      expect(harness.dictation.stops, 1);
      expect(mic, findsOneWidget);
      expect(find.text(es.chatComposerListeningHint), findsNothing);
    });

    testWidgets('después de un espacio no agrega otro', (tester) async {
      await pumpChat(tester, dictationAvailable: true);
      await tester.enterText(
        find.byKey(const Key('chat-composer-field')),
        'Hola ',
      );

      await tester.tap(mic);
      await tester.pump();
      await harness.dictation.finish('mundo');
      await tester.pumpAndSettle();

      expect(fieldText(tester), 'Hola mundo');
    });

    for (final (error, message) in [
      (const DictationPermissionDeniedException(), 'permiso'),
      (const DictationFailedException('network'), 'red'),
      (const DictationFailedException('busy'), 'otro'),
    ]) {
      testWidgets('si falla ($message), lo dice y el 🎤 vuelve', (
        tester,
      ) async {
        await pumpChat(tester, dictationAvailable: true);
        await tester.tap(mic);
        await tester.pump();

        await harness.dictation.fail(error);
        await tester.pumpAndSettle();

        expect(
          find.text(switch (error) {
            DictationPermissionDeniedException() =>
              es.chatDictationPermissionDenied,
            DictationFailedException(code: 'network') =>
              es.chatDictationNoNetwork,
            _ => es.chatDictationFailed,
          }),
          findsOneWidget,
        );
        expect(mic, findsOneWidget);
      });
    }
  });

  group('letra grande y los nueve temas', () {
    testWidgets('con letra al doble en una pantalla chica, la pantalla '
        'entera —la barra, el vacío y el campo— y la hoja del «+» no se '
        'desbordan', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640) * 3
        ..devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // Sin el modelo: el vacío lleva también la tarjeta del aviso.
      await pumpChat(tester, dictationAvailable: true);
      await harness.capture('Un título bastante largo para una pastilla\n\nx');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('chat-scope-line')), findsOneWidget);
      expect(find.byKey(const Key('chat-model-notice')), findsOneWidget);
      expect(find.byTooltip(es.chatSendTooltip), findsOneWidget);

      await openAddToChat(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('chat-add-think-more')), findsOneWidget);
      await closeChatSheets(tester);

      // Y ya en una conversación, con el aviso en una línea arriba del
      // campo.
      await sendChatMessage(tester, 'hola');
      expect(tester.takeException(), isNull);
    });

    test('en cada tema, lo que se lee del vacío y del campo tiene '
        'contraste', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
      }

      for (final choice in AppThemeChoice.values) {
        for (final theme in {choice.theme, choice.darkTheme}) {
          final s = theme.colorScheme;
          final field = theme.brightness == Brightness.dark
              ? s.surfaceContainerHigh
              : s.surfaceContainerLowest;
          final reason = '${choice.name} ${theme.brightness.name}';
          // Texto común: 4,5 a 1.
          expect(
            contrast(s.onSurface, s.surfaceContainerHigh),
            greaterThanOrEqualTo(4.5),
            reason: 'sugerencias, $reason',
          );
          expect(
            contrast(s.onSurfaceVariant, s.surface),
            greaterThanOrEqualTo(4.5),
            reason: 'pregunta, $reason',
          );
          expect(
            contrast(s.onSurface, field),
            greaterThanOrEqualTo(4.5),
            reason: 'campo, $reason',
          );
          expect(
            contrast(s.onSecondaryContainer, s.secondaryContainer),
            greaterThanOrEqualTo(4.5),
            reason: 'aviso y «Pensar más», $reason',
          );
          // El saludo es texto grande: 3 a 1 en las dos puntas del degradé.
          expect(
            contrast(s.primary, s.surface),
            greaterThanOrEqualTo(3),
            reason: 'saludo, primario, $reason',
          );
          expect(
            contrast(s.tertiary, s.surface),
            greaterThanOrEqualTo(3),
            reason: 'saludo, terciario, $reason',
          );
        }
      }
    });
  });
}
