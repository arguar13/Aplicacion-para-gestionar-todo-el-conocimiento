import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_query_sql.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';

/// [NotebookTopicReader] contra `AppDatabase` (F30).
///
/// - **Temas**: cuántos elementos vivos tiene cada espacio (`item.space_id`).
/// - **Etiquetas**: los valores de la categoría de sistema, cada uno con lo
///   asignado a él y a todo lo que cuelga de él (`VocabularyTree`): lo mismo
///   que trae filtrar por la etiqueta en la Biblioteca. Se arma en una pasada
///   sobre las asignaciones, no con una consulta por etiqueta: un árbol puede
///   tener miles de ramas.
class NotebookTopicReaderImpl implements NotebookTopicReader {
  NotebookTopicReaderImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
  }) : _db = database,
       _telemetry = telemetry;

  final AppDatabase _db;
  final TelemetryService _telemetry;

  @override
  Stream<List<NotebookTopic>> watchTopics() => watchQuery(
    db: _db,
    tables: [
      _db.spaces,
      _db.propertyValues,
      _db.itemPropertyValues,
      _db.knowledgeEntries,
    ],
    read: _read,
    telemetry: _telemetry,
    hint: 'NotebookTopicReaderImpl.watchTopics',
  );

  Future<List<NotebookTopic>> _read() async => [
    ...await _spaces(),
    ...await _tags(),
  ];

  Future<List<NotebookTopic>> _spaces() async {
    final entries = _db.knowledgeEntries;
    final count = entries.id.count();
    final rows =
        await (_db.selectOnly(entries)
              ..addColumns([entries.spaceId, count])
              ..where(entries.isActive & entries.spaceId.isNotNull())
              ..groupBy([entries.spaceId]))
            .get();
    final counts = {
      for (final row in rows) row.read(entries.spaceId)!: row.read(count)!,
    };
    return [
      for (final space in await _db.select(_db.spaces).get())
        if ((counts[space.id] ?? 0) > 0)
          NotebookTopic(
            kind: NotebookTopicKind.space,
            id: space.id,
            name: space.name,
            itemCount: counts[space.id]!,
          ),
    ];
  }

  Future<List<NotebookTopic>> _tags() async {
    final temaId = await temaDefinitionId(_db);
    final values = await (_db.select(
      _db.propertyValues,
    )..where((v) => v.definitionId.equals(temaId))).get();
    if (values.isEmpty) return const [];

    // Qué elementos vivos tiene cada etiqueta puesta directamente.
    final assigned = _db.itemPropertyValues;
    final itemId = assigned.itemId;
    final valueId = assigned.propertyValueId;
    final rows =
        await (_db.selectOnly(assigned).join([
                innerJoin(
                  _db.propertyValues,
                  _db.propertyValues.id.equalsExp(valueId),
                ),
              ])
              ..addColumns([itemId, valueId])
              ..where(
                _db.propertyValues.definitionId.equals(temaId) &
                    itemIsActive(_db, itemId),
              ))
            .get();
    final direct = <String, Set<String>>{};
    for (final row in rows) {
      final tag = row.read(valueId)!;
      final item = row.read(itemId)!;
      (direct[tag] ??= <String>{}).add(item);
    }

    final tree = VocabularyTree([
      for (final v in values) (id: v.id, parentId: v.parentId),
    ]);
    return [
      for (final value in values)
        if (_withBranches(value.id, direct, tree).length case final n
            when n > 0)
          NotebookTopic(
            kind: NotebookTopicKind.tag,
            id: value.id,
            name: value.value,
            itemCount: n,
            parentId: tree.parentOf(value.id),
          ),
    ];
  }

  /// Los elementos de la etiqueta [id] y de todo lo que cuelga de ella, sin
  /// repetir.
  static Set<String> _withBranches(
    String id,
    Map<String, Set<String>> direct,
    VocabularyTree tree,
  ) => {
    ...?direct[id],
    for (final child in tree.descendantsOf(id)) ...?direct[child],
  };

  @override
  Future<List<String>> sampleTitles(
    NotebookSuggestion suggestion, {
    int limit = kNotebookSuggestionSampleTitles,
  }) async {
    final topic = suggestion.topic;
    final inTopic = switch (topic.kind) {
      NotebookTopicKind.space => 'i.space_id = ?',
      NotebookTopicKind.tag =>
        'i.id IN (SELECT item_id FROM item_property_values '
            'WHERE property_value_id IN (${valuesWithDescendantsSql(1)}))',
    };
    final rows = await _db
        .customSelect(
          'SELECT i.title AS title FROM item i '
          'WHERE ${activeItemSql('i')} AND $inTopic '
          'ORDER BY i.created_at DESC LIMIT ?',
          variables: [Variable.withString(topic.id), Variable.withInt(limit)],
          readsFrom: {
            _db.knowledgeEntries,
            _db.itemPropertyValues,
            _db.propertyValues,
          },
        )
        .get();
    return [for (final row in rows) row.read<String>('title')];
  }
}
