import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/features/relations/domain/services/relation_candidate_selector.dart';

/// Cuántos caracteres del primer chunk de un candidato se muestran como
/// excerpt — mismo límite que ya usa el diálogo manual de sugerencias del
/// grafo (`ai_suggest_relations_dialog.dart`), para que el LLM reciba un
/// fragmento de tamaño consistente sin importar por qué vía llegó.
const _excerptMaxLength = 280;

/// [RelationCandidateSelector] contra `AppDatabase`: lee los embeddings ya
/// persistidos por `ChunkEmbeddingIndexer`, sin calcular ninguno nuevo —
/// si el semilla o un candidato todavía no tienen embeddings, simplemente
/// no participan de la preselección.
class RelationCandidateSelectorImpl implements RelationCandidateSelector {
  const RelationCandidateSelectorImpl({required AppDatabase database})
    : _db = database;

  final AppDatabase _db;

  @override
  Future<List<ScoredRelationCandidate>> selectCandidates({
    required String seedItemId,
    int limit = 15,
    double minSimilarity = 0.5,
  }) async {
    final seedCentroid = await _centroidFor(seedItemId);
    if (seedCentroid == null) return const [];

    // Solo de elementos vivos: sugerir vincular con algo que está en la
    // papelera sería mandar al usuario a un elemento que ya borró.
    final otherChunks =
        await (_db.select(_db.chunks)..where(
              (c) =>
                  c.itemId.equals(seedItemId).not() &
                  itemIsActive(_db, c.itemId),
            ))
            .get();
    final chunksByItem = <String, List<ChunkRow>>{};
    for (final chunk in otherChunks) {
      chunksByItem.putIfAbsent(chunk.itemId, () => []).add(chunk);
    }

    final scored = <ScoredRelationCandidate>[];
    for (final entry in chunksByItem.entries) {
      final itemId = entry.key;
      final chunks = entry.value;

      final vectors = await _vectorsFor(chunks.map((c) => c.id).toList());
      if (vectors.isEmpty) continue;

      final score = cosineSimilarity(seedCentroid, centroid(vectors));
      if (score < minSimilarity) continue;

      final title = await _titleFor(itemId);
      if (title == null) continue;

      scored.add(
        ScoredRelationCandidate(
          itemId: itemId,
          title: title,
          excerpt: _excerptOf(chunks),
          score: score,
        ),
      );
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  Future<List<double>?> _centroidFor(String itemId) async {
    final chunks = await (_db.select(
      _db.chunks,
    )..where((c) => c.itemId.equals(itemId))).get();
    if (chunks.isEmpty) return null;

    final vectors = await _vectorsFor(chunks.map((c) => c.id).toList());
    if (vectors.isEmpty) return null;

    return centroid(vectors);
  }

  Future<List<List<double>>> _vectorsFor(List<String> chunkIds) async {
    final rows = await (_db.select(
      _db.embeddings,
    )..where((e) => e.chunkId.isIn(chunkIds))).get();
    return rows.map((row) => decodeEmbeddingVector(row.vector)).toList();
  }

  Future<String?> _titleFor(String itemId) async {
    final row = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId) & e.isActive)).getSingleOrNull();
    return row?.title;
  }

  String _excerptOf(List<ChunkRow> chunks) {
    final first = chunks.firstWhere(
      (c) => c.seq == 0,
      orElse: () => chunks.first,
    );
    return first.content.length > _excerptMaxLength
        ? '${first.content.substring(0, _excerptMaxLength)}…'
        : first.content;
  }
}
