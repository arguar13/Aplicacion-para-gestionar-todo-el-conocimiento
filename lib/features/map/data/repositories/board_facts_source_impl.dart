import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/map/data/repositories/board_facts_sql.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_query_sql.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_repository_impl.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';

/// Lo que el Resumen del Mapa lee de la base (F44, paso 3), con el mismo
/// recorte y el mismo filtro que el mapa.
class BoardFactsSourceImpl implements BoardFactsSource {
  const BoardFactsSourceImpl({
    required AppDatabase database,
    required LibraryRepository library,
    StudyDay studyDay = const StudyDay(),
  }) : _db = database,
       _library = library,
       _studyDay = studyDay;

  final AppDatabase _db;
  final LibraryRepository _library;
  final StudyDay _studyDay;

  @override
  Future<BoardFacts> readFacts(
    String definitionId, {
    LibraryQuery filter = const LibraryQuery(),
  }) async {
    final allowed = await _allowedItemIds(filter);
    final spaces = isSpacesDimension(definitionId);
    final rows = await _db
        .customSelect(
          spaces ? boardSpaceItemsSql : boardItemsSql,
          variables: [if (!spaces) Variable.withString(definitionId)],
          readsFrom: mapTables(_db).toSet(),
        )
        .get();

    final items = <BoardItemFact>[];
    final ids = <String>{};
    for (final row in rows) {
      final data = row.data;
      final id = data['id'] as String;
      if (allowed != null && !allowed.contains(id)) continue;
      final valueIds = data['value_ids'] as String?;
      ids.add(id);
      items.add(
        BoardItemFact(
          id: id,
          title: data['title'] as String,
          // La fecha por `read`: cómo se guarda un instante lo sabe drift.
          createdAt: row.read<DateTime>('created_at'),
          valueIds: valueIds == null
              ? const []
              : valueIds.split(mapValueIdSeparator),
        ),
      );
    }

    // Los vínculos entre documentos procesados vivos —la consulta de la vista
    // «Vínculos»—, y de ellos los que tienen los dos extremos en el filtro.
    final linkRows = await _db
        .customSelect(mapLinksSql, readsFrom: mapTables(_db).toSet())
        .get();
    return BoardFacts(
      items: items,
      links: [
        for (final row in linkRows)
          if (ids.contains(row.data['from_id']) &&
              ids.contains(row.data['to_id']))
            BoardLinkFact(
              fromId: row.data['from_id'] as String,
              toId: row.data['to_id'] as String,
              createdAt: row.read<DateTime>('created_at'),
            ),
      ],
    );
  }

  @override
  Future<Map<String, BoardCardFact>> readCards(DateTime now) async {
    final rows = await _db
        .customSelect(
          boardCardsSql,
          variables: [
            Variable.withDateTime(now),
            Variable.withDateTime(_studyDay.endOf(now)),
          ],
          readsFrom: {
            _db.flashcards,
            _db.processedDocuments,
            _db.knowledgeEntries,
          },
        )
        .get();
    return {
      for (final row in rows)
        row.data['id'] as String: BoardCardFact(
          cards: row.data['cards'] as int,
          dueToday: row.data['due'] as int,
        ),
    };
  }

  @override
  Stream<void> cardChanges() => _db.tableUpdates(
    TableUpdateQuery.onAllTables([
      _db.flashcards,
      // Un documento que se procesa trae las tarjetas de su fuente.
      _db.processedDocuments,
      // Una fuente que va a la papelera se lleva sus tarjetas.
      _db.knowledgeEntries,
    ]),
  );

  /// Los documentos procesados que pasan el filtro, o `null` si no hay filtro:
  /// lo mismo que resuelve el mapa, y con el mismo error si no se pudo.
  Future<Set<String>?> _allowedItemIds(LibraryQuery filter) async {
    if (!filter.isFiltered) return null;
    final result = await _library.matchingIds(
      filter.copyWith(limit: null, offset: 0, scope: LibraryScope.processed),
    );
    return result.fold(
      (failure) => throw MapFilterFailed(failure),
      (ids) => ids.toSet(),
    );
  }
}
