/// Hasta dónde llegó el trabajo sobre una rama del Atlas (F13, D6): del
/// material que no hay a lo que la persona escribió sobre él.
///
/// Desde F41 (paso 6) el Atlas se arma solo con documentos procesados, así que
/// cada nivel dice cuánto se trabajó lo procesado de la rama
/// (`ProcessedDepth`): el texto copiado tal cual, lo que se destiló de él, los
/// pasajes cortados a mano y las notas propias.
///
/// Van de menos a más, así que `index` sirve para comparar. Cada nivel es el
/// MÁS AVANZADO que hay en la rama entera —ella y todos sus subtemas—. Por eso
/// un estado alto puede esconder un hueco: un documento con notas sobre un tema
/// con cien documentos sin tocar figura como `annotated`. El Atlas muestra
/// siempre los conteos al lado del estado para que no se lea de más.
enum AtlasCoverage {
  /// El valor existe y no tiene nada asignado, ni él ni sus subtemas.
  empty,

  /// Hay documentos procesados, pero solo con su texto: material sin destilar.
  textOnly,

  /// Alguno tiene el resumen o la síntesis: la persona eligió qué se queda.
  summarized,

  /// Alguno tiene fragmentos cortados a mano.
  cut,

  /// Alguno tiene notas propias: lo que la persona escribió.
  annotated,
}
