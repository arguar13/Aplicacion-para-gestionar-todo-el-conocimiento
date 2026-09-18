import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';

part 'property_value.freezed.dart';

/// Un valor bajo una categoría, en general —"Roma" bajo "Región"—, sin
/// atarlo todavía a ningún elemento en particular.
///
/// Aparte de [ItemProperty], que es "este elemento tiene puesto este
/// valor": [PropertyValue] es el valor en sí, el que se lista para
/// sugerir mientras se escribe uno nuevo o para armar un filtro — la
/// misma distinción que ya existe entre [Tag] y una fila de `ItemTags`.
@freezed
sealed class PropertyValue with _$PropertyValue {
  const factory PropertyValue({
    required String id,
    required String definitionId,
    required String value,
    required DateTime createdAt,

    /// Solo si la categoría dueña es de tipo número: el valor real, para
    /// poder ordenar y filtrar por rango. [value] sigue siendo el texto
    /// que se muestra ("42.5").
    double? numberValue,

    /// Solo si la categoría dueña es de tipo fecha. [value] sigue siendo
    /// el texto que se muestra; esta es la representación estructurada
    /// que hace posible ordenar por fecha de verdad.
    HistoricalDate? historicalDate,
  }) = _PropertyValue;
}
