import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
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

  /// Los datos bibliográficos que se pudieron leer del PDF, de la página o
  /// de YouTube de una fuente — F15, D12. No es del modelo de lenguaje como
  /// las otras tres, pero comparte con ellas lo que importa: nunca se
  /// escribe sin que alguien la mire primero, y por eso vive en la misma
  /// unión. Una sola por fuente, con todo lo que encontró junto —no una por
  /// dato—: aceptarla de a poco dejaría una referencia a medio completar sin
  /// que quien la revisó lo supiera.
  const factory Suggestion.metadata({
    required String id,
    required String targetItemId,
    required ExtractedMetadata extracted,
    required SuggestionStatus status,
    required DateTime createdAt,
    double? confidence,
  }) = MetadataSuggestion;

  /// Poner el tema [valueName], que estaba suelto —sin padre ni subtemas—,
  /// bajo [parentName] en el árbol de la categoría [definitionId] — F27, el
  /// Atlas. [targetItemId] es el elemento en cuya pasada la IA lo encontró:
  /// por él se agrupa en «Para revisar».
  ///
  /// Con [aiRunId], la IA la aplicó sola —estaba segura y el tema era nuevo—
  /// y la fila queda `accepted` como registro de lo que hizo: deshacer la
  /// pasada lo devuelve a la raíz. Sin él, es una propuesta para revisar.
  /// Los nombres van denormalizados, mismo criterio que
  /// [PropertySuggestion.definitionName].
  const factory Suggestion.topicParent({
    required String id,
    required String targetItemId,
    required String definitionId,
    required String valueId,
    required String valueName,
    required String parentId,
    required String parentName,
    required SuggestionStatus status,
    required DateTime createdAt,
    String? aiRunId,
    double? confidence,
  }) = TopicParentSuggestion;

  /// Subir la madurez de la nota viva [targetItemId] de [from] a [to] — F27,
  /// el Atlas. Solo se propone: cambiarla es el juicio de la persona, y la
  /// IA nunca lo hace sola (decisión A).
  const factory Suggestion.maturity({
    required String id,
    required String targetItemId,
    required NoteMaturity from,
    required NoteMaturity to,
    required SuggestionStatus status,
    required DateTime createdAt,
    double? confidence,
  }) = MaturitySuggestion;
}
