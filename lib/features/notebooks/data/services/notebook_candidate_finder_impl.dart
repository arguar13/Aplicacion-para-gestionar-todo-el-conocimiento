import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';
import 'package:sinapsis/features/relations/domain/services/item_vector_index.dart';

/// [NotebookCandidateFinder] sobre lo que ya hay (F30), **solo entre los
/// documentos procesados** (F41, paso 5): un cuaderno se arma con ellos y con
/// nada más.
///
/// - **Por palabras**, el buscador del chat (`ChunkPassageRetriever`) acotado
///   a los procesados vivos: de cada uno, el pasaje de sus partes que más
///   palabras de lo buscado junta.
/// - **Por sentido**, si el modelo de vínculos está bajado: el vector de lo
///   buscado (`EmbeddingService.embedQuery`) contra los ya guardados de cada
///   fragmento (`ItemVectorIndex.nearestTo`). Los vectores son de las fuentes
///   —un procesado no tiene fragmentos propios—, así que se busca solo entre
///   las fuentes de los procesados vivos, y cada una cuenta por su documento
///   procesado; una fuente sin procesar no se propone, ni ocupa lugar.
///   Encuentra «el Senado» buscando «Roma» aunque no diga Roma, y lo que se
///   muestra y revisa la IA es el texto del procesado.
///
/// Las dos listas se juntan con [fuseRankings]. Si buscar por sentido falla,
/// se sigue con lo de las palabras y el resultado lo dice
/// ([SenseSearch.failed]): es una mejora de la búsqueda, no la búsqueda.
class NotebookCandidateFinderImpl implements NotebookCandidateFinder {
  NotebookCandidateFinderImpl({
    required AppDatabase database,
    required ProcessedRepository processed,
    required VaultRetriever retriever,
    required ItemVectorIndex vectors,
    required EmbeddingService embeddings,
    required Future<bool> Function() embeddingsReady,
    required TelemetryService telemetry,
  }) : _db = database,
       _processed = processed,
       _retriever = retriever,
       _vectors = vectors,
       _embeddings = embeddings,
       _embeddingsReady = embeddingsReady,
       _telemetry = telemetry;

  final AppDatabase _db;
  final ProcessedRepository _processed;
  final VaultRetriever _retriever;
  final ItemVectorIndex _vectors;
  final EmbeddingService _embeddings;
  final Future<bool> Function() _embeddingsReady;
  final TelemetryService _telemetry;

  /// Cuántos ids entran en una sola consulta: por debajo del tope de
  /// parámetros de SQLite.
  static const _idsPerQuery = 400;

  @override
  Future<NotebookSearchResult> find(
    String topic, {
    int limit = kNotebookCandidateLimit,
  }) async {
    // Sin ningún procesado no hay nada que proponer: ni se busca.
    final processed = (await _processed.matchingIds(
      const ProcessedQuery(),
    )).getOrElse((_) => const []).toSet();
    if (processed.isEmpty) {
      return const NotebookSearchResult(
        candidates: [],
        senseSearch: SenseSearch.unavailable,
      );
    }

    final words = notebookTopicQuery(topic);
    final byWords = words.isEmpty
        ? const <({String itemId, String title, String excerpt})>[]
        : [
            for (final source in await _retriever.retrieve(
              words,
              limit: limit,
              scopeIds: processed,
            ))
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
        // Los vectores son de las fuentes: se busca solo entre las de los
        // procesados vivos —y entre los procesados mismos, si tuvieran—, así
        // el tope se llena con lo que se puede proponer.
        final docOf = await _documentsBySource(processed);
        bySense = _asDocuments(
          await _vectors.nearestTo(
            await _embeddings.embedQuery(topic.trim()),
            limit: limit,
            minSimilarity: kNotebookMinSimilarity,
            among: docOf.keys,
          ),
          docOf,
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
      final excerpt = hit?.excerpt.trim() ?? '';
      candidates.add(
        NotebookCandidate(
          itemId: id,
          title: row.title,
          // Si lo encontró solo el título, el principio de lo que tiene.
          excerpt: _clip(excerpt.isNotEmpty ? excerpt : await _beginningOf(id)),
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

  /// De qué documento procesado es cada id que puede tener vectores: la
  /// fuente de cada uno de [documents], y cada uno de ellos mismo.
  Future<Map<String, String>> _documentsBySource(Set<String> documents) async {
    final docOf = {for (final doc in documents) doc: doc};
    final ids = documents.toList();
    for (var start = 0; start < ids.length; start += _idsPerQuery) {
      final slice = ids.skip(start).take(_idsPerQuery).toList();
      final rows = await _db
          .customSelect(
            'SELECT item_id AS doc, source_item_id AS source '
            'FROM processed_documents WHERE source_item_id IS NOT NULL '
            'AND item_id IN (${List.filled(slice.length, '?').join(', ')})',
            variables: [for (final id in slice) Variable.withString(id)],
            readsFrom: {_db.processedDocuments},
          )
          .get();
      for (final row in rows) {
        docOf[row.read<String>('source')] = row.read<String>('doc');
      }
    }
    return docOf;
  }

  /// Los parecidos de [hits] como parecidos de sus documentos procesados
  /// ([docOf]), en el mismo orden y sin repetir: una fuente cuenta por su
  /// procesado.
  static List<ItemSimilarity> _asDocuments(
    List<ItemSimilarity> hits,
    Map<String, String> docOf,
  ) {
    final seen = <String>{};
    return [
      for (final hit in hits)
        if (docOf[hit.itemId] case final doc? when seen.add(doc))
          ItemSimilarity(itemId: doc, score: hit.score),
    ];
  }

  /// El título y el tipo de la fuente de origen de cada uno de [ids] que
  /// sigue vivo.
  Future<Map<String, ({String title, SourceKind kind})>> _rowsOf(
    List<String> ids,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT i.id AS id, i.title AS title, pd.source_kind AS kind '
          'FROM item i JOIN processed_documents pd ON pd.item_id = i.id '
          'WHERE ${activeItemSql('i')} '
          'AND i.id IN (${List.filled(ids.length, '?').join(', ')})',
          variables: [for (final id in ids) Variable.withString(id)],
          readsFrom: {_db.knowledgeEntries, _db.processedDocuments},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): (
          title: row.read<String>('title'),
          kind:
              SourceKind.values.asNameMap()[row.read<String>('kind')] ??
              SourceKind.manualNote,
        ),
    };
  }

  /// El comienzo de [documentId]: su primera parte, en el orden en que se lee
  /// el documento —el texto, el resumen, la síntesis, las notas, los
  /// fragmentos—.
  Future<String> _beginningOf(String documentId) async {
    for (final section in ProcessedSection.values) {
      final first = await _processed
          .watchParts(documentId, section, limit: 1)
          .first;
      if (first.isNotEmpty) return first.single.content;
    }
    return '';
  }

  static String _clip(String text) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length <= kNotebookExcerptChars) return trimmed;
    final cut = trimmed.lastIndexOf(' ', kNotebookExcerptChars);
    return '${trimmed.substring(0, cut > 0 ? cut : kNotebookExcerptChars)}…';
  }
}
