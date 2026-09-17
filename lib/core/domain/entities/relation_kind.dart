/// Qué clase de vínculo hay entre dos elementos.
///
/// Tener tipos, y no un "relacionado con" genérico, es lo que convierte una
/// pila de recortes en algo con forma: poder decir que una charla *contradice*
/// un artículo vale mucho más que saber que se tocaron alguna vez.
enum RelationKind {
  /// Vínculo sin más precisión. El caso por defecto.
  relatedTo,

  /// El destino continúa al origen: la parte 2 de una serie, el capítulo
  /// siguiente.
  continues,

  /// El destino sostiene lo contrario que el origen. De los vínculos más
  /// valiosos al estudiar un tema.
  contradicts,

  /// El origen cita o toma del destino.
  cites,

  /// El origen es un resumen del destino.
  summarizes,

  /// El origen es un fragmento atómico extraído del destino, a mano,
  /// seleccionando un pedazo de su texto.
  extractedFrom,
}
