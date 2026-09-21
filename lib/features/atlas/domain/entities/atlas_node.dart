import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_coverage.dart';

part 'atlas_node.freezed.dart';

/// Una nota mapa asociada a una rama: el punto de entrada que el Atlas
/// destaca.
@freezed
sealed class AtlasMapNote with _$AtlasMapNote {
  const factory AtlasMapNote({required String id, required String title}) =
      _AtlasMapNote;
}

/// Una rama del Atlas: un valor del vocabulario con lo que hay debajo de él.
///
/// Todos los conteos son EN CASCADA: cuentan los elementos asignados al valor
/// o a cualquiera de sus descendientes, y un elemento asignado a varios de la
/// rama cuenta UNA vez. Asignar un hijo no asigna el padre —eso sigue siendo
/// cierto en la base—: el padre lo muestra porque el Atlas cuenta hacia abajo,
/// como el filtro de la Biblioteca.
///
/// Una fuente y una nota se cuentan aparte, no juntas: son cosas distintas
/// —material crudo y entendimiento— y el estado de cobertura sale de esa
/// diferencia.
@freezed
sealed class AtlasNode with _$AtlasNode {
  const factory AtlasNode({
    required String valueId,
    required String label,
    required int depth,
    String? parentId,

    /// Cuántos hijos directos tiene.
    @Default(0) int childCount,

    /// Fuentes en la rama.
    @Default(0) int sourceCount,

    /// Notas atómicas en la rama.
    @Default(0) int atomicCount,

    /// Notas vivas `seed` o `developing`: las que se están construyendo.
    @Default(0) int growingLivingCount,

    /// Notas vivas `mature`.
    @Default(0) int matureLivingCount,

    /// Notas mapa en la rama.
    @Default(0) int mapCount,

    /// La actualización más reciente de un elemento de la rama; `null` si no
    /// tiene ninguno.
    DateTime? lastTouched,

    /// El año astronómico más temprano de la «Fecha del hecho» de los
    /// elementos de la rama; `null` si ninguno tiene fecha.
    int? firstYear,

    /// El año astronómico más tardío. Con `firstYear` es el eje temporal de la
    /// rama.
    int? lastYear,

    /// Las notas mapa de la rama, por título: sus puntos de entrada.
    @Default(<AtlasMapNote>[]) List<AtlasMapNote> mapNotes,
  }) = _AtlasNode;

  const AtlasNode._();

  /// Notas vivas, del grado de madurez que sean.
  int get livingCount => growingLivingCount + matureLivingCount;

  /// Notas de cualquier subtipo.
  int get noteCount => atomicCount + livingCount + mapCount;

  /// Elementos en la rama: fuentes más notas, sin repetir ninguno.
  int get itemCount => sourceCount + noteCount;

  /// Si la rama tiene subtemas.
  bool get hasChildren => childCount > 0;

  /// El estado de cobertura: el nivel más avanzado que hay en la rama.
  AtlasCoverage get coverage {
    if (matureLivingCount > 0) return AtlasCoverage.mature;
    if (growingLivingCount > 0) return AtlasCoverage.growing;
    if (noteCount > 0) return AtlasCoverage.fragments;
    if (sourceCount > 0) return AtlasCoverage.sourcesOnly;
    return AtlasCoverage.empty;
  }
}
