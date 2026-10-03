import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';

/// El Atlas: el índice dinámico de lo que se sabe y de lo que falta (F13).
///
/// Sale de las propiedades y las notas, y ninguna escritura es de este
/// repositorio. Los agregados por rama son costosos —recorren cada asignación
/// de la categoría—, así que el resultado se guarda en memoria y se descarta
/// con cualquier escritura que pueda cambiarlo: abrir el Atlas dos veces sin
/// tocar nada en medio no recalcula.
abstract interface class AtlasRepository {
  /// El Atlas de la categoría [definitionId], que se actualiza solo cuando
  /// cambia algo que lo afecta: asignar una propiedad, mover un valor en el
  /// vocabulario, crear o borrar un elemento.
  ///
  /// Una categoría que no existe da un Atlas vacío. Con
  /// `kSpacesDimensionId`, el Atlas de los temas —los espacios—: una rama del
  /// primer nivel por tema, sin subtemas (F28).
  Stream<AtlasSnapshot> watchAtlas(String definitionId);

  /// El Atlas ahora, una sola vez: para lo que no necesita seguir cambios,
  /// como la exportación.
  Future<AtlasSnapshot> snapshot(String definitionId);
}
