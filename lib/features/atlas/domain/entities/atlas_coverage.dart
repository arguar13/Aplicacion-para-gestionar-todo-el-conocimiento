/// Hasta dónde llegó el trabajo sobre una rama del Atlas (F13, D6): del
/// material que no hay al entendimiento maduro.
///
/// Van de menos a más, así que `index` sirve para comparar. Cada nivel es el
/// MÁS AVANZADO que hay en la rama entera —ella y todos sus subtemas—. Por eso
/// un estado alto puede esconder un hueco: una nota viva madura sobre un tema
/// con cien fuentes sin tocar figura como `mature`. El Atlas muestra siempre
/// los conteos al lado del estado para que no se lea de más.
enum AtlasCoverage {
  /// El valor existe y no tiene nada asignado, ni él ni sus subtemas.
  empty,

  /// Solo fuentes: hay material crudo y ningún entendimiento sobre él.
  sourcesOnly,

  /// Hay notas, pero ninguna viva: fragmentos sin consolidar. Una nota mapa
  /// sola cuenta acá —ordena, no consolida—.
  fragments,

  /// Hay una nota viva `seed` o `developing`: se está construyendo.
  growing,

  /// Hay una nota viva `mature`.
  mature,
}
