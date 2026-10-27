import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_feedback.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_answer.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_answer_message.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/read_aloud_test_support.dart';

/// La respuesta del chat (F42): el Markdown con buena tipografía, las citas
/// como chips que abren la fuente en su lugar, el amarillo del lector, el
/// fundido de lo que llega y las acciones de debajo.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late List<String> copied;

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
      ],
    );
    copied = [];
  });

  void listenClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
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
  }

  /// Monta [child] con un router de verdad, para ver adónde lleva una cita.
  Future<void> pump(WidgetTester tester, Widget child) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
        GoRoute(
          path: '/reading/:id',
          builder: (context, state) => Scaffold(
            body: Text(
              'lectura ${state.pathParameters['id']} ${state.uri.query}',
            ),
          ),
        ),
        GoRoute(
          path: '/library/:id',
          builder: (context, state) =>
              Scaffold(body: Text('detalle ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const sources = [
    ChatSource(
      itemId: 'roma',
      itemTitle: 'Historia de Roma',
      excerpt: 'Roma fue una república.',
      sourceCharStart: 120,
      sourceCharEnd: 180,
    ),
    ChatSource(
      itemId: 'nota',
      itemTitle: 'Una nota suelta',
      excerpt: 'Sin fragmentos.',
    ),
  ];

  /// El estilo del tramo de [text] dentro de los textos de la pantalla.
  TextStyle? styleOf(WidgetTester tester, String text) {
    TextStyle? found;
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == text) {
          found = span.style;
          return false;
        }
        return true;
      });
      if (found != null) break;
    }
    return found;
  }

  group('la tipografía', () {
    const raw =
        '# Roma\n\n'
        'Fue **una república** y usó `latín`.\n\n'
        '- uno\n'
        '  - adentro\n'
        '1. primero\n\n'
        '> una cita\n\n'
        '---\n\n'
        '```dart\nprint(1);\n```\n\n'
        '| País | Capital |\n|---|---|\n| Perú | Lima |';

    testWidgets('títulos, negritas, código en línea, listas, citas, '
        'separadores, código y tablas', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const ChatAnswerBody(text: raw, sourceKey: 'k'));

      // El título, más grande y marcado como título; sin los numerales.
      expect(find.text('Roma'), findsOneWidget);
      expect(find.textContaining('#'), findsNothing);
      expect(
        tester.getSemantics(find.text('Roma')),
        isSemantics(isHeader: true, label: 'Roma'),
      );
      final body = styleOf(tester, 'Fue ')!;
      expect(styleOf(tester, 'Roma')!.fontSize, greaterThan(body.fontSize!));
      expect(styleOf(tester, 'Roma')!.fontWeight, FontWeight.w700);
      // La negrita y el código en línea, con su fondo.
      expect(styleOf(tester, 'una república')!.fontWeight, FontWeight.bold);
      final code = styleOf(tester, 'latín')!;
      expect(code.fontFamily, 'monospace');
      expect(code.backgroundColor, isNotNull);
      // Las viñetas y los números, sin los guiones; lo de adentro, metido.
      expect(find.text('•'), findsOneWidget);
      expect(find.text('◦'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('adentro')).dx,
        greaterThan(tester.getTopLeft(find.text('uno')).dx),
      );
      expect(find.text('una cita'), findsOneWidget);
      expect(styleOf(tester, 'una cita')!.fontStyle, FontStyle.italic);
      expect(find.byType(Divider), findsOneWidget);
      // El código, con su lenguaje y sin las cercas.
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('print(1);'), findsOneWidget);
      expect(styleOf(tester, 'print(1);')!.fontFamily, 'monospace');
      expect(find.textContaining('```'), findsNothing);
      // La tabla, celda por celda; los títulos, en negrita.
      expect(find.byType(Table), findsOneWidget);
      for (final cell in ['País', 'Capital', 'Perú', 'Lima']) {
        expect(find.text(cell), findsOneWidget);
      }
      expect(styleOf(tester, 'País')!.fontWeight, FontWeight.w700);
      handle.dispose();
    });

    testWidgets('«Copiar el código» copia solo el código', (tester) async {
      listenClipboard(tester);
      await pump(tester, const ChatAnswerBody(text: raw, sourceKey: 'k'));

      await tester.tap(find.byTooltip(es.chatCodeCopy));
      await tester.pumpAndSettle();

      expect(copied, ['print(1);']);
      expect(find.text(es.chatAnswerCopied), findsOneWidget);
    });

    testWidgets('un bloque de código sin lenguaje dice «Código»', (
      tester,
    ) async {
      await pump(
        tester,
        const ChatAnswerBody(text: '```\nx = 1\n```', sourceKey: 'k'),
      );
      expect(find.text(es.chatCodeLabel), findsOneWidget);
    });

    testWidgets('una fila con menos celdas que los títulos no rompe la tabla', (
      tester,
    ) async {
      await pump(
        tester,
        const ChatAnswerBody(
          text: '| a | b | c |\n|---|---|---|\n| 1 |',
          sourceKey: 'k',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);
    });
  });

  group('las citas', () {
    testWidgets('son chips numerados; tocar uno abre la fuente en su pasaje', (
      tester,
    ) async {
      await pump(
        tester,
        const ChatAnswerBody(
          text: 'Fue una república [1] y tuvo notas [2].',
          sourceKey: 'k',
          sources: sources,
        ),
      );

      expect(find.textContaining('[1]'), findsNothing);
      expect(find.byKey(const Key('chat-citation-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat-citation-1')));
      await tester.pumpAndSettle();
      expect(find.text('lectura roma start=120&end=180'), findsOneWidget);
    });

    testWidgets('una fuente sin pasaje abre el detalle del elemento', (
      tester,
    ) async {
      await pump(
        tester,
        const ChatAnswerBody(
          text: 'Nota [2].',
          sourceKey: 'k',
          sources: sources,
        ),
      );
      await tester.tap(find.byKey(const Key('chat-citation-2')));
      await tester.pumpAndSettle();
      expect(find.text('detalle nota'), findsOneWidget);
    });

    testWidgets('«[1, 2]» son dos chips; «[3]» con dos fuentes queda como lo '
        'escribió el modelo', (tester) async {
      await pump(
        tester,
        const ChatAnswerBody(
          text: 'Ambas [1, 2]; otra [3].',
          sourceKey: 'k',
          sources: sources,
        ),
      );
      expect(find.byKey(const Key('chat-citation-1')), findsOneWidget);
      expect(find.byKey(const Key('chat-citation-2')), findsOneWidget);
      expect(find.byKey(const Key('chat-citation-3')), findsNothing);
      expect(find.textContaining('otra [3].'), findsOneWidget);
    });

    testWidgets('sin fuentes, un «[1]» es texto', (tester) async {
      await pump(
        tester,
        const ChatAnswerBody(text: 'Uno [1].', sourceKey: 'k'),
      );
      expect(find.text('Uno [1].'), findsOneWidget);
      expect(find.byKey(const Key('chat-citation-1')), findsNothing);
    });

    testWidgets('el lector de pantalla dice qué fuente es', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const ChatAnswerBody(
          text: 'Dato [1].',
          sourceKey: 'k',
          sources: sources,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('chat-citation-1'))),
        isSemantics(
          label: es.chatCitationSemantics(1, 'Historia de Roma'),
          isButton: true,
        ),
      );
      // El párrafo sigue siendo texto, no un botón.
      expect(
        tester.getSemantics(find.textContaining('Dato')),
        isNot(isSemantics(isButton: true)),
      );
      handle.dispose();
    });

    testWidgets('si las fuentes llegan después, la cita se vuelve chip', (
      tester,
    ) async {
      final given = ValueNotifier<List<ChatSource>>(const []);
      addTearDown(given.dispose);
      await pump(
        tester,
        ValueListenableBuilder<List<ChatSource>>(
          valueListenable: given,
          builder: (context, value, _) =>
              ChatAnswerBody(text: 'Dato [1].', sourceKey: 'k', sources: value),
        ),
      );
      expect(find.byKey(const Key('chat-citation-1')), findsNothing);
      given.value = sources;
      await tester.pump();
      expect(find.byKey(const Key('chat-citation-1')), findsOneWidget);
      // Las mismas fuentes en otra lista no cambian nada.
      given.value = [...sources];
      await tester.pump();
      expect(find.byKey(const Key('chat-citation-1')), findsOneWidget);
    });

    testWidgets('dentro del código, un «[1]» es código', (tester) async {
      await pump(
        tester,
        const ChatAnswerBody(
          text: '```\nlista[1]\n```',
          sourceKey: 'k',
          sources: sources,
        ),
      );
      expect(find.text('lista[1]'), findsOneWidget);
      expect(find.byKey(const Key('chat-citation-1')), findsNothing);
    });
  });

  group('el amarillo del lector (F25)', () {
    const raw = '## Título\n\nUn párrafo.\n\n- uno\n- dos\n\n```\ncódigo\n```';

    Future<void> readLine(WidgetTester tester, int index) async {
      final document = documentFrom('d', 't', [
        (sourceKey: 'k', text: raw, markdown: true, transcript: false),
      ]);
      (harness.container.read(readAloudControllerProvider.notifier)
              as FakeReadAloudController)
          .readAt(document, index);
      await tester.pump();
    }

    testWidgets('cae en el renglón que suena, sin las marcas', (tester) async {
      await pump(tester, const ChatAnswerBody(text: raw, sourceKey: 'k'));
      expect(readAloudHighlights(tester), isEmpty);

      final segments = documentFrom('d', 't', [
        (sourceKey: 'k', text: raw, markdown: true, transcript: false),
      ]).segments;
      for (var i = 0; i < segments.length; i++) {
        await readLine(tester, i);
        final spoken = segments[i].spoken;
        expect(readAloudHighlights(tester), [spoken], reason: 'pedazo $i');
      }
    });

    testWidgets('otro texto no se pinta', (tester) async {
      await pump(tester, const ChatAnswerBody(text: raw, sourceKey: 'otro'));
      await readLine(tester, 1);
      expect(readAloudHighlights(tester), isEmpty);
    });
  });

  group('mientras se escribe', () {
    late ValueNotifier<String> text;

    Future<void> pumpGrowing(WidgetTester tester, String first) async {
      text = ValueNotifier(first);
      addTearDown(text.dispose);
      await pump(
        tester,
        ValueListenableBuilder<String>(
          valueListenable: text,
          builder: (context, value, _) => ChatAnswerBody(
            text: value,
            sourceKey: 'k',
            sources: sources,
            growing: true,
          ),
        ),
      );
    }

    double alphaOf(WidgetTester tester, String piece) =>
        styleOf(tester, piece)!.color!.a;

    testWidgets('lo que llega entra con un fundido, y queda entero', (
      tester,
    ) async {
      await pumpGrowing(tester, 'Hola');
      text.value = 'Hola mundo';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final arriving = alphaOf(tester, ' mundo');
      expect(arriving, greaterThan(0));
      expect(arriving, lessThan(1));
      expect(alphaOf(tester, 'Hola'), 1);

      await tester.pump(kChatWordFade);
      expect(find.text('Hola mundo'), findsOneWidget);
      expect(alphaOf(tester, 'Hola mundo'), 1);
      // Terminado el fundido, nada sigue pidiendo cuadros.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('una cita que llega también se funde', (tester) async {
      await pumpGrowing(tester, 'Dato');
      text.value = 'Dato [1].';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final chip = find.ancestor(
        of: find.byKey(const Key('chat-citation-1')),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(chip.first).opacity, lessThan(1));
      await tester.pumpAndSettle();
      expect(chip, findsNothing);
    });

    testWidgets('con «sin animaciones», aparece de una', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpGrowing(tester, 'Hola');
      text.value = 'Hola mundo';
      await tester.pump();

      expect(alphaOf(tester, 'Hola mundo'), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('los bloques ya escritos no se vuelven a armar con cada '
        'palabra', (tester) async {
      await pumpGrowing(tester, 'Uno.\n\nDos.\n\nTres.\n\nCua');
      await tester.pumpAndSettle();
      final first = tester.widget(find.text('Uno.'));

      for (final next in ['Cuatro', 'Cuatro y', 'Cuatro y cinco.']) {
        text.value = 'Uno.\n\nDos.\n\nTres.\n\n$next';
        await tester.pump();
        expect(identical(tester.widget(find.text('Uno.')), first), isTrue);
      }
      await tester.pumpAndSettle();
      expect(find.text('Cuatro y cinco.'), findsOneWidget);
    });

    testWidgets('si el texto vuelve a empezar, se lee de nuevo', (
      tester,
    ) async {
      await pumpGrowing(tester, 'Uno.\n\nDos.\n\nTres.\n\nCuatro');
      text.value = 'Otra cosa.';
      await tester.pumpAndSettle();
      expect(find.text('Otra cosa.'), findsOneWidget);
      expect(find.text('Uno.'), findsNothing);
    });
  });

  test('el texto para seleccionar es lo que se ve, sin marcas', () {
    expect(
      chatAnswerPlainText(
        '# Roma\n\nFue **una** república.\n\n- uno\n  - dos\n1. tres\n\n'
        '> cita\n\n---\n\n```\nx = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |',
      ),
      'Roma\n\nFue una república.\n\n• uno\n  • dos\n1. tres\n\ncita\n\n'
      '———\n\nx = 1\n\na | b\n1 | 2',
    );
  });

  group('la respuesta guardada', () {
    PersistedChatMessage answer({
      String text = 'Una respuesta.',
      List<ChatSource> sources = const [],
      String? error,
    }) => PersistedChatMessage(
      id: 'm1',
      conversationId: 'c',
      isUser: false,
      text: text,
      createdAt: DateTime(2026, 10, 27),
      sources: sources,
      error: error,
    );

    testWidgets('lo escrito antes de un error se ve, con el aviso debajo', (
      tester,
    ) async {
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(error: 'Se cortó.'),
          sourceKey: 'k',
        ),
      );
      expect(find.text('Una respuesta.'), findsOneWidget);
      expect(find.text('Se cortó.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Se cortó.')).dy,
        greaterThan(tester.getTopLeft(find.text('Una respuesta.')).dy),
      );
      // En su recuadro, con los colores que se leen (AA) en todos los temas.
      final scheme = Theme.of(
        tester.element(find.text('Se cortó.')),
      ).colorScheme;
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('Se cortó.'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color, scheme.errorContainer);
      expect(styleOf(tester, 'Se cortó.')?.color, scheme.onErrorContainer);
    });

    testWidgets('solo el error, sin acciones de un texto que no hay', (
      tester,
    ) async {
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(text: '', error: 'Falló.'),
          sourceKey: 'k',
        ),
      );
      expect(find.text('Falló.'), findsOneWidget);
      expect(find.byTooltip(es.chatAnswerCopy), findsNothing);
      expect(find.byTooltip(es.chatAnswerRegenerate), findsNothing);
    });

    testWidgets('«Fuentes» plegado dice cuántas; abierto, sus tarjetas '
        'numeradas, que abren la fuente en su lugar', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(text: 'Dato [1].', sources: sources),
          sourceKey: 'k',
        ),
      );
      expect(find.text(es.chatSourcesHeader(2)), findsOneWidget);
      expect(find.text('Historia de Roma'), findsNothing);
      expect(
        tester.getSemantics(find.byKey(const Key('chat-sources-toggle'))),
        isSemantics(
          isButton: true,
          onTapHint: es.chatSourcesShow,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );

      await tester.tap(find.text(es.chatSourcesHeader(2)));
      await tester.pumpAndSettle();
      expect(find.text('Historia de Roma'), findsOneWidget);
      expect(find.text('Una nota suelta'), findsOneWidget);
      expect(find.text('Sin fragmentos.'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('chat-sources-toggle'))),
        isSemantics(
          isButton: true,
          onTapHint: es.chatSourcesHide,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );

      await tester.tap(find.text('Historia de Roma'));
      await tester.pumpAndSettle();
      expect(find.text('lectura roma start=120&end=180'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('plegarlo de nuevo las esconde', (tester) async {
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(sources: sources),
          sourceKey: 'k',
        ),
      );
      await tester.tap(find.text(es.chatSourcesHeader(2)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.chatSourcesHeader(2)));
      await tester.pumpAndSettle();
      expect(find.text('Historia de Roma'), findsNothing);
    });

    testWidgets('sin el modelo, las fuentes son la respuesta: a la vista, '
        'con su explicación', (tester) async {
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(text: '', sources: sources),
          sourceKey: 'k',
        ),
      );
      expect(find.text(es.chatSourcesOnlyExplanation), findsOneWidget);
      expect(find.text('Historia de Roma'), findsOneWidget);
      expect(find.text(es.chatSourcesHeader(2)), findsNothing);
    });

    testWidgets('sin nada encontrado, lo dice', (tester) async {
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(text: ''),
          sourceKey: 'k',
        ),
      );
      expect(find.text(es.chatNoSourcesFound), findsOneWidget);
    });

    testWidgets('copiar copia el texto tal cual, con su Markdown', (
      tester,
    ) async {
      listenClipboard(tester);
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(text: 'Es **así**.'),
          sourceKey: 'k',
        ),
      );
      await tester.tap(find.byTooltip(es.chatAnswerCopy));
      await tester.pumpAndSettle();
      expect(copied, ['Es **así**.']);
      expect(find.text(es.chatAnswerCopied), findsOneWidget);
    });

    testWidgets('«Volver a generar» solo si se lo pasan, y lo llama', (
      tester,
    ) async {
      var regenerated = 0;
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(),
          sourceKey: 'k',
          onRegenerate: () => regenerated++,
        ),
      );
      await tester.tap(find.byTooltip(es.chatAnswerRegenerate));
      expect(regenerated, 1);

      await pump(tester, ChatAnswerMessage(message: answer(), sourceKey: 'k'));
      expect(find.byTooltip(es.chatAnswerRegenerate), findsNothing);
    });

    testWidgets('un error sin texto, si es la última, se puede volver a '
        'pedir', (tester) async {
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(text: '', error: 'Falló.'),
          sourceKey: 'k',
          onRegenerate: () {},
        ),
      );
      expect(find.byTooltip(es.chatAnswerRegenerate), findsOneWidget);
    });

    testWidgets('👍 y 👎 quedan en el teléfono: marcar, cambiar y desmarcar', (
      tester,
    ) async {
      await pump(tester, ChatAnswerMessage(message: answer(), sourceKey: 'k'));
      IconButton button(String what) =>
          tester.widget<IconButton>(find.byKey(Key('chat-answer-$what-m1')));
      Map<String, ChatFeedback> stored() =>
          harness.container.read(chatFeedbackProvider);

      expect(button('good').isSelected, isFalse);
      await tester.tap(find.byTooltip(es.chatAnswerGood));
      await tester.pumpAndSettle();
      expect(button('good').isSelected, isTrue);
      expect(stored(), {'m1': ChatFeedback.good});
      expect(find.text(es.chatAnswerRatedSnack), findsOneWidget);

      await tester.tap(find.byTooltip(es.chatAnswerBad));
      await tester.pumpAndSettle();
      expect(button('good').isSelected, isFalse);
      expect(button('bad').isSelected, isTrue);
      expect(stored(), {'m1': ChatFeedback.bad});

      ScaffoldMessenger.of(
        tester.element(find.byType(ChatAnswerMessage)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(es.chatAnswerBad));
      await tester.pumpAndSettle();
      expect(button('bad').isSelected, isFalse);
      expect(stored(), isEmpty);
      // Desmarcar no avisa nada.
      expect(find.text(es.chatAnswerRatedSnack), findsNothing);
    });

    testWidgets('mantenerla apretada: copiar y seleccionar lo que se ve', (
      tester,
    ) async {
      listenClipboard(tester);
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(text: '# Roma\n\nFue **una** república.'),
          sourceKey: 'k',
        ),
      );
      await tester.longPress(find.text('Roma'));
      await tester.pumpAndSettle();
      // De una respuesta no se edita nada.
      expect(find.byKey(const Key('chat-menu-edit')), findsNothing);
      await tester.tap(find.byKey(const Key('chat-menu-copy')));
      await tester.pumpAndSettle();
      expect(copied, ['# Roma\n\nFue **una** república.']);

      await tester.longPress(find.text('Roma'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-menu-select')));
      await tester.pumpAndSettle();
      final selectable = tester.widget<SelectableText>(
        find.byKey(const Key('chat-selectable-text')),
      );
      expect(selectable.data, 'Roma\n\nFue una república.');
      expect(find.text(es.chatSelectTitle), findsOneWidget);
    });

    testWidgets('el lector de pantalla sabe que se puede mantener apretada, y '
        'cada acción tiene nombre', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        ChatAnswerMessage(
          message: answer(),
          sourceKey: 'k',
          onRegenerate: () {},
        ),
      );
      expect(
        tester.getSemantics(find.text('Una respuesta.')),
        isSemantics(onLongPressHint: es.chatMessageOptionsHint),
      );
      for (final tooltip in [
        es.chatAnswerCopy,
        es.chatAnswerListen,
        es.chatAnswerRegenerate,
        es.chatAnswerGood,
        es.chatAnswerBad,
      ]) {
        expect(
          tester.getSemantics(find.byTooltip(tooltip)),
          isSemantics(tooltip: tooltip, isButton: true),
          reason: tooltip,
        );
      }
      handle.dispose();
    });
  });
}
