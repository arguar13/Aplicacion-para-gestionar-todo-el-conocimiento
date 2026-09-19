import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';

part 'property_suggestion_group.freezed.dart';

/// Las sugerencias de propiedad pendientes que proponen el MISMO valor de la
/// misma categoría: "14 elementos parecen ser `Región: Roma`".
///
/// Es lo que permite triar 30 elementos de golpe en vez de uno por uno. Se
/// agrupa por categoría y valor normalizado —sin distinguir mayúsculas ni
/// acentos, la misma regla con la que el vocabulario decide qué es "el mismo
/// texto"—, así "Roma", "roma" y "ROMA" son un solo grupo.
///
/// El lote acelera la confirmación, no la quita: cada sugerencia del grupo se
/// marca o se desmarca por separado, y nada se aplica sin que alguien lo
/// haya mirado.
@freezed
sealed class PropertySuggestionGroup with _$PropertySuggestionGroup {
  const factory PropertySuggestionGroup({
    required String definitionId,

    /// El nombre ACTUAL de la categoría, no el que llevaba la sugerencia al
    /// generarse: si se renombró desde entonces, el grupo muestra el vigente.
    required String definitionName,

    /// El valor como lo escribió la mayoría de las sugerencias del grupo; a
    /// igual cantidad, el que se propuso primero.
    required String value,

    /// El valor para comparar: `normalizeVocabularyLabel`.
    required String normalizedValue,

    /// Si el valor ya existe hoy en la categoría —por su nombre o por un
    /// alias—. Si no, aceptar el grupo lo crea: es lo que hace falta mirar
    /// con más cuidado. No es lo que decía cada sugerencia al generarse:
    /// el valor pudo crearse desde entonces.
    required bool valueExists,

    /// Las sugerencias del grupo, de la más vieja a la más nueva. Cada una
    /// apunta a un elemento distinto.
    required List<PropertySuggestion> suggestions,
  }) = _PropertySuggestionGroup;
}
