import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failures.dart';

/// La cola de sugerencias del modelo de lenguaje: dueño de crearlas,
/// listarlas y decidir su destino —no de la asignación en sí, que sigue
/// siendo de `OrganizeRepository`—.
abstract interface class SuggestionRepository {
  /// Las sugerencias en `pending` para [itemId], de más vieja a más
  /// nueva, actualizándose solas.
  Stream<List<Suggestion>> watchPendingSuggestions(String itemId);

  /// Todas las sugerencias de duplicado en `pending`, de toda la bóveda
  /// —no de un solo elemento—, de más vieja a más nueva, actualizándose
  /// solas. Para la pantalla "Posibles duplicados" (F7): a diferencia
  /// de [watchPendingSuggestions], que alimenta el 4º botón de la
  /// Bandeja sobre un elemento puntual, acá no hay ningún elemento de
  /// partida — se revisan todas juntas, sin importar cuál las generó.
  Stream<List<Suggestion>> watchPendingDuplicateSuggestions();

  /// Crea una sugerencia de propiedad nueva, en `status: pending`.
  /// Genera `id`/`createdAt` internamente — mismo patrón que
  /// `OrganizeRepository.createHighlight`.
  Future<Either<Failure, Suggestion>> createPropertySuggestion({
    required String targetItemId,
    required String definitionId,
    required String definitionName,
    required String value,
    required bool isNewValue,
  });

  /// Crea una sugerencia de vínculo nueva, en `status: pending`. Mismo
  /// criterio que [createPropertySuggestion]: genera `id`/`createdAt`
  /// internamente. [relatedItemTitle] queda denormalizado en el
  /// payload, mismo criterio que `definitionName` en la forma
  /// `property`.
  Future<Either<Failure, Suggestion>> createRelationSuggestion({
    required String targetItemId,
    required String relatedItemId,
    required String relatedItemTitle,
    required RelationKind kind,
    required String reason,
    double? confidence,
  });

  /// Crea una sugerencia de duplicado nueva, en `status: pending`. Mismo
  /// criterio que [createRelationSuggestion]: genera `id`/`createdAt`
  /// internamente. [duplicateItemTitle] queda denormalizado en el
  /// payload, mismo criterio que `relatedItemTitle`.
  Future<Either<Failure, Suggestion>> createDuplicateSuggestion({
    required String targetItemId,
    required String duplicateItemId,
    required String duplicateItemTitle,
    required DuplicateMatchKind matchKind,
    double? confidence,
  });

  /// Aplica el payload de verdad —vía
  /// `OrganizeRepository.assignProperty` con `origin: suggestedAccepted`
  /// para una sugerencia de propiedad, `OrganizeRepository.createRelation`
  /// para una de vínculo, o `MergeDuplicateItemsUseCase` para una de
  /// duplicado— y marca `status: accepted`. Si la aplicación falla, la
  /// sugerencia queda `pending`, reintentable.
  Future<Either<Failure, Unit>> accept(String id);

  /// Marca `status: rejected` sin aplicar nada.
  Future<Either<Failure, Unit>> reject(String id);
}
