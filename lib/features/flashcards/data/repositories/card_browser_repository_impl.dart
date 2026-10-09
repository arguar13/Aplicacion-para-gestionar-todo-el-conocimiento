import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/flashcards/data/repositories/card_browser_sql.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_row_mapping.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_row.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/card_browser_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';

/// [CardBrowserRepository] sobre la base (F31, ola 2, decisión 72). Las reglas
/// están en la interfaz; el SQL, en [CardBrowserSql].
class CardBrowserRepositoryImpl implements CardBrowserRepository {
  const CardBrowserRepositoryImpl({
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
  /// consulta (SQLite admite 32.766), igual que en la cola de estudio.
  static const maxScopeItems = 30000;

  /// De a cuántas tarjetas se escribe por sentencia en las operaciones en
  /// lote: bien por debajo del tope de parámetros de SQLite, todas dentro de
  /// una misma transacción.
  static const writeChunk = 500;

  @override
  Future<Either<Failure, int>> count(CardBrowserQuery query) =>
      _guarded('CardBrowserRepositoryImpl.count', () async {
        final sql = await _sqlFor(query);
        final row = await _db
            .customSelect(
              'SELECT COUNT(*) AS n ${CardBrowserSql.from} WHERE ${sql.where}',
              variables: sql.args,
              readsFrom: _reads,
            )
            .getSingle();
        return right(row.read<int>('n'));
      });

  @override
  Future<Either<Failure, List<CardBrowserRow>>> page(
    CardBrowserQuery query, {
    required int offset,
    required int limit,
  }) => _guarded('CardBrowserRepositoryImpl.page', () async {
    if (offset < 0 || limit <= 0) {
      return left(
        Failure.validation(
          message: 'Página inválida: offset $offset, límite $limit.',
        ),
      );
    }
    final sql = await _sqlFor(query);
    final rows = await _db
        .customSelect(
          'SELECT f.*, i.title AS item_title ${CardBrowserSql.from} '
          '${sql.lapsesJoin} WHERE ${sql.where} ${sql.orderBy} '
          'LIMIT ? OFFSET ?',
          variables: [
            ...sql.args,
            Variable.withInt(limit),
            Variable.withInt(offset),
          ],
          readsFrom: _reads,
        )
        .get();
    if (rows.isEmpty) return right(const []);

    // Los olvidos, solo de las tarjetas de esta página: el agregado sobre todo
    // el historial no se paga por mostrar cincuenta renglones.
    final ids = [for (final row in rows) row.read<String>('id')];
    final lapses = await _lapsesOf(ids);

    return right([
      for (final row in rows)
        CardBrowserRow(
          card: flashcardFromRow(_db.flashcards.map(row.data)),
          itemTitle: row.read<String>('item_title'),
          lapses: lapses[row.read<String>('id')] ?? 0,
        ),
    ]);
  });

  Future<Map<String, int>> _lapsesOf(List<String> ids) async {
    final rows = await _db
        .customSelect(
          'SELECT flashcard_id, COUNT(*) AS lapses FROM review_log '
          "WHERE grade = 'again' AND phase_before = 'review' "
          'AND flashcard_id IN (${List.filled(ids.length, '?').join(', ')}) '
          'GROUP BY flashcard_id',
          variables: ids.map(Variable.withString).toList(),
          readsFrom: {_db.reviewLogs},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('flashcard_id'): row.read<int>('lapses'),
    };
  }

  @override
  Future<Either<Failure, List<String>>> ids(CardBrowserQuery query) =>
      _guarded('CardBrowserRepositoryImpl.ids', () async {
        final sql = await _sqlFor(query);
        final rows = await _db
            .customSelect(
              'SELECT f.id AS id ${CardBrowserSql.from} ${sql.lapsesJoin} '
              'WHERE ${sql.where} ${sql.orderBy}',
              variables: sql.args,
              readsFrom: _reads,
            )
            .get();
        return right([for (final row in rows) row.read<String>('id')]);
      });

  @override
  Future<Either<Failure, Map<CardBrowserStatus, int>>> statusCounts(
    CardBrowserQuery query,
  ) => _guarded('CardBrowserRepositoryImpl.statusCounts', () async {
    final sql = await _sqlFor(query, withStatus: false);
    const isNew = CardBrowserSql.isNew;
    final row = await _db
        .customSelect(
          'SELECT '
          'COALESCE(SUM(CASE WHEN f.suspended = 0 AND ($isNew) '
          'THEN 1 ELSE 0 END), 0) AS new_cards, '
          'COALESCE(SUM(CASE WHEN f.suspended = 0 '
          'AND f.learning_step IS NOT NULL THEN 1 ELSE 0 END), 0) AS learning, '
          'COALESCE(SUM(CASE WHEN f.suspended = 0 '
          'AND f.learning_step IS NULL AND NOT ($isNew) '
          'AND f.interval_days < $kMatureIntervalDays '
          'THEN 1 ELSE 0 END), 0) AS young, '
          'COALESCE(SUM(CASE WHEN f.suspended = 0 '
          'AND f.learning_step IS NULL AND NOT ($isNew) '
          'AND f.interval_days >= $kMatureIntervalDays '
          'THEN 1 ELSE 0 END), 0) AS mature, '
          'COALESCE(SUM(CASE WHEN f.suspended = 1 THEN 1 ELSE 0 END), 0) '
          'AS suspended, '
          'COALESCE(SUM(CASE WHEN f.suspended = 0 AND NOT ($isNew) '
          'AND f.due_at < ? THEN 1 ELSE 0 END), 0) AS due, '
          'COALESCE(SUM(CASE WHEN f.buried_until IS NOT NULL '
          'AND f.buried_until > ? THEN 1 ELSE 0 END), 0) AS buried '
          '${CardBrowserSql.from} WHERE ${sql.where}',
          variables: [
            Variable.withDateTime(sql.dayEnd),
            Variable.withDateTime(sql.now),
            ...sql.args,
          ],
          readsFrom: _reads,
        )
        .getSingle();
    return right({
      CardBrowserStatus.newCards: row.read<int>('new_cards'),
      CardBrowserStatus.learning: row.read<int>('learning'),
      CardBrowserStatus.young: row.read<int>('young'),
      CardBrowserStatus.mature: row.read<int>('mature'),
      CardBrowserStatus.suspended: row.read<int>('suspended'),
      CardBrowserStatus.due: row.read<int>('due'),
      CardBrowserStatus.buried: row.read<int>('buried'),
    });
  });

  @override
  Stream<void> changes() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.flashcards,
          _db.knowledgeEntries,
          // De qué está hecho un recorte.
          _db.itemPropertyValues,
          _db.propertyValues,
          _db.spaces,
          _db.notebooks,
          _db.notebookItems,
        ]),
      )
      .map((_) {});

  @override
  Future<Either<Failure, int>> resetSchedule(Iterable<String> ids) =>
      _guarded('CardBrowserRepositoryImpl.resetSchedule', () async {
        final wanted = ids.toSet().toList();
        if (wanted.isEmpty) return right(0);
        final now = _clock();
        final changed = await _db.transaction(() async {
          var total = 0;
          for (var start = 0; start < wanted.length; start += writeChunk) {
            final chunk = wanted.skip(start).take(writeChunk).toList();
            total +=
                await (_db.update(
                  _db.flashcards,
                )..where((f) => f.id.isIn(chunk))).write(
                  FlashcardsCompanion(
                    easeFactor: const Value(2.5),
                    intervalDays: const Value(0),
                    repetitions: const Value(0),
                    learningStep: const Value(null),
                    lastReviewedAt: const Value(null),
                    // Una nueva se estudia desde ya, como al crearla; y una
                    // «hasta mañana» vuelve a la cola: empezar de cero.
                    dueAt: Value(now),
                    buriedUntil: const Value(null),
                  ),
                );
          }
          return total;
        });
        return right(changed);
      });

  @override
  Future<Either<Failure, int>> deleteMany(Iterable<String> ids) =>
      _guarded('CardBrowserRepositoryImpl.deleteMany', () async {
        final wanted = ids.toSet().toList();
        if (wanted.isEmpty) return right(0);
        final deleted = await _db.transaction(() async {
          var total = 0;
          for (var start = 0; start < wanted.length; start += writeChunk) {
            final chunk = wanted.skip(start).take(writeChunk).toList();
            total += await (_db.delete(
              _db.flashcards,
            )..where((f) => f.id.isIn(chunk))).go();
          }
          return total;
        });
        return right(deleted);
      });

  Set<TableInfo<dynamic, dynamic>> get _reads => {
    _db.flashcards,
    _db.knowledgeEntries,
    _db.reviewLogs,
  };

  /// El SQL de [query], con el recorte ya resuelto a elementos.
  Future<CardBrowserSql> _sqlFor(
    CardBrowserQuery query, {
    bool withStatus = true,
  }) async {
    final resolved = await _resolver.itemIds(query.scope);
    final ids = resolved.getOrElse((failure) => throw StateError('$failure'));
    if (ids != null && ids.length > maxScopeItems) {
      throw StateError(
        'El recorte tiene ${ids.length} elementos y la lista admite hasta '
        '$maxScopeItems.',
      );
    }
    final now = _clock();
    return CardBrowserSql(
      query: query,
      now: now,
      dayEnd: _day.endOf(now),
      itemIds: ids?.toList(),
      withStatus: withStatus,
    );
  }

  /// Catch-all deliberado, igual que en el resto de los repositorios: un
  /// `TypeError` es `Error`, no `Exception`, y atrapar solo `Exception` lo
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
