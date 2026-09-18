import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';
import 'package:sinapsis/features/relations/domain/services/relation_candidate_selector.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/features/suggestions/domain/services/relation_suggestion_generator.dart';

/// Cuántos caracteres del elemento semilla se le mandan al LLM como
/// excerpt — mismo límite que ya usa el diálogo manual de sugerencias del
/// grafo, para que el modelo reciba un fragmento de tamaño consistente
/// sin importar por qué vía llegó.
const _seedExcerptMaxLength = 280;

/// Cuántos candidatos, como máximo, se le mandan al LLM en el camino
/// automático — menos que los 30 del diálogo manual, porque este corre
/// en segundo plano sin que nadie lo esté esperando. El pool que
/// preselecciona [RelationCandidateSelector] antes de excluir los ya
/// vinculados es más grande que esto a propósito (su propio default,
/// `limit: 15`) — no hace falta repetirlo acá: algunos de esos 15 pueden
/// descartarse por ya estar vinculados, y este número es el tope
/// después de ese filtro, no antes.
const _maxCandidatesToLlm = 10;

/// [RelationSuggestionGenerator] — el motor de relaciones de F5.
///
/// Vive en `data/`, no en `domain/`, porque orquesta directamente
/// `AppDatabase` (para el chunking) además de varios servicios de
/// dominio — mismo criterio que `GeneratePropertySuggestionsUseCase` de
/// F4 (D10 de esa fase).
class GenerateRelationSuggestionsUseCase
    implements RelationSuggestionGenerator {
  const GenerateRelationSuggestionsUseCase({
    required AppDatabase database,
    required IdGenerator ids,
    required EmbeddingModelManager embeddingModelManager,
    required ChunkEmbeddingIndexer indexer,
    required RelationCandidateSelector selector,
    required ChatModelManager chatModelManager,
    required RelationSuggestionService service,
    required OrganizeRepository organize,
    required SuggestionRepository suggestions,
    required TelemetryService telemetry,
  }) : _db = database,
       _ids = ids,
       _embeddingModelManager = embeddingModelManager,
       _indexer = indexer,
       _selector = selector,
       _chatModelManager = chatModelManager,
       _service = service,
       _organize = organize,
       _suggestions = suggestions,
       _telemetry = telemetry;

  final AppDatabase _db;
  final IdGenerator _ids;
  final EmbeddingModelManager _embeddingModelManager;
  final ChunkEmbeddingIndexer _indexer;
  final RelationCandidateSelector _selector;
  final ChatModelManager _chatModelManager;
  final RelationSuggestionService _service;
  final OrganizeRepository _organize;
  final SuggestionRepository _suggestions;
  final TelemetryService _telemetry;

  @override
  Future<void> generate(KnowledgeItem item) async {
    try {
      // El motor solo actúa sobre fuentes, nunca notas: `chunk`/`fullText`
      // están atados por diseño de F1 a `KnowledgeSources` (ver D4).
      if (itemKindFor(item.source.kind) != ItemKind.source) return;

      // Siempre, sin depender de ningún modelo: chunking es puro (D2/D13).
      await chunkAndPersistSource(_db, itemId: item.id, ids: _ids);

      if (!await _embeddingModelManager.isReady()) return;
      await _indexer.indexItem(item.id);

      if (!await _chatModelManager.isReady()) return;

      final candidates = await _selector.selectCandidates(seedItemId: item.id);
      if (candidates.isEmpty) return;

      final relations = await _organize.watchRelationsForItem(item.id).first;
      final alreadyLinked = relations.map((r) => r.otherItemId).toSet();

      final toSend = candidates
          .where((c) => !alreadyLinked.contains(c.itemId))
          .take(_maxCandidatesToLlm)
          .toList();
      if (toSend.isEmpty) return;

      final scoreByItemId = {for (final c in toSend) c.itemId: c.score};
      final titleByItemId = {for (final c in toSend) c.itemId: c.title};

      final seedContent = item.searchableText.trim();
      final seedExcerpt = seedContent.length > _seedExcerptMaxLength
          ? '${seedContent.substring(0, _seedExcerptMaxLength)}…'
          : seedContent;

      final suggestions = await _service.suggestRelations(
        seedTitle: item.title,
        seedExcerpt: seedExcerpt,
        candidates: [
          for (final c in toSend)
            RelationCandidate(
              itemId: c.itemId,
              title: c.title,
              excerpt: c.excerpt,
            ),
        ],
      );

      for (final suggestion in suggestions) {
        final relatedItemTitle = titleByItemId[suggestion.itemId];
        if (relatedItemTitle == null) continue;

        await _suggestions.createRelationSuggestion(
          targetItemId: item.id,
          relatedItemId: suggestion.itemId,
          relatedItemTitle: relatedItemTitle,
          kind: suggestion.kind,
          reason: suggestion.reason,
          confidence: scoreByItemId[suggestion.itemId],
        );
      }
      // Nunca deja escapar un error: una sugerencia que no se pudo generar
      // degrada a "no se generó nada", no a un error visible en ningún lado.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'GenerateRelationSuggestionsUseCase.generate',
      );
    }
  }
}
