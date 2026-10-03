import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_organize_backlog.dart';

/// Cuántas pasadas a medias se le aguantan a un elemento antes de dejarlo:
/// el mismo tope que la cola de procesamiento le da a lo que quedó en curso
/// (`ProcessingQueueNotifier.maxInterruptedAttempts`). Tres cubren un cierre
/// por accidente y un sistema que congela la app; más es algo que la hace
/// caer, y retomarlo en cada arranque sería un bucle.
const kMaxAiRunAttempts = 3;

/// [AiOrganizeBacklog] contra la base: todo sale de `item`, `source` y
/// `ai_runs`, por sus índices —`ai_runs` por `item_id`—, sin traer filas que
/// no hagan falta. Con diez mil elementos, cada pregunta es una búsqueda, no
/// un recorrido en memoria.
class AiOrganizeBacklogImpl implements AiOrganizeBacklog {
  const AiOrganizeBacklogImpl(this._db);

  final AppDatabase _db;

  static final _note = ItemKind.note.name;
  static final _done = SourceProcessingStatus.done.name;

  /// Lo pendiente de `item i` (ver [AiOrganizeBacklog]); el único `?` es
  /// hasta cuándo una nota tiene que estar quieta.
  static final _pendingSql =
      '''
      ${activeItemSql('i')}
      AND (i.kind = '$_note' OR EXISTS (
            SELECT 1 FROM source s
             WHERE s.item_id = i.id AND s.processing_status = '$_done'))
      AND NOT EXISTS (
            SELECT 1 FROM ai_runs r
             WHERE r.item_id = i.id
               AND (r.finished_at IS NOT NULL OR r.undone_at IS NOT NULL))
      AND (SELECT COUNT(*) FROM ai_runs r WHERE r.item_id = i.id)
            < $kMaxAiRunAttempts
      AND (i.kind <> '$_note' OR i.updated_at <= ?)''';

  @override
  Future<String?> nextFresh({
    required DateTime since,
    required DateTime notesQuietBefore,
    Set<String> skip = const {},
  }) => _next(
    createdSql: 'i.created_at >= ?',
    created: since,
    order: 'ASC',
    notesQuietBefore: notesQuietBefore,
    skip: skip,
  );

  @override
  Future<String?> nextExisting({
    required DateTime before,
    required DateTime notesQuietBefore,
    Set<String> skip = const {},
  }) => _next(
    createdSql: 'i.created_at < ?',
    created: before,
    order: 'DESC',
    notesQuietBefore: notesQuietBefore,
    skip: skip,
  );

  Future<String?> _next({
    required String createdSql,
    required DateTime created,
    required String order,
    required DateTime notesQuietBefore,
    required Set<String> skip,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT i.id FROM item i
           WHERE $_pendingSql
             AND $createdSql
             ${skip.isEmpty ? '' : 'AND i.id NOT IN (${_marks(skip.length)})'}
           ORDER BY i.created_at $order, i.id $order
           LIMIT 1''',
          variables: [
            Variable.withDateTime(notesQuietBefore),
            Variable.withDateTime(created),
            for (final id in skip) Variable.withString(id),
          ],
          readsFrom: _tables,
        )
        .getSingleOrNull();
    return row?.read<String>('id');
  }

  @override
  Future<List<EditedNote>> editedNotes({required DateTime quietBefore}) async {
    // La última pasada de cada nota: si está terminada y en pie, y la nota
    // cambió después, es candidata. Si está deshecha, no: la IA no vuelve a
    // tocar sola algo cuya pasada se deshizo.
    final rows = await _db
        .customSelect(
          '''
          SELECT i.id, i.updated_at, r.content_simhash FROM item i
            JOIN ai_runs r ON r.item_id = i.id
           WHERE ${activeItemSql('i')}
             AND i.kind = '$_note'
             AND r.started_at = (
                   SELECT MAX(last.started_at) FROM ai_runs last
                    WHERE last.item_id = i.id)
             AND r.finished_at IS NOT NULL
             AND r.undone_at IS NULL
             AND i.updated_at > r.finished_at
             AND i.updated_at <= ?
           ORDER BY i.updated_at ASC''',
          variables: [Variable.withDateTime(quietBefore)],
          readsFrom: _tables,
        )
        .get();
    return [
      for (final row in rows)
        (
          itemId: row.read<String>('id'),
          updatedAt: row.read<DateTime>('updated_at'),
          simhashSeen: row.readNullable<String>('content_simhash'),
        ),
    ];
  }

  @override
  Future<AiBacklogCount> count({
    required DateTime epoch,
    required DateTime notesQuietBefore,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(CASE WHEN i.created_at >= ? THEN 1 ELSE 0 END), 0)
                   AS fresh,
                 COALESCE(SUM(CASE WHEN i.created_at < ? THEN 1 ELSE 0 END), 0)
                   AS existing
            FROM item i
           WHERE $_pendingSql''',
          variables: [
            Variable.withDateTime(epoch),
            Variable.withDateTime(epoch),
            Variable.withDateTime(notesQuietBefore),
          ],
          readsFrom: _tables,
        )
        .getSingle();
    return AiBacklogCount(
      fresh: row.read<int>('fresh'),
      existing: row.read<int>('existing'),
    );
  }

  @override
  Stream<DateTime?> watchLastNoteEdit() => _db
      .customSelect(
        '''
        SELECT MAX(i.updated_at) AS last_edit FROM item i
         WHERE ${activeItemSql('i')} AND i.kind = '$_note' ''',
        readsFrom: {_db.knowledgeEntries},
      )
      .watchSingle()
      .map((row) => row.readNullable<DateTime>('last_edit'))
      .distinct();

  Set<ResultSetImplementation<dynamic, dynamic>> get _tables => {
    _db.knowledgeEntries,
    _db.knowledgeSources,
    _db.aiRuns,
  };

  static String _marks(int count) => List.filled(count, '?').join(', ');
}
