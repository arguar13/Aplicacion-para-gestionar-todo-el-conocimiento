import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_scope_sql.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_stats_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';
import 'package:sinapsis/features/habit/data/repositories/review_history_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// Cuenta las consultas que se corren, para medir la estructura y no el
/// reloj: cuántas lecturas hace un cálculo entero.
class _SelectCounter extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return super.runSelect(executor, statement, args);
  }
}

/// Las estadísticas y el historial con 6.000 tarjetas en 600 elementos y
/// 24.000 repasos (F43, M16 y M17), midiendo la ESTRUCTURA —qué plan elige
/// SQLite y cuántas lecturas se hacen—, nunca milisegundos: un recorrido
/// completo del registro no se nota con cien repasos y arruina la pantalla con
/// cien mil, y esto lo atrapa con cualquiera de los dos tamaños.
void main() {
  const cards = 6000;
  const items = 600;
  const logs = 24000;
  final now = DateTime(2026, 10, 8, 10);
  final counter = _SelectCounter();
  late AppDatabase db;
  late ReviewStatsRepositoryImpl stats;
  late ReviewHistoryRepositoryImpl history;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory().interceptWith(counter));
    final telemetry = _MockTelemetry();
    final resolver = StudyScopeResolver(
      library: LibraryRepositoryImpl(
        database: db,
        telemetry: telemetry,
        files: InMemoryFileStore(),
      ),
      notebooks: NotebookRepositoryImpl(
        database: db,
        processed: ProcessedRepositoryImpl(
          database: db,
          telemetry: telemetry,
          files: InMemoryFileStore(),
        ),
        telemetry: telemetry,
        ids: FakeIdGenerator(prefix: 'nb'),
        clock: () => now,
      ),
    );
    stats = ReviewStatsRepositoryImpl(
      database: db,
      telemetry: telemetry,
      clock: () => now,
      resolver: resolver,
    );
    history = ReviewHistoryRepositoryImpl(
      database: db,
      telemetry: telemetry,
      clock: () => now,
      resolver: resolver,
    );
    for (var n = 0; n < items; n++) {
      await insertItemRows(db, id: 'e$n', title: 'Elemento $n');
    }
    await db.batch((b) {
      b.insertAll(db.flashcards, [
        for (var n = 0; n < cards; n++)
          FlashcardsCompanion.insert(
            id: 'c${n.toString().padLeft(5, '0')}',
            itemId: 'e${n % items}',
            front: 'Pregunta $n',
            back: 'Respuesta $n',
            dueAt: now.add(Duration(hours: (n * 7) % (24 * 120) - 48)),
            createdAt: DateTime(2026).add(Duration(minutes: n * 37)),
            intervalDays: Value(switch (n % 10) {
              0 || 1 => 0,
              2 => 3,
              3 => 10,
              _ => 25 + n % 200,
            }),
            easeFactor: Value(1.3 + (n % 18) / 10),
            repetitions: Value(n % 10 < 2 ? 0 : 4),
            lastReviewedAt: n % 10 < 2 ? const Value(null) : Value(now),
            learningStep: n % 25 == 0 ? const Value(0) : const Value(null),
            suspended: Value(n % 40 == 0),
          ),
      ]);
    });
    await db.batch((b) {
      b.insertAll(db.reviewLogs, [
        for (var n = 0; n < logs; n++)
          ReviewLogsCompanion.insert(
            id: 'l$n',
            flashcardId: 'c${(n % cards).toString().padLeft(5, '0')}',
            reviewedAt: now.subtract(
              Duration(minutes: n * 23 % (60 * 24 * 400)),
            ),
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
              2 => CardPhase.relearning,
              _ => CardPhase.review,
            }),
          ),
      ]);
    });
  });

  tearDownAll(() => db.close());

  /// Los pasos del plan de [query] que leen una tabla.
  Future<List<String>> planOf(ScopedQuery query) async {
    final rows = await db
        .customSelect(
          'EXPLAIN QUERY PLAN ${query.sql}',
          variables: query.variables,
        )
        .get();
    return [
      for (final row in rows)
        if (row.read<String>('detail') case final d
            when d.startsWith('SCAN') || d.startsWith('SEARCH'))
          d,
    ];
  }

  /// Si el plan recorre TODA la tabla de alias [alias]. Se compara la palabra
  /// entera: `SCAN rl` no es `SCAN rlx`.
  bool scans(List<String> plan, String alias) =>
      plan.any((step) => RegExp('^SCAN $alias(?![A-Za-z0-9_])').hasMatch(step));

  final scoped = ReviewScopeSql(itemIds: [for (var n = 0; n < 12; n++) 'e$n']);
  final everything = ReviewScopeSql();
  final queries = <String, ScopedQuery Function(ReviewScopeSql)>{
    'activity': (s) => s.activity,
    'today': (s) => s.today(DateTime(2026, 10, 8, 4)),
    'cardShape': (s) => s.cardShape,
    'added': (s) => s.added,
    'forecast': (s) => s.forecast(
      today: DateTime(2026, 10, 8, 4),
      now: now,
      ends: [
        for (var k = 1; k <= kForecastDays; k++) DateTime(2026, 10, 8 + k, 4),
      ],
    ),
    'difficult': (s) => s.difficult(minReviews: 3, limit: 10),
  };

  group('con un recorte, nada recorre una tabla entera', () {
    for (final MapEntry(key: name, value: query) in queries.entries) {
      test(name, () async {
        final plan = await planOf(query(scoped));
        expect(scans(plan, 'f'), isFalse, reason: plan.join('\n'));
        expect(scans(plan, 'rl'), isFalse, reason: plan.join('\n'));
        expect(scans(plan, 'i'), isFalse, reason: plan.join('\n'));
        expect(
          plan.any((s) => s.contains('idx_flashcards_item')),
          isTrue,
          reason: plan.join('\n'),
        );
        if (query(scoped).sql.contains('review_log')) {
          expect(
            plan.any((s) => s.contains('idx_review_log_flashcard')),
            isTrue,
            reason: plan.join('\n'),
          );
        }
      });
    }
  });

  group('sin recorte, se recorren las tarjetas y no el registro', () {
    for (final MapEntry(key: name, value: query) in queries.entries) {
      test(name, () async {
        final plan = await planOf(query(everything));
        expect(scans(plan, 'rl'), isFalse, reason: plan.join('\n'));
      });
    }
  });

  test(
    'las estadísticas son seis lecturas, chico o grande el recorte',
    () async {
      Future<int> selectsOf(StudyScope scope) async {
        counter.selects = 0;
        (await stats.load(scope: scope)).getOrElse((f) => fail('$f'));
        return counter.selects;
      }

      final one = await selectsOf(const StudyScope.item('e1'));
      final all = await selectsOf(const StudyScope.all());
      expect(one, 6);
      expect(all, 6);
    },
  );

  test('el historial son dos lecturas, chico o grande el recorte', () async {
    counter.selects = 0;
    await history.current(const StudyScope.item('e1'));
    expect(counter.selects, 2);
    counter.selects = 0;
    await history.current(const StudyScope.all());
    expect(counter.selects, 2);
  });

  test('con miles de repasos, los números cierran', () async {
    final s = (await stats.load(
      scope: const StudyScope.all(),
    )).getOrElse((f) => fail('$f'));
    expect(s.distribution.total, cards);
    expect(s.forecast.days, hasLength(kForecastDays));
    expect(s.buttonsFor(StatsPeriod.all).overall.total, logs);
    expect(
      s.buttonsFor(StatsPeriod.days30).overall.total,
      lessThan(s.buttonsFor(StatsPeriod.days90).overall.total),
    );
    expect(s.daily.fold(0, (n, d) => n + d.total), logs);
    expect(s.hours.fold(0, (n, h) => n + h.answers), logs);
    expect(s.added.fold(0, (n, d) => n + d.count), cards);
    expect(s.reviewCards, s.distribution.young + s.distribution.mature);

    final h = await history.current(const StudyScope.all());
    expect(h.hardestCards, hasLength(10));
    expect(h.hardestCards.every((c) => c.againCount >= 1), isTrue);
    expect(h.activityByDay, hasLength(365));
  });
}
