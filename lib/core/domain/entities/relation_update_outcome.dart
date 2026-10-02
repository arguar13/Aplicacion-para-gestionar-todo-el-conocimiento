/// Cómo terminó editar un vínculo (F27): ver
/// `OrganizeRepository.updateRelation`.
enum RelationUpdateOutcome {
  /// Quedó el mismo vínculo, con el tipo y la frase nuevos.
  updated,

  /// Ya había otro vínculo del tipo elegido entre los mismos dos elementos, en
  /// el mismo sentido: los dos se fundieron en ese otro. Es lo que la persona
  /// pidió —«esto es una contradicción»— sin dejar dos líneas iguales, que el
  /// esquema no permite.
  merged,
}
