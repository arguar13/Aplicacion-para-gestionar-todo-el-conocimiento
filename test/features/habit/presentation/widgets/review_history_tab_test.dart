import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/habit/domain/entities/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/entities/difficult_card.dart';
import 'package:sinapsis/features/habit/domain/entities/review_history.dart';
import 'package:sinapsis/features/habit/domain/entities/true_retention.dart';
import 'package:sinapsis/features/habit/domain/entities/weekly_retention.dart';
import 'package:sinapsis/features/habit/presentation/widgets/review_history_tab.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// La pestaña «Historial» suelta, con un historial armado a mano (F43, M16):
/// lo que se dibuja, lo que se lee y lo que se toca.
void main() {
  final es = AppLocalizationsEs();

  setUpAll(() => initializeDateFormatting('es'));

  // Del jueves 10 de septiembre de 2026 hacia atrás, un año de días.
  final today = DateTime(2026, 9, 10, 4);
  DateTime dayAt(int back) =>
      DateTime(today.year, today.month, today.day - back, 4);

  ReviewHistory history({List<DifficultCard> hardest = const []}) =>
      ReviewHistory(
        retentionByWeek: [
          for (var w = 11; w >= 0; w--)
            WeeklyRetention(
              weekStart: dayAt(w * 7 + 6),
              total: w == 0 ? 20 : (w.isEven ? 10 : 0),
              retained: w == 0 ? 17 : (w.isEven ? 9 : 0),
            ),
        ],
        trueRetention: [
          for (final period in RetentionPeriod.values)
            TrueRetentionRow(
              period: period,
              young: const PassFail(passed: 9, failed: 1),
              mature: const PassFail(),
            ),
        ],
        activityByDay: [
          for (var back = 364; back >= 0; back--)
            DailyActivity(
              day: dayAt(back),
              count: back < 3 ? 12 : 0,
              correct: back < 3 ? 9 : 0,
            ),
        ],
        currentRun: 3,
        longestRun: 8,
        hardestCards: hardest,
      );

  Future<void> pump(
    WidgetTester tester,
    ReviewHistory value, {
    Size size = const Size(800, 3000),
    ThemeData? theme,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [ReviewHistorySections(history: value)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('la retención: eje de 0 a 100 %, la meta y cada semana al '
      'tocarla', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, history());
    final chart = find.byKey(const Key('review-history-retention-chart'));
    final label = tester.getSemantics(chart).label;
    expect(label, startsWith(es.f43S20RetentionChartLabel(12)));
    expect(label, contains(es.f43S20WeekRetention('4 sept', 85, 20)));
    expect(label, contains(es.f43S20WeekNoReviews('3 jul')));
    semantics.dispose();

    final plot = tester.getRect(
      find.descendant(of: chart, matching: find.byType(CustomPaint)).first,
    );
    await tester.tapAt(Offset(plot.right - 4, plot.center.dy));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: chart,
              matching: find.byKey(const Key('stats-chart-callout')),
            ),
          )
          .data,
      es.f43S20WeekRetention('4 sept', 85, 20),
    );
  });

  testWidgets('la retención real: los cinco tramos, jóvenes y maduras', (
    tester,
  ) async {
    await pump(tester, history());
    for (final period in RetentionPeriod.values) {
      expect(find.byKey(ValueKey('true-retention-${period.name}')), findsOne);
    }
    expect(find.text(es.f43S20Young), findsOneWidget);
    expect(find.text(es.f43S20Mature), findsOneWidget);
    expect(find.text('90 %'), findsNWidgets(10));
    expect(find.text(es.f43S20RetentionCount(10)), findsNWidgets(10));
  });

  testWidgets('la constancia: las rachas, los días estudiados, el promedio '
      'y un día al tocarlo', (tester) async {
    await pump(tester, history());
    expect(find.text(es.f43S20RunDays(3)), findsOneWidget);
    expect(find.text(es.f43S20RunDays(8)), findsOneWidget);
    expect(find.text(es.f43S20StudiedOf(3, 90, 3)), findsOneWidget);
    expect(find.text(es.f43S20AveragePerDay('12')), findsOneWidget);
    expect(find.text(es.f43S20Less), findsOneWidget);
    expect(find.text(es.f43S20More), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey('activity-day-${today.toIso8601String()}')),
    );
    await tester.pumpAndSettle();
    final date = DateFormat.MMMEd('es').format(today);
    expect(find.text(es.f43S20DayReviews(date, 12, 75)), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-history-range-year')));
    await tester.pumpAndSettle();
    expect(find.text(es.f43S20StudiedOf(3, 365, 1)), findsOneWidget);
    // El calendario de un año no entra: se desliza, y empieza por hoy.
    expect(
      find.descendant(
        of: find.byKey(const Key('review-history-activity-calendar')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('las difíciles: cuántos «De nuevo» de cuántos y los lapsos', (
    tester,
  ) async {
    await pump(
      tester,
      history(
        hardest: const [
          DifficultCard(
            flashcardId: 'a',
            front: '¿Capital de Australia?',
            back: 'Canberra',
            itemId: 'geo',
            total: 9,
            againCount: 3,
            lapses: 2,
          ),
        ],
      ),
    );
    expect(find.text('3 de 9 «De nuevo» · 2 lapsos'), findsOneWidget);
    expect(find.text(es.f43S20PracticeThese(1)), findsOneWidget);

    await tester.tap(find.byKey(const Key('hardest-card-a')));
    await tester.pumpAndSettle();
    expect(find.text('Canberra'), findsOneWidget);
    expect(find.text(es.flashcardsViewSource), findsOneWidget);
  });

  testWidgets('sin difíciles lo dice, y no ofrece repasar nada', (
    tester,
  ) async {
    await pump(tester, history());
    expect(find.text(es.f43S20HardestEmpty), findsOneWidget);
    expect(
      find.byKey(const Key('review-history-practice-hardest')),
      findsNothing,
    );
  });

  for (final dark in [false, true]) {
    testWidgets('360 dp con la letra al doble, ${dark ? 'oscuro' : 'claro'}: '
        'nada se desborda', (tester) async {
      await pump(
        tester,
        history(
          hardest: const [
            DifficultCard(
              flashcardId: 'a',
              front: 'Una pregunta bastante larga para un teléfono angosto',
              total: 12,
              againCount: 5,
              lapses: 4,
            ),
          ],
        ),
        size: const Size(360, 6000),
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      for (final range in ['days30', 'year']) {
        await tester.tap(find.byKey(Key('review-history-range-$range')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  group('CalendarLayout', () {
    test('la columna es la semana, de lunes a domingo; la fila, el día', () {
      // El 1 de septiembre de 2026 es martes.
      final layout = CalendarLayout([
        for (var d = 1; d <= 14; d++) DateTime(2026, 9, d, 4),
      ]);
      expect(layout.firstMonday, DateTime(2026, 8, 31));
      expect(layout.positionOf(DateTime(2026, 9, 1, 4)), (0, 1));
      expect(layout.positionOf(DateTime(2026, 9, 6, 4)), (0, 6));
      expect(layout.positionOf(DateTime(2026, 9, 7, 4)), (1, 0));
      expect(layout.columns, 3);
    });

    test('el nombre de cada mes va donde empieza, sin pisarse', () {
      final layout = CalendarLayout([
        for (var d = 0; d < 90; d++) DateTime(2026, 7, 28 + d, 4),
      ]);
      final months = layout.monthStarts(DateFormat.MMM('es'));
      // Julio dura cuatro días: le deja el lugar a agosto.
      expect([for (final (_, m) in months) m], ['ago', 'sept', 'oct']);
      expect(months.first.$1, layout.positionOf(DateTime(2026, 8, 1, 4)).$1);
    });
  });
}
