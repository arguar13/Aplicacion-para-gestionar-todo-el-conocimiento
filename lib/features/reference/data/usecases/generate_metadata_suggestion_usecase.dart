import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/item_metadata_extraction.dart';
import 'package:sinapsis/features/reference/domain/services/metadata_suggestion_generator.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

/// [MetadataSuggestionGenerator] — F15, D12.
///
/// Vive en `data/`, no en `domain/`: orquesta `FileStore` y
/// `SuggestionRepository` directo, mismo criterio que
/// `GenerateDuplicateSuggestionsUseCase` de F7.
class GenerateMetadataSuggestionUseCase implements MetadataSuggestionGenerator {
  const GenerateMetadataSuggestionUseCase({
    required FileStore files,
    required SuggestionRepository suggestions,
    required TelemetryService telemetry,
  }) : _files = files,
       _suggestions = suggestions,
       _telemetry = telemetry;

  final FileStore _files;
  final SuggestionRepository _suggestions;
  final TelemetryService _telemetry;

  @override
  Future<void> generate(KnowledgeItem item) async {
    try {
      final extracted = await extractedMetadataOf(item, _files);
      if (extracted == null || extracted.isEmpty) return;

      await _suggestions.createMetadataSuggestion(
        targetItemId: item.id,
        extracted: extracted,
      );
      // Nunca debe tumbar el procesamiento del elemento: un fallo al leer el
      // archivo original o al escribir la sugerencia se registra y se sigue,
      // igual que el resto de los generadores fire-and-forget.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'GenerateMetadataSuggestionUseCase',
      );
    }
  }
}
