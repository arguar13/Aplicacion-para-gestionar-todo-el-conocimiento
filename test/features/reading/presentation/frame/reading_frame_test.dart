import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/reading_scroll_physics.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_player_extent.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_contents_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_more_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_text_to_speech_service.dart';

/// El marco de lectura (F47, paso 1): la barra con ← y los cuatro botones
/// redondos, la fila de IA, Apariencia, ⋮, Contenido y el lugar del
/// reproductor —sin el botón flotante—, en un teléfono con la letra al
/// doble y en una pantalla ancha, en claro, oscuro y sepia.
void main() {
  final es = AppLocalizationsEs();
  const text = 'Uno dos tres.\nCuatro cinco.\nSeis.';
  final document = ReadableDocument(
    id: 'marco:1',
    title: 'Roma',
    segments: buildReadableSegments(text, sourceKey: 'texto:1'),
  );

  late ProviderContainer container;
  late SharedPreferences prefs;
  late GoRouter router;

  /// Un cuerpo que ofrece [document] para escuchar, le da al marco un índice
  /// y —en una página— un zoom.
  Widget body({ReadingZoom? zoom}) => _Body(document: document, zoom: zoom);

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(420, 900),
    double textScale = 1,
    AppThemeChoice theme = AppThemeChoice.light,
    ReadingBodyKind bodyKind = ReadingBodyKind.text,
    ReadingZoom? zoom,
    bool showTitle = true,
    CreationScope? podcastScope,
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    _done.clear();
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ReadingFrame(
            info: ReadingDocumentInfo(
              title: 'Roma y la república',
              kindLabel: 'Resumen · 2 oraciones',
              kindIcon: Icons.notes_outlined,
              onRename: (host) async => _done.add('renombrar'),
            ),
            bodyKind: bodyKind,
            showTitle: showTitle,
            body: body(zoom: zoom),
            onSummarize: () => _done.add('resumir'),
            contents: [
              ReadingContentsSection(
                title: 'Fuentes',
                entries: [
                  ReadingOutlineEntry(
                    key: const Key('fuente'),
                    label: 'La fuente',
                    onSelected: () => _done.add('fuente'),
                  ),
                ],
              ),
            ],
            menu: [
              ReadingMenuGroup([
                ReadingMenuEntry(
                  key: const Key('exportar'),
                  icon: Icons.download_outlined,
                  label: 'Exportar',
                  onSelected: () => _done.add('exportar'),
                ),
                const ReadingMenuEntry(
                  key: Key('apagada'),
                  icon: Icons.block,
                  label: 'Apagada',
                  detail: 'Por qué',
                  onSelected: null,
                ),
              ]),
              ReadingMenuGroup([
                ReadingMenuEntry(
                  key: const Key('borrar'),
                  icon: Icons.delete_outline,
                  label: 'Mover a la papelera',
                  destructive: true,
                  onSelected: () => _done.add('borrar'),
                ),
              ]),
            ],
            podcastScope: podcastScope,
          ),
        ),
        GoRoute(path: '/chat', builder: (_, _) => const Text('El chat')),
      ],
    );
    addTearDown(router.dispose);
    // Un `ProviderScope` y no uno de afuera: se va con la pantalla, y lo que
    // las regiones de lectura retiran al irse no queda pendiente.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          textToSpeechServiceProvider.overrideWithValue(
            FakeTextToSpeechService(),
          ),
          narrationClockProvider.overrideWithValue(() => Duration.zero),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: theme.theme,
          darkTheme: theme.darkTheme,
          themeMode: theme.mode,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: ReadAloudOverlay(router: router, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
  }

  ReadAloudController controller() =>
      container.read(readAloudControllerProvider.notifier);

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  const buttons = [
    'reading-frame-contents',
    'reading-frame-ai',
    'reading-frame-appearance',
    'reading-frame-more',
  ];

  group('la barra', () {
    testWidgets('← a la izquierda y los cuatro botones redondos a la derecha, '
        'del mismo tamaño; el título va grande en el cuerpo, no en la barra', (
      tester,
    ) async {
      await pump(tester);

      final back = tester.getRect(find.byKey(const Key('reading-frame-back')));
      final rects = [
        for (final key in buttons) tester.getRect(find.byKey(Key(key))),
      ];
      for (final rect in rects) {
        expect(rect.size, rects.first.size);
        expect(rect.top, rects.first.top);
        expect(rect.left, greaterThan(back.right));
      }
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left, greaterThan(rects[i - 1].left));
      }
      expect(rects.last.right, closeTo(420, 12));
      // Redondos y con borde.
      for (final key in buttons) {
        final style = tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(Key(key)),
                matching: find.byType(IconButton),
              ),
            )
            .style!;
        expect(style.shape!.resolve({}), isA<CircleBorder>());
        expect(style.side!.resolve({}), isNot(BorderSide.none));
      }
      // El título, una sola vez: el encabezado del cuerpo.
      expect(find.text('Roma y la república'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ReadingFrameBar),
          matching: find.text('Roma y la república'),
        ),
        findsNothing,
      );
      expect(find.text('RESUMEN · 2 ORACIONES'), findsOneWidget);
    });

    testWidgets('el lector de pantalla dice cada botón por su nombre, y el '
        'título es el encabezado', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      for (final label in [
        es.f47P1FrameContents,
        es.f47P1FrameAi,
        es.f47P1FrameAppearance,
        es.f47P1FrameMore,
      ]) {
        // El nombre de cada botón es su ayuda, que el lector de pantalla dice.
        final node = tester.getSemantics(find.byTooltip(label));
        expect(node.tooltip, label);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      expect(
        tester.getSemantics(find.byKey(const Key('reading-frame-title'))),
        matchesSemantics(label: 'Roma y la república', isHeader: true),
      );
      semantics.dispose();
    });

    testWidgets('← vuelve atrás', (tester) async {
      await pump(tester);
      unawaited(router.push<void>('/chat'));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      await tapKey(tester, 'reading-frame-back');
      expect(find.byKey(const Key('reading-frame')), findsOneWidget);
    });
  });

  group('la fila de IA', () {
    testWidgets('abierta de entrada; IA la cierra y la abre, y se recuerda', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byKey(const Key('reading-ai-row')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(const Key('reading-frame-ai')),
                matching: find.byType(IconButton),
              ),
            )
            .isSelected,
        isTrue,
      );

      await tapKey(tester, 'reading-frame-ai');
      expect(find.byKey(const Key('reading-ai-row')), findsNothing);
      expect(prefs.getBool(ReadingAppearanceNotifier.aiRowKey), isFalse);

      await tapKey(tester, 'reading-frame-ai');
      expect(find.byKey(const Key('reading-ai-row')), findsOneWidget);
      expect(prefs.getBool(ReadingAppearanceNotifier.aiRowKey), isTrue);
    });

    testWidgets('Podcast, fuera de lo procesado, queda apagado y dice por '
        'qué: tocarlo no hace nada', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      final podcast = find.byKey(const Key('reading-ai-podcast'));
      expect(
        find.descendant(
          of: podcast,
          matching: find.text(es.f47P1PodcastOnlyProcessed),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(podcast),
        matchesSemantics(
          label: '${es.f47P1Podcast}. ${es.f47P1PodcastOnlyProcessed}',
          hint: es.f47P1PodcastOnlyProcessedHint,
          isButton: true,
          hasEnabledState: true,
        ),
      );
      await tester.ensureVisible(podcast);
      await tester.pumpAndSettle();
      await tester.tap(podcast);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      semantics.dispose();
    });

    testWidgets('Podcast, sobre lo procesado, está prendido y dice qué hace '
        '(la hoja que abre se prueba en reading_podcast_test)', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, podcastScope: const CreationScope.document('d-1'));

      final podcast = find.byKey(const Key('reading-ai-podcast'));
      expect(
        find.descendant(of: podcast, matching: find.text(es.f47P1PodcastMade)),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(podcast),
        isSemantics(
          label: '${es.f47P1Podcast}. ${es.f47P1PodcastMade}',
          hint: es.f47P1PodcastHint,
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('Preguntar a la IA abre el chat con la pregunta sobre el '
        'documento a medio escribir, sin mandarla', (tester) async {
      await pump(tester);
      await tapKey(tester, 'reading-ai-ask');

      expect(find.text('El chat'), findsOneWidget);
      expect(
        container.read(chatHandoffProvider),
        ChatHandoff(
          question: es.f47P1AskAiDraft('Roma y la república'),
          send: false,
        ),
      );
    });
  });

  group('Apariencia', () {
    testWidgets('en el texto: las cinco letras, cada una con la suya; elegir '
        'una cambia el cuerpo y se guarda', (tester) async {
      await pump(tester);
      expect(_bodyStyle(tester).fontFamily, ReadingFont.lora.family);

      await tapKey(tester, 'reading-frame-appearance');
      for (final font in ReadingFont.values) {
        expect(find.byKey(Key('reading-font-${font.name}')), findsOneWidget);
      }
      expect(find.byKey(const Key('reading-zoom-in')), findsNothing);
      expect(find.byKey(const Key('reading-paper-dark')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('reading-font-atkinson')),
      );
      await tapKey(tester, 'reading-font-atkinson');
      expect(prefs.getString(ReadingAppearanceNotifier.fontKey), 'atkinson');
      expect(_bodyStyle(tester).fontFamily, ReadingFont.atkinson.family);
    });

    testWidgets('el tamaño, con el deslizador, de 80 % a 160 %', (
      tester,
    ) async {
      await pump(tester);
      final before = _bodyStyle(tester).fontSize!;
      await tapKey(tester, 'reading-frame-appearance');

      final slider = find.byKey(const Key('reading-size'));
      await tester.ensureVisible(slider);
      await tester.tapAt(
        tester.getRect(slider).centerRight - const Offset(4, 0),
      );
      await tester.pumpAndSettle();

      expect(prefs.getDouble(ReadingAppearanceNotifier.scaleKey), 1.6);
      expect(find.text(es.f47P1AppearanceSizeValue(160)), findsWidgets);
      expect(_bodyStyle(tester).fontSize, closeTo(before * 1.6, 0.01));
    });

    testWidgets('el color de lo que suena y el modo, con su muestra: sepia '
        'pinta el marco de papel cálido', (tester) async {
      await pump(tester);
      await tapKey(tester, 'reading-frame-appearance');

      final lilac = find.byKey(const Key('reading-highlight-lilac'));
      await tester.ensureVisible(lilac);
      await tester.tap(lilac);
      await tester.pumpAndSettle();
      expect(
        container.read(readingHighlightColorProvider),
        ReadingHighlight.lilac.color,
      );

      final sepia = find.byKey(const Key('reading-mode-sepia'));
      await tester.ensureVisible(sepia);
      await tester.tap(sepia);
      await tester.pumpAndSettle();
      expect(prefs.getString(ReadingAppearanceNotifier.modeKey), 'sepia');
      expect(
        tester
            .widget<Scaffold>(find.byKey(const Key('reading-frame')))
            .backgroundColor,
        AppThemeChoice.sepia.theme.colorScheme.surface,
      );
    });

    testWidgets('en una página: el zoom y el tono, no la letra', (
      tester,
    ) async {
      final zoom = _FakeZoom();
      await pump(tester, bodyKind: ReadingBodyKind.page, zoom: zoom);
      await tapKey(tester, 'reading-frame-appearance');

      expect(find.byKey(const Key('reading-font-lora')), findsNothing);
      await tapKey(tester, 'reading-zoom-in');
      await tapKey(tester, 'reading-zoom-in');
      await tapKey(tester, 'reading-zoom-out');
      expect(zoom.calls, ['in', 'in', 'out']);
      expect(find.text(es.f47P1AppearanceSizeValue(125)), findsOneWidget);
      await tapKey(tester, 'reading-zoom-fit');
      expect(zoom.calls.last, 'fit');

      await tapKey(tester, 'reading-paper-dark');
      expect(find.byKey(const Key('reading-page-tone-dark')), findsOneWidget);
      await tapKey(tester, 'reading-paper-original');
      expect(find.byType(ColorFiltered), findsNothing);
    });
  });

  group('⋮', () {
    testWidgets('arriba el título con ✎ y el tipo; los grupos separados; lo '
        'que se borra, en rojo; lo que no se puede, apagado', (tester) async {
      await pump(tester);
      await tapKey(tester, 'reading-frame-more');

      expect(
        tester.widget<Text>(find.byKey(const Key('reading-more-title'))).data,
        'Roma y la república',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('reading-more-kind'))).data,
        'Resumen · 2 oraciones',
      );
      expect(find.byKey(const Key('reading-more-summarize')), findsOneWidget);
      expect(find.byKey(const Key('reading-more-enqueue')), findsOneWidget);
      // Cuatro grupos —Resumir, la cola, los del lector y lo que se borra—,
      // separados.
      expect(
        find.descendant(
          of: find.byKey(const Key('reading-more-sheet')),
          matching: find.byType(Divider),
        ),
        findsNWidgets(3),
      );
      final scheme = Theme.of(
        tester.element(find.byKey(const Key('reading-more-sheet'))),
      ).colorScheme;
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('borrar')),
                matching: find.text('Mover a la papelera'),
              ),
            )
            .style!
            .color,
        scheme.error,
      );
      expect(
        tester.widget<ListTile>(find.byKey(const Key('apagada'))).enabled,
        isFalse,
      );

      await tapKey(tester, 'exportar');
      expect(_done, ['exportar']);
      expect(find.byKey(const Key('reading-more-sheet')), findsNothing);

      await tapKey(tester, 'reading-frame-more');
      await tapKey(tester, 'reading-more-rename');
      await tapKey(tester, 'reading-frame-more');
      await tapKey(tester, 'reading-more-summarize');
      expect(_done, ['exportar', 'renombrar', 'resumir']);
    });
  });

  group('Contenido', () {
    testWidgets('el índice que arma el cuerpo, las secciones de quien arma el '
        'marco y «Leer en voz alta»; cada uno se hace con la hoja cerrada', (
      tester,
    ) async {
      await pump(tester);
      await tapKey(tester, 'reading-frame-contents');

      expect(find.text(es.f47P1ContentsInDocument), findsOneWidget);
      expect(find.text('Capítulo 1'), findsOneWidget);
      expect(find.text('Fuentes'), findsOneWidget);
      await tapKey(tester, 'capitulo');
      expect(_done, ['capítulo']);
      expect(find.byKey(const Key('reading-contents-sheet')), findsNothing);

      await tapKey(tester, 'reading-frame-contents');
      // Un texto que no se estudia: solo «Todo».
      expect(find.byKey(const Key('reading-read-summary')), findsNothing);
      await tapKey(tester, 'reading-read-all');
      final state = container.read(readAloudControllerProvider);
      expect(state.document?.id, document.id);
      expect(state.scope, ReadScope.all);
    });
  });

  group('el lugar del reproductor', () {
    final floating = find.byKey(const Key('read-aloud-button'));
    final slot = find.byKey(const Key('reading-player-slot'));

    /// Lo que ocupa el reproductor anclado según el lector flotante.
    double resting() => container.read(readAloudPlayerExtentProvider).resting;

    testWidgets('sin nada sonando, «Escuchar»; sonando, el reproductor '
        'anclado de toda la app, abierto o achicado, con su lugar libre abajo '
        'para no tapar lo último que se lee. Nunca el botón flotante', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byKey(const Key('reading-listen')), findsOneWidget);
      expect(floating, findsNothing);

      await tapKey(tester, 'reading-listen');
      final player = find.byKey(const Key('read-aloud-player'));
      expect(player, findsOneWidget);
      expect(find.byKey(const Key('read-aloud-speed')), findsOneWidget);
      expect(find.byKey(const Key('read-aloud-voice')), findsOneWidget);
      expect(find.byKey(const Key('read-aloud-queue')), findsOneWidget);
      expect(floating, findsNothing);
      // Uno solo: el del lector flotante, no uno del marco.
      expect(find.descendant(of: slot, matching: player), findsNothing);
      expect(resting(), greaterThan(0));
      expect(tester.getSize(slot).height, resting());
      expect(
        tester.getTopLeft(player).dy,
        greaterThanOrEqualTo(tester.getTopLeft(slot).dy),
      );

      await tapKey(tester, 'read-aloud-minimize');
      final collapsed = find.byKey(const Key('read-aloud-collapsed'));
      expect(collapsed, findsOneWidget);
      expect(floating, findsNothing);
      expect(tester.getSize(slot).height, resting());
      expect(
        tester.getTopLeft(collapsed).dy,
        greaterThanOrEqualTo(tester.getTopLeft(slot).dy),
      );

      await tapKey(tester, 'read-aloud-expand');
      expect(player, findsOneWidget);
    });

    testWidgets('lo que se lee lleva la dirección de su pantalla, para '
        'volver a ella desde la tarjeta y «Seguir escuchando»', (tester) async {
      await pump(tester);
      expect(
        currentReadableOf(container.read(readableRegistryProvider))?.location,
        '/',
      );
      await tapKey(tester, 'reading-listen');
      expect(
        container.read(readAloudControllerProvider).document?.location,
        '/',
      );
    });

    testWidgets('la voz del reproductor abre la biblioteca de voces, como en '
        'el lector flotante (F47, paso 3)', (tester) async {
      await pump(tester);
      await tapKey(tester, 'reading-listen');
      await tapKey(tester, 'read-aloud-voice');

      expect(find.text(es.f47P3LibraryTitle), findsOneWidget);
    });

    testWidgets('al salir del marco sigue sonando, en el mismo reproductor', (
      tester,
    ) async {
      await pump(tester);
      await tapKey(tester, 'reading-listen');
      unawaited(router.push<void>('/chat'));
      await tester.pumpAndSettle();

      expect(
        container.read(readAloudControllerProvider).document?.id,
        'marco:1',
      );
      expect(find.byKey(const Key('read-aloud-player')), findsOneWidget);
      expect(slot, findsNothing);
    });

    testWidgets('⋮ «Añadir a la cola»: sin nada sonando, empieza; con otra '
        'cosa sonando, va a la cola; lo que ya suena no se repite', (
      tester,
    ) async {
      final enqueue = find.byKey(const Key('reading-more-enqueue'));
      bool enabled() => tester.widget<ListTile>(enqueue).enabled;
      Future<void> openMore() => tapKey(tester, 'reading-frame-more');

      await pump(tester);
      await openMore();
      expect(find.text(es.f47P2AddToQueue), findsOneWidget);
      expect(enabled(), isTrue);
      await tester.tap(enqueue);
      await tester.pumpAndSettle();
      expect(
        container.read(readAloudControllerProvider).document?.id,
        'marco:1',
      );

      await openMore();
      expect(enabled(), isFalse);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await controller().open(
        ReadableDocument(
          id: 'otro',
          title: 'Otro',
          segments: buildReadableSegments('Otra cosa.', sourceKey: 'otro'),
        ),
      );
      await tester.pumpAndSettle();
      await openMore();
      expect(enabled(), isTrue);
      await tester.tap(enqueue);
      await tester.pumpAndSettle();
      final state = container.read(readAloudControllerProvider);
      expect(state.document?.id, 'otro');
      expect(
        [for (final q in state.queue.upcoming) q.document.id],
        ['marco:1'],
      );
    });
  });

  group('cómo se ve', () {
    for (final theme in [
      AppThemeChoice.light,
      AppThemeChoice.dark,
      AppThemeChoice.sepia,
    ]) {
      testWidgets('en 360 dp con la letra al doble, en ${theme.name} y sin '
          'animaciones: la barra, la fila que se desplaza de costado, las '
          'hojas y el reproductor, sin desbordes', (tester) async {
        await pump(
          tester,
          size: const Size(360, 780),
          textScale: 2,
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        final strip = find.byKey(const Key('reading-ai-strip'));
        expect(
          tester.widget<SingleChildScrollView>(strip).scrollDirection,
          Axis.horizontal,
        );
        // Los cuatro botones no crecen con la letra: 48 para el dedo y su
        // aire a los costados.
        expect(
          tester.getSize(find.byKey(const Key('reading-frame-more'))),
          const Size(52, 48),
        );

        for (final sheet in [
          'reading-frame-appearance',
          'reading-frame-more',
          'reading-frame-contents',
        ]) {
          await tapKey(tester, sheet);
          expect(tester.takeException(), isNull, reason: sheet);
          // Con la letra al doble la hoja puede ocupar toda la pantalla:
          // se cierra como con «atrás».
          Navigator.of(tester.element(find.byType(BottomSheet))).pop();
          await tester.pumpAndSettle();
        }

        await tapKey(tester, 'reading-listen');
        expect(find.byKey(const Key('read-aloud-player')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('en una pantalla ancha el título va en la columna de '
        'lectura, centrado, y no a lo ancho', (tester) async {
      await pump(tester, size: const Size(1280, 900));
      final title = tester.getRect(
        find.byKey(const Key('reading-frame-title')),
      );
      expect(title.left, greaterThan((1280 - readingColumnWidth) / 2 - 1));
      expect(title.right, lessThan((1280 + readingColumnWidth) / 2 + 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('el desplazamiento de lo que se lee de corrido (F45, mejora 13)', () {
    /// Cuánto recorre una lista de [physics] con el mismo gesto: un arrastre
    /// corto con impulso.
    Future<double> fling(WidgetTester tester, ScrollPhysics? physics) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView.builder(
            controller: scroll,
            physics: physics,
            itemCount: 2000,
            itemBuilder: (_, index) =>
                SizedBox(height: 40, child: Text('$index')),
          ),
        ),
      );
      await tester.fling(find.byType(ListView), const Offset(0, -120), 1500);
      await tester.pumpAndSettle();
      return scroll.offset;
    }

    testWidgets('la causa: la física de pasar hojas lleva un mismo gesto '
        'mucho más lejos que la de la plataforma', (tester) async {
      final platform = await fling(tester, null);
      final pages = await fling(tester, const ReadingScrollPhysics());
      expect(platform, greaterThan(0));
      expect(pages, greaterThan(platform * 1.4));
    });
  });
}

/// La letra del texto del cuerpo de prueba: la de «Apariencia».
TextStyle _bodyStyle(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('cuerpo'))).style!;

/// Un cuerpo de prueba: ofrece su texto para escuchar, le pasa al marco un
/// capítulo y, si se lo dan, su zoom.
class _Body extends ConsumerStatefulWidget {
  const _Body({required this.document, this.zoom});

  final ReadableDocument document;
  final ReadingZoom? zoom;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final frame = ReadingFrameController.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || frame == null) return;
      frame
        ..outline = [
          ReadingOutlineEntry(
            key: const Key('capitulo'),
            label: 'Capítulo 1',
            onSelected: () => _done.add('capítulo'),
          ),
        ]
        ..zoom = widget.zoom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(readingAppearanceProvider);
    return ReadableRegion(
      document: widget.document,
      child: Text(
        'Uno dos tres.',
        key: const Key('cuerpo'),
        style: appearance.bodyStyle(Theme.of(context)),
      ),
    );
  }
}

/// Lo que hizo cada opción de prueba, en orden.
final _done = <String>[];

class _FakeZoom implements ReadingZoom {
  final calls = <String>[];

  @override
  final ValueNotifier<double> level = ValueNotifier(1);

  @override
  void zoomIn() {
    calls.add('in');
    level.value += 0.25;
  }

  @override
  void zoomOut() {
    calls.add('out');
    level.value -= 0.25;
  }

  @override
  void fit() {
    calls.add('fit');
    level.value = 1;
  }
}
