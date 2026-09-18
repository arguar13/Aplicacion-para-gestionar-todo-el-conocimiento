import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_generator.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

/// Implementación de [PropertySuggestionGenerator]. Vive en `data/`, no en
/// `domain/`, porque [_loadVocabulary] lee `PropertyDefinitions`/
/// `PropertyValues`/`PropertyAliases` directo de [AppDatabase] — ver la
/// documentación de la interfaz para el motivo completo.
class GeneratePropertySuggestionsUseCase
    implements PropertySuggestionGenerator {
  const GeneratePropertySuggestionsUseCase({
    required AppDatabase database,
    required PropertySuggestionService service,
    required ChatModelManager modelManager,
    required OrganizeRepository organize,
    required SuggestionRepository suggestions,
    required TelemetryService telemetry,
  }) : _db = database,
       _service = service,
       _modelManager = modelManager,
       _organize = organize,
       _suggestions = suggestions,
       _telemetry = telemetry;

  final AppDatabase _db;
  final PropertySuggestionService _service;
  final ChatModelManager _modelManager;
  final OrganizeRepository _organize;
  final SuggestionRepository _suggestions;
  final TelemetryService _telemetry;

  @override
  Future<void> generate(KnowledgeItem item) async {
    try {
      final content = item.searchableText.trim();
      if (content.isEmpty) return;
      if (!await _modelManager.isReady()) return;

      final categories = await _loadVocabulary();
      if (categories.isEmpty) return;

      final drafts = await _service.suggestProperties(
        itemTitle: item.title,
        itemContent: content,
        categories: categories,
      );

      final alreadyAssigned = item.properties.map((p) => p.valueId).toSet();

      for (final draft in drafts) {
        final resolved = await _organize.resolvePropertyValue(
          definitionId: draft.definitionId,
          text: draft.value,
        );
        final existing = resolved.getRight().toNullable();
        if (existing != null && alreadyAssigned.contains(existing.id)) {
          // Ya lo tiene asignado: sugerirlo de nuevo sería ruido.
          continue;
        }

        await _suggestions.createPropertySuggestion(
          targetItemId: item.id,
          definitionId: draft.definitionId,
          definitionName: draft.definitionName,
          value: draft.value,
          isNewValue: existing == null,
        );
      }
      // Nunca deja escapar un error: una sugerencia que no se pudo generar
      // degrada a "no se generó nada", no a un error visible en ningún lado.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'GeneratePropertySuggestionsUseCase.generate',
      );
    }
  }

  /// Solo categorías [PropertyValueType.text]: `assignProperty` solo
  /// escribe `PropertyValues.value` como texto, nunca los campos de fecha
  /// o el valor numérico, así que aceptar una sugerencia bajo una categoría
  /// de otro tipo dejaría esos campos en `null` de forma inconsistente.
  Future<List<PropertyVocabularyCategory>> _loadVocabulary() async {
    final definitions = await (_db.select(
      _db.propertyDefinitions,
    )..where((d) => d.type.equalsValue(PropertyValueType.text))).get();

    final categories = <PropertyVocabularyCategory>[];
    for (final definition in definitions) {
      final values = await (_db.select(
        _db.propertyValues,
      )..where((v) => v.definitionId.equals(definition.id))).get();
      final aliases = await (_db.select(
        _db.propertyAliases,
      )..where((a) => a.definitionId.equals(definition.id))).get();

      categories.add(
        PropertyVocabularyCategory(
          definitionId: definition.id,
          name: definition.name,
          values: values.map((v) => v.value).toList(),
          aliases: aliases.map((a) => a.alias).toList(),
        ),
      );
    }
    return categories;
  }
}
