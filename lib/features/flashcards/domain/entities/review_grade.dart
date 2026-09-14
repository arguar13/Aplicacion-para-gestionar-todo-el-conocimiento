/// Qué tan bien se recordó una tarjeta, en las cuatro opciones de siempre
/// —las mismas que Anki, herederas del original SM-2 de Piotr Wozniak—.
///
/// Cuatro y no las seis del algoritmo original (0 a 5): la mayoría de
/// quien repasa una tarjeta no distingue con sentido entre "la olvidé por
/// completo" y "la recordé mal pero algo sabía" — la simplificación que ya
/// adoptó Anki hace décadas y que a nadie le hace ruido.
enum ReviewGrade {
  /// No se recordó: hay que volver a verla pronto, como si fuera nueva.
  again,

  /// Se recordó, pero costó — el intervalo crece bastante menos que con
  /// "bien".
  hard,

  /// Se recordó sin problema: el caso esperado, el intervalo crece según
  /// el factor de facilidad de la tarjeta.
  good,

  /// Se recordó de inmediato: el intervalo crece más de lo normal.
  easy,
}
