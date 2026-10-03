import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/item_metadata_extraction.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

/// Los datos de la referencia de una fuente —autor, año, editorial…—,
/// completados solos (F27) con lo que se lee del archivo o de la página:
/// lo mismo que la sugerencia de F15 (D12), aceptada sin esperar a nadie.
///
/// Completa **solo los campos vacíos** (`AiRunRepository.completeReference`):
/// nunca pisa lo que la persona escribió. No usa el modelo de lenguaje; está
/// en la cola porque es parte de organizar el elemento y tiene su
/// interruptor.
///
/// Si la persona ya descartó o aceptó la de esta fuente, no se repite: lo
/// descartado es un «no», y lo aceptado ya se aplicó. Cada dato que completa
/// queda en la pasada (v35): «deshacer todo» lo vacía de nuevo, si sigue con
/// lo que puso la IA.
class AutoReferenceStep implements AiOrganizeStep {
  const AutoReferenceStep({
    required FileStore files,
    required SuggestionRepository suggestions,
    required AiRunRepository runs,
  }) : _files = files,
       _suggestions = suggestions,
       _runs = runs;

  final FileStore _files;
  final SuggestionRepository _suggestions;
  final AiRunRepository _runs;

  @override
  AiOrganizeToggle get toggle => AiOrganizeToggle.reference;

  @override
  Future<AiStepReport> organize(
    KnowledgeItem item, {
    required String runId,
  }) async {
    if (itemKindFor(item.source.kind) != ItemKind.source) {
      return AiStepReport.nothing;
    }

    final earlier = (await _suggestions.suggestionsFor(item.id))
        .orThrowStep('leer las sugerencias de la fuente')
        .whereType<MetadataSuggestion>();
    if (earlier.any((s) => s.status != SuggestionStatus.pending)) {
      return AiStepReport.nothing;
    }

    final extracted = await extractedMetadataOf(item, _files);
    if (extracted == null || extracted.isEmpty) return AiStepReport.nothing;

    // La pendiente que dejó el procesamiento, si la hay, es la misma lectura:
    // queda aceptada.
    final completed = (await _runs.completeReference(
      runId: runId,
      itemId: item.id,
      extracted: extracted,
    )).orThrowStep('completar la referencia');
    return AiStepReport(applied: completed);
  }
}
