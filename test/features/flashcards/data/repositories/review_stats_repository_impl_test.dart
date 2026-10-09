import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_stats_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';

import '../../../../support/card_browser_harness.dart';
import '../../../../support/item_rows.dart';

/// Las estadísticas contra SQLite real, en memoria (F31, ola 2, decisión
/// 72): el pronóstico por día de estudio, el reparto por etapa y los botones
/// usados.
void main() {
  late CardBrowserHarness h;
  late ReviewStatsRepositoryImpl stats;
  var now = DateTime(2026, 10, 8, 10);

  setUp(() async {
    now = DateTime(2026, 10, 8, 10);
    h = await CardBrowserHarness.create(clock: () => now);
    stats = ReviewStatsRepositoryImpl(
      database: h.db,
      telemetry: h.telemetry,
      clock: () => now,
      browser: h.browser,
    );
  });

  tearDown(() => h.close());

  Future<ReviewStats> load({StatsPeriod period = StatsPeriod.all}) async =>
      (await stats.load(period: period)).getOrElse((f) => fail('$f'));

  List<int> counts(ReviewStats s) => [for (final d in s.forecast.days) d.count];

  group('el pronóstico', () {
    test('sin tarjetas: treinta días en cero', () async {
      final s = await load();
      expect(s.forecast.days, hasLength(kForecastDays));
      expect(counts(s).every((n) => n == 0), isTrue);
      expect(s.forecast.overdue, 0);
      expect(s.forecast.total, 0);
      expect(s.forecast.peak, 0);
      expect(s.distribution.total, 0);
      expect(s.distribution, const CardDistribution.empty());
    });

    test('cada día de estudio va de las 4:00 a las 4:00', () async {
      final today = DateTime(2026, 10, 8, 4);
      expect(await load().then((s) => s.forecast.days.first.start), today);
      await h.card('hoy-22', dueAt: DateTime(2026, 10, 8, 22));
      await h.card('hoy-madrugada', dueAt: DateTime(2026, 10, 9, 3, 59));
      await h.card('manana-4', dueAt: DateTime(2026, 10, 9, 4));
      await h.card('manana-5', dueAt: DateTime(2026, 10, 9, 5));
      await h.card('pasado', dueAt: DateTime(2026, 10, 10, 12));

      final s = await load();
      expect(counts(s).take(4), [2, 2, 1, 0]);
      expect(s.forecast.days[1].start, DateTime(2026, 10, 9, 4));
      expect(s.forecast.days[29].start, DateTime(2026, 11, 6, 4));
    });

    test('lo atrasado cuenta hoy, y se dice cuánto', () async {
      await h.card('atrasada-1', dueAt: DateTime(2026, 10, 7, 12));
      await h.card('atrasada-2', dueAt: DateTime(2026, 9));
      await h.card('de-hoy', dueAt: DateTime(2026, 10, 8, 20));
      final s = await load();
      expect(s.forecast.days.first.count, 3);
      expect(s.forecast.overdue, 2);
    });

    test('la última casilla es el día 30; después, afuera', () async {
      await h.card('ultimo', dueAt: DateTime(2026, 11, 7, 3, 59));
      await h.card('afuera', dueAt: DateTime(2026, 11, 7, 4));
      await h.card('lejos', dueAt: DateTime(2027, 5));
      final s = await load();
      expect(s.forecast.days.last.count, 1);
      expect(s.forecast.total, 1);
    });

    test('no cuenta nuevas, pausadas ni elementos en la papelera', () async {
      await h.card('nueva', phase: CardPhase.newCard);
      await h.card(
        'pausada',
        suspended: true,
        dueAt: DateTime(2026, 10, 9, 12),
      );
      await insertItemRows(h.db, id: 'borrado', title: 'Borrado');
      await h.card(
        'muerta',
        itemId: 'borrado',
        dueAt: DateTime(2026, 10, 9, 12),
      );
      await (h.db.update(h.db.knowledgeEntries)
            ..where((e) => e.id.equals('borrado')))
          .write(KnowledgeEntriesCompanion(deletedAt: Value(now)));
      await h.card('viva', dueAt: DateTime(2026, 10, 9, 12));

      expect((await load()).forecast.total, 1);
    });

    test('lo que se aprende cuenta hoy', () async {
      await h.card(
        'aprendiendo',
        phase: CardPhase.learning,
        dueAt: now.add(const Duration(minutes: 10)),
      );
      final s = await load();
      expect(s.forecast.days.first.count, 1);
      expect(s.forecast.overdue, 0);
    });

    test(
      'una pospuesta cuenta el día en que vuelve, no el que tenía',
      () async {
        await h.card(
          'pospuesta',
          dueAt: DateTime(2026, 10, 8, 9),
          buriedUntil: DateTime(2026, 10, 9, 4),
        );
        // Una posposición que ya pasó no mueve nada.
        await h.card(
          'vieja',
          dueAt: DateTime(2026, 10, 8, 9),
          buriedUntil: DateTime(2026, 10, 7, 4),
        );
        final s = await load();
        expect(counts(s).take(2), [1, 1]);
        expect(s.forecast.overdue, 0);
      },
    );

    test('posponer no adelanta una tarjeta que vence más tarde', () async {
      // Pospuesta hasta mañana, pero le tocaba dentro de cinco días.
      await h.card(
        'lejana',
        dueAt: DateTime(2026, 10, 13, 12),
        buriedUntil: DateTime(2026, 10, 9, 4),
      );
      final s = await load();
      expect(counts(s)[1], 0);
      expect(counts(s)[5], 1);
    });

    test('una posposición vencida no esconde lo atrasado', () async {
      // Le tocaba el 1 de octubre; la posposición terminó hoy a las 5:00.
      await h.card(
        'atrasada',
        dueAt: DateTime(2026, 10, 1, 12),
        buriedUntil: DateTime(2026, 10, 8, 5),
      );
      final s = await load();
      expect(s.forecast.overdue, 1);
      expect(s.forecast.days.first.count, 1);
    });

    test('cambia con el día de estudio, no con la medianoche', () async {
      await h.card('a', dueAt: DateTime(2026, 10, 9, 3));
      await h.card('b', dueAt: DateTime(2026, 10, 9, 5));

      now = DateTime(2026, 10, 9, 3, 30); // todavía es el día del 8
      var s = await load();
      expect(s.forecast.days.first.start, DateTime(2026, 10, 8, 4));
      expect(counts(s).take(2), [1, 1]);
      expect(s.forecast.overdue, 0);

      now = DateTime(2026, 10, 9, 4, 30); // ya empezó el del 9
      s = await load();
      expect(s.forecast.days.first.start, DateTime(2026, 10, 9, 4));
      expect(counts(s).take(2), [2, 0]);
      expect(s.forecast.overdue, 1);
    });

    test('una sola tarjeta', () async {
      await h.card('sola', dueAt: DateTime(2026, 10, 12, 12));
      final s = await load();
      expect(counts(s)[4], 1);
      expect(s.forecast.total, 1);
      expect(s.forecast.peak, 1);
    });
  });

  group('el reparto', () {
    test('es una partición con la pausa por encima', () async {
      await h.card('n1', phase: CardPhase.newCard);
      await h.card('n2', phase: CardPhase.newCard, suspended: true);
      await h.card('l1', phase: CardPhase.learning);
      await h.card('r1', phase: CardPhase.relearning);
      await h.card('j1', interval: 20);
      await h.card('m1', interval: 21);
      await h.card('m2', interval: 300);
      await h.card('p1', suspended: true, interval: 300);

      final d = (await load()).distribution;
      expect(d.newCards, 1);
      expect(d.learning, 2);
      expect(d.young, 1);
      expect(d.mature, 2);
      expect(d.suspended, 2);
      expect(d.total, 8);
    });
  });

  group('los botones', () {
    DateTime daysAgo(int d) =>
        DateTime(2026, 10, 8, 12).subtract(Duration(days: d));

    Future<void> log(
      String grade, {
      required CardPhase phase,
      int intervalBefore = 0,
      DateTime? at,
      String card = 'c',
    }) => h.answered(
      card,
      phase: phase,
      at: at ?? daysAgo(1),
      grade: grade,
      intervalBefore: intervalBefore,
    );

    setUp(() => h.card('c'));

    test('por etapa, con el porcentaje de acierto', () async {
      // Nueva: 1 de nuevo, 3 bien.
      await log('again', phase: CardPhase.newCard);
      for (var n = 0; n < 3; n++) {
        await log('good', phase: CardPhase.newCard);
      }
      // Aprendiendo y reaprendiendo cuentan juntas.
      await log('hard', phase: CardPhase.learning);
      await log('easy', phase: CardPhase.relearning);
      // Jóvenes (20) y maduras (21), por el intervalo de antes.
      await log('good', phase: CardPhase.review, intervalBefore: 20);
      await log('again', phase: CardPhase.review, intervalBefore: 20);
      await log('good', phase: CardPhase.review, intervalBefore: 21);
      await log('good', phase: CardPhase.review, intervalBefore: 400);
      await log('again', phase: CardPhase.review, intervalBefore: 400);
      await log('hard', phase: CardPhase.review, intervalBefore: 400);

      final b = (await load()).buttons;
      expect(b.of(StatsStage.newCard), const ButtonUsage(again: 1, good: 3));
      expect(b.of(StatsStage.newCard).accuracy, 0.75);
      expect(b.of(StatsStage.learning), const ButtonUsage(hard: 1, easy: 1));
      expect(b.of(StatsStage.learning).accuracy, 1.0);
      expect(b.of(StatsStage.young), const ButtonUsage(again: 1, good: 1));
      expect(b.of(StatsStage.young).accuracy, 0.5);
      expect(
        b.of(StatsStage.mature),
        const ButtonUsage(again: 1, hard: 1, good: 2),
      );
      expect(b.of(StatsStage.mature).accuracy, 0.75);
      expect(b.overall.total, 12);
      expect(b.overall.again, 3);
    });

    test('una etapa sin respuestas no tiene porcentaje, no un cero', () async {
      await log('good', phase: CardPhase.newCard);
      final b = (await load()).buttons;
      expect(b.of(StatsStage.mature).total, 0);
      expect(b.of(StatsStage.mature).accuracy, isNull);
      expect(b.overall.accuracy, 1.0);
    });

    test('sin ningún repaso', () async {
      final b = (await load()).buttons;
      expect(b.overall.total, 0);
      expect(b.overall.accuracy, isNull);
    });

    test('el período corta por día de estudio', () async {
      // Hoy es el día de estudio que empezó el 8 a las 4:00; 30 días son desde
      // el 9 de septiembre a las 4:00.
      await log('good', phase: CardPhase.newCard, at: DateTime(2026, 9, 9, 4));
      await log(
        'good',
        phase: CardPhase.newCard,
        at: DateTime(2026, 9, 9, 3, 59),
      );
      await log('good', phase: CardPhase.newCard, at: DateTime(2026, 7));

      expect((await load(period: StatsPeriod.days30)).buttons.overall.total, 1);
      expect((await load(period: StatsPeriod.days90)).buttons.overall.total, 2);
      expect((await load()).buttons.overall.total, 3);
      expect(
        (await load(period: StatsPeriod.days30)).period,
        StatsPeriod.days30,
      );
    });

    test('no cuenta el historial de una tarjeta de la papelera', () async {
      await insertItemRows(h.db, id: 'borrado', title: 'Borrado');
      await h.card('d', itemId: 'borrado');
      await log('good', phase: CardPhase.newCard, card: 'd');
      await log('good', phase: CardPhase.newCard);
      await (h.db.update(h.db.knowledgeEntries)
            ..where((e) => e.id.equals('borrado')))
          .write(KnowledgeEntriesCompanion(deletedAt: Value(now)));
      expect((await load()).buttons.overall.total, 1);
    });
  });

  test('el reparto y el filtro de «Mis tarjetas» dicen lo mismo', () async {
    await h.card('n', phase: CardPhase.newCard);
    await h.card('j', interval: 5);
    await h.card('m', interval: 50);
    await h.card('p', suspended: true);
    final d = (await load()).distribution;
    final c = (await h.browser.statusCounts(
      const CardBrowserQuery(),
    )).getOrElse((f) => fail('$f'));
    expect(d.newCards, c[CardBrowserStatus.newCards]);
    expect(d.young, c[CardBrowserStatus.young]);
    expect(d.mature, c[CardBrowserStatus.mature]);
    expect(d.suspended, c[CardBrowserStatus.suspended]);
  });

  test('watch emite al cambiar una tarjeta', () async {
    final values = <ReviewStats>[];
    final sub = stats.watch(period: StatsPeriod.all).listen(values.add);
    await pumpEventQueue(times: 50);
    final before = values.length;
    expect(before, greaterThan(0));
    await h.card('nueva', dueAt: DateTime(2026, 10, 12, 12));
    await pumpEventQueue(times: 50);
    expect(values.length, greaterThan(before));
    expect(values.last.forecast.total, 1);
    await sub.cancel();
  });
}
