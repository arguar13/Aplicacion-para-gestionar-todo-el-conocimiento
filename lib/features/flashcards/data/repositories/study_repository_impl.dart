import 'dart:async';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_row_mapping.dart';
import 'package:sinapsis/features/flashcards/data/repositories/study_queue_sql.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';

/// [StudyRepository] sobre la base (F31, decisión 69). El orden de la sesión y
/// sus reglas están en la interfaz; el SQL, en [StudyQueueSql].
class StudyRepositoryImpl implements StudyRepository {
  const StudyRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required Clock clock,
    required StudyScopeResolver resolver,
    StudyDay day = const StudyDay(),
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock,
       _resolver = resolver,
       _day = day;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;
  final StudyScopeResolver _resolver;
  final StudyDay _day;

  /// Hasta cuántos elementos acepta un recorte: cada uno es un parámetro de la
  /// consulta, y SQLite admite 32.766. Una bóveda de diez mil elementos entra
  /// con holgura.
  static const maxScopeItems = 30000;

  @override
  Future<Either<Failure, StudyNext>> next(
    StudyScope scope, {
    required StudyLimits limits,
    Duration learnAhead = Duration.zero,
  }) => _guarded('StudyRepositoryImpl.next', () async {
    final now = _clock();
    final sql = await _sqlFor(scope, now);
    if (sql == null) return right(const StudyNextDone());

    // 1. Lo que se aprende y ya volvió.
    final learning = await _first(sql, sql.learningDue);
    if (learning != null) {
      return right(
        StudyNextCard(card: learning, queue: StudyQueueKind.learning),
      );
    }

    // 2 y 3. Repasos, y después nuevas, dentro de los límites de hoy.
    final done = await _doneToday(sql);
    if (limits.reviewsLeft(done.reviews) > 0) {
      final review = await _first(sql, sql.reviewDue);
      if (review != null) {
        return right(StudyNextCard(card: review, queue: StudyQueueKind.review));
      }
    }
    if (limits.newLeft(done.newCards) > 0) {
      final fresh = await _first(sql, sql.newDue);
      if (fresh != null) {
        return right(StudyNextCard(card: fresh, queue: StudyQueueKind.newCard));
      }
    }

    // 4. Nada más: lo que vuelve más tarde hoy, o se terminó.
    final counts = await _counts(sql, limits, done);
    final later = await _first(sql, sql.learningLater);
    if (later != null) {
      if (!later.dueAt.isAfter(now.add(learnAhead))) {
        return right(
          StudyNextCard(
            card: later,
            queue: StudyQueueKind.learning,
            early: true,
          ),
        );
      }
      return right(
        StudyNextWait(
          until: later.dueAt,
          learningLeft: counts.learning,
          newBeyondLimit: counts.newBeyondLimit,
          reviewsBeyondLimit: counts.reviewsBeyondLimit,
        ),
      );
    }
    return right(
      StudyNextDone(
        newBeyondLimit: counts.newBeyondLimit,
        reviewsBeyondLimit: counts.reviewsBeyondLimit,
      ),
    );
  });

  @override
  Future<Either<Failure, StudyCounts>> counts(
    StudyScope scope, {
    required StudyLimits limits,
  }) => _guarded('StudyRepositoryImpl.counts', () async {
    final sql = await _sqlFor(scope, _clock());
    if (sql == null) return right(const StudyCounts.empty());
    return right(await _counts(sql, limits, await _doneToday(sql)));
  });

  @override
  Stream<StudyCounts> watchCounts(
    StudyScope scope, {
    required StudyLimits limits,
  }) {
    Timer? dayChange;
    StreamController<void>? wake;

    // Lo único que cambia con el reloj, sin que nada se escriba, es el día de
    // estudio: al llegar su fin se vuelve a leer (los límites empiezan de
    // cero y lo pospuesto vuelve). El resto cambia por escrituras.
    void scheduleDayChange(DateTime now) {
      dayChange?.cancel();
      final wait = _day.endOf(now).difference(now) + const Duration(seconds: 1);
      dayChange = Timer(wait, () {
        final controller = wake;
        if (controller != null && !controller.isClosed) controller.add(null);
      });
    }

    return watchReads<StudyCounts>(
      changes: () {
        StreamSubscription<void>? updates;
        late final StreamController<void> controller;
        controller = StreamController<void>(
          onListen: () {
            updates = _db
                .tableUpdates(
                  TableUpdateQuery.onAllTables([
                    _db.flashcards,
                    _db.reviewLogs,
                    _db.knowledgeEntries,
                    // De qué está hecho un recorte.
                    _db.itemPropertyValues,
                    _db.propertyValues,
                    _db.spaces,
                    _db.notebooks,
                    _db.notebookItems,
                  ]),
                )
                .listen((_) => controller.add(null));
          },
          onCancel: () async {
            dayChange?.cancel();
            await updates?.cancel();
          },
        );
        wake = controller;
        return controller.stream;
      },
      read: () async {
        final now = _clock();
        scheduleDayChange(now);
        final result = await counts(scope, limits: limits);
        // Un fallo viaja por el stream, como en el resto de las lecturas.
        return result.getOrElse((failure) => throw StateError('$failure'));
      },
      telemetry: _telemetry,
      hint: 'StudyRepositoryImpl.watchCounts',
    );
  }

  /// El SQL del recorte, o `null` si el recorte no tiene ningún elemento
  /// (no hay nada que consultar).
  Future<StudyQueueSql?> _sqlFor(StudyScope scope, DateTime now) async {
    final resolved = await _resolver.itemIds(scope);
    final ids = resolved.getOrElse((failure) => throw StateError('$failure'));
    if (ids != null && ids.isEmpty) return null;
    if (ids != null && ids.length > maxScopeItems) {
      throw StateError(
        'El recorte tiene ${ids.length} elementos y la cola admite hasta '
        '$maxScopeItems.',
      );
    }
    return StudyQueueSql(
      now: now,
      dayStart: _day.startOf(now),
      dayEnd: _day.endOf(now),
      itemIds: ids?.toList(),
    );
  }

  Future<Flashcard?> _first(StudyQueueSql sql, String query) async {
    final rows = await _db
        .customSelect(
          query,
          variables: sql.bind(query),
          readsFrom: {_db.flashcards, _db.knowledgeEntries},
        )
        .get();
    if (rows.isEmpty) return null;
    return flashcardFromRow(_db.flashcards.map(rows.first.data));
  }

  Future<({int newCards, int reviews})> _doneToday(StudyQueueSql sql) async {
    final row = await _db
        .customSelect(
          StudyQueueSql.doneToday,
          variables: sql.bind(StudyQueueSql.doneToday),
          readsFrom: {_db.reviewLogs},
        )
        .getSingle();
    return (
      newCards: row.read<int>('new_done'),
      reviews: row.read<int>('reviews_done'),
    );
  }

  Future<StudyCounts> _counts(
    StudyQueueSql sql,
    StudyLimits limits,
    ({int newCards, int reviews}) done,
  ) async {
    final query = sql.counts;
    final row = await _db
        .customSelect(
          query,
          variables: sql.bind(query),
          readsFrom: {_db.flashcards, _db.knowledgeEntries},
        )
        .getSingle();
    final newAvailable = row.read<int>('new_available');
    final reviewsAvailable = row.read<int>('reviews_available');
    final nextDue = row.readNullable<DateTime>('next_learning_due');
    return StudyCounts(
      newCards: _min(newAvailable, limits.newLeft(done.newCards)),
      learning: row.read<int>('learning'),
      reviews: _min(reviewsAvailable, limits.reviewsLeft(done.reviews)),
      newAvailable: newAvailable,
      reviewsAvailable: reviewsAvailable,
      newDoneToday: done.newCards,
      reviewsDoneToday: done.reviews,
      nextLearningDue: nextDue,
    );
  }

  static int _min(int a, int b) => a < b ? a : b;

  /// Catch-all deliberado, igual que en el resto de los repositorios: un
  /// `TypeError` es `Error`, no `Exception`, y atraparía solo `Exception`
  /// dejaría escapar y a quien llamó esperando una respuesta que nunca llega.
  Future<Either<Failure, T>> _guarded<T>(
    String hint,
    Future<Either<Failure, T>> Function() body,
  ) async {
    try {
      return await body();
      // Ver arriba: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: hint);
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}
