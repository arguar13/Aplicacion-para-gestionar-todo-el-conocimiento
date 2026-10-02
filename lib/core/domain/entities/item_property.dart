import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';

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

    /// A mano, heredada al extraer una nota, o una sugerencia del
    /// modelo ya aceptada. Viaja acá y no solo en la columna de la base
    /// porque `LibraryRepositoryImpl._syncProperties` reescribe
    /// `ItemPropertyValues` entera en cada `save()` a partir de esta
    /// lista: si `origin` no estuviera acá, cualquier edición
    /// posterior del elemento lo devolvería en silencio a `manual`.
    @Default(ItemPropertyOrigin.manual) ItemPropertyOrigin origin,

    /// La pasada de la IA que la puso (F27), solo con [origin] en `ai`. Viaja
    /// acá por lo mismo que [origin]: `save()` reescribe las asignaciones a
    /// partir de esta lista, y sin ella la pasada se perdería en silencio y
    /// «deshacer todo» ya no la encontraría.
    String? aiRunId,
  }) = _ItemProperty;
}
