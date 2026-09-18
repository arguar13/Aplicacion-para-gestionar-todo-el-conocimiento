import 'package:fpdart/fpdart.dart';
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

  /// Aplica el payload de verdad —vía
  /// `OrganizeRepository.assignProperty` con `origin: suggestedAccepted`
  /// para una sugerencia de propiedad, o `OrganizeRepository.
  /// createRelation` para una de vínculo— y marca `status: accepted`. Si
  /// la aplicación falla, la sugerencia queda `pending`, reintentable.
  Future<Either<Failure, Unit>> accept(String id);

  /// Marca `status: rejected` sin aplicar nada.
  Future<Either<Failure, Unit>> reject(String id);
}
