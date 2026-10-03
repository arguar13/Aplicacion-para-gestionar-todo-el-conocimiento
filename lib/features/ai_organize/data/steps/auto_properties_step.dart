import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

/// Cuánto del elemento ve el modelo para elegir sus propiedades: el
/// comienzo, que es donde un texto dice de qué trata. Con el vocabulario y
/// la respuesta, entra holgado en la ventana de 2048 tokens; mandar el texto
/// entero —como hacían las sugerencias de F4— desbordaba la ventana con
/// cualquier libro.
const kPropertyExcerptChars = 2400;

/// Los temas, las etiquetas y las propiedades de un elemento, puestos por la
/// IA (F27): lo que hasta acá quedaba como sugerencia.
///
/// Qué es seguro y qué no lo decide algo que se puede comprobar, no lo que
/// dice el modelo: **un valor que ya está en el vocabulario de la persona se
/// asigna solo** —marcado como de la IA, con su pasada—; **uno nuevo queda en
/// «Para revisar»**: inventar una palabra para el vocabulario de alguien es
/// justo lo que hay que mirar antes.
///
/// Nunca repite: deja afuera lo que el elemento ya tiene, lo que ya está
/// propuesto o se descartó en «Para revisar», y lo que la persona dijo que
/// «no era». Y nunca pisa una asignación de otro origen
/// (`OrganizeRepository.assignProperty`).
class AutoPropertiesStep implements AiOrganizeStep {
  const AutoPropertiesStep({
    required AppDatabase database,
    required PropertySuggestionService service,
    required OrganizeRepository organize,
    required SuggestionRepository suggestions,
    required AiRunRepository runs,
  }) : _db = database,
       _service = service,
       _organize = organize,
       _suggestions = suggestions,
       _runs = runs;

  final AppDatabase _db;
  final PropertySuggestionService _service;
  final OrganizeRepository _organize;
  final SuggestionRepository _suggestions;
  final AiRunRepository _runs;

  @override
  AiOrganizeToggle get toggle => AiOrganizeToggle.properties;

  @override
  Future<AiStepReport> organize(
    KnowledgeItem item, {
    required String runId,
  }) async {
    final content = item.searchableText.trim();
    if (content.isEmpty) return AiStepReport.nothing;

    final categories = await _loadVocabulary();
    if (categories.isEmpty) return AiStepReport.nothing;

    final drafts = await _service.suggestProperties(
      itemTitle: item.title,
      itemContent: content.length > kPropertyExcerptChars
          ? '${content.substring(0, kPropertyExcerptChars)}…'
          : content,
      categories: categories,
    );

    // Las etiquetas son valores de Tema: si el elemento ya tiene el valor
    // como etiqueta, ponerlo de nuevo es ruido.
    final assigned = {
      ...item.properties.map((p) => p.valueId),
      ...item.tags.map((t) => t.id),
    };
    final proposed = {
      for (final suggestion
          in (await _suggestions.suggestionsFor(item.id))
              .orThrowStep('leer las sugerencias del elemento')
              .whereType<PropertySuggestion>())
        propertyRejectionFingerprint(
          definitionName: suggestion.definitionName,
          value: suggestion.value,
        ),
    };

    var applied = 0;
    var forReview = 0;
    for (final draft in drafts) {
      final fingerprint = propertyRejectionFingerprint(
        definitionName: draft.definitionName,
        value: draft.value,
      );
      if (!proposed.add(fingerprint)) continue;
      final rejected = (await _runs.isPropertyRejected(
        itemId: item.id,
        definitionName: draft.definitionName,
        value: draft.value,
      )).orThrowStep('leer lo que «no era»');
      if (rejected) continue;

      final existing = (await _organize.resolvePropertyValue(
        definitionId: draft.definitionId,
        text: draft.value,
      )).orThrowStep('buscar el valor en el vocabulario');

      if (existing != null) {
        if (assigned.contains(existing.id)) continue;
        // Con el nombre del valor, no con lo que escribió el modelo: si
        // escribió un alias, se asigna el valor de ese alias, no uno nuevo.
        // Un fallo es que se dijo «no era» o que la persona lo puso entre la
        // lectura y la escritura: no hay nada que poner.
        final result = await _organize.assignProperty(
          itemId: item.id,
          definitionId: draft.definitionId,
          value: existing.value,
          origin: ItemPropertyOrigin.ai,
          aiRunId: runId,
        );
        if (result.isRight()) {
          assigned.add(existing.id);
          applied++;
        }
      } else {
        (await _suggestions.createPropertySuggestion(
          targetItemId: item.id,
          definitionId: draft.definitionId,
          definitionName: draft.definitionName,
          value: draft.value,
          isNewValue: true,
        )).orThrowStep('dejar un valor nuevo para revisar');
        forReview++;
      }
    }
    return AiStepReport(applied: applied, forReview: forReview);
  }

  /// Las categorías de texto con sus valores y alias. Solo las de texto:
  /// `assignProperty` escribe el valor como texto, y bajo una categoría de
  /// fecha o de número dejaría esos campos vacíos —mismo criterio que las
  /// sugerencias de F4—.
  Future<List<PropertyVocabularyCategory>> _loadVocabulary() async {
    final definitions = await (_db.select(
      _db.propertyDefinitions,
    )..where((d) => d.type.equalsValue(PropertyValueType.text))).get();

    return [
      for (final definition in definitions)
        PropertyVocabularyCategory(
          definitionId: definition.id,
          name: definition.name,
          values: [
            for (final value in await (_db.select(
              _db.propertyValues,
            )..where((v) => v.definitionId.equals(definition.id))).get())
              value.value,
          ],
          aliases: [
            for (final alias in await (_db.select(
              _db.propertyAliases,
            )..where((a) => a.definitionId.equals(definition.id))).get())
              alias.alias,
          ],
        ),
    ];
  }
}
