import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/export/domain/services/anki_topic_resolver.dart';
import 'package:sinapsis/features/flashcards/domain/services/distractor_sourcer.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/relations/domain/services/relation_candidate_selector.dart';

/// Cuántos caracteres del chunk elegido se usan como texto de la opción —
/// mismo límite que ya usa `RelationCandidateSelectorImpl._excerptOf` para
/// un extracto de presentación, acá además es el ancla: el texto de la
/// opción es exactamente `chunk.content` recortado a esto, así que
/// `sourceCharEnd` puede calcularse sin volver a mirar el chunk.
const _distractorContentMaxLength = 280;

/// Cuántos temas hermanos como máximo se recorren antes de rendirse: un
/// tema con pocos elementos puede tener decenas de hermanos, y ya con
/// `count` candidatos reales sobra.
const _maxSiblingTopicsChecked = 8;

/// [DistractorSourcer] contra la bóveda real (F20, decisión C): reusa
/// `AnkiTopicResolver` (pese al nombre, resuelve el árbol de Temas en
/// general, no algo propio de exportar a Anki), `KnowledgeMapRepository`
/// para los elementos reales de un tema, `OrganizeRepository` para
/// `contradicts` y `RelationCandidateSelector` para cercanía por embedding.
class DistractorSourcerImpl implements DistractorSourcer {
  const DistractorSourcerImpl({
    required AppDatabase database,
    required AnkiTopicResolver topics,
    required KnowledgeMapRepository map,
    required OrganizeRepository organize,
    required RelationCandidateSelector relations,
  }) : _db = database,
       _topics = topics,
       _map = map,
       _organize = organize,
       _relations = relations;

  final AppDatabase _db;
  final AnkiTopicResolver _topics;
  final KnowledgeMapRepository _map;
  final OrganizeRepository _organize;
  final RelationCandidateSelector _relations;

  @override
  Future<List<DistractorCandidate>> sourceDistractors({
    required String seedItemId,
    required String excludeContent,
    int count = 3,
  }) async {
    final ordered = [
      ...await _atlasSiblings(seedItemId, count),
      ...await _contradicts(seedItemId),
      ...await _embeddingNeighbors(seedItemId, count),
    ];

    final trimmedExclude = excludeContent.trim();
    final usedItems = {seedItemId};
    final found = <DistractorCandidate>[];
    for (final itemId in ordered) {
      if (found.length >= count) break;
      if (!usedItems.add(itemId)) continue;

      final candidate = await _candidateFor(itemId, trimmedExclude);
      if (candidate != null) found.add(candidate);
    }
    return found;
  }

  /// Otros elementos que caen bajo un tema hermano del tema de [seedItemId]
  /// en el árbol de Temas —mismo padre, distinto valor—.
  Future<List<String>> _atlasSiblings(String seedItemId, int count) async {
    final resolution = await _topics.resolve({seedItemId});
    final topicId = resolution.firstTopicByItem[seedItemId];
    if (topicId == null) return const [];

    final parent = resolution.tree.parentOf(topicId);
    final siblings =
        (parent == null
                ? resolution.tree.roots
                : resolution.tree.childrenOf(parent))
            .where((id) => id != topicId)
            .take(_maxSiblingTopicsChecked);

    final itemIds = <String>[];
    for (final siblingId in siblings) {
      if (itemIds.length >= count) break;
      final graph = await _map.readTopicItems(siblingId, limit: count * 4);
      for (final node in graph.items) {
        if (node.id != seedItemId) itemIds.add(node.id);
      }
    }
    return itemIds;
  }

  /// El otro lado de cada relación `contradicts` de [seedItemId].
  Future<List<String>> _contradicts(String seedItemId) async {
    final relations = await _organize.watchRelationsForItem(seedItemId).first;
    return [
      for (final relation in relations)
        if (relation.kind == RelationKind.contradicts) relation.otherItemId,
    ];
  }

  /// Elementos cercanos por embedding a [seedItemId], de más a menos
  /// parecido.
  Future<List<String>> _embeddingNeighbors(String seedItemId, int count) async {
    // Solo fuentes: un distractor se ancla a un fragmento, y una nota no
    // tiene.
    final candidates = await _relations.selectSourceCandidates(
      seedItemId: seedItemId,
      limit: count,
    );
    return [for (final candidate in candidates) candidate.itemId];
  }

  /// El primer chunk vivo de [itemId], como candidato anclado —`null` si el
  /// elemento no tiene chunks, está en la papelera, o su texto coincide con
  /// [trimmedExclude] (la respuesta correcta: un distractor nunca puede ser
  /// también correcto).
  Future<DistractorCandidate?> _candidateFor(
    String itemId,
    String trimmedExclude,
  ) async {
    final chunk =
        await (_db.select(_db.chunks)
              ..where(
                (c) => c.itemId.equals(itemId) & itemIsActive(_db, c.itemId),
              )
              ..orderBy([(c) => OrderingTerm(expression: c.seq)])
              ..limit(1))
            .getSingleOrNull();
    if (chunk == null) return null;

    final content = chunk.content.length > _distractorContentMaxLength
        ? chunk.content.substring(0, _distractorContentMaxLength)
        : chunk.content;
    if (content.trim() == trimmedExclude) return null;

    return DistractorCandidate(
      itemId: itemId,
      content: content,
      sourceChunkId: chunk.id,
      sourceCharStart: chunk.charStart,
      sourceCharEnd: chunk.charStart + content.length,
    );
  }
}
