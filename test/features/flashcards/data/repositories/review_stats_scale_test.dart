import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_stats_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';

import '../../../../support/card_browser_harness.dart';
import '../../../../support/item_rows.dart';

/// Las estadísticas con 10.000 tarjetas en 1.000 elementos y 20.000 repasos
/// (F31, ola 2, decisión 72): las cifras de la decisión salen de acá
/// (escritorio, base en memoria). El tope es holgado: falla ante algo
/// patológico, no ante una máquina cargada.
void main() {
  const cards = 10000;
  const items = 1000;
  const logs = 20000;
  late CardBrowserHarness h;
  late ReviewStatsRepositoryImpl stats;
  final now = DateTime(2026, 10, 8, 10);

  setUpAll(() async {
    h = await CardBrowserHarness.create(clock: () => now);
    stats = ReviewStatsRepositoryImpl(
      database: h.db,
      telemetry: h.telemetry,
      clock: () => now,
      browser: h.browser,
    );
    for (var n = 0; n < items; n++) {
      await insertItemRows(h.db, id: 'e$n', title: 'Elemento $n');
    }
    await h.db.batch((b) {
      b.insertAll(h.db.flashcards, [
        for (var n = 0; n < cards; n++)
          FlashcardsCompanion.insert(
            id: 'c${n.toString().padLeft(5, '0')}',
            itemId: 'e${n % items}',
            front: 'Pregunta $n',
            back: 'Respuesta $n',
            dueAt: now.add(Duration(hours: (n * 7) % (24 * 45) - 48)),
            createdAt: DateTime(2026).add(Duration(minutes: n)),
            intervalDays: Value(switch (n % 10) {
              0 || 1 => 0,
              2 => 3,
              3 => 10,
              _ => 25 + n % 200,
            }),
            repetitions: Value(n % 10 < 2 ? 0 : 4),
            lastReviewedAt: n % 10 < 2 ? const Value(null) : Value(now),
            learningStep: n % 25 == 0 ? const Value(0) : const Value(null),
            suspended: Value(n % 40 == 0),
          ),
      ]);
    });
    await h.db.batch((b) {
      b.insertAll(h.db.reviewLogs, [
        for (var n = 0; n < logs; n++)
          ReviewLogsCompanion.insert(
            id: 'l$n',
            flashcardId: 'c${(n % cards).toString().padLeft(5, '0')}',
            reviewedAt: now.subtract(Duration(hours: n % (24 * 400))),
            grade: switch (n % 9) {
              0 => 'again',
              1 => 'hard',
              2 => 'easy',
              _ => 'good',
            },
            quality: 4,
            intervalBefore: n % 60,
            intervalAfter: 10,
            easeBefore: 2.5,
            easeAfter: 2.5,
            deviceId: 'd',
            phaseBefore: Value(switch (n % 5) {
              0 => CardPhase.newCard,
              1 => CardPhase.learning,
              _ => CardPhase.review,
            }),
          ),
      ]);
    });
  });

  tearDownAll(() => h.close());

  test('el cálculo entero, con cada período, es rápido', () async {
    for (final period in StatsPeriod.values) {
      final watch = Stopwatch()..start();
      final result = (await stats.load(
        period: period,
      )).getOrElse((f) => fail('$f'));
      watch.stop();
      // Las cifras de la decisión 72 salen de acá: son el resultado de la
      // prueba, no un registro de depuración.
      // ignore: avoid_print
      print('estadísticas ${period.name}: ${watch.elapsedMilliseconds} ms');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));

      expect(result.distribution.total, cards);
      expect(result.forecast.days, hasLength(kForecastDays));
      // Lo que vence en 30 días no puede pasar de las programadas.
      expect(
        result.forecast.total,
        lessThanOrEqualTo(
          cards - result.distribution.newCards - result.distribution.suspended,
        ),
      );
      expect(result.buttons.overall.total, greaterThan(0));
    }
  });

  test('los botones: los períodos más largos cuentan más', () async {
    final d30 = await stats
        .load(period: StatsPeriod.days30)
        .then((r) => r.getOrElse((f) => fail('$f')).buttons.overall.total);
    final d90 = await stats
        .load(period: StatsPeriod.days90)
        .then((r) => r.getOrElse((f) => fail('$f')).buttons.overall.total);
    final all = await stats
        .load(period: StatsPeriod.all)
        .then((r) => r.getOrElse((f) => fail('$f')).buttons.overall.total);
    expect(d30, lessThan(d90));
    expect(d90, lessThan(all));
    expect(all, logs);
  });
}
