import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/suggestions/domain/entities/pending_review_item.dart';
import 'package:sinapsis/features/suggestions/domain/entities/property_suggestion_group.dart';

/// La cola de sugerencias del modelo de lenguaje: dueño de crearlas,
/// listarlas y decidir su destino —no de la asignación en sí, que sigue
/// siendo de `OrganizeRepository`—.
abstract interface class SuggestionRepository {
  /// Las sugerencias en `pending` para [itemId], de más vieja a más
  /// nueva, actualizándose solas.
  Stream<List<Suggestion>> watchPendingSuggestions(String itemId);

  /// Todas las sugerencias de [itemId], en cualquier estado —pendientes,
  /// aceptadas o descartadas—, de más vieja a más nueva (F27). Es lo que mira
  /// la IA antes de proponer algo: lo que ya está para revisar no se repite,
  /// y lo que la persona descartó en «Para revisar» no se vuelve a proponer.
  Future<Either<Failure, List<Suggestion>>> suggestionsFor(String itemId);

  /// Todas las sugerencias de duplicado en `pending`, de toda la bóveda
  /// —no de un solo elemento—, de más vieja a más nueva, actualizándose
  /// solas. Para la pantalla "Posibles duplicados" (F7): a diferencia
  /// de [watchPendingSuggestions], que alimenta el 4º botón de la
  /// Bandeja sobre un elemento puntual, acá no hay ningún elemento de
  /// partida — se revisan todas juntas, sin importar cuál las generó.
  Stream<List<Suggestion>> watchPendingDuplicateSuggestions();

  /// Los elementos vivos con algo «Para revisar» (F27) —sugerencias
  /// pendientes de vínculo, propiedad o referencia—, el de la más reciente
  /// primero, actualizándose solos.
  ///
  /// Es la otra mitad de [watchPendingSuggestions]: la Bandeja y el detalle
  /// leen elemento por elemento; «Lo que hizo la IA» necesita saber de qué
  /// elementos hablar sin abrir una consulta por cada uno de la bóveda. Trae
  /// solo los ids: lo que se ve de cada sugerencia lo decodifica
  /// [watchPendingSuggestions], y solo para lo que está en pantalla.
  ///
  /// Los duplicados no entran: fusionar borra un elemento y tienen su propia
  /// pantalla (decisión A de F27). Un vínculo propuesto hacia algo que está
  /// en la papelera tampoco, igual que en [watchPendingSuggestions].
  Stream<List<PendingReviewItem>> watchItemsWithPendingReview();

  /// Cuántas sugerencias hay «Para revisar» en toda la bóveda (F27), con el
  /// mismo criterio que [watchItemsWithPendingReview], actualizándose solo:
  /// el número que acompaña a «Lo que hizo la IA» en Ajustes › IA. Un solo
  /// número, sin traer ni agrupar las filas.
  Stream<int> watchPendingReviewCount();

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

  /// Crea la sugerencia de referencia de [targetItemId] con lo que
  /// [extracted] encontró —F15, D12—, en `status: pending`.
  ///
  /// Una sola por fuente: si ya había una pendiente, la reemplaza —es lo
  /// que pasa al volver a generarla al abrir el formulario—, en vez de
  /// acumular una por cada vez que alguien la mira. Quien llama comprueba
  /// antes que [extracted] no esté vacío —`ExtractedMetadata.isEmpty`—: no
  /// hay sugerencia que ofrecer sin nada encontrado.
  Future<Either<Failure, Suggestion>> createMetadataSuggestion({
    required String targetItemId,
    required ExtractedMetadata extracted,
  });

  /// Aplica el payload de verdad —vía
  /// `OrganizeRepository.assignProperty` con `origin: suggestedAccepted`
  /// para una sugerencia de propiedad, `OrganizeRepository.createRelation`
  /// para una de vínculo, `MergeDuplicateItemsUseCase` para una de
  /// duplicado, o `KnowledgeEntryWriter.setReference` para una de
  /// referencia, completando solo lo que la referencia todavía no tenía—
  /// y marca `status: accepted`. Si la aplicación falla, la sugerencia
  /// queda `pending`, reintentable.
  Future<Either<Failure, Unit>> accept(String id);

  /// Marca `status: rejected` sin aplicar nada.
  Future<Either<Failure, Unit>> reject(String id);

  /// Las sugerencias de propiedad pendientes de toda la bóveda, agrupadas por
  /// categoría y valor propuesto, actualizándose solas: los grupos con más
  /// elementos primero y, a igual cantidad, por categoría y valor.
  ///
  /// Solo entran las que se pueden aplicar: se dejan afuera las de una
  /// categoría que ya no existe y las de un valor vacío. Una sola que no se
  /// pudiera aplicar haría fallar el lote entero de [acceptMany].
  Stream<List<PropertySuggestionGroup>> watchPendingPropertySuggestionGroups();

  /// Aplica varias sugerencias de propiedad de una sola vez —igual que
  /// [accept] con cada una— y devuelve cuántas.
  ///
  /// Es atómico: si alguna no se puede aplicar, ninguna queda aplicada y
  /// todas siguen `pending`. Falla sin aplicar nada si alguna de [ids] no
  /// existe, ya no está pendiente o no es de propiedad. Un id repetido cuenta
  /// una vez. El valor que propone el grupo se crea una sola vez, no una por
  /// sugerencia.
  Future<Either<Failure, int>> acceptMany(List<String> ids);

  /// Marca `status: rejected` varias sugerencias pendientes sin aplicar nada
  /// y devuelve cuántas. Una que ya no está pendiente no se toca.
  Future<Either<Failure, int>> rejectMany(List<String> ids);

  /// Deshace la aceptación de una sugerencia de propiedad ya aceptada: quita
  /// del elemento la propiedad que esa aceptación puso y la deja `pending` de
  /// nuevo, como si nadie la hubiera tocado.
  ///
  /// Solo quita lo que la propia aceptación puso. Si el elemento ya tenía esa
  /// propiedad —puesta a mano o heredada— la aceptación no la tocó, y esto
  /// tampoco: se deshace el estado de la sugerencia, nunca una decisión del
  /// usuario. El valor que la aceptación haya creado y nadie más use se va con
  /// ella, para no dejar en el vocabulario un valor huérfano.
  ///
  /// Falla si la sugerencia no existe, no es de propiedad o no está aceptada.
  Future<Either<Failure, Unit>> revertAccepted(String id);

  /// Deshace de una vez la aceptación de varias sugerencias de propiedad
  /// —lo que [acceptMany] aplicó— igual que [revertAccepted] con cada una, y
  /// devuelve cuántas.
  ///
  /// Es atómico, como [acceptMany]: si alguna no se puede deshacer —no existe,
  /// no es de propiedad o ya no está aceptada, porque otra cosa la tocó
  /// mientras tanto—, ninguna se deshace y todas siguen como estaban. Un id
  /// repetido cuenta una vez.
  ///
  /// El valor que la aceptación en lote haya creado se va cuando la última
  /// asignación se quita y nadie más lo usa: no queda un valor huérfano en el
  /// vocabulario.
  Future<Either<Failure, int>> revertAcceptedMany(List<String> ids);
}
