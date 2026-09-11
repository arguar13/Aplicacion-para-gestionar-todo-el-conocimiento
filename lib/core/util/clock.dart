/// De dónde sale "ahora".
///
/// Existe para que nada lea el reloj del sistema directamente. Un test que
/// necesite comprobar qué pasa a los diez minutos no puede esperarlos, y uno
/// que compare fechas contra `DateTime.now()` es una prueba que falla sola
/// alguna madrugada.
///
/// En producción se usa `DateTime.now` tal cual, que ya cumple esta firma.
typedef Clock = DateTime Function();
