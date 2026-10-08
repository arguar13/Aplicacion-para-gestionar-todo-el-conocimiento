import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// La cola de estudio contra SQLite real, en memoria (F31, decisión 69): qué
/// tarjeta toca, en qué orden, con qué límites y cuántas hay.
void main() {
  late AppDatabase db;
  late StudyRepositoryImpl study;
  late NotebookRepositoryImpl notebooks;
  // Las 10:00 del 8 de octubre: el día de estudio va de las 4:00 de hoy a las
  // 4:00 de mañana.
  var now = DateTime(2026, 10, 8, 10);
  const all = StudyScope.all();
  const limits = StudyLimits();

  DateTime minutesFromNow(int m) => now.add(Duration(minutes: m));
  DateTime daysFromNow(int d) => now.add(Duration(days: d));

  setUp(() async {
    now = DateTime(2026, 10, 8, 10);
    db = AppDatabase(NativeDatabase.memory());
    final telemetry = _MockTelemetry();
    final library = LibraryRepositoryImpl(
      database: db,
      telemetry: telemetry,
      files: InMemoryFileStore(),
    );
    notebooks = NotebookRepositoryImpl(
      database: db,
      telemetry: telemetry,
      ids: FakeIdGenerator(prefix: 'nb'),
      clock: () => now,
    );
    study = StudyRepositoryImpl(
      database: db,
      telemetry: telemetry,
      clock: () => now,
      resolver: StudyScopeResolver(library: library, notebooks: notebooks),
    );
    await insertItemRows(db, id: 'item', title: 'Un elemento');
  });

  tearDown(() => db.close());

  /// Una tarjeta, directo en la tabla: en la etapa que se pida.
  Future<void> card(
    String id, {
    String itemId = 'item',
    CardPhase phase = CardPhase.review,
    DateTime? dueAt,
    DateTime? createdAt,
    bool suspended = false,
    DateTime? buriedUntil,
    String? groupId,
    int? learningStep,
  }) {
    final (repetitions, interval, step, reviewed) = switch (phase) {
      CardPhase.newCard => (0, 0, null, null),
      CardPhase.learning => (0, 0, learningStep ?? 0, DateTime(2026, 10, 8, 9)),
      CardPhase.relearning => (
        0,
        1,
        learningStep ?? 0,
        DateTime(2026, 10, 8, 9),
      ),
      CardPhase.review => (3, 15, null, DateTime(2026, 9, 20)),
    };
    return db
        .into(db.flashcards)
        .insert(
          FlashcardsCompanion.insert(
            id: id,
            itemId: itemId,
            front: 'Pregunta $id',
            back: 'Respuesta $id',
            dueAt: dueAt ?? now,
            createdAt: createdAt ?? DateTime(2026, 9),
            repetitions: Value(repetitions),
            intervalDays: Value(interval),
            learningStep: Value(step),
            lastReviewedAt: Value(reviewed),
            suspended: Value(suspended),
            buriedUntil: Value(buriedUntil),
            groupId: Value(groupId),
          ),
        );
  }

  var logCounter = 0;

  /// Una respuesta ya dada, en el log. Si la tarjeta no existe se crea una
  /// PAUSADA para colgarle el renglón: no entra en ninguna sesión.
  Future<void> answered(
    String cardId, {
    required CardPhase phase,
    required DateTime at,
  }) async {
    final exists = await (db.select(
      db.flashcards,
    )..where((f) => f.id.equals(cardId))).getSingleOrNull();
    if (exists == null) {
      await card(cardId, suspended: true, dueAt: DateTime(2030));
    }
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            id: 'log-${logCounter++}',
            flashcardId: cardId,
            reviewedAt: at,
            grade: 'good',
            quality: 4,
            intervalBefore: 0,
            intervalAfter: 0,
            easeBefore: 2.5,
            easeAfter: 2.5,
            deviceId: 'dispositivo',
            phaseBefore: Value(phase),
          ),
        );
  }

  Future<StudyNext> next({
    StudyScope scope = all,
    StudyLimits limit = limits,
    Duration learnAhead = Duration.zero,
  }) async => (await study.next(
    scope,
    limits: limit,
    learnAhead: learnAhead,
  )).getOrElse((f) => fail('$f'));

  Future<String> nextId({
    StudyScope scope = all,
    StudyLimits limit = limits,
  }) async {
    final result = await next(scope: scope, limit: limit);
    expect(result, isA<StudyNextCard>());
    return (result as StudyNextCard).card.id;
  }

  Future<StudyCounts> counts({
    StudyScope scope = all,
    StudyLimits limit = limits,
  }) async =>
      (await study.counts(scope, limits: limit)).getOrElse((f) => fail('$f'));

  group('el orden de la sesión', () {
    test('primero lo que se aprende y ya volvió, después los repasos, al '
        'final las nuevas', () async {
      await card('nueva', phase: CardPhase.newCard);
      await card('repaso', dueAt: daysFromNow(-2));
      await card(
        'aprendiendo',
        phase: CardPhase.learning,
        dueAt: minutesFromNow(-1),
      );

      expect(await nextId(), 'aprendiendo');
      await db.delete(db.flashcards).go(); // vaciar y probar sin la primera
      await card('nueva', phase: CardPhase.newCard);
      await card('repaso', dueAt: daysFromNow(-2));
      expect(await nextId(), 'repaso');
      await (db.delete(
        db.flashcards,
      )..where((f) => f.id.equals('repaso'))).go();
      expect(await nextId(), 'nueva');
    });

    test('el tipo de cada una queda dicho', () async {
      await card('nueva', phase: CardPhase.newCard);
      await card('repaso', dueAt: daysFromNow(-1));
      await card(
        'aprendiendo',
        phase: CardPhase.relearning,
        dueAt: minutesFromNow(-3),
      );

      final first = await next() as StudyNextCard;
      expect(first.queue, StudyQueueKind.learning);
      expect(first.early, isFalse);
      await (db.delete(
        db.flashcards,
      )..where((f) => f.id.equals('aprendiendo'))).go();
      expect((await next() as StudyNextCard).queue, StudyQueueKind.review);
      await (db.delete(
        db.flashcards,
      )..where((f) => f.id.equals('repaso'))).go();
      expect((await next() as StudyNextCard).queue, StudyQueueKind.newCard);
    });

    test(
      'los repasos van del más atrasado al menos, y los empates por id',
      () async {
        await card('b', dueAt: daysFromNow(-1));
        await card('a', dueAt: daysFromNow(-1));
        await card('c', dueAt: daysFromNow(-5));
        await card('d', dueAt: minutesFromNow(-10));

        final order = <String>[];
        for (var i = 0; i < 4; i++) {
          final id = await nextId();
          order.add(id);
          await (db.delete(db.flashcards)..where((f) => f.id.equals(id))).go();
        }

        expect(order, ['c', 'a', 'b', 'd']);
      },
    );

    test('las nuevas van en el orden en que se crearon', () async {
      await card(
        'tarde',
        phase: CardPhase.newCard,
        createdAt: DateTime(2026, 9, 3),
      );
      await card(
        'temprano',
        phase: CardPhase.newCard,
        createdAt: DateTime(2026, 9),
      );
      await card(
        'medio',
        phase: CardPhase.newCard,
        createdAt: DateTime(2026, 9, 2),
      );

      final order = <String>[];
      for (var i = 0; i < 3; i++) {
        final id = await nextId();
        order.add(id);
        await (db.delete(db.flashcards)..where((f) => f.id.equals(id))).go();
      }

      expect(order, ['temprano', 'medio', 'tarde']);
    });

    test('los de aprendizaje, el que venció antes primero', () async {
      await card('b', phase: CardPhase.learning, dueAt: minutesFromNow(-2));
      await card('a', phase: CardPhase.learning, dueAt: minutesFromNow(-9));

      expect(await nextId(), 'a');
    });
  });

  group('lo que vence hoy', () {
    test(
      'un repaso que vence más tarde HOY entra; uno de mañana, no',
      () async {
        // Hasta las 4:00 de mañana es el día de estudio de hoy.
        await card('hoy-tarde', dueAt: DateTime(2026, 10, 8, 23));
        await card('madrugada', dueAt: DateTime(2026, 10, 9, 3, 59));
        await card('manana', dueAt: DateTime(2026, 10, 9, 4, 1));

        final first = await nextId();
        await (db.delete(db.flashcards)..where((f) => f.id.equals(first))).go();
        final second = await nextId();
        await (db.delete(
          db.flashcards,
        )..where((f) => f.id.equals(second))).go();

        expect({first, second}, {'hoy-tarde', 'madrugada'});
        expect(await next(), isA<StudyNextDone>());
      },
    );

    test(
      'lo que vence a las 4:00 de mañana en punto es del día siguiente',
      () async {
        await card('justo', dueAt: DateTime(2026, 10, 9, 4));

        expect(await next(), isA<StudyNextDone>());
      },
    );
  });

  group('lo que se aprende en minutos', () {
    test(
      'una que vuelve en 5 minutos espera: la sesión avisa cuándo',
      () async {
        await card('l', phase: CardPhase.learning, dueAt: minutesFromNow(5));

        final result = await next();

        expect(result, isA<StudyNextWait>());
        final wait = result as StudyNextWait;
        expect(wait.until, minutesFromNow(5));
        expect(wait.learningLeft, 1);
      },
    );

    test('con margen para adelantarse, se trae antes de su hora', () async {
      await card('l', phase: CardPhase.learning, dueAt: minutesFromNow(5));

      final result = await next(learnAhead: const Duration(minutes: 20));

      final shown = result as StudyNextCard;
      expect(shown.card.id, 'l');
      expect(shown.early, isTrue);
      expect(shown.queue, StudyQueueKind.learning);
    });

    test('el margen justo: a exactamente learnAhead ya se trae', () async {
      await card('l', phase: CardPhase.learning, dueAt: minutesFromNow(20));

      expect(
        await next(learnAhead: const Duration(minutes: 20)),
        isA<StudyNextCard>(),
      );
      expect(
        await next(learnAhead: const Duration(minutes: 19)),
        isA<StudyNextWait>(),
      );
    });

    test(
      'hay otra cosa para hacer: la que vuelve más tarde no se adelanta',
      () async {
        await card('l', phase: CardPhase.learning, dueAt: minutesFromNow(5));
        await card('repaso', dueAt: daysFromNow(-1));

        final result = await next(learnAhead: const Duration(minutes: 20));

        expect((result as StudyNextCard).card.id, 'repaso');
      },
    );

    test(
      'una que vuelve mañana (pasado el día de estudio) no cuenta hoy',
      () async {
        await card('l', phase: CardPhase.learning, dueAt: daysFromNow(1));

        expect(await next(), isA<StudyNextDone>());
      },
    );

    test('espera con el primero que vuelve, y cuenta los que quedan', () async {
      await card('tarde', phase: CardPhase.learning, dueAt: minutesFromNow(30));
      await card('pronto', phase: CardPhase.learning, dueAt: minutesFromNow(8));

      final wait = await next() as StudyNextWait;

      expect(wait.until, minutesFromNow(8));
      expect(wait.learningLeft, 2);
    });
  });

  group('los límites por día', () {
    test(
      'las nuevas se cortan en el límite, contando las de HOY ya hechas',
      () async {
        for (var i = 0; i < 5; i++) {
          await card(
            'n$i',
            phase: CardPhase.newCard,
            createdAt: DateTime(2026, 9, 1 + i),
          );
        }
        const two = StudyLimits(newPerDay: 2);
        await answered(
          'hecha1',
          phase: CardPhase.newCard,
          at: DateTime(2026, 10, 8, 8),
        );

        // Una hecha hoy: queda una por hacer.
        expect(await counts(limit: two).then((c) => c.newCards), 1);
        expect(await nextId(limit: two), 'n0');

        await answered(
          'hecha2',
          phase: CardPhase.newCard,
          at: DateTime(2026, 10, 8, 9),
        );

        final result = await next(limit: two);
        expect(result, isA<StudyNextDone>());
        final done = result as StudyNextDone;
        expect(done.hitLimit, isTrue);
        expect(done.newBeyondLimit, 5);
        expect(done.reviewsBeyondLimit, 0);
      },
    );

    test('los repasos también, y el límite de uno no toca al otro', () async {
      await card('r1', dueAt: daysFromNow(-3));
      await card('r2', dueAt: daysFromNow(-2));
      await card('r3', dueAt: daysFromNow(-1));
      await card('nueva', phase: CardPhase.newCard);
      const limitReviews = StudyLimits(reviewsPerDay: 2);
      await answered(
        'x',
        phase: CardPhase.review,
        at: DateTime(2026, 10, 8, 5),
      );
      await answered(
        'y',
        phase: CardPhase.review,
        at: DateTime(2026, 10, 8, 6),
      );

      // Los repasos llegaron al tope; las nuevas siguen disponibles.
      expect(await nextId(limit: limitReviews), 'nueva');
      await (db.delete(db.flashcards)..where((f) => f.id.equals('nueva'))).go();
      final result = await next(limit: limitReviews) as StudyNextDone;
      expect(result.reviewsBeyondLimit, 3);
      expect(result.hitLimit, isTrue);
    });

    test(
      'lo que se aprende y reaprende no tiene tope, ni cuenta contra él',
      () async {
        await card('l', phase: CardPhase.learning, dueAt: minutesFromNow(-1));
        await card(
          'rl',
          phase: CardPhase.relearning,
          dueAt: minutesFromNow(-1),
        );
        // Las respuestas de los pasos cortos no cuentan.
        await answered(
          'l',
          phase: CardPhase.learning,
          at: DateTime(2026, 10, 8, 8),
        );
        await answered(
          'rl',
          phase: CardPhase.relearning,
          at: DateTime(2026, 10, 8, 8),
        );
        const none = StudyLimits(newPerDay: 0, reviewsPerDay: 0);

        expect(await nextId(limit: none), isIn(['l', 'rl']));
        final c = await counts(limit: none);
        expect(c.learning, 2);
        expect(c.newDoneToday, 0);
        expect(c.reviewsDoneToday, 0);
      },
    );

    test('un límite en 0 deja ese tipo fuera del día', () async {
      await card('nueva', phase: CardPhase.newCard);

      final result = await next(limit: const StudyLimits(newPerDay: 0));

      expect(result, isA<StudyNextDone>());
      expect((result as StudyNextDone).newBeyondLimit, 1);
    });

    test('ampliar el límite por hoy trae más', () async {
      await card('n1', phase: CardPhase.newCard);
      await answered(
        'hecha',
        phase: CardPhase.newCard,
        at: DateTime(2026, 10, 8, 7),
      );
      const one = StudyLimits(newPerDay: 1);

      expect(await next(limit: one), isA<StudyNextDone>());
      expect(await nextId(limit: one.extendedBy(newCards: 5)), 'n1');
    });

    test(
      'lo de ayer no cuenta hoy: el día cambia a las 4:00, no a medianoche',
      () async {
        await card('n1', phase: CardPhase.newCard);
        const one = StudyLimits(newPerDay: 1);
        // Hecha ayer a las 23:00 y hoy a las 3:30: ambas del día de estudio de
        // ayer. Hoy, a las 10:00, el límite está entero.
        await answered(
          'a',
          phase: CardPhase.newCard,
          at: DateTime(2026, 10, 7, 23),
        );
        await answered(
          'b',
          phase: CardPhase.newCard,
          at: DateTime(2026, 10, 8, 3, 30),
        );

        expect(await nextId(limit: one), 'n1');

        // Hecha a las 4:00 en punto: ya es de hoy.
        await answered(
          'c',
          phase: CardPhase.newCard,
          at: DateTime(2026, 10, 8, 4),
        );
        expect(await next(limit: one), isA<StudyNextDone>());
      },
    );

    test('de madrugada, lo de la noche anterior sigue siendo "hoy"', () async {
      now = DateTime(2026, 10, 8, 1, 30);
      await card('n1', phase: CardPhase.newCard, createdAt: DateTime(2026, 9));
      const one = StudyLimits(newPerDay: 1);
      await answered(
        'a',
        phase: CardPhase.newCard,
        at: DateTime(2026, 10, 7, 23),
      );

      expect(await next(limit: one), isA<StudyNextDone>());

      // Pasadas las 4:00 se renuevan.
      now = DateTime(2026, 10, 8, 4, 1);
      expect(await nextId(limit: one), 'n1');
    });
  });

  group('lo que queda afuera', () {
    test('una tarjeta pausada no entra, y al reactivarla vuelve', () async {
      await card('r', dueAt: daysFromNow(-1), suspended: true);
      await card('n', phase: CardPhase.newCard, suspended: true);
      await card(
        'l',
        phase: CardPhase.learning,
        dueAt: minutesFromNow(-1),
        suspended: true,
      );

      expect(await next(), isA<StudyNextDone>());
      expect((await counts()).total, 0);

      await db
          .update(db.flashcards)
          .write(const FlashcardsCompanion(suspended: Value(false)));
      expect((await counts()).total, 3);
    });

    test('una pospuesta no entra hasta que llega su fecha', () async {
      await card(
        'r',
        dueAt: daysFromNow(-1),
        buriedUntil: DateTime(2026, 10, 9, 4),
      );

      expect(await next(), isA<StudyNextDone>());

      // A las 4:00 de mañana (y no antes) vuelve.
      now = DateTime(2026, 10, 9, 3, 59);
      expect(await next(), isA<StudyNextDone>());
      now = DateTime(2026, 10, 9, 4);
      expect(await nextId(), 'r');
    });

    test('una pospuesta con fecha ya pasada vuelve sola', () async {
      await card(
        'r',
        dueAt: daysFromNow(-1),
        buriedUntil: DateTime(2026, 10, 8, 4),
      );

      expect(await nextId(), 'r');
    });

    test(
      'las de un elemento en la papelera no entran, y al restaurarlo vuelven',
      () async {
        await insertItemRows(db, id: 'borrado', title: 'Borrado');
        await card('r', itemId: 'borrado', dueAt: daysFromNow(-1));
        await card('n', itemId: 'borrado', phase: CardPhase.newCard);
        await card(
          'l',
          itemId: 'borrado',
          phase: CardPhase.learning,
          dueAt: minutesFromNow(-1),
        );
        await (db.update(db.knowledgeEntries)
              ..where((e) => e.id.equals('borrado')))
            .write(KnowledgeEntriesCompanion(deletedAt: Value(now)));

        expect(await next(), isA<StudyNextDone>());
        expect((await counts()).total, 0);

        await (db.update(db.knowledgeEntries)
              ..where((e) => e.id.equals('borrado')))
            .write(const KnowledgeEntriesCompanion(deletedAt: Value(null)));
        expect((await counts()).total, 3);
      },
    );

    test(
      'una sola hermana por grupo por día: contestar una esconde a las otras',
      () async {
        // "ida" ya se contestó hoy y está en su primer paso; "vuelta" es su
        // hermana nueva; "sola" no tiene hermanas.
        await card(
          'ida',
          phase: CardPhase.learning,
          groupId: 'g',
          dueAt: minutesFromNow(30),
        );
        await card('vuelta', phase: CardPhase.newCard, groupId: 'g');
        await card(
          'sola',
          phase: CardPhase.newCard,
          createdAt: DateTime(2026, 9, 3),
        );
        expect((await counts()).newAvailable, 2);

        await answered(
          'ida',
          phase: CardPhase.newCard,
          at: DateTime(2026, 10, 8, 9),
        );

        expect(await nextId(), 'sola');
        expect((await counts()).newAvailable, 1);
      },
    );

    test('las hermanas de una tarjeta contestada ayer sí entran hoy', () async {
      await card('ida', groupId: 'g', dueAt: daysFromNow(1));
      await card('vuelta', groupId: 'g', dueAt: daysFromNow(-1));
      await answered(
        'ida',
        phase: CardPhase.review,
        at: DateTime(2026, 10, 7, 12),
      );

      expect(await nextId(), 'vuelta');
    });

    test(
      'al deshacer la respuesta (se borra su renglón) la hermana vuelve',
      () async {
        await card('ida', groupId: 'g', dueAt: daysFromNow(1));
        await card('vuelta', groupId: 'g', dueAt: daysFromNow(-1));
        await answered(
          'ida',
          phase: CardPhase.review,
          at: DateTime(2026, 10, 8, 9),
        );

        expect(await next(), isA<StudyNextDone>());

        await db.delete(db.reviewLogs).go();
        expect(await nextId(), 'vuelta');
      },
    );

    test(
      'una hermana en aprendizaje sí se muestra aunque otra se haya contestado',
      () async {
        await card(
          'ida',
          phase: CardPhase.learning,
          groupId: 'g',
          dueAt: minutesFromNow(-1),
        );
        await card('vuelta', groupId: 'g', dueAt: daysFromNow(-1));
        await answered(
          'vuelta',
          phase: CardPhase.review,
          at: DateTime(2026, 10, 8, 9),
        );

        expect(await nextId(), 'ida');
      },
    );
  });

  group('los recortes', () {
    setUp(() async {
      await insertItemRows(db, id: 'roma', title: 'Roma');
      await insertItemRows(db, id: 'grecia', title: 'Grecia');
      await insertItemRows(db, id: 'suelto', title: 'Suelto');
      for (final (id, itemId) in [
        ('c-roma', 'roma'),
        ('c-grecia', 'grecia'),
        ('c-suelto', 'suelto'),
        ('c-item', 'item'),
      ]) {
        await card(id, itemId: itemId, dueAt: daysFromNow(-1));
      }
    });

    Future<Set<String>> studied(StudyScope scope) async {
      final ids = <String>{};
      while (true) {
        final result = await next(scope: scope);
        if (result is! StudyNextCard) return ids;
        ids.add(result.card.id);
        await (db.delete(
          db.flashcards,
        )..where((f) => f.id.equals(result.card.id))).go();
      }
    }

    test('todo: todas', () async {
      expect(await studied(all), {'c-roma', 'c-grecia', 'c-suelto', 'c-item'});
    });

    test('un elemento: solo las suyas', () async {
      expect(await studied(const StudyScope.item('roma')), {'c-roma'});
    });

    test('un espacio: los elementos de ese espacio', () async {
      await db
          .into(db.spaces)
          .insert(
            SpacesCompanion.insert(
              id: 'historia',
              name: 'Historia',
              createdAt: now,
            ),
          );
      await (db.update(db.knowledgeEntries)
            ..where((e) => e.id.isIn(['roma', 'grecia'])))
          .write(const KnowledgeEntriesCompanion(spaceId: Value('historia')));

      expect(await studied(const StudyScope.space('historia')), {
        'c-roma',
        'c-grecia',
      });
    });

    Future<void> value(String id, String name, {String? parentId}) => db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: 'tema',
            value: name,
            createdAt: now,
            parentId: Value(parentId),
          ),
        );

    Future<void> assign(String itemId, String valueId) => db
        .into(db.itemPropertyValues)
        .insert(
          ItemPropertyValuesCompanion.insert(
            itemId: itemId,
            propertyValueId: valueId,
          ),
        );

    test('un tema o etiqueta incluye sus ramas, no sus hermanos', () async {
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'tema',
              name: 'Categoría de prueba',
              createdAt: now,
            ),
          );
      await value('antigua', 'Antigüedad');
      await value('rom', 'Roma', parentId: 'antigua');
      await value('rep', 'República', parentId: 'rom');
      await value('gre', 'Grecia', parentId: 'antigua');
      await assign('roma', 'rom');
      await assign('item', 'rep');
      await assign('grecia', 'gre');

      expect(await studied(const StudyScope.value('rom')), {
        'c-roma',
        'c-item',
      }, reason: 'Roma incluye República');
      expect(await studied(const StudyScope.value('gre')), {'c-grecia'});
    });

    test('un cuaderno manual: los elementos que tiene hoy', () async {
      final book = await notebooks.create(
        name: 'Para el examen',
        mode: NotebookMode.manual,
      );
      await notebooks.addItem(notebookId: book.id, itemId: 'roma');
      await notebooks.addItem(notebookId: book.id, itemId: 'suelto');

      expect(await studied(StudyScope.notebook(book.id)), {
        'c-roma',
        'c-suelto',
      });

      // Es lo que es HOY: sacar uno lo saca de la cola.
      await notebooks.removeItem(notebookId: book.id, itemId: 'suelto');
      await db
          .into(db.flashcards)
          .insert(
            FlashcardsCompanion.insert(
              id: 'otra',
              itemId: 'roma',
              front: 'f',
              back: 'b',
              dueAt: daysFromNow(-1),
              createdAt: DateTime(2026, 9),
            ),
          );
      expect(await studied(StudyScope.notebook(book.id)), {'otra'});
    });

    test('un cuaderno por consulta: lo que la consulta encuentra', () async {
      await db
          .into(db.spaces)
          .insert(SpacesCompanion.insert(id: 'sp', name: 'Sp', createdAt: now));
      await (db.update(db.knowledgeEntries)
            ..where((e) => e.id.equals('grecia')))
          .write(const KnowledgeEntriesCompanion(spaceId: Value('sp')));
      final book = await notebooks.create(
        name: 'Por espacio',
        mode: NotebookMode.query,
        query: const LibraryQuery(spaceId: 'sp'),
      );

      expect(await studied(StudyScope.notebook(book.id)), {'c-grecia'});
    });

    test('un recorte sin ningún elemento no tiene nada', () async {
      final empty = await notebooks.create(
        name: 'Vacío',
        mode: NotebookMode.manual,
      );

      expect(
        await next(scope: StudyScope.notebook(empty.id)),
        isA<StudyNextDone>(),
      );
      final c = await counts(scope: StudyScope.notebook(empty.id));
      expect(c.total, 0);
      expect(c.isEmpty, isTrue);
    });

    test(
      'un cuaderno que ya no existe es un fallo claro, no un cuelgue',
      () async {
        final result = await study.next(
          const StudyScope.notebook('fantasma'),
          limits: limits,
        );

        expect(result.isLeft(), isTrue);
      },
    );

    test(
      'el recorte filtra lo que entra, pero los límites son del día entero',
      () async {
        await card('n-roma', itemId: 'roma', phase: CardPhase.newCard);
        await card('n-grecia', itemId: 'grecia', phase: CardPhase.newCard);
        // Hoy ya se hizo una nueva, en otro recorte.
        await answered(
          'c-item',
          phase: CardPhase.newCard,
          at: DateTime(2026, 10, 8, 7),
        );
        const one = StudyLimits(newPerDay: 1);

        final c = await counts(
          scope: const StudyScope.item('roma'),
          limit: one,
        );
        expect(c.newDoneToday, 1);
        expect(c.newCards, 0);
        expect(c.newAvailable, 1);
      },
    );
  });

  group('los conteos', () {
    test('nuevas, aprendiendo y por repasar, con sus límites', () async {
      for (var i = 0; i < 30; i++) {
        await card('n$i', phase: CardPhase.newCard);
      }
      for (var i = 0; i < 250; i++) {
        await card('r$i', dueAt: daysFromNow(-1));
      }
      await card('l1', phase: CardPhase.learning, dueAt: minutesFromNow(-1));
      await card('l2', phase: CardPhase.relearning, dueAt: minutesFromNow(15));

      final c = await counts();

      expect(c.newCards, 20);
      expect(c.newAvailable, 30);
      expect(c.newBeyondLimit, 10);
      expect(c.reviews, 200);
      expect(c.reviewsAvailable, 250);
      expect(c.reviewsBeyondLimit, 50);
      expect(c.learning, 2);
      expect(c.total, 222);
      expect(c.isEmpty, isFalse);
      expect(c.nextLearningDue, minutesFromNow(-1));
    });

    test('lo ya hecho hoy se descuenta', () async {
      for (var i = 0; i < 25; i++) {
        await card('n$i', phase: CardPhase.newCard);
      }
      for (var i = 0; i < 5; i++) {
        await answered(
          'x',
          phase: CardPhase.newCard,
          at: DateTime(2026, 10, 8, 6),
        );
      }

      final c = await counts();

      expect(c.newDoneToday, 5);
      expect(c.newCards, 15);
    });

    test('sin tarjetas es vacío', () async {
      final c = await counts();

      expect(c, const StudyCounts.empty());
      expect(c.total, 0);
      expect(c.nextLearningDue, isNull);
    });

    test('lo que vence mañana no cuenta hoy', () async {
      await card('r', dueAt: daysFromNow(1));
      await card('r2', dueAt: DateTime(2026, 10, 9, 4));

      expect((await counts()).reviews, 0);
    });

    test(
      'coincide con lo que next() va entregando, en cualquier estado',
      () async {
        // Una mezcla de todo.
        await card('n1', phase: CardPhase.newCard);
        await card('n2', phase: CardPhase.newCard, groupId: 'g');
        await card('n3', phase: CardPhase.newCard, groupId: 'g');
        await card('r1', dueAt: daysFromNow(-2));
        await card('r2', dueAt: daysFromNow(3));
        await card('r3', dueAt: daysFromNow(-1), suspended: true);
        await card('l1', phase: CardPhase.learning, dueAt: minutesFromNow(-4));
        await card('l2', phase: CardPhase.learning, dueAt: minutesFromNow(4));
        const tight = StudyLimits(newPerDay: 2, reviewsPerDay: 5);

        final expected = (await counts(limit: tight)).total;
        var served = 0;
        while (true) {
          final result = await next(
            limit: tight,
            learnAhead: const Duration(hours: 1),
          );
          if (result is! StudyNextCard) break;
          served++;
          // "Contestarla": sale del día.
          await (db.update(
            db.flashcards,
          )..where((f) => f.id.equals(result.card.id))).write(
            FlashcardsCompanion(
              dueAt: Value(daysFromNow(9)),
              learningStep: const Value(null),
            ),
          );
          await answered(result.card.id, phase: result.card.phase, at: now);
        }

        expect(served, expected);
      },
    );
  });

  group('watchCounts', () {
    test('emite lo que hay y se actualiza solo cuando algo cambia', () async {
      final queue = StreamQueue(study.watchCounts(all, limits: limits));
      addTearDown(queue.cancel);
      expect((await queue.next).total, 0);

      await card('r', dueAt: daysFromNow(-1));
      expect((await queue.next.timeout(const Duration(seconds: 5))).reviews, 1);

      await db
          .update(db.flashcards)
          .write(const FlashcardsCompanion(suspended: Value(true)));
      expect((await queue.next.timeout(const Duration(seconds: 5))).total, 0);
    });
  });
}
