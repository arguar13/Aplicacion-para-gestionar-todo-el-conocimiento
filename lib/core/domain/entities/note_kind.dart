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

  /// Un documento procesado (F41, decisión A): la información pura que la
  /// persona sacó de UNA fuente al triarla —su texto, su resumen, su síntesis,
  /// sus notas y sus fragmentos—, con el enlace a esa fuente
  /// (`processed_documents`). Vive en «Procesado», no en la Biblioteca.
  ///
  /// Se pone solo al nacer (`KnowledgeEntryWriter.upsert` con `noteKind`) y
  /// nunca cambia: ni un procesado pasa a ser otra nota ni otra nota pasa a
  /// ser un procesado —un procesado sin su fuente no es un procesado—.
  processed,
}
