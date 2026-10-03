import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/relation_confidence.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/services/relation_candidate_selector.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

/// Cuántos candidatos, como mucho, juzga el modelo por elemento: los mismos
/// diez del motor de sugerencias de F5. Con el título y 280 caracteres de
/// cada uno son unos mil tokens, y la ventana es de 2048 para todo.
const kAutoRelateMaxCandidates = 10;

/// Cuántos caracteres del elemento ve el modelo como su fragmento: los mismos
/// que ya ve de cada candidato.
const kAutoRelateSeedExcerptChars = 280;

/// Vincula sola un elemento con el resto de la biblioteca (F27): el mismo
/// camino que las sugerencias de F5 —candidatos por parecido de embeddings,
/// el modelo de lenguaje juzga cuáles van y de qué tipo—, pero lo seguro se
/// crea solo, marcado como de la IA y con el motivo en su frase, y lo dudoso
/// queda en «Para revisar» (`relationConfidence`).
///
/// También para notas, y las notas son destino igual que las fuentes: una
/// nota no tiene fragmentos, pero sí vectores de sus tramos
/// (`ChunkEmbeddingIndexer.indexNote`), que esta pasada deja al día y quedan
/// guardados para cuando otro elemento busque con qué vincularse.
///
/// Nunca repite: deja afuera lo que ya está vinculado de cualquier tipo, lo
/// que ya está para revisar o la persona descartó ahí, lo que dijo que «no
/// era», y los elementos cuya pasada de la IA se deshizo.
class AutoRelateStep implements AiOrganizeStep {
  const AutoRelateStep({
    required AppDatabase database,
    required IdGenerator ids,
    required ChunkEmbeddingIndexer indexer,
    required RelationCandidateSelector selector,
    required RelationSuggestionService service,
    required OrganizeRepository organize,
    required SuggestionRepository suggestions,
    required AiRunRepository runs,
  }) : _db = database,
       _ids = ids,
       _indexer = indexer,
       _selector = selector,
       _service = service,
       _organize = organize,
       _suggestions = suggestions,
       _runs = runs;

  final AppDatabase _db;
  final IdGenerator _ids;
  final ChunkEmbeddingIndexer _indexer;
  final RelationCandidateSelector _selector;
  final RelationSuggestionService _service;
  final OrganizeRepository _organize;
  final SuggestionRepository _suggestions;
  final AiRunRepository _runs;

  @override
  AiOrganizeToggle get toggle => AiOrganizeToggle.relations;

  @override
  Future<AiStepReport> organize(
    KnowledgeItem item, {
    required String runId,
  }) async {
    final candidates = await _candidatesFor(item);
    if (candidates.isEmpty) return AiStepReport.nothing;

    final ids = candidates.map((c) => c.itemId).toList();
    final linked = {
      for (final relation
          in await _organize.watchRelationsForItem(item.id).first)
        relation.otherItemId,
    };
    final undone = (await _runs.undoneItemsAmong(
      ids,
    )).orThrowStep('leer qué pasadas se deshicieron');
    final proposed = await _alreadyProposed(item.id, ids);

    final toSend = candidates
        .where(
          (c) =>
              !linked.contains(c.itemId) &&
              !undone.contains(c.itemId) &&
              !proposed.contains(c.itemId),
        )
        .take(kAutoRelateMaxCandidates)
        .toList();
    if (toSend.isEmpty) return AiStepReport.nothing;

    final seed = item.searchableText.trim();
    final suggestions = await _service.suggestRelations(
      seedTitle: item.title,
      seedExcerpt: seed.length > kAutoRelateSeedExcerptChars
          ? '${seed.substring(0, kAutoRelateSeedExcerptChars)}…'
          : seed,
      candidates: [
        for (final c in toSend)
          RelationCandidate(
            itemId: c.itemId,
            title: c.title,
            excerpt: c.excerpt,
          ),
      ],
    );

    final byId = {for (final c in toSend) c.itemId: c};
    // Un vínculo por candidato: si el modelo repite uno con otro tipo, vale
    // el primero —dos líneas entre los mismos dos elementos en una sola
    // pasada son ruido—.
    final decided = <String>{};
    var applied = 0;
    var forReview = 0;
    for (final suggestion in suggestions) {
      final candidate = byId[suggestion.itemId];
      if (candidate == null || !decided.add(candidate.itemId)) continue;

      final rejected = (await _runs.isRelationRejected(
        fromItemId: item.id,
        toItemId: candidate.itemId,
        kind: suggestion.kind,
      )).orThrowStep('leer lo que «no era»');
      if (rejected) continue;

      final confidence = relationConfidence(
        cosine: candidate.score,
        certainty: suggestion.certainty,
      );
      switch (relationVerdictFor(confidence)) {
        case RelationVerdict.apply:
          // Un fallo acá es que ya existe o que se dijo que «no era» entre
          // la lectura y la escritura: no hay nada que crear, y no es un
          // error del paso.
          final created = await _organize.createRelation(
            fromItemId: item.id,
            toItemId: candidate.itemId,
            kind: suggestion.kind,
            note: suggestion.reason,
            ai: AiProvenance(runId: runId, confidence: confidence),
          );
          if (created.isRight()) applied++;
        case RelationVerdict.review:
          (await _suggestions.createRelationSuggestion(
            targetItemId: item.id,
            relatedItemId: candidate.itemId,
            relatedItemTitle: candidate.title,
            kind: suggestion.kind,
            reason: suggestion.reason,
            confidence: confidence,
          )).orThrowStep('dejar un vínculo para revisar');
          forReview++;
        case RelationVerdict.discard:
          break;
      }
    }
    return AiStepReport(applied: applied, forReview: forReview);
  }

  /// Los candidatos a vincular con [item], del más parecido al menos.
  Future<List<ScoredRelationCandidate>> _candidatesFor(
    KnowledgeItem item,
  ) async {
    if (itemKindFor(item.source.kind) == ItemKind.source) {
      // Los fragmentos ya los deja `LibraryRepository.save`; esto solo cubre
      // una fuente guardada antes de que existieran. Es idempotente.
      await chunkAndPersistSource(_db, itemId: item.id, ids: _ids);
      await _indexer.indexItem(item.id);
    } else {
      // Solo los tramos que cambiaron desde la última vez.
      await _indexer.indexNote(item.id);
    }
    return _selector.selectCandidates(seedItemId: item.id);
  }

  /// De [candidateIds], los que ya tienen un vínculo propuesto con [itemId]
  /// —en cualquier sentido, en cualquier estado—: pendiente, ya está para
  /// revisar; descartado, la persona dijo que no; aceptado, ya es un vínculo.
  Future<Set<String>> _alreadyProposed(
    String itemId,
    List<String> candidateIds,
  ) async {
    final proposed = <String>{};
    final own = (await _suggestions.suggestionsFor(
      itemId,
    )).orThrowStep('leer las sugerencias del elemento');
    for (final suggestion in own.whereType<RelationSuggestionEntry>()) {
      proposed.add(suggestion.relatedItemId);
    }
    for (final candidateId in candidateIds) {
      final theirs = (await _suggestions.suggestionsFor(
        candidateId,
      )).orThrowStep('leer las sugerencias de un candidato');
      if (theirs.whereType<RelationSuggestionEntry>().any(
        (s) => s.relatedItemId == itemId,
      )) {
        proposed.add(candidateId);
      }
    }
    return proposed;
  }
}
