import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';

import '../../../../support/card_browser_harness.dart';
import '../../../../support/item_rows.dart';

/// «Mis tarjetas» con 10.000 tarjetas en 1.000 elementos (F31, ola 2, decisión
/// 72): las cifras que se citan en la decisión salen de acá (escritorio, base
/// en memoria). Los topes de la prueba no son los de la decisión: están
/// holgados para fallar solo ante algo patológico —un recorrido de más, un
/// cuadrático—, no ante una máquina cargada.
void main() {
  const cards = 10000;
  const items = 1000;
  late CardBrowserHarness h;
  final now = DateTime(2026, 10, 8, 10);

  setUpAll(() async {
    h = await CardBrowserHarness.create(clock: () => now);
    for (var n = 0; n < items; n++) {
      await insertItemRows(h.db, id: 'e$n', title: 'Elemento $n');
    }
    await h.db.batch((b) {
      b.insertAll(h.db.flashcards, [
        for (var n = 0; n < cards; n++)
          // Un reparto parecido al de una bóveda real: la mitad madura.
          FlashcardsCompanion.insert(
            id: 'c${n.toString().padLeft(5, '0')}',
            itemId: 'e${n % items}',
            front: 'Pregunta $n sobre el Imperio Romano',
            back: 'Respuesta $n',
            dueAt: now.add(Duration(days: (n % 60) - 5)),
            createdAt: DateTime(2026).add(Duration(minutes: n)),
            easeFactor: Value(1.3 + (n % 18) / 10),
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
        for (var n = 0; n < cards; n += 2)
          ReviewLogsCompanion.insert(
            id: 'l$n',
            flashcardId: 'c${n.toString().padLeft(5, '0')}',
            reviewedAt: now.subtract(Duration(days: n % 90)),
            grade: n % 7 == 0 ? 'again' : 'good',
            quality: 4,
            intervalBefore: 5,
            intervalAfter: 10,
            easeBefore: 2.5,
            easeAfter: 2.5,
            deviceId: 'd',
            phaseBefore: const Value(CardPhase.review),
          ),
      ]);
    });
  });

  tearDownAll(() => h.close());

  void report(String line) {
    // Las cifras de la decisión 72 salen de acá: son el resultado de la
    // prueba, no un registro de depuración.
    // ignore: avoid_print
    print(line);
  }

  Future<Duration> timed(Future<void> Function() body) async {
    final watch = Stopwatch()..start();
    await body();
    return watch.elapsed;
  }

  test(
    'el recuento y las páginas, con cada orden, en cualquier lugar',
    () async {
      final browser = h.browser;
      final count = (await browser.count(
        const CardBrowserQuery(),
      )).getOrElse((f) => fail('$f'));
      expect(count, cards);

      for (final sort in CardBrowserSort.values) {
        for (final offset in [0, 5000, cards - 50]) {
          final query = CardBrowserQuery(sort: sort);
          final spent = await timed(() async {
            final page = (await browser.page(
              query,
              offset: offset,
              limit: 50,
            )).getOrElse((f) => fail('$f'));
            expect(page, hasLength(50));
          });
          report('página ${sort.name} @ $offset: ${spent.inMilliseconds} ms');
          expect(spent, lessThan(const Duration(seconds: 2)));
        }
      }
    },
  );

  test(
    'las páginas no se solapan ni dejan huecos a lo largo de 10.000',
    () async {
      final browser = h.browser;
      const query = CardBrowserQuery(sort: CardBrowserSort.ease);
      final expected = (await browser.ids(query)).getOrElse((f) => fail('$f'));
      expect(expected, hasLength(cards));
      final seen = <String>[];
      for (var offset = 0; offset < cards; offset += 500) {
        final page = (await browser.page(
          query,
          offset: offset,
          limit: 500,
        )).getOrElse((f) => fail('$f'));
        seen.addAll(page.map((r) => r.card.id));
      }
      expect(seen, expected);
    },
  );

  test('ids, conteos por estado, búsqueda y recorte', () async {
    final browser = h.browser;
    var spent = await timed(() async {
      final ids = (await browser.ids(
        const CardBrowserQuery(),
      )).getOrElse((f) => fail('$f'));
      expect(ids, hasLength(cards));
    });
    report('ids de 10.000: ${spent.inMilliseconds} ms');
    expect(spent, lessThan(const Duration(seconds: 2)));

    spent = await timed(() async {
      final counts = (await browser.statusCounts(
        const CardBrowserQuery(),
      )).getOrElse((f) => fail('$f'));
      expect(
        counts[CardBrowserStatus.newCards]! +
            counts[CardBrowserStatus.learning]! +
            counts[CardBrowserStatus.young]! +
            counts[CardBrowserStatus.mature]! +
            counts[CardBrowserStatus.suspended]!,
        cards,
      );
    });
    report('conteos por estado: ${spent.inMilliseconds} ms');
    expect(spent, lessThan(const Duration(seconds: 2)));

    spent = await timed(() async {
      final found = (await browser.count(
        const CardBrowserQuery(text: 'imperio ROMANO 77'),
      )).getOrElse((f) => fail('$f'));
      // «77» aparece en el número de pregunta: 77, 177, 277…, 770 a 779…
      expect(found, greaterThan(0));
      expect(found, lessThan(cards));
    });
    report('búsqueda de texto: ${spent.inMilliseconds} ms');
    expect(spent, lessThan(const Duration(seconds: 2)));

    spent = await timed(() async {
      final inItem = (await browser.count(
        const CardBrowserQuery(scope: StudyScope.item('e7')),
      )).getOrElse((f) => fail('$f'));
      expect(inItem, cards ~/ items);
    });
    report('recorte de un elemento: ${spent.inMilliseconds} ms');
    expect(spent, lessThan(const Duration(seconds: 2)));
  });

  test('volver a nueva y borrar las 10.000 de una vez', () async {
    final browser = h.browser;
    final ids = (await browser.ids(
      const CardBrowserQuery(),
    )).getOrElse((f) => fail('$f'));

    var spent = await timed(() async {
      final changed = (await browser.resetSchedule(
        ids,
      )).getOrElse((f) => fail('$f'));
      expect(changed, cards);
    });
    report('volver a nueva 10.000: ${spent.inMilliseconds} ms');
    expect(spent, lessThan(const Duration(seconds: 5)));
    final counts = (await browser.statusCounts(
      const CardBrowserQuery(),
    )).getOrElse((f) => fail('$f'));
    expect(
      counts[CardBrowserStatus.newCards],
      cards - counts[CardBrowserStatus.suspended]!,
    );

    spent = await timed(() async {
      final deleted = (await browser.deleteMany(
        ids,
      )).getOrElse((f) => fail('$f'));
      expect(deleted, cards);
    });
    report('borrar 10.000: ${spent.inMilliseconds} ms');
    expect(spent, lessThan(const Duration(seconds: 5)));
    expect(
      (await browser.count(
        const CardBrowserQuery(),
      )).getOrElse((f) => fail('$f')),
      0,
    );
  });
}
