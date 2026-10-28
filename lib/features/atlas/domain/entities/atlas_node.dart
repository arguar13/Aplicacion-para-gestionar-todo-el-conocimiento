import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/processed_depth.dart';
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
/// Todos los conteos son EN CASCADA: cuentan los documentos asignados al valor
/// o a cualquiera de sus descendientes, y uno asignado a varios de la rama
/// cuenta UNA vez. Asignar un hijo no asigna el padre —eso sigue siendo cierto
/// en la base—: el padre lo muestra porque el Atlas cuenta hacia abajo, como el
/// filtro de la Biblioteca.
///
/// Desde F41 (paso 6) lo que se cuenta son documentos procesados, cada uno en
/// el escalón más alto de [ProcessedDepth] que alcanza: el estado de cobertura
/// sale de esa diferencia.
@freezed
sealed class AtlasNode with _$AtlasNode {
  const factory AtlasNode({
    required String valueId,
    required String label,
    required int depth,
    String? parentId,

    /// Cuántos hijos directos tiene.
    @Default(0) int childCount,

    /// Documentos procesados con su texto y nada más.
    @Default(0) int textOnlyCount,

    /// Con el resumen o la síntesis, sin fragmentos ni notas.
    @Default(0) int summarizedCount,

    /// Con fragmentos cortados a mano, sin notas.
    @Default(0) int cutCount,

    /// Con notas propias.
    @Default(0) int annotatedCount,

    /// La actualización más reciente de un documento de la rama; `null` si no
    /// tiene ninguno.
    DateTime? lastTouched,

    /// El año astronómico más temprano de la «Fecha del hecho» de los
    /// documentos de la rama; `null` si ninguno tiene fecha.
    int? firstYear,

    /// El año astronómico más tardío. Con `firstYear` es el eje temporal de la
    /// rama.
    int? lastYear,

    /// Las notas mapa de la rama, por título: sus puntos de entrada.
    @Default(<AtlasMapNote>[]) List<AtlasMapNote> mapNotes,
  }) = _AtlasNode;

  const AtlasNode._();

  /// Cuántos documentos hay en [depth].
  int countOf(ProcessedDepth depth) => switch (depth) {
    ProcessedDepth.textOnly => textOnlyCount,
    ProcessedDepth.summarized => summarizedCount,
    ProcessedDepth.cut => cutCount,
    ProcessedDepth.annotated => annotatedCount,
  };

  /// Documentos procesados en la rama, sin repetir ninguno.
  int get itemCount =>
      textOnlyCount + summarizedCount + cutCount + annotatedCount;

  /// Si la rama tiene subtemas.
  bool get hasChildren => childCount > 0;

  /// El estado de cobertura: el nivel más avanzado que hay en la rama.
  AtlasCoverage get coverage {
    if (annotatedCount > 0) return AtlasCoverage.annotated;
    if (cutCount > 0) return AtlasCoverage.cut;
    if (summarizedCount > 0) return AtlasCoverage.summarized;
    if (textOnlyCount > 0) return AtlasCoverage.textOnly;
    return AtlasCoverage.empty;
  }
}
