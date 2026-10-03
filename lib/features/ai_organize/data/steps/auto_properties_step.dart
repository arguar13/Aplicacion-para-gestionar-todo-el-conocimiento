import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/features/ai_organize/data/services/vocabulary_candidates.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/vocabulary_budget.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

/// Cuánto del elemento ve el modelo para elegir sus propiedades: el
/// comienzo, que es donde un texto dice de qué trata. Con el vocabulario
/// (`kPropertyVocabularyBudgetChars`) y la respuesta, entra en la ventana de
/// 2048 tokens; mandar el texto entero —como hacían las sugerencias de F4—
/// desbordaba la ventana con cualquier libro.
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
/// El modelo no ve el vocabulario entero —uno de miles de valores no entra en
/// su ventana—, sino lo más pertinente para el elemento
/// (`selectVocabularyForPrompt`): lo que nombra, lo más parecido por
/// vectores y lo más usado, de cada categoría.
///
/// Nunca repite: deja afuera lo que el elemento ya tiene, lo que ya está
/// propuesto o se descartó en «Para revisar», y lo que la persona dijo que
/// «no era». Y nunca pisa una asignación de otro origen
/// (`OrganizeRepository.assignProperty`).
class AutoPropertiesStep implements AiOrganizeStep {
  const AutoPropertiesStep({
    required VocabularyCandidatesReader vocabulary,
    required PropertySuggestionService service,
    required OrganizeRepository organize,
    required SuggestionRepository suggestions,
    required AiRunRepository runs,
  }) : _vocabulary = vocabulary,
       _service = service,
       _organize = organize,
       _suggestions = suggestions,
       _runs = runs;

  final VocabularyCandidatesReader _vocabulary;
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

    final excerpt = content.length > kPropertyExcerptChars
        ? '${content.substring(0, kPropertyExcerptChars)}…'
        : content;
    // Lo que el modelo va a ver del elemento: con eso se mide qué parte del
    // vocabulario le sirve.
    final seen = '${item.title}\n$excerpt';
    final categories = selectVocabularyForPrompt(
      await _vocabulary.read(seen),
      mentionedIn: seen,
    );
    if (categories.isEmpty) return AiStepReport.nothing;

    final drafts = await _service.suggestProperties(
      itemTitle: item.title,
      itemContent: excerpt,
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
}
