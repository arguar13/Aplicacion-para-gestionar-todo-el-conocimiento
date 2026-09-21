/// Cómo llegó una propiedad a estar puesta en un elemento.
///
/// No es una etiqueta de calidad —un valor `manual` no vale más que uno
/// `inherited`—, es de procedencia: para saber qué revisar primero, o
/// para no volver a sugerir algo que ya se aceptó.
enum ItemPropertyOrigin {
  /// El usuario la puso a mano, desde `PropertyEditor`.
  manual,

  /// Copiada de la fuente al extraer una nota atómica —ver
  /// `OrganizeRepositoryImpl.createRelation`, el efecto lateral sobre
  /// `RelationKind.extractedFrom`—. Extraer 8 fragmentos de un video no
  /// puede costar 8 clasificaciones manuales.
  inherited,

  /// Una sugerencia del modelo de lenguaje que el usuario confirmó. El
  /// modelo nunca la puso por su cuenta: esta es la marca de que alguien
  /// la revisó y aceptó tal cual.
  suggestedAccepted,

  /// El espejo de una persona de la obra (F15): la pone `KnowledgeEntryWriter`
  /// al guardar la referencia de una fuente, para que los conteos, el
  /// explorador y «las obras de este autor» no tengan que conocer la tabla de
  /// personas. Se va sola si la persona deja de figurar en la obra; una
  /// asignación `manual` de la misma persona nunca se toca.
  reference,
}
