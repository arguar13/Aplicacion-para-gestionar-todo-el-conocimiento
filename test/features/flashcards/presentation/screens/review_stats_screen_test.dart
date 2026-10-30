import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_stats_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../creations/presentation/repasar_harness.dart';

/// Estadísticas e Historial de punta a punta (F43, M16 y M17): una pantalla
/// con dos pestañas que sigue al selector de Repasar, con el SQL de verdad.
/// Hoy es el viernes 11 de septiembre de 2026 a las 10:00.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;
  final now = DateTime(2026, 9, 11, 10);
  var logs = 0;

  setUpAll(() => initializeDateFormatting('es'));

  setUp(() async {
    harness = await RepasarHarness.create();
    logs = 0;
  });

  AppDatabase db() => harness.library.database;

  Future<void> card(
    String id, {
    String item = 'p-roma',
    CardPhase phase = CardPhase.review,
    int interval = 15,
    DateTime? dueAt,
    DateTime? createdAt,
    String? front,
  }) {
    final (reps, days, step) = switch (phase) {
      CardPhase.newCard => (0, 0, null),
      CardPhase.learning => (0, 0, 0),
      CardPhase.relearning => (0, 1, 0),
      CardPhase.review => (3, interval, null),
    };
    return db()
        .into(db().flashcards)
        .insert(
          FlashcardsCompanion.insert(
            id: id,
            itemId: item,
            front: front ?? 'Pregunta $id',
            back: 'Respuesta $id',
            dueAt: dueAt ?? now,
            createdAt: createdAt ?? DateTime(2026, 9, 1, 12),
            repetitions: Value(reps),
            intervalDays: Value(days),
            learningStep: Value(step),
            lastReviewedAt: phase == CardPhase.newCard
                ? const Value(null)
                : Value(DateTime(2026, 9, 2)),
          ),
        );
  }

  Future<void> answer(
    String card,
    DateTime at, {
    String grade = 'good',
    CardPhase phase = CardPhase.review,
    int before = 5,
  }) => db()
      .into(db().reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          id: 'log-${logs++}',
          flashcardId: card,
          reviewedAt: at,
          grade: grade,
          quality: grade == 'again' ? 0 : 4,
          intervalBefore: before,
          intervalAfter: 10,
          easeBefore: 2.5,
          easeAfter: 2.5,
          deviceId: 'dispositivo',
          phaseBefore: Value(phase),
        ),
      );

  /// Un poco de todo sobre «Roma procesada»: tarjetas en cada etapa y
  /// respuestas de hoy y de días anteriores.
  Future<void> seed() async {
    await harness.processed('p-roma', 'Roma procesada');
    await card('atrasada', dueAt: DateTime(2026, 9, 9, 12), interval: 5);
    await card('hoy', dueAt: DateTime(2026, 9, 11, 22), interval: 5);
    await card('manana', dueAt: DateTime(2026, 9, 12, 12), interval: 30);
    await card('en-20', dueAt: DateTime(2026, 10, 1, 12), interval: 40);
    await card('nueva', phase: CardPhase.newCard);
    await answer('hoy', DateTime(2026, 9, 11, 9));
    await answer('hoy', DateTime(2026, 9, 11, 9, 5), grade: 'again');
    await answer('manana', DateTime(2026, 9, 11, 9, 30), before: 30);
    await answer(
      'nueva',
      DateTime(2026, 9, 11, 9, 40),
      phase: CardPhase.newCard,
    );
    for (var d = 1; d <= 3; d++) {
      await answer('atrasada', DateTime(2026, 9, 11 - d, 20), grade: 'again');
    }
  }

  Future<void> open(
    WidgetTester tester, {
    String location = kRouteReviewStats,
    Size size = const Size(800, 6000),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) => harness.openRepasar(
    tester,
    location: location,
    size: size,
    theme: theme,
    textScale: textScale,
  );

  String textOf(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).data!;

  String figure(WidgetTester tester, String key) => textOf(
    tester,
    find
        .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
        .at(1),
  );

  group('una pantalla, dos pestañas', () {
    testWidgets('las dos direcciones de antes abren cada una su pestaña', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(ReviewStatsScreen), findsOneWidget);
      expect(find.byKey(const Key('stats-today')), findsOneWidget);
      expect(find.byKey(const Key('review-history-retention')), findsNothing);

      harness.library.goTo(RoutePaths.reviewHistory);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-history-retention')), findsOneWidget);
      expect(find.byKey(const Key('stats-today')), findsNothing);

      // Y se pasa de una a otra con las pestañas.
      await tester.tap(find.byKey(const Key('review-stats-tab-stats')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stats-today')), findsOneWidget);
    });

    testWidgets('en la barra de Repasar, 📊 y 📈 abren su pestaña', (
      tester,
    ) async {
      await open(tester, location: '/review', size: const Size(800, 1600));

      await tester.tap(find.byKey(const Key('review-open-stats')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stats-today')), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-open-history')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-history-retention')), findsOneWidget);
    });
  });

  group('sin nada todavía', () {
    testWidgets('cada sección dice que no hay datos, sin romperse', (
      tester,
    ) async {
      await open(tester);
      expect(figure(tester, 'stats-today-reviewed'), '0');
      expect(figure(tester, 'stats-today-accuracy'), '—');
      expect(find.text(es.f43S20ForecastEmpty), findsOneWidget);
      expect(find.text(es.f43S20DailyEmpty), findsOneWidget);
      expect(find.text(es.cardStatsDistributionEmpty), findsOneWidget);
      expect(find.text(es.cardStatsButtonsEmpty), findsOneWidget);
      expect(find.text(es.f43S20NoReviewCards), findsNWidgets(2));
      expect(find.text(es.f43S20NoAnswers), findsOneWidget);
      expect(find.text(es.f43S20AddedEmpty), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-stats-tab-history')));
      await tester.pumpAndSettle();
      expect(find.text(es.reviewHistoryRetentionEmpty), findsOneWidget);
      expect(find.text(es.f43S20HardestEmpty), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('con datos', () {
    setUp(seed);

    testWidgets('hoy: repasadas, acierto, nuevas y racha', (tester) async {
      await open(tester);
      expect(figure(tester, 'stats-today-reviewed'), '3');
      expect(figure(tester, 'stats-today-accuracy'), '75 %');
      expect(figure(tester, 'stats-today-new'), '1');
      expect(
        find.descendant(
          of: find.byKey(const Key('stats-today-accuracy')),
          matching: find.text(es.f43S20TodayCorrect(3, 4)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('lo que viene: hoy, lo atrasado, el promedio y su tramo', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Hoy vencen 2 · 1 atrasada'), findsOneWidget);
      expect(
        textOf(tester, find.byKey(const Key('stats-forecast-average'))),
        es.f43S20ForecastAverage('0,1', 4),
      );

      await tester.tap(find.byKey(const Key('stats-forecast-range-days7')));
      await tester.pumpAndSettle();
      expect(
        textOf(tester, find.byKey(const Key('stats-forecast-average'))),
        es.f43S20ForecastAverage('0,4', 3),
      );
      await tester.tap(find.byKey(const Key('stats-forecast-range-months3')));
      await tester.pumpAndSettle();
      expect(
        textOf(tester, find.byKey(const Key('stats-forecast-average'))),
        es.f43S20ForecastAverage('0', 4),
      );
    });

    testWidgets('tocar una barra dice su número exacto', (tester) async {
      await open(tester);
      final chart = find.byKey(const Key('card-stats-forecast-chart'));
      final callout = find.descendant(
        of: chart,
        matching: find.byKey(const Key('stats-chart-callout')),
      );
      expect(textOf(tester, callout), es.f43S20ChartTapHint);

      // La primera columna, la de hoy, está pegada al eje de la izquierda.
      final plot = find.descendant(
        of: chart,
        matching: find.byType(CustomPaint),
      );
      final box = tester.getRect(plot.first);
      await tester.tapAt(Offset(box.right - 2, box.center.dy));
      await tester.pumpAndSettle();
      expect(textOf(tester, callout), contains(': ninguna'));
      await tester.tapAt(Offset(box.left + 16, box.center.dy));
      await tester.pumpAndSettle();
      expect(textOf(tester, callout), endsWith('2 tarjetas'));
    });

    testWidgets('el lector de pantalla lee el resumen y los valores', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(tester);
      await tester.tap(find.byKey(const Key('stats-forecast-range-days7')));
      await tester.pumpAndSettle();
      final label = tester
          .getSemantics(find.byKey(const Key('card-stats-forecast-chart')))
          .label;
      expect(label, startsWith(es.f43S20ForecastChartLabel(7, 3, 2)));
      expect(label, contains('2 tarjetas'));
      expect(label, contains('ninguna'));
      semantics.dispose();
    });

    testWidgets('«Ver los números» abre la tabla', (tester) async {
      await open(tester);
      final section = find.byKey(const Key('stats-daily'));
      await tester.tap(
        find.descendant(
          of: section,
          matching: find.text(es.cardStatsForecastTable),
        ),
      );
      await tester.pumpAndSettle();
      // Hoy hubo cuatro respuestas.
      expect(
        find.descendant(of: section, matching: find.text('4')),
        findsWidgets,
      );
    });

    testWidgets('las secciones en su orden, cada una con sus números', (
      tester,
    ) async {
      await open(tester);
      final order = [
        'stats-today',
        'stats-forecast',
        'stats-daily',
        'stats-distribution',
        'stats-buttons',
        'stats-intervals',
        'stats-ease',
        'stats-hours',
        'stats-added',
      ];
      final tops = [
        for (final key in order) tester.getTopLeft(find.byKey(Key(key))).dy,
      ];
      expect([...tops]..sort(), tops);

      expect(
        textOf(tester, find.byKey(const Key('stats-daily-summary'))),
        es.f43S20DailySummary(7, '0,2'),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('stats-distribution-donut')),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card-stats-buttons-row-overall')),
        findsOneWidget,
      );
      expect(
        textOf(tester, find.byKey(const Key('stats-ease-average'))),
        es.f43S20EaseAverage(250),
      );
      expect(
        textOf(tester, find.byKey(const Key('stats-best-hour'))),
        es.f43S20BestHourNone(10),
      );
      expect(
        textOf(tester, find.byKey(const Key('stats-added-summary'))),
        es.f43S20AddedSummary(5, '0,2'),
      );
    });

    testWidgets('el historial: la meta del 90 %, la retención real y la '
        'constancia', (tester) async {
      await open(tester, location: RoutePaths.reviewHistory);
      expect(
        find.byKey(const Key('review-history-retention-chart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('true-retention-today')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('review-history-studied')),
          matching: find.text(es.f43S20StudiedOf(4, 90, 4)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('review-history-range-days30')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('review-history-studied')),
          matching: find.text(es.f43S20StudiedOf(4, 30, 13)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('una difícil abre su hoja, y «Repasar estas» practica solo '
        'esas', (tester) async {
      await open(tester, location: RoutePaths.reviewHistory);
      final tile = find.byKey(const Key('hardest-card-atrasada'));
      expect(
        find.descendant(
          of: tile,
          matching: find.text(
            '${es.f43S20HardestAgain(3, 3)} · ${es.f43S20HardestLapses(3)}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('hardest-card-hoy')), findsNothing);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('difficult-card-sheet')), findsOneWidget);
      expect(find.text('Respuesta atrasada'), findsOneWidget);
      expect(find.byKey(const Key('difficult-card-source')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('review-history-practice-hardest')),
      );
      await tester.tap(
        find.byKey(const Key('review-history-practice-hardest')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('Pregunta atrasada'), findsOneWidget);
    });
  });

  testWidgets('sigue al selector de Repasar, con su píldora arriba', (
    tester,
  ) async {
    await harness.processed('p-roma', 'Roma procesada');
    await harness.processed('p-grecia', 'Grecia procesada');
    await card('r1');
    await card('r2');
    await card('g1', item: 'p-grecia');
    await answer('g1', DateTime(2026, 9, 11, 9));
    harness.container.read(repasarScopeProvider.notifier).state =
        const CreationScope.document('p-grecia');

    await open(tester);
    expect(find.byKey(const Key('repasar-scope')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('stats-distribution-donut')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(figure(tester, 'stats-today-reviewed'), '1');

    harness.container.read(repasarScopeProvider.notifier).state =
        const CreationScope.allProcessed();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('stats-distribution-donut')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
  });

  for (final theme in [AppThemeChoice.light, AppThemeChoice.dark]) {
    testWidgets('360 dp con la letra al doble, en ${theme.name}: ninguna '
        'pestaña se desborda', (tester) async {
      await seed();
      await open(
        tester,
        size: const Size(360, 760),
        theme: theme,
        textScale: 2,
      );
      for (final (list, last) in [
        ('review-stats-list', 'stats-added'),
        ('review-history-list', 'review-history-hardest'),
      ]) {
        if (list == 'review-history-list') {
          await tester.tap(find.byKey(const Key('review-stats-tab-history')));
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(
          find.byKey(Key(last)),
          300,
          scrollable: find
              .descendant(
                of: find.byKey(Key(list)),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
