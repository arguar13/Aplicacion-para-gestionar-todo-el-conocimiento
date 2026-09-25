import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/features/export/domain/services/anki_topic_resolver.dart';
import 'package:sinapsis/features/flashcards/domain/entities/topic_error_summary.dart';
import 'package:sinapsis/features/flashcards/domain/services/quiz_session_summary_service.dart';

/// [QuizSessionSummaryService] contra la bóveda real: reusa
/// `AnkiTopicResolver` (pese al nombre, resuelve el árbol de Temas en
/// general —ver `DistractorSourcerImpl`, mismo criterio—) para el tema de
/// cada pregunta fallada, y una consulta propia —mismo patrón que
/// `atlasMapNotesSql`, pero para `NoteKind.living` en vez de `.map`— para
/// la nota viva de cada tema.
class QuizSessionSummaryServiceImpl implements QuizSessionSummaryService {
  const QuizSessionSummaryServiceImpl({
    required AppDatabase database,
    required AnkiTopicResolver topics,
  }) : _db = database,
       _topics = topics;

  final AppDatabase _db;
  final AnkiTopicResolver _topics;

  @override
  Future<List<TopicErrorSummary>> summarize(List<String> missedItemIds) async {
    if (missedItemIds.isEmpty) return const [];

    final resolution = await _topics.resolve(missedItemIds.toSet());
    final countByTopic = <String, int>{};
    for (final itemId in missedItemIds) {
      final topicId = resolution.firstTopicByItem[itemId];
      if (topicId == null) continue;
      countByTopic[topicId] = (countByTopic[topicId] ?? 0) + 1;
    }
    if (countByTopic.isEmpty) return const [];

    final livingNotes = await _livingNoteIdsByTopic(countByTopic.keys.toSet());
    final summaries = [
      for (final entry in countByTopic.entries)
        TopicErrorSummary(
          topicLabel: resolution.labelOf[entry.key] ?? '',
          missedCount: entry.value,
          livingNoteItemId: livingNotes[entry.key],
        ),
    ];
    return summaries..sort((a, b) => b.missedCount.compareTo(a.missedCount));
  }

  /// El elemento de la nota viva de cada valor de [topicIds], si tiene una
  /// —con más de una, la de `rowid` menor—. Se lee en crudo, mismo motivo
  /// que `atlasMapNotesSql`: es una consulta puntual sobre pocos temas, no
  /// vale la pena una entidad completa por fila.
  Future<Map<String, String>> _livingNoteIdsByTopic(
    Set<String> topicIds,
  ) async {
    final marks = List.filled(topicIds.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          '''
      SELECT item.id AS note_id, ipv.property_value_id AS value_id,
             note.rowid AS row_id
        FROM note
        CROSS JOIN item ON item.id = note.item_id
        CROSS JOIN item_property_values ipv ON ipv.item_id = item.id
       WHERE note.note_kind = ? AND ipv.property_value_id IN ($marks)
         AND $kActiveItemSql
      ''',
          variables: [
            Variable.withString(NoteKind.living.name),
            for (final id in topicIds) Variable.withString(id),
          ],
          readsFrom: {
            _db.knowledgeNotes,
            _db.knowledgeEntries,
            _db.itemPropertyValues,
          },
        )
        .get();

    final bestRowId = <String, int>{};
    final result = <String, String>{};
    for (final row in rows) {
      final valueId = row.read<String>('value_id');
      final rowId = row.read<int>('row_id');
      final current = bestRowId[valueId];
      if (current == null || rowId < current) {
        bestRowId[valueId] = rowId;
        result[valueId] = row.read<String>('note_id');
      }
    }
    return result;
  }
}
