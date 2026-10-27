import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_history.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_conversations_panel.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_top_bar.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebooks_screen.dart';
import 'package:sinapsis/features/settings/presentation/providers/owner_name.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// El panel de conversaciones (F42): lo que hace más allá de abrir, empezar
/// y borrar —que prueba `chat_screen_test.dart`—: los días, las fijadas, el
/// buscador, renombrar, el pie con el nombre, los atajos, y que se vea bien
/// con «sin animaciones», con letra grande y en los nueve temas.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  /// La hora fija de la harness: viernes 11 de septiembre de 2026, 10:00.
  final now = DateTime(2026, 9, 11, 10);

  Finder inPanel(Finder matching) => find.descendant(
    of: find.byKey(const Key('chat-panel')),
    matching: matching,
  );

  Future<void> pumpChat(WidgetTester tester) async {
    harness = await LibraryHarness.create();
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byTooltip(es.chatPanelOpenTooltip));
    await tester.pumpAndSettle();
  }

  /// Una conversación guardada de [mode] cuyo último mensaje fue [at], con
  /// [title] como primer mensaje —y por lo tanto como título—.
  Future<String> seed(
    String title,
    DateTime at, {
    ChatConversationMode mode = ChatConversationMode.vault,
  }) async {
    final repo = harness.container.read(chatConversationRepositoryProvider);
    final conversation = await repo.createConversation(mode);
    await repo.addMessage(
      PersistedChatMessage(
        id: 'm-$title',
        conversationId: conversation.id,
        isUser: true,
        text: title,
        createdAt: at,
      ),
    );
    return conversation.id;
  }

  Future<void> openMenuOf(WidgetTester tester, String title) async {
    await tester.tap(find.byTooltip(es.chatPanelRowMenu(title)));
    await tester.pumpAndSettle();
  }

  testWidgets('agrupa por día —Hoy, Ayer y la fecha— de la más nueva a la '
      'más vieja, y fijar sube una a «Fijadas»', (tester) async {
    // Alto, para que todas las filas se dibujen a la vez.
    tester.view
      ..physicalSize = const Size(1200, 3200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await pumpChat(tester);
    await seed('de hoy', now.subtract(const Duration(hours: 1)));
    await seed('de anoche', DateTime(2026, 9, 10, 23, 50));
    await seed('del domingo', DateTime(2026, 9, 6, 18));
    await seed('del año pasado', DateTime(2025, 12, 31, 9));
    await openPanel(tester);

    final sunday = DateFormat.MMMMEEEEd('es').format(DateTime(2026, 9, 6));
    final lastYear = DateFormat.yMMMMEEEEd('es').format(DateTime(2025, 12, 31));
    expect(sunday, contains('domingo'));
    final order = [
      es.chatPanelToday,
      'de hoy',
      es.chatPanelYesterday,
      'de anoche',
      sunday,
      'del domingo',
      lastYear,
      'del año pasado',
    ];
    final tops = [
      for (final t in order) tester.getTopLeft(inPanel(find.text(t))).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));

    await openMenuOf(tester, 'del domingo');
    await tester.tap(find.text(es.chatPanelPin));
    await tester.pumpAndSettle();

    expect(inPanel(find.text(es.chatPanelPinned)), findsOneWidget);
    expect(
      tester.getTopLeft(inPanel(find.text('del domingo'))).dy,
      lessThan(tester.getTopLeft(inPanel(find.text(es.chatPanelToday))).dy),
    );
    expect(inPanel(find.byIcon(Icons.push_pin)), findsOneWidget);
    // Su día quedó sin conversaciones: el encabezado se va.
    expect(inPanel(find.text(sunday)), findsNothing);
  });

  testWidgets('lo fijado se recuerda; desfijar lo devuelve a su día', (
    tester,
  ) async {
    await pumpChat(tester);
    final id = await seed('para fijar', now);
    await openPanel(tester);

    await openMenuOf(tester, 'para fijar');
    await tester.tap(find.text(es.chatPanelPin));
    await tester.pumpAndSettle();
    final prefs = harness.container.read(sharedPreferencesProvider);
    expect(prefs.getStringList(ChatPinsNotifier.prefsKey), [id]);

    await openMenuOf(tester, 'para fijar');
    await tester.tap(find.text(es.chatPanelUnpin));
    await tester.pumpAndSettle();

    expect(prefs.getStringList(ChatPinsNotifier.prefsKey), isEmpty);
    expect(inPanel(find.text(es.chatPanelPinned)), findsNothing);
    expect(inPanel(find.text(es.chatPanelToday)), findsOneWidget);
  });

  testWidgets('borrar una fijada también la desfija', (tester) async {
    await pumpChat(tester);
    final id = await seed('fijada y borrada', now);
    await harness.container.read(chatPinsProvider.notifier).pin(id);
    await openPanel(tester);

    await openMenuOf(tester, 'fijada y borrada');
    await tester.tap(find.text(es.chatHistoryDeleteTooltip));
    await tester.pumpAndSettle();
    await tester.pump(kChatDeleteUndoWindow);
    await tester.pumpAndSettle();

    expect(harness.container.read(chatPinsProvider), isEmpty);
  });

  testWidgets('el buscador filtra por título sin mirar acentos, dice si no '
      'hay nada y se vacía con la cruz', (tester) async {
    await pumpChat(tester);
    await seed('La Revolución francesa', now);
    await seed('Recetas de cocina', now);
    await openPanel(tester);

    await tester.enterText(
      find.byKey(const Key('chat-panel-search')),
      'revolucion',
    );
    await tester.pumpAndSettle();
    expect(inPanel(find.text('La Revolución francesa')), findsOneWidget);
    expect(inPanel(find.text('Recetas de cocina')), findsNothing);

    await tester.enterText(find.byKey(const Key('chat-panel-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(inPanel(find.text(es.chatPanelNoMatches)), findsOneWidget);

    await tester.tap(find.byTooltip(es.chatPanelSearchClear));
    await tester.pumpAndSettle();
    expect(inPanel(find.text('Recetas de cocina')), findsOneWidget);
  });

  testWidgets('renombrar le pone el nombre a mano; vacío no lo cambia', (
    tester,
  ) async {
    await pumpChat(tester);
    await seed('un título automático', now);
    await openPanel(tester);

    await openMenuOf(tester, 'un título automático');
    await tester.tap(find.text(es.commonRename));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat-panel-rename-field')),
      '  Mi   charla  ',
    );
    await tester.tap(find.byKey(const Key('chat-panel-rename-save')));
    await tester.pumpAndSettle();

    expect(inPanel(find.text('Mi charla')), findsOneWidget);
    expect(inPanel(find.text('un título automático')), findsNothing);

    await openMenuOf(tester, 'Mi charla');
    await tester.tap(find.text(es.commonRename));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat-panel-rename-field')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('chat-panel-rename-save')));
    await tester.pumpAndSettle();

    expect(inPanel(find.text('Mi charla')), findsOneWidget);
  });

  testWidgets('cada fila dice su modo y, si tiene, su cuaderno', (
    tester,
  ) async {
    await pumpChat(tester);
    await seed('una libre', now, mode: ChatConversationMode.free);
    await openPanel(tester);

    expect(inPanel(find.text('${es.chatModeFree} · 10:00')), findsOneWidget);
  });

  group('el pie', () {
    testWidgets('sin nombre, pregunta cómo llamarte; ponerlo lo muestra y lo '
        'guarda', (tester) async {
      await pumpChat(tester);
      await openPanel(tester);

      expect(inPanel(find.text(es.chatPanelOwnerUnnamed)), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat-panel-owner')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('owner-name-field')), 'Ana');
      await tester.tap(find.byKey(const Key('owner-name-save')));
      await tester.pumpAndSettle();

      expect(inPanel(find.text('Ana')), findsOneWidget);
      expect(inPanel(find.text('A')), findsOneWidget);
      expect(harness.container.read(ownerNameProvider), 'Ana');
    });
  });

  testWidgets('los atajos llevan a la Biblioteca y a los Cuadernos, y el '
      'panel se cierra', (tester) async {
    harness = await LibraryHarness.create();
    await tester.pumpWidget(harness.wrapWithAppRouter());
    harness.goTo(RoutePaths.chat);
    await tester.pumpAndSettle();

    await openPanel(tester);
    await tester.tap(find.byKey(const Key('chat-panel-notebooks')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-panel')), findsNothing);
    expect(find.byType(NotebooksScreen), findsOneWidget);

    harness.goTo(RoutePaths.chat);
    await tester.pumpAndSettle();
    await openPanel(tester);
    await tester.tap(find.byKey(const Key('chat-panel-library')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-panel')), findsNothing);
    expect(
      harness.container.read(goRouterProvider).state.matchedLocation,
      RoutePaths.library,
    );
  });

  testWidgets('deslizarlo hacia la izquierda lo cierra', (tester) async {
    await pumpChat(tester);
    await openPanel(tester);

    await tester.fling(
      find.byKey(const Key('chat-panel')),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-panel')), findsNothing);
  });

  testWidgets('se abre deslizándose; con «sin animaciones», de una', (
    tester,
  ) async {
    await pumpChat(tester);

    await tester.tap(find.byTooltip(es.chatPanelOpenTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // A mitad de camino: todavía entrando desde la izquierda.
    expect(
      tester.getTopLeft(find.byKey(const Key('chat-panel'))).dx,
      lessThan(0),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('chat-panel'))).dx, 0);
    Navigator.of(tester.element(find.byKey(const Key('chat-panel')))).pop();
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      harness.wrap(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const ChatScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(es.chatPanelOpenTooltip));
    await tester.pump();
    await tester.pump();

    expect(tester.getTopLeft(find.byKey(const Key('chat-panel'))).dx, 0);
  });

  testWidgets('con letra grande, ni la barra ni el panel se desbordan', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    harness = await LibraryHarness.create();
    await seed('una conversación con un título bastante largo', now);
    // Solo la barra y el panel: el cuerpo del chat (el vacío y el campo) es
    // del paso 2 de F42.
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          appBar: ChatTopBar(
            textScaler: const TextScaler.linear(2),
            onOpenPanel: () {},
            onNewConversation: () {},
            onOpenRoute: (_) {},
          ),
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showChatConversationsPanel(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // La barra creció con la letra, en vez de cortar la píldora.
    expect(
      tester.getSize(find.byType(AppBar)).height,
      chatTopBarHeight(const TextScaler.linear(2)),
    );
    expect(
      chatTopBarHeight(const TextScaler.linear(2)),
      greaterThan(chatTopBarHeight(TextScaler.noScaling)),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      inPanel(find.text('una conversación con un título bastante largo')),
      findsOneWidget,
    );
  });

  group('los nueve temas', () {
    double luminance(Color c) => c.computeLuminance();
    double contrast(Color a, Color b) {
      final (hi, lo) = luminance(a) > luminance(b)
          ? (luminance(a), luminance(b))
          : (luminance(b), luminance(a));
      return (hi + 0.05) / (lo + 0.05);
    }

    final themes = {
      for (final choice in AppThemeChoice.values)
        for (final theme in choice.previews) theme,
    };

    test('lo que escriben la barra y el panel se lee (AA) en cada tema', () {
      // «El del sistema» es el claro y el oscuro: nueve temas, ocho caras.
      expect(themes, hasLength(AppThemeChoice.values.length - 1));
      for (final theme in themes) {
        final s = theme.colorScheme;
        final bar = theme.appBarTheme.backgroundColor ?? s.surface;
        for (final (fore, back, what) in [
          (s.onSurface, s.surfaceContainerHigh, 'la píldora del modelo'),
          (s.onSurfaceVariant, bar, 'la línea debajo del modelo'),
          (s.onSurface, s.surfaceContainerLow, 'el título de una fila'),
          (s.onSurfaceVariant, s.surfaceContainerLow, 'el día y la hora'),
          (s.onSecondaryContainer, s.secondaryContainer, 'la fila abierta'),
          (s.onSurfaceVariant, s.surfaceContainerHighest, 'el buscador'),
        ]) {
          expect(
            contrast(fore, back),
            greaterThanOrEqualTo(4.5),
            reason: '$what en ${theme.brightness} ${s.primary}',
          );
        }
      }
    });

    testWidgets('la barra y el panel se dibujan en cada tema', (tester) async {
      harness = await LibraryHarness.create();
      await seed('una conversación', now);
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
        await openPanel(tester);
        expect(tester.takeException(), isNull);
        expect(inPanel(find.text('una conversación')), findsOneWidget);
        Navigator.of(tester.element(find.byKey(const Key('chat-panel')))).pop();
        await tester.pumpAndSettle();
      }
    });
  });

  testWidgets('cada botón tiene nombre para el lector de pantalla', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpChat(tester);
    final id = await seed('algo', now);

    expect(
      tester.getSemantics(find.byKey(const Key('chat-open-panel'))),
      isSemantics(tooltip: es.chatPanelOpenTooltip, isButton: true),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('chat-new-conversation'))),
      isSemantics(tooltip: es.chatNewConversationTooltip),
    );
    expect(
      find.bySemanticsLabel(
        es.chatModelPillSemantics(
          es.chatModelOptionGemma4Title,
          es.chatModelPillNotReady,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        es.chatScopeLineSemantics(
          '${es.chatScopeLineVault} · ${es.chatNotebookScopeAll}',
        ),
      ),
      findsOneWidget,
    );

    await openPanel(tester);
    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byKey(Key('chat-panel-menu-$id')),
          matching: find.byIcon(Icons.more_vert),
        ),
      ),
      isSemantics(tooltip: es.chatPanelRowMenu('algo'), isButton: true),
    );
    expect(find.bySemanticsLabel(es.chatPanelOwnerUnnamed), findsOneWidget);
    expect(find.bySemanticsLabel(es.chatPanelLabel), findsOneWidget);
    handle.dispose();
  });
}
