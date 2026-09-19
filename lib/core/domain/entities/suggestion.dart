import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';

part 'suggestion.freezed.dart';

/// Una propuesta del modelo de lenguaje, siempre confirmable.
///
/// Unión sellada por variante, no campos planos ni un enum `kind`
/// aparte —hasta F4 alcanzaba con `property` a secas, con el
/// discriminante en un campo `SuggestionKind kind` (ver la decisión 35
/// de `docs/arquitectura.md` para el criterio general de no sellar
/// payloads para una sola forma). F5 agrega `relation`, así que ahora sí
/// conviene reconsiderarlo: cada variante fuerza su propio `switch`
/// exhaustivo en vez de campos que solo tienen sentido para una forma.
/// El *tipo* de la variante ya es el discriminante —no hace falta un
/// enum paralelo que podría desincronizarse de él—, aunque la columna
/// `Suggestions.kind` de la base sigue existiendo para poder filtrar en
/// SQL y saber qué forma de `payloadJson` decodificar.
///
/// `id`/`targetItemId`/`status`/`createdAt`/`confidence` son comunes a
/// las dos formas: freezed los expone como getters en la clase base
/// —confirmado en `rendition.freezed.dart`, mismo patrón—, así que
/// siguen funcionando sin `switch` en todo el código que solo necesita
/// eso.
@freezed
sealed class Suggestion with _$Suggestion {
  const factory Suggestion.property({
    required String id,
    required String targetItemId,
    required String definitionId,
    required String definitionName,
    required String value,

    /// Si [value] no coincidía con ningún valor existente bajo
    /// [definitionId] al momento de generarse — el modelo lo propuso
    /// porque "ninguno encaja", y por eso necesita confirmación
    /// explícita antes de crearse de verdad.
    required bool isNewValue,
    required SuggestionStatus status,
    required DateTime createdAt,
    double? confidence,
  }) = PropertySuggestion;

  const factory Suggestion.relation({
    required String id,
    required String targetItemId,
    required String relatedItemId,

    /// Denormalizado en el payload, no resuelto por join al leer —mismo
    /// criterio que [PropertySuggestion.definitionName].
    required String relatedItemTitle,
    required RelationKind kind,
    required String reason,
    required SuggestionStatus status,
    required DateTime createdAt,
    double? confidence,
  }) = RelationSuggestionEntry;

  /// Dos elementos que podrían ser el mismo — F7, deduplicación. Ver
  /// `MergeDuplicateItemsUseCase`, a quien `accept()` termina llamando.
  const factory Suggestion.duplicate({
    required String id,

    /// El elemento que sobrevive si se acepta — el que ya existía cuando
    /// se generó la sugerencia, no el recién capturado.
    required String targetItemId,
    required String duplicateItemId,

    /// Denormalizado en el payload, no resuelto por join al leer — mismo
    /// criterio que [PropertySuggestion.definitionName].
    required String duplicateItemTitle,
    required DuplicateMatchKind matchKind,
    required SuggestionStatus status,
    required DateTime createdAt,
    double? confidence,
  }) = DuplicateSuggestionEntry;
}
