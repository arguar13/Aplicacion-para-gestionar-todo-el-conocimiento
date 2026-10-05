import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/note_text.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';
import 'package:sinapsis/features/relations/domain/services/item_vector_index.dart';

/// [NotebookCandidateFinder] sobre lo que ya hay (F30):
///
/// - **Por palabras**, el buscador del chat (`ChunkPassageRetriever`): de cada
///   elemento, el pasaje que más palabras de lo buscado junta.
/// - **Por sentido**, si el modelo de vínculos está bajado: el vector de lo
///   buscado (`EmbeddingService.embedQuery`) contra los ya guardados de cada
///   fragmento (`ItemVectorIndex.nearestTo`). Encuentra «el Senado» buscando
///   «Roma» aunque no diga Roma.
///
/// Las dos listas se juntan con [fuseRankings]. Si buscar por sentido falla,
/// se sigue con lo de las palabras y el resultado lo dice
/// ([SenseSearch.failed]): es una mejora de la búsqueda, no la búsqueda.
class NotebookCandidateFinderImpl implements NotebookCandidateFinder {
  NotebookCandidateFinderImpl({
    required AppDatabase database,
    required VaultRetriever retriever,
    required ItemVectorIndex vectors,
    required EmbeddingService embeddings,
    required Future<bool> Function() embeddingsReady,
    required TelemetryService telemetry,
  }) : _db = database,
       _retriever = retriever,
       _vectors = vectors,
       _embeddings = embeddings,
       _embeddingsReady = embeddingsReady,
       _telemetry = telemetry;

  final AppDatabase _db;
  final VaultRetriever _retriever;
  final ItemVectorIndex _vectors;
  final EmbeddingService _embeddings;
  final Future<bool> Function() _embeddingsReady;
  final TelemetryService _telemetry;

  @override
  Future<NotebookSearchResult> find(
    String topic, {
    int limit = kNotebookCandidateLimit,
  }) async {
    final words = notebookTopicQuery(topic);
    final byWords = words.isEmpty
        ? const <({String itemId, String title, String excerpt})>[]
        : [
            for (final source in await _retriever.retrieve(words, limit: limit))
              (
                itemId: source.itemId,
                title: source.itemTitle,
                excerpt: source.excerpt,
              ),
          ];

    var senseSearch = SenseSearch.unavailable;
    var bySense = const <ItemSimilarity>[];
    if (topic.trim().isNotEmpty && await _embeddingsReady()) {
      try {
        bySense = await _vectors.nearestTo(
          await _embeddings.embedQuery(topic.trim()),
          limit: limit,
          minSimilarity: kNotebookMinSimilarity,
        );
        senseSearch = SenseSearch.used;
        // El modelo de vínculos es de terceros (flutter_gemma) y puede fallar
        // de formas sin un tipo propio. No se pierde: queda registrado y la
        // pantalla dice que se buscó solo por palabras.
        // ignore: avoid_catches_without_on_clauses
      } catch (error, stackTrace) {
        senseSearch = SenseSearch.failed;
        _telemetry.recordError(
          error,
          stackTrace,
          hint: 'NotebookCandidateFinderImpl: buscar por sentido',
        );
      }
    }

    final ids = fuseRankings([
      [for (final hit in byWords) hit.itemId],
      [for (final hit in bySense) hit.itemId],
    ]).take(limit).toList();
    if (ids.isEmpty) {
      return NotebookSearchResult(
        candidates: const [],
        senseSearch: senseSearch,
      );
    }

    final wordHits = {for (final hit in byWords) hit.itemId: hit};
    final similarity = {for (final hit in bySense) hit.itemId: hit.score};
    final rows = await _rowsOf(ids);
    final candidates = <NotebookCandidate>[];
    for (final id in ids) {
      final row = rows[id];
      // Se borró entre la búsqueda y ahora.
      if (row == null) continue;
      final hit = wordHits[id];
      candidates.add(
        NotebookCandidate(
          itemId: id,
          title: row.title,
          excerpt: _clip(hit?.excerpt ?? await _beginningOf(id, row.kind)),
          kind: row.kind,
          matchedText: hit != null,
          similarity: similarity[id],
        ),
      );
    }
    return NotebookSearchResult(
      candidates: candidates,
      senseSearch: senseSearch,
    );
  }

  /// El título y el tipo de cada uno de [ids] que sigue vivo.
  Future<Map<String, ({String title, SourceKind kind})>> _rowsOf(
    List<String> ids,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT i.id AS id, i.title AS title, s.source_type AS kind '
          'FROM item i LEFT JOIN source s ON s.item_id = i.id '
          'WHERE ${activeItemSql('i')} '
          'AND i.id IN (${List.filled(ids.length, '?').join(', ')})',
          variables: [for (final id in ids) Variable.withString(id)],
          readsFrom: {_db.knowledgeEntries, _db.knowledgeSources},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): (
          title: row.read<String>('title'),
          kind: _kindOf(row.readNullable<String>('kind')),
        ),
    };
  }

  /// El tipo guardado; una nota no tiene fila en `source`.
  static SourceKind _kindOf(String? name) {
    if (name == null) return SourceKind.manualNote;
    return SourceKind.values.asNameMap()[name] ?? SourceKind.manualNote;
  }

  /// El comienzo de [itemId]: su primer fragmento, o el texto de una nota.
  Future<String> _beginningOf(String itemId, SourceKind kind) async {
    if (kind == SourceKind.manualNote) {
      return await noteTextOf(_db, itemId) ?? '';
    }
    final first =
        await (_db.select(_db.chunks)
              ..where((c) => c.itemId.equals(itemId))
              ..orderBy([(c) => OrderingTerm.asc(c.seq)])
              ..limit(1))
            .getSingleOrNull();
    return first?.content ?? '';
  }

  static String _clip(String text) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length <= kNotebookExcerptChars) return trimmed;
    final cut = trimmed.lastIndexOf(' ', kNotebookExcerptChars);
    return '${trimmed.substring(0, cut > 0 ? cut : kNotebookExcerptChars)}…';
  }
}
