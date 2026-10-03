import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_review/domain/entities/pending_review_item.dart';
import 'package:sinapsis/features/ai_review/domain/repositories/pending_review_repository.dart';

class PendingReviewRepositoryImpl implements PendingReviewRepository {
  const PendingReviewRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
  }) : _db = database,
       _telemetry = telemetry;

  final AppDatabase _db;
  final TelemetryService _telemetry;

  /// Lo que se revisa en «Para revisar» (F27). Ni los duplicados —tienen su
  /// pantalla— ni las tarjetas, que nunca pasan por la cola de sugerencias.
  static const _reviewable = [
    SuggestionKind.relation,
    SuggestionKind.property,
    SuggestionKind.metadata,
  ];

  /// Lo que cuenta como «para revisar», igual para la lista y para el número:
  /// pendiente, de un tipo que se revisa, de un elemento vivo y —si es un
  /// vínculo— hacia otro que tampoco está en la papelera. El otro extremo
  /// vive dentro del JSON; el conjunto de la papelera es chico y se arma una
  /// vez por consulta, como en `kChunkOutsideTrashSql`.
  static final _where =
      '''
      s.status = ?
      AND s.kind IN (${_reviewable.map((_) => '?').join(', ')})
      AND $kActiveItemSql
      AND (s.kind <> ? OR json_extract(s.payload_json, '\$.relatedItemId')
           NOT IN (SELECT ti.id FROM item ti WHERE ti.deleted_at IS NOT NULL))''';

  static final List<Variable<Object>> _whereVariables = [
    Variable.withString(SuggestionStatus.pending.name),
    for (final kind in _reviewable) Variable.withString(kind.name),
    Variable.withString(SuggestionKind.relation.name),
  ];

  @override
  Stream<List<PendingReviewItem>> watchItemsWithPendingReview() {
    return watchQuery(
      db: _db,
      tables: [_db.suggestions, _db.knowledgeEntries],
      read: _readItems,
      telemetry: _telemetry,
      hint: 'PendingReviewRepositoryImpl.watchItemsWithPendingReview',
    );
  }

  @override
  Stream<int> watchPendingReviewCount() {
    return watchQuery(
      db: _db,
      tables: [_db.suggestions, _db.knowledgeEntries],
      read: () async {
        final row = await _db
            .customSelect(
              '''
              SELECT COUNT(*) AS pending
                FROM suggestions s
                JOIN item ON item.id = s.target_item_id
               WHERE $_where''',
              variables: _whereVariables,
              readsFrom: {_db.suggestions, _db.knowledgeEntries},
            )
            .getSingle();
        return row.read<int>('pending');
      },
      telemetry: _telemetry,
      hint: 'PendingReviewRepositoryImpl.watchPendingReviewCount',
    );
  }

  Future<List<PendingReviewItem>> _readItems() async {
    // Solo los ids y el elemento: la carga útil entera la decodifica
    // `SuggestionRepository`, y solo para lo que está en pantalla.
    final rows = await _db
        .customSelect(
          '''
          SELECT s.id, s.target_item_id, s.created_at,
                 item.title AS item_title
            FROM suggestions s
            JOIN item ON item.id = s.target_item_id
           WHERE $_where
           ORDER BY s.created_at, s.id''',
          variables: _whereVariables,
          readsFrom: {_db.suggestions, _db.knowledgeEntries},
        )
        .get();

    final byItem = <String, _Group>{};
    for (final row in rows) {
      final group = byItem.putIfAbsent(
        row.read<String>('target_item_id'),
        () => _Group(row.read<String>('item_title')),
      );
      group.ids.add(row.read<String>('id'));
      // Las filas llegan de la más vieja a la más nueva: la última gana.
      group.latestAt = row.read<DateTime>('created_at');
    }

    // El de la sugerencia más nueva primero; a igual momento, por título, para
    // que la lista no baile entre una lectura y la siguiente.
    return [
      for (final MapEntry(key: itemId, value: group) in byItem.entries)
        PendingReviewItem(
          itemId: itemId,
          itemTitle: group.title,
          suggestionIds: List.unmodifiable(group.ids),
          latestAt: group.latestAt!,
        ),
    ]..sort((a, b) {
      final byDate = b.latestAt.compareTo(a.latestAt);
      return byDate != 0 ? byDate : a.itemTitle.compareTo(b.itemTitle);
    });
  }
}

class _Group {
  _Group(this.title);

  final String title;
  final ids = <String>[];
  DateTime? latestAt;
}
