import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/flashcards/data/repositories/card_browser_repository_impl.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_row_mapping.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_row.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';

import '../../../../support/card_browser_harness.dart';
import '../../../../support/item_rows.dart';

/// «Mis tarjetas» contra SQLite real, en memoria (F31, ola 2, decisión 72): qué
/// entra en cada filtro, el orden, la búsqueda, las páginas y las dos
/// escrituras en lote.
void main() {
  late CardBrowserHarness h;
  late CardBrowserRepositoryImpl browser;
  var now = DateTime(2026, 10, 8, 10);

  DateTime daysFromNow(int d) => now.add(Duration(days: d));

  setUp(() async {
    now = DateTime(2026, 10, 8, 10);
    h = await CardBrowserHarness.create(clock: () => now);
    browser = h.browser;
  });

  tearDown(() => h.close());

  Future<List<String>> idsOf(CardBrowserQuery query) async =>
      (await browser.ids(query)).getOrElse((f) => fail('$f'));

  Future<Set<String>> setOf(CardBrowserQuery query) async =>
      (await idsOf(query)).toSet();

  CardBrowserQuery status(CardBrowserStatus s) => CardBrowserQuery(status: s);

  group('los estados', () {
    setUp(() async {
      await h.card('nueva', phase: CardPhase.newCard);
      await h.card('nueva-pausada', phase: CardPhase.newCard, suspended: true);
      await h.card('nueva-pospuesta', phase: CardPhase.newCard);
      await (h.db.update(h.db.flashcards)
            ..where((f) => f.id.equals('nueva-pospuesta')))
          .write(FlashcardsCompanion(buriedUntil: Value(daysFromNow(1))));
      await h.card(
        'aprendiendo',
        phase: CardPhase.learning,
        dueAt: now.add(const Duration(minutes: 10)),
      );
      await h.card(
        'reaprendiendo',
        phase: CardPhase.relearning,
        dueAt: now.add(const Duration(minutes: 10)),
      );
      await h.card('joven-20', interval: 20, dueAt: daysFromNow(-3)); // vencida
      await h.card('madura-21', interval: 21, dueAt: daysFromNow(30));
      await h.card('madura-90', interval: 90, dueAt: daysFromNow(40));
      await h.card('repaso-pausada', suspended: true, dueAt: daysFromNow(-1));
      // Vence a las 22:00 de hoy: dentro del día de estudio (hasta las 4:00 de
      // mañana).
      await h.card('esta-noche', interval: 7, dueAt: DateTime(2026, 10, 8, 22));
      // Vence a las 05:00 de mañana: ya es otro día de estudio.
      await h.card('manana-5', interval: 7, dueAt: DateTime(2026, 10, 9, 5));
    });

    test('cada filtro trae justo las suyas', () async {
      expect(await setOf(status(CardBrowserStatus.newCards)), {
        'nueva',
        'nueva-pospuesta',
      });
      expect(await setOf(status(CardBrowserStatus.learning)), {
        'aprendiendo',
        'reaprendiendo',
      });
      expect(await setOf(status(CardBrowserStatus.young)), {
        'joven-20',
        'esta-noche',
        'manana-5',
      });
      expect(await setOf(status(CardBrowserStatus.mature)), {
        'madura-21',
        'madura-90',
      });
      expect(await setOf(status(CardBrowserStatus.suspended)), {
        'nueva-pausada',
        'repaso-pausada',
      });
      expect(await setOf(status(CardBrowserStatus.buried)), {
        'nueva-pospuesta',
      });
    });

    test('por repasar: lo atrasado, lo de hoy y lo que se aprende; no lo '
        'nuevo, ni lo pausado, ni lo de otro día de estudio', () async {
      expect(await setOf(status(CardBrowserStatus.due)), {
        'aprendiendo',
        'reaprendiendo',
        'joven-20',
        'esta-noche',
      });
    });

    test('el día de estudio manda: a las 3:30 todavía es el de ayer', () async {
      // A las 3:30 el día de estudio es el del 8, que termina a las 4:00 del 9:
      // lo de las 22:00 ya está atrasado y lo de las 5:00 es de «mañana».
      now = DateTime(2026, 10, 9, 3, 30);
      final early = await setOf(status(CardBrowserStatus.due));
      expect(early, contains('esta-noche'));
      expect(early, isNot(contains('manana-5')));
      // A las 4:30 empezó otro día: «hoy» llega hasta las 4:00 del 10 y entra
      // lo de las 5:00.
      now = DateTime(2026, 10, 9, 4, 30);
      expect(await setOf(status(CardBrowserStatus.due)), contains('manana-5'));
    });

    test(
      'etapas y pausadas son una partición; coincide con la entidad',
      () async {
        final counts = (await browser.statusCounts(
          const CardBrowserQuery(),
        )).getOrElse((f) => fail('$f'));
        final total = (await browser.count(
          const CardBrowserQuery(),
        )).getOrElse((f) => fail('$f'));
        expect(total, 11);
        expect(
          counts[CardBrowserStatus.newCards]! +
              counts[CardBrowserStatus.learning]! +
              counts[CardBrowserStatus.young]! +
              counts[CardBrowserStatus.mature]! +
              counts[CardBrowserStatus.suspended]!,
          total,
        );
        expect(counts, {
          CardBrowserStatus.newCards: 2,
          CardBrowserStatus.learning: 2,
          CardBrowserStatus.young: 3,
          CardBrowserStatus.mature: 2,
          CardBrowserStatus.suspended: 2,
          CardBrowserStatus.due: 4,
          CardBrowserStatus.buried: 1,
        });

        // El SQL y la entidad dicen lo mismo de cada tarjeta.
        final rows = await h.db.select(h.db.flashcards).get();
        for (final row in rows) {
          final card = flashcardFromRow(row);
          final expected = card.suspended
              ? CardBrowserStatus.suspended
              : switch (card.phase) {
                  CardPhase.newCard => CardBrowserStatus.newCards,
                  CardPhase.learning ||
                  CardPhase.relearning => CardBrowserStatus.learning,
                  CardPhase.review =>
                    card.intervalDays >= kMatureIntervalDays
                        ? CardBrowserStatus.mature
                        : CardBrowserStatus.young,
                };
          final sqlStatus = [
            for (final s in [
              CardBrowserStatus.newCards,
              CardBrowserStatus.learning,
              CardBrowserStatus.young,
              CardBrowserStatus.mature,
              CardBrowserStatus.suspended,
            ])
              if ((await setOf(status(s))).contains(card.id)) s,
          ];
          expect(sqlStatus, [expected], reason: card.id);
        }
      },
    );

    test('los conteos respetan el recorte y el texto, no el estado', () async {
      await insertItemRows(h.db, id: 'otro', title: 'Otro');
      await h.card('otro-nueva', itemId: 'otro', phase: CardPhase.newCard);
      final counts = (await browser.statusCounts(
        const CardBrowserQuery(
          scope: StudyScope.item('otro'),
          status: CardBrowserStatus.mature,
        ),
      )).getOrElse((f) => fail('$f'));
      expect(counts[CardBrowserStatus.newCards], 1);
      expect(counts[CardBrowserStatus.mature], 0);
    });
  });

  test('una posposición que ya pasó no cuenta como pospuesta', () async {
    await h.card('vencida', buriedUntil: daysFromNow(-1));
    await h.card('vigente', buriedUntil: daysFromNow(1));
    expect(await setOf(status(CardBrowserStatus.buried)), {'vigente'});
    // Y a las 4:00 de mañana, la vigente también pasó.
    now = DateTime(2026, 10, 9, 4);
    expect(await setOf(status(CardBrowserStatus.buried)), {'vigente'});
    now = DateTime(2026, 10, 9, 10);
    expect(await setOf(status(CardBrowserStatus.buried)), isEmpty);
  });

  group('la papelera y los recortes', () {
    test('las tarjetas de un elemento en la papelera no se ven', () async {
      await insertItemRows(h.db, id: 'borrado', title: 'Borrado');
      await h.card('viva');
      await h.card('muerta', itemId: 'borrado');
      await (h.db.update(h.db.knowledgeEntries)
            ..where((e) => e.id.equals('borrado')))
          .write(KnowledgeEntriesCompanion(deletedAt: Value(now)));

      expect(await setOf(const CardBrowserQuery()), {'viva'});
      expect(
        (await browser.count(
          const CardBrowserQuery(),
        )).getOrElse((f) => fail('$f')),
        1,
      );
      expect(
        (await browser.statusCounts(
          const CardBrowserQuery(),
        )).getOrElse((f) => fail('$f'))[CardBrowserStatus.mature],
        0,
      );
    });

    test(
      'un elemento, un tema y un cuaderno: los de la cola de estudio',
      () async {
        for (final id in ['roma', 'grecia', 'suelto']) {
          await insertItemRows(h.db, id: id, title: id);
          await h.card('c-$id', itemId: id);
        }
        await h.db
            .into(h.db.spaces)
            .insert(
              SpacesCompanion.insert(
                id: 'hist',
                name: 'Historia',
                createdAt: now,
              ),
            );
        await (h.db.update(h.db.knowledgeEntries)
              ..where((e) => e.id.isIn(['roma', 'grecia'])))
            .write(const KnowledgeEntriesCompanion(spaceId: Value('hist')));
        final book = await h.notebooks.create(
          name: 'Para el examen',
          mode: NotebookMode.manual,
        );
        await h.notebooks.addItem(notebookId: book.id, itemId: 'suelto');

        expect(
          await setOf(const CardBrowserQuery(scope: StudyScope.item('roma'))),
          {'c-roma'},
        );
        expect(
          await setOf(const CardBrowserQuery(scope: StudyScope.space('hist'))),
          {'c-roma', 'c-grecia'},
        );
        expect(
          await setOf(CardBrowserQuery(scope: StudyScope.notebook(book.id))),
          {'c-suelto'},
        );
        // Un recorte sin elementos no trae nada (y no es un error).
        final empty = await h.notebooks.create(
          name: 'Vacío',
          mode: NotebookMode.manual,
        );
        expect(
          await setOf(CardBrowserQuery(scope: StudyScope.notebook(empty.id))),
          isEmpty,
        );
        // Un cuaderno que no existe es un fallo claro, no un cuelgue.
        expect(
          (await browser.count(
            const CardBrowserQuery(scope: StudyScope.notebook('fantasma')),
          )).isLeft(),
          isTrue,
        );
      },
    );
  });

  group('la búsqueda', () {
    setUp(() async {
      await h.card(
        'a',
        front: 'El Imperio Romano cayó en 476',
        back: 'Occidente',
      );
      await h.card(
        'b',
        front: 'Álvaro de Bazán',
        back: 'Marqués de Santa Cruz',
      );
      await h.card('c', front: 'Cuántos años tiene', back: 'Un año y medio');
      await h.card(
        'd',
        front: 'Cuántos anos tiene',
        back: 'El ano es otra cosa',
      );
      await h.card('e', front: '¿Qué es 100% seguro? [a-z]*', back: 'f(x) = ?');
    });

    test(
      'no distingue mayúsculas ni acentos, en el frente o en el dorso',
      () async {
        expect(await setOf(const CardBrowserQuery(text: 'ROMANO')), {'a'});
        expect(await setOf(const CardBrowserQuery(text: 'alvaro')), {'b'});
        expect(await setOf(const CardBrowserQuery(text: 'ÁLVARO')), {'b'});
        expect(await setOf(const CardBrowserQuery(text: 'marques')), {'b'});
        expect(await setOf(const CardBrowserQuery(text: 'occidénte')), {'a'});
      },
    );

    test('la ñ no es una n', () async {
      expect(await setOf(const CardBrowserQuery(text: 'años')), {'c'});
      expect(await setOf(const CardBrowserQuery(text: 'anos')), {'d'});
    });

    test('todas las palabras, en cualquier orden', () async {
      expect(await setOf(const CardBrowserQuery(text: 'cayó imperio')), {'a'});
      expect(await setOf(const CardBrowserQuery(text: 'imperio zzz')), isEmpty);
      expect(await setOf(const CardBrowserQuery(text: '   ')), hasLength(5));
    });

    test('los signos de los comodines se toman al pie de la letra', () async {
      expect(await setOf(const CardBrowserQuery(text: '100%')), {'e'});
      expect(await setOf(const CardBrowserQuery(text: '[a-z]*')), {'e'});
      expect(await setOf(const CardBrowserQuery(text: '?')), {'e'});
      expect(await setOf(const CardBrowserQuery(text: '*')), {'e'});
      expect(await setOf(const CardBrowserQuery(text: '[')), {'e'});
    });

    test('se combina con el estado y el recorte', () async {
      await (h.db.update(h.db.flashcards)..where((f) => f.id.equals('a')))
          .write(const FlashcardsCompanion(suspended: Value(true)));
      expect(
        await setOf(
          const CardBrowserQuery(
            text: 'romano',
            status: CardBrowserStatus.suspended,
          ),
        ),
        {'a'},
      );
      expect(
        await setOf(
          const CardBrowserQuery(
            text: 'romano',
            status: CardBrowserStatus.mature,
          ),
        ),
        isEmpty,
      );
    });
  });

  group('el orden y las páginas', () {
    setUp(() async {
      // Cinco con los mismos valores (empate) y otras con valores distintos.
      for (var n = 0; n < 5; n++) {
        await h.card(
          'empate-$n',
          dueAt: DateTime(2026, 10, 20),
          createdAt: DateTime(2026, 9),
          interval: 10,
        );
      }
      await h.card(
        'dificil',
        dueAt: DateTime(2026, 10),
        createdAt: DateTime(2026, 9, 5),
        interval: 3,
        ease: 1.3,
      );
      await h.card(
        'facil',
        dueAt: DateTime(2026, 11),
        createdAt: DateTime(2026, 8, 5),
        interval: 200,
        ease: 3.1,
      );
      // «dificil» se olvidó tres veces sobre un repaso; «facil», una; y una
      // respuesta «De nuevo» sobre una nueva no es un olvido.
      for (var n = 0; n < 3; n++) {
        await h.answered(
          'dificil',
          phase: CardPhase.review,
          at: DateTime(2026, 9, 10 + n),
          grade: 'again',
        );
      }
      await h.answered(
        'facil',
        phase: CardPhase.review,
        at: DateTime(2026, 9, 10),
        grade: 'again',
      );
      await h.answered(
        'facil',
        phase: CardPhase.newCard,
        at: DateTime(2026, 9, 9),
        grade: 'again',
      );
      await h.answered(
        'facil',
        phase: CardPhase.review,
        at: DateTime(2026, 9, 11),
      );
      // Una que solo se equivocó aprendiendo: ningún olvido.
      await h.card('novata', phase: CardPhase.learning);
      for (final phase in [CardPhase.newCard, CardPhase.learning]) {
        await h.answered(
          'novata',
          phase: phase,
          at: DateTime(2026, 9, 12),
          grade: 'again',
        );
      }
    });

    Future<List<String>> ordered(
      CardBrowserSort sort, {
      bool descending = false,
    }) => idsOf(CardBrowserQuery(sort: sort, descending: descending));

    test('por vencimiento, creación, facilidad, intervalo y olvidos', () async {
      final due = await ordered(CardBrowserSort.due);
      expect(due.first, 'dificil');
      expect(due.last, 'facil');

      final created = await ordered(CardBrowserSort.created);
      expect(created.first, 'facil');
      expect(created.last, 'dificil');

      final ease = await ordered(CardBrowserSort.ease);
      expect(ease.first, 'dificil');
      expect(ease.last, 'facil');

      final interval = await ordered(CardBrowserSort.interval);
      expect(interval.first, 'novata'); // se aprende: intervalo 0
      expect(interval[1], 'dificil');
      expect(interval.last, 'facil');

      final lapses = await ordered(CardBrowserSort.lapses, descending: true);
      expect(lapses.first, 'dificil');
      expect(lapses[1], 'facil');
      final fewest = await ordered(CardBrowserSort.lapses);
      expect(fewest.last, 'dificil');
      expect(fewest[fewest.length - 2], 'facil');
    });

    test(
      'al revés es exactamente el orden inverso, empates incluidos',
      () async {
        for (final sort in CardBrowserSort.values) {
          final up = await ordered(sort);
          final down = await ordered(sort, descending: true);
          expect(down, up.reversed.toList(), reason: '$sort');
        }
      },
    );

    test(
      'las páginas juntas son la lista entera, sin repetir ni saltear',
      () async {
        for (final sort in CardBrowserSort.values) {
          final query = CardBrowserQuery(sort: sort);
          final expected = await idsOf(query);
          final paged = <String>[];
          for (var offset = 0; ; offset += 3) {
            final page = (await browser.page(
              query,
              offset: offset,
              limit: 3,
            )).getOrElse((f) => fail('$f'));
            if (page.isEmpty) break;
            paged.addAll(page.map((r) => r.card.id));
          }
          expect(paged, expected, reason: '$sort');
          expect(paged.toSet(), hasLength(paged.length), reason: '$sort');
        }
      },
    );

    test('cada renglón trae el título del elemento y sus olvidos', () async {
      final rows = (await browser.page(
        const CardBrowserQuery(sort: CardBrowserSort.lapses, descending: true),
        offset: 0,
        limit: 2,
      )).getOrElse((f) => fail('$f'));
      expect(rows.map((r) => (r.card.id, r.lapses)), [
        ('dificil', 3),
        ('facil', 1),
      ]);
      expect(rows.first.itemTitle, 'Un elemento');
      expect(rows.first.card.easeFactor, 1.3);
    });

    test(
      'una página fuera de rango está vacía; una inválida es un fallo',
      () async {
        expect(
          (await browser.page(
            const CardBrowserQuery(),
            offset: 500,
            limit: 10,
          )).getOrElse((f) => fail('$f')),
          isEmpty,
        );
        expect(
          (await browser.page(
            const CardBrowserQuery(),
            offset: -1,
            limit: 10,
          )).isLeft(),
          isTrue,
        );
        expect(
          (await browser.page(
            const CardBrowserQuery(),
            offset: 0,
            limit: 0,
          )).isLeft(),
          isTrue,
        );
      },
    );
  });

  group('los bordes', () {
    test('sin ninguna tarjeta: todo da cero y vacío', () async {
      expect(
        (await browser.count(
          const CardBrowserQuery(),
        )).getOrElse((f) => fail('$f')),
        0,
      );
      expect(await idsOf(const CardBrowserQuery()), isEmpty);
      final counts = (await browser.statusCounts(
        const CardBrowserQuery(),
      )).getOrElse((f) => fail('$f'));
      expect(counts.values.every((n) => n == 0), isTrue);
      expect(
        (await browser.page(
          const CardBrowserQuery(),
          offset: 0,
          limit: 10,
        )).getOrElse((f) => fail('$f')),
        isEmpty,
      );
    });

    test('con una sola tarjeta', () async {
      await h.card('sola', phase: CardPhase.newCard);
      final rows = (await browser.page(
        const CardBrowserQuery(),
        offset: 0,
        limit: 50,
      )).getOrElse((f) => fail('$f'));
      expect(rows, hasLength(1));
      expect(rows.single.card.id, 'sola');
      expect(rows.single.lapses, 0);
      expect(await setOf(status(CardBrowserStatus.newCards)), {'sola'});
      expect(await setOf(status(CardBrowserStatus.mature)), isEmpty);
    });
  });

  group('volver a nueva', () {
    Future<void> trained(String id, {bool suspended = false}) async {
      await h.card(id, interval: 40, ease: 1.9, suspended: suspended);
      await (h.db.update(h.db.flashcards)..where((f) => f.id.equals(id))).write(
        FlashcardsCompanion(buriedUntil: Value(daysFromNow(1))),
      );
      await h.answered(id, phase: CardPhase.review, at: DateTime(2026, 9, 20));
    }

    test('deja la tarjeta como una nueva y conserva lo demás', () async {
      await trained('t1', suspended: true);
      await trained('t2');
      // Una que se estaba reaprendiendo: pierde el paso.
      await h.card('t3', phase: CardPhase.relearning, learningStep: 1);
      await h.card('intacta', interval: 40);

      final changed = (await browser.resetSchedule([
        't1',
        't2',
        't3',
        'fantasma',
      ])).getOrElse((f) => fail('$f'));
      expect(changed, 3);

      for (final id in ['t1', 't2', 't3']) {
        final row = await (h.db.select(
          h.db.flashcards,
        )..where((f) => f.id.equals(id))).getSingle();
        final card = flashcardFromRow(row);
        expect(card.phase, CardPhase.newCard, reason: id);
        expect(card.easeFactor, 2.5);
        expect(card.intervalDays, 0);
        expect(card.repetitions, 0);
        expect(card.learningStep, isNull);
        expect(card.lastReviewedAt, isNull);
        expect(card.buriedUntil, isNull);
        expect(card.dueAt, now);
        expect(card.front, 'Pregunta $id');
      }
      // La pausa se respeta; el historial no se reescribe.
      final t1 = await (h.db.select(
        h.db.flashcards,
      )..where((f) => f.id.equals('t1'))).getSingle();
      expect(t1.suspended, isTrue);
      expect(await h.db.select(h.db.reviewLogs).get(), hasLength(2));
      // Las que no se pidieron, intactas.
      final intacta = await (h.db.select(
        h.db.flashcards,
      )..where((f) => f.id.equals('intacta'))).getSingle();
      expect(intacta.intervalDays, 40);
    });

    test('sin ids no hace nada', () async {
      expect(
        (await browser.resetSchedule(const [])).getOrElse((f) => fail('$f')),
        0,
      );
    });

    test('con más tarjetas que un lote, todas cambian', () async {
      const total = CardBrowserRepositoryImpl.writeChunk * 2 + 17;
      await h.db.batch((b) {
        b.insertAll(h.db.flashcards, [
          for (var n = 0; n < total; n++)
            FlashcardsCompanion.insert(
              id: 'm$n',
              itemId: 'item',
              front: 'f',
              back: 'b',
              dueAt: daysFromNow(30),
              createdAt: DateTime(2026, 9),
              intervalDays: const Value(30),
              repetitions: const Value(4),
              lastReviewedAt: Value(DateTime(2026, 9)),
            ),
        ]);
      });
      final changed = (await browser.resetSchedule([
        for (var n = 0; n < total; n++) 'm$n',
      ])).getOrElse((f) => fail('$f'));
      expect(changed, total);
      expect(await setOf(status(CardBrowserStatus.newCards)), hasLength(total));
    });

    test('es todo o nada: si una falla, ninguna cambia', () async {
      // Una tarjeta del segundo lote que la base se niega a tocar.
      const total = CardBrowserRepositoryImpl.writeChunk + 10;
      await h.db.batch((b) {
        b.insertAll(h.db.flashcards, [
          for (var n = 0; n < total; n++)
            FlashcardsCompanion.insert(
              id: 'm${n.toString().padLeft(4, '0')}',
              itemId: 'item',
              front: 'f',
              back: 'b',
              dueAt: daysFromNow(30),
              createdAt: DateTime(2026, 9),
              intervalDays: const Value(30),
              repetitions: const Value(4),
              lastReviewedAt: Value(DateTime(2026, 9)),
            ),
        ]);
      });
      await h.db.customStatement(
        'CREATE TRIGGER trampa BEFORE UPDATE ON flashcards '
        "WHEN NEW.id = 'm${(total - 1).toString().padLeft(4, '0')}' "
        "BEGIN SELECT RAISE(ABORT, 'no'); END",
      );

      final result = await browser.resetSchedule([
        for (var n = 0; n < total; n++) 'm${n.toString().padLeft(4, '0')}',
      ]);

      expect(result.isLeft(), isTrue);
      expect(await setOf(status(CardBrowserStatus.newCards)), isEmpty);
      final untouched =
          await (h.db.selectOnly(h.db.flashcards)
                ..addColumns([h.db.flashcards.id.count()])
                ..where(h.db.flashcards.intervalDays.equals(30)))
              .map((r) => r.read(h.db.flashcards.id.count()))
              .getSingle();
      expect(untouched, total);
    });
  });

  group('borrar varias', () {
    test('se van con sus opciones y su historial; las demás quedan', () async {
      await h.card('x1');
      await h.card('x2');
      await h.card('queda');
      await h.answered(
        'x1',
        phase: CardPhase.review,
        at: DateTime(2026, 9, 20),
      );
      await h.answered(
        'queda',
        phase: CardPhase.review,
        at: DateTime(2026, 9, 20),
      );
      await h.db
          .into(h.db.flashcardOptions)
          .insert(
            FlashcardOptionsCompanion.insert(
              id: 'op1',
              flashcardId: 'x1',
              content: 'Una opción',
              isCorrect: true,
              position: 0,
            ),
          );

      final deleted = (await browser.deleteMany([
        'x1',
        'x2',
        'fantasma',
      ])).getOrElse((f) => fail('$f'));

      expect(deleted, 2);
      expect(await setOf(const CardBrowserQuery()), {'queda'});
      expect(await h.db.select(h.db.flashcardOptions).get(), isEmpty);
      final logs = await h.db.select(h.db.reviewLogs).get();
      expect(logs.map((l) => l.flashcardId), ['queda']);
    });

    test('es todo o nada: si una falla, ninguna se borra', () async {
      const total = CardBrowserRepositoryImpl.writeChunk + 10;
      await h.db.batch((b) {
        b.insertAll(h.db.flashcards, [
          for (var n = 0; n < total; n++)
            FlashcardsCompanion.insert(
              id: 'm${n.toString().padLeft(4, '0')}',
              itemId: 'item',
              front: 'f',
              back: 'b',
              dueAt: daysFromNow(30),
              createdAt: DateTime(2026, 9),
            ),
        ]);
      });
      await h.db.customStatement(
        'CREATE TRIGGER trampa BEFORE DELETE ON flashcards '
        "WHEN OLD.id = 'm${(total - 1).toString().padLeft(4, '0')}' "
        "BEGIN SELECT RAISE(ABORT, 'no'); END",
      );

      final result = await browser.deleteMany([
        for (var n = 0; n < total; n++) 'm${n.toString().padLeft(4, '0')}',
      ]);

      expect(result.isLeft(), isTrue);
      expect(
        (await browser.count(
          const CardBrowserQuery(),
        )).getOrElse((f) => fail('$f')),
        total,
      );
    });

    test('sin ids no hace nada', () async {
      await h.card('queda');
      expect(
        (await browser.deleteMany(const [])).getOrElse((f) => fail('$f')),
        0,
      );
      expect(await setOf(const CardBrowserQuery()), {'queda'});
    });
  });

  test('changes avisa cuando cambia una tarjeta', () async {
    final seen = <void>[];
    final sub = browser.changes().listen(seen.add);
    await pumpEventQueue();
    await h.card('nueva');
    await pumpEventQueue();
    expect(seen, isNotEmpty);
    await sub.cancel();
  });

  test('CardBrowserRow compara por valor', () async {
    await h.card('a');
    final rows = (await browser.page(
      const CardBrowserQuery(),
      offset: 0,
      limit: 1,
    )).getOrElse((f) => fail('$f'));
    final again = (await browser.page(
      const CardBrowserQuery(),
      offset: 0,
      limit: 1,
    )).getOrElse((f) => fail('$f'));
    expect(rows.single, again.single);
    expect(rows.single, isA<CardBrowserRow>());
    expect(rows.single.hashCode, again.single.hashCode);
  });
}
