import 'package:freezed_annotation/freezed_annotation.dart';

part 'item_property.freezed.dart';

/// Un valor de propiedad puesto en un elemento: "Región: Roma".
///
/// [definitionName] y [value] llegan ya resueltos —no solo los `id`—
/// porque es lo único que hace falta para mostrarlo: la Biblioteca y el
/// detalle no necesitan volver a consultar la categoría ni el valor cada
/// vez que dibujan un elemento, igual que [Tag] ya trae su propio
/// [Tag.name] en vez de solo un `id`.
///
/// [valueId] identifica el par (categoría, valor) tal como vive en
/// `PropertyValues`: dos elementos con "Región: Roma" comparten el mismo
/// [valueId], igual que dos elementos con la etiqueta "Filosofía"
/// comparten el mismo `Tag.id` — es lo que permite después filtrar por
/// "todo lo que tiene esta propiedad puesta", no solo mostrarla.
@freezed
sealed class ItemProperty with _$ItemProperty {
  const factory ItemProperty({
    required String definitionId,
    required String definitionName,
    required String valueId,
    required String value,
    required DateTime createdAt,
  }) = _ItemProperty;
}
