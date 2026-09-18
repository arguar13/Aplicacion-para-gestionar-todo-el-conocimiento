import 'package:fpdart/fpdart.dart';
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

  /// Aplica el payload de verdad —vía
  /// `OrganizeRepository.assignProperty` con `origin: suggestedAccepted`—
  /// y marca `status: accepted`. Si la aplicación falla, la sugerencia
  /// queda `pending`, reintentable.
  Future<Either<Failure, Unit>> accept(String id);

  /// Marca `status: rejected` sin aplicar nada.
  Future<Either<Failure, Unit>> reject(String id);
}
