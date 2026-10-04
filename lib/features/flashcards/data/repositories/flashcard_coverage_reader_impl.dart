import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_coverage_reader.dart';

/// [FlashcardCoverageReader] contra la base: una consulta por `item`, con
/// `source`, `renditions` y `flashcards` por sus índices de `item_id`. Con
/// diez mil elementos, contar es recorrer `item` una vez, sin traer textos.
class FlashcardCoverageReaderImpl implements FlashcardCoverageReader {
  const FlashcardCoverageReaderImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
  }) : _db = database,
       _telemetry = telemetry;

  final AppDatabase _db;
  final TelemetryService _telemetry;

  /// Cuántos ids por consulta: SQLite admite muchas más variables, pero
  /// cortar en tandas deja cada consulta chica aunque el cuaderno sea enorme.
  static const _batch = 500;

  static final _note = ItemKind.note.name;
  static final _done = SourceProcessingStatus.done.name;

  /// Lo que puede tener tarjetas, sobre `item i` (ver
  /// [FlashcardCoverageReader]). El texto de una forma no vacía: una nota de
  /// bloques sin nada guarda `[]`.
  static final _eligibleSql =
      '''
      ${activeItemSql('i')}
      AND (i.kind = '$_note' OR EXISTS (
            SELECT 1 FROM source s
             WHERE s.item_id = i.id AND s.processing_status = '$_done'))
      AND EXISTS (
            SELECT 1 FROM renditions r
             WHERE r.item_id = i.id
               AND r.content IS NOT NULL
               AND length(trim(r.content)) > 0
               AND r.content <> '[]')''';

  static const _hasCardsSql =
      'EXISTS (SELECT 1 FROM flashcards f WHERE f.item_id = i.id)';

  List<TableInfo<dynamic, dynamic>> get _tables => [
    _db.knowledgeEntries,
    _db.knowledgeSources,
    _db.renditions,
    _db.flashcards,
  ];

  @override
  Future<Either<Failure, FlashcardCoverage>> coverageOf(
    Iterable<String>? itemIds,
  ) async {
    try {
      final rows = <QueryRow>[];
      if (itemIds == null) {
        rows.addAll(await _read(null));
      } else {
        final ids = itemIds.toSet().toList();
        for (var start = 0; start < ids.length; start += _batch) {
          final end = (start + _batch).clamp(0, ids.length);
          rows.addAll(await _read(ids.sublist(start, end)));
        }
        // Las tandas, cada una ordenada: el orden de todas juntas lo pone el
        // momento de cada elemento.
        rows.sort(
          (a, b) => b
              .read<DateTime>('created_at')
              .compareTo(a.read<DateTime>('created_at')),
        );
      }
      return right(
        FlashcardCoverage(
          eligible: [for (final row in rows) row.read<String>('id')],
          withCards: {
            for (final row in rows)
              if (row.read<bool>('has_cards')) row.read<String>('id'),
          },
        ),
      );
      // `Object` y no `Exception`: un TypeError de una fila rara es Error.
    } on Object catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'FlashcardCoverageReaderImpl.coverageOf',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }

  Future<List<QueryRow>> _read(List<String>? ids) => _db
      .customSelect(
        '''
        SELECT i.id, i.created_at, $_hasCardsSql AS has_cards
          FROM item i
         WHERE $_eligibleSql
           ${ids == null ? '' : 'AND i.id IN (${List.filled(ids.length, '?').join(', ')})'}
         ORDER BY i.created_at DESC, i.id DESC''',
        variables: [
          if (ids != null)
            for (final id in ids) Variable.withString(id),
        ],
        readsFrom: _tables.toSet(),
      )
      .get();

  @override
  Stream<int> watchWithoutCardsCount() => watchQuery(
    db: _db,
    tables: _tables,
    read: () async {
      final row = await _db.customSelect(
        '''
            SELECT COUNT(*) AS waiting FROM item i
             WHERE $_eligibleSql AND NOT $_hasCardsSql''',
        readsFrom: _tables.toSet(),
      ).getSingle();
      return row.read<int>('waiting');
    },
    telemetry: _telemetry,
    hint: 'FlashcardCoverageReaderImpl.watchWithoutCardsCount',
  );

  @override
  Stream<bool> watchHasCards() => watchQuery(
    db: _db,
    tables: [_db.flashcards, _db.knowledgeEntries],
    read: () async {
      final row = await _db
          .customSelect(
            '''
            SELECT EXISTS (
              SELECT 1 FROM flashcards f JOIN item i ON i.id = f.item_id
               WHERE ${activeItemSql('i')}) AS any_card''',
            readsFrom: {_db.flashcards, _db.knowledgeEntries},
          )
          .getSingle();
      return row.read<bool>('any_card');
    },
    telemetry: _telemetry,
    hint: 'FlashcardCoverageReaderImpl.watchHasCards',
  );
}
