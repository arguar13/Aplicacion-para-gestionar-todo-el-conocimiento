/// Qué clase de nota es, dentro de lo que el usuario construye.
///
/// La distinción es la que hace que la bóveda absorba material nuevo sin
/// reorganizar nada: una nota viva crece cuando aparece algo relacionado,
/// en vez de que cada fuente nueva obligue a decidir dónde archivarla de
/// cero.
enum NoteKind {
  /// Una idea sola, extraída literalmente de una fuente. No crece: si hace
  /// falta decir algo más sobre ella, esa idea nueva es otra nota atómica.
  atomic,

  /// La nota de una entidad —un hecho, una persona, un proceso, un
  /// concepto— que crece con el tiempo. Cuando aparece material nuevo de
  /// un tema ya estudiado, se anexa acá: no se reorganiza nada.
  living,

  /// Una nota índice: solo estructura y enlaces, sin contenido propio.
  /// Da puntos de entrada al grafo.
  map,
}
