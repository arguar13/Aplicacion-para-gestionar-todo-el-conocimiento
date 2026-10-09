import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/my_cards_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_stats_screen.dart';
import 'package:sinapsis/features/habit/presentation/screens/badges_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/my_cards_screen_fixture.dart';

/// Las estadísticas de repaso de punta a punta (F31, ola 2, decisión 72): la
/// pantalla, los gráficos hechos a mano y el SQL de verdad.
void main() {
  final es = AppLocalizationsEs();
  late MyCardsFixture f;
  final now = MyCardsFixture.now; // 11/09/2026 10:00
  var logs = 0;

  setUpAll(() => initializeDateFormatting('es'));

  setUp(() async {
    f = await MyCardsFixture.create();
    logs = 0;
  });

  Future<void> answered(
    String card, {
    required String grade,
    CardPhase phase = CardPhase.review,
    int intervalBefore = 5,
    DateTime? at,
  }) => f.db
      .into(f.db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          id: 'log-${logs++}',
          flashcardId: card,
          reviewedAt: at ?? now.subtract(const Duration(hours: 1)),
          grade: grade,
          quality: grade == 'again' ? 0 : 4,
          intervalBefore: intervalBefore,
          intervalAfter: 10,
          easeBefore: 2.5,
          easeAfter: 2.5,
          deviceId: 'dispositivo',
          phaseBefore: Value(phase),
        ),
      );

  /// Monta la pantalla en una ventana tan alta que entra toda: la lista
  /// construye de a poco y con medidas estimadas, y `ensureVisible` no
  /// alcanza para llegar a lo de abajo.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(f.harness.wrap(const ReviewStatsScreen()));
    await tester.pumpAndSettle();
  }

  group('sin nada todavía', () {
    testWidgets('cada sección dice que no hay datos, sin romperse', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text(es.cardStatsTitle), findsOneWidget);
      expect(find.text('Sin racha todavía'), findsOneWidget);
      expect(find.text(es.cardStatsForecastEmpty), findsOneWidget);
      expect(find.text(es.cardStatsDistributionEmpty), findsOneWidget);
      expect(find.text(es.cardStatsButtonsEmpty), findsOneWidget);
      // Lo que ya había (F17) sigue ahí, con sus propios vacíos.
      expect(find.text(es.reviewHistoryRetentionSectionTitle), findsOneWidget);
      expect(find.text(es.reviewHistoryRetentionEmpty), findsOneWidget);
      expect(find.text(es.reviewHistoryHardestCardsEmpty), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('con tarjetas de todas las etapas', () {
    setUp(() async {
      // Hoy son las 10:00; el día de estudio termina a las 4:00 de mañana.
      await f.card('atrasada', dueAt: DateTime(2026, 9, 9, 12), interval: 5);
      await f.card('hoy-1', dueAt: DateTime(2026, 9, 11, 22), interval: 5);
      await f.card(
        'aprende',
        phase: CardPhase.learning,
        dueAt: now.add(const Duration(minutes: 10)),
      );
      await f.card('manana', dueAt: DateTime(2026, 9, 12, 12), interval: 30);
      await f.card('en-5', dueAt: DateTime(2026, 9, 16, 12), interval: 40);
      await f.card('nueva', phase: CardPhase.newCard);
      await f.card('pausada', suspended: true);
    });

    testWidgets('el pronóstico: hoy, lo atrasado y el total', (tester) async {
      await pump(tester);

      expect(find.text('Hoy vencen 3 · 1 atrasada'), findsOneWidget);
      expect(find.text('5 tarjetas en los próximos 30 días'), findsOneWidget);
      expect(find.text('Máximo en un día: 3'), findsOneWidget);
    });

    testWidgets('las columnas son altas según la cuenta, desde cero', (
      tester,
    ) async {
      await pump(tester);

      double height(int day) => tester
          .getSize(find.byKey(Key('card-stats-forecast-bar-$day')))
          .height;
      final chart = tester.getSize(
        find.byKey(const Key('card-stats-forecast-chart')),
      );

      expect(find.byType(DecoratedBox), findsWidgets);
      // El pico (hoy, 3) ocupa casi todo el alto; los de 1 son un tercio.
      expect(height(0), closeTo(chart.height - 1.5, 2));
      expect(height(1), closeTo(height(0) / 3, 1));
      expect(height(5), closeTo(height(0) / 3, 1));
      // Un día sin nada es una marca casi plana, no un hueco.
      expect(height(2), lessThan(4));
      expect(height(2), greaterThan(0));
    });

    testWidgets('«Ver los números» lista los treinta días', (tester) async {
      await pump(tester);
      await tester.tap(find.text(es.cardStatsForecastTable));
      await tester.pumpAndSettle();

      // La cabecera del desplegable es otro ListTile: los días son los densos.
      expect(
        find.descendant(
          of: find.byKey(const Key('card-stats-forecast-table')),
          matching: find.byWidgetPredicate(
            (widget) => widget is ListTile && (widget.dense ?? false),
          ),
        ),
        findsNWidgets(30),
      );
    });

    testWidgets('el reparto por etapa suma todas las tarjetas', (tester) async {
      await pump(tester);

      expect(find.text('7 tarjetas en total'), findsOneWidget);
      Finder row(String key) =>
          find.byKey(Key('card-stats-distribution-row-$key'));
      for (final (key, count, percent) in [
        ('new', 1, 14),
        ('learning', 1, 14),
        ('young', 2, 29),
        ('mature', 2, 29),
        ('suspended', 1, 14),
      ]) {
        expect(
          find.descendant(of: row(key), matching: find.text('$count')),
          findsOneWidget,
          reason: key,
        );
        expect(
          find.descendant(of: row(key), matching: find.text('$percent %')),
          findsOneWidget,
          reason: key,
        );
      }
      // Los tramos de la barra: solo los que tienen algo.
      expect(
        find.byKey(const Key('card-stats-distribution-segment-young')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card-stats-distribution-segment-mature')),
        findsOneWidget,
      );
    });

    testWidgets('sin maduras, ese tramo no se dibuja', (tester) async {
      await f.db.customStatement(
        'UPDATE flashcards SET interval_days = 5 WHERE interval_days > 20',
      );
      await pump(tester);

      expect(
        find.byKey(const Key('card-stats-distribution-segment-mature')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('card-stats-distribution-row-mature')),
          matching: find.text('0 %'),
        ),
        findsOneWidget,
      );
    });
  });

  group('los botones apretados', () {
    setUp(() async {
      await f.card('c');
      await answered('c', grade: 'again', phase: CardPhase.newCard);
      await answered('c', grade: 'good', phase: CardPhase.newCard);
      await answered('c', grade: 'good', phase: CardPhase.newCard);
      await answered('c', grade: 'good', phase: CardPhase.newCard);
      await answered('c', grade: 'hard', phase: CardPhase.learning);
      await answered('c', grade: 'good');
      await answered('c', grade: 'again', intervalBefore: 60);
      // Hace dos meses: fuera de los 30 días.
      await answered(
        'c',
        grade: 'easy',
        intervalBefore: 60,
        at: DateTime(2026, 7),
      );
    });

    testWidgets('por etapa y en total, con el acierto, para 30 días', (
      tester,
    ) async {
      await pump(tester);

      String accuracy(String stage) => tester
          .widget<Text>(find.byKey(Key('card-stats-buttons-accuracy-$stage')))
          .data!;

      expect(accuracy('overall'), '71 % de acierto · 7 respuestas');
      expect(accuracy('newCard'), '75 % de acierto · 4 respuestas');
      expect(accuracy('learning'), '100 % de acierto · 1 respuesta');
      expect(accuracy('young'), '100 % de acierto · 1 respuesta');
      expect(accuracy('mature'), '0 % de acierto · 1 respuesta');
      // Cada fila cuenta sus botones: «De nuevo» es 2 en total, 1 en nuevas y
      // 1 en maduras.
      expect(find.text('De nuevo 2'), findsOneWidget);
      expect(find.text('De nuevo 1'), findsNWidgets(2));
    });

    testWidgets('cambiar el período cambia la cuenta', (tester) async {
      await pump(tester);

      await tester.tap(find.text(es.cardStatsPeriodAll));
      await tester.pumpAndSettle();

      final text = tester
          .widget<Text>(
            find.byKey(const Key('card-stats-buttons-accuracy-overall')),
          )
          .data!;
      expect(text, '75 % de acierto · 8 respuestas');
    });

    testWidgets('una etapa sin respuestas dice «Sin respuestas»', (
      tester,
    ) async {
      await f.db.customStatement('DELETE FROM review_log');
      await answered('c', grade: 'good', phase: CardPhase.newCard);
      await pump(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('card-stats-buttons-accuracy-mature')),
            )
            .data,
        es.cardStatsButtonsNoData,
      );
      expect(
        find.byKey(const Key('card-stats-buttons-segment-mature-good')),
        findsNothing,
      );
    });
  });

  group('el aspecto y la accesibilidad', () {
    setUp(() async {
      await f.card('a', dueAt: DateTime(2026, 9, 11, 22));
      await f.card('b', dueAt: DateTime(2026, 9, 14, 12), interval: 30);
      await answered('a', grade: 'good');
      await answered('b', grade: 'again');
    });

    testWidgets('el gráfico tiene una lectura para quien no lo ve', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      expect(
        find.bySemanticsLabel(
          RegExp('Gráfico de columnas con las tarjetas que vencen'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Maduras (21 días o más): sin respuestas'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('cada columna tiene su ayuda con la fecha y la cuenta', (
      tester,
    ) async {
      await pump(tester);

      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .whereType<String>()
          .toList();
      expect(
        tooltips.where((m) => m.contains(': 1 tarjeta')).length,
        2,
        reason: 'un día con 1 en hoy y otro tres días después',
      );
      expect(tooltips.where((m) => m.endsWith(': ninguna')).length, 28);
    });

    for (final dark in [false, true]) {
      testWidgets(
        'angosto y con letra grande, en modo ${dark ? 'oscuro' : 'claro'}: '
        'no se desborda',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: f.harness.container,
              child: MaterialApp(
                theme: dark ? ThemeData.dark() : ThemeData.light(),
                locale: const Locale('es'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.6)),
                  child: child!,
                ),
                home: const ReviewStatsScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          await tester.dragUntilVisible(
            find.text(es.cardStatsButtonsOverall),
            find.byType(ListView).first,
            const Offset(0, -200),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('en la app', () {
    testWidgets('las rutas existen y se llega a ellas', (tester) async {
      await f.card('a', itemId: 'grecia', front: 'Algo de Grecia');
      await f.card('b', front: 'Algo de Roma');
      await tester.pumpWidget(f.harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      f.harness.goTo(kRouteReviewStats);
      await tester.pumpAndSettle();
      expect(find.byType(ReviewStatsScreen), findsOneWidget);

      f.harness.goTo(kRouteCards);
      await tester.pumpAndSettle();
      expect(find.byType(MyCardsScreen), findsOneWidget);
      expect(find.text('2 tarjetas'), findsOneWidget);

      f.harness.goTo('$kRouteCards?item=grecia');
      await tester.pumpAndSettle();
      expect(find.text('Algo de Grecia'), findsOneWidget);
      expect(find.text('Algo de Roma'), findsNothing);
    });

    testWidgets('las insignias se abren desde las estadísticas', (
      tester,
    ) async {
      await tester.pumpWidget(f.harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      f.harness.goTo(kRouteReviewStats);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('card-stats-badges')));
      await tester.pumpAndSettle();

      expect(find.byType(BadgesScreen), findsOneWidget);
    });
  });
}
