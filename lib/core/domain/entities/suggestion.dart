import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';

part 'suggestion.freezed.dart';

/// Una propuesta del modelo de lenguaje, siempre confirmable.
///
/// Campos planos, no un payload sellado tipo `ContentBlock`: hoy solo
/// existe la forma `property` —F4 no genera `relation`/`duplicate`/
/// `flashcard` todavía, aunque `SuggestionKind` ya las modele—. Sellar el
/// payload para una sola variante es ceremonia de más; cuando F5/F7
/// agreguen las otras formas, ahí sí conviene reconsiderarlo.
@freezed
sealed class Suggestion with _$Suggestion {
  const factory Suggestion({
    required String id,
    required SuggestionKind kind,
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
  }) = _Suggestion;
}
