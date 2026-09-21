/// Qué clase de dato acepta una categoría de propiedad.
///
/// Hasta ahora toda categoría era, en los hechos, texto libre —"Época:
/// Siglo I a.C." es tan válido como "Época: siglo primero antes de
/// cristo"—. Tipar la categoría es lo que permite ordenar por fecha de
/// verdad o filtrar por rango numérico, en vez de comparar strings.
enum PropertyValueType {
  /// Texto libre, el comportamiento de siempre.
  text,

  /// Un número, para poder ordenar y filtrar por rango.
  number,

  /// Una fecha histórica, con precisión propia —ver [DatePrecision]— e
  /// incertidumbre ("circa"), separada de cuándo se capturó la fuente.
  date,

  /// Una persona o una institución, con su apellido y su nombre por separado
  /// (F15): es lo que hace falta para citarla. Solo la categoría de sistema
  /// «Autor» es de este tipo. El valor sigue siendo el texto que se muestra,
  /// «Apellido, Nombre», y no tiene jerarquía.
  person,
}
