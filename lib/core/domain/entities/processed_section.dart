/// Las secciones de un documento procesado (F41, decisión B), en el orden en
/// que se leen.
///
/// Un documento procesado guarda SOLO texto —nunca audio, video, archivos ni la
/// ficha bibliográfica—, repartido en estas cinco. Cada sección es una lista
/// ordenada de partes (`processed_parts`), y cada parte sabe de dónde salió: es
/// lo que deja elegir, al volver a triar, entre agregar, actualizar, reemplazar
/// y quitar sin adivinar. Las palabras clave **no** van.
enum ProcessedSection {
  /// El texto extraído entero, o la transcripción. Se guarda en páginas —ver
  /// `kProcessedTextPageChars`—: un libro de millones de caracteres nunca viaja
  /// entero a la interfaz ni se reescribe entero por una corrección.
  text,

  /// Las oraciones del resumen elegidas, en el orden del texto.
  summary,

  /// Las oraciones de la síntesis elegidas, en el orden del texto.
  synthesis,

  /// Lo que antes era «Extraer nota» (decisión C): lo que la persona escribe.
  notes,

  /// Los pasajes que la persona cortó a mano del original, cada uno con su
  /// ancla para «Abrir en el original».
  fragments;

  /// Si la fuente tiene una «versión de ahora» de esta sección que
  /// «Actualizar» pueda traer: su texto, su resumen y su síntesis. Las notas y
  /// los fragmentos son de la persona: no hay nada en la fuente que los
  /// renueve, así que solo se agregan, se reemplazan o se quitan.
  bool get canUpdate => switch (this) {
    text || summary || synthesis => true,
    notes || fragments => false,
  };
}

/// De dónde salió una parte de un documento procesado (F41).
///
/// No es una marca de calidad sino de procedencia, como `ContentOrigin`: dice
/// qué puede renovar «Actualizar» y qué no se toca nunca.
enum ProcessedPartOrigin {
  /// Copiada literalmente de la fuente —una página de su texto, una oración de
  /// su resumen o su síntesis, un fragmento cortado—, con su ancla. Si la
  /// persona la edita después queda marcada (`edited`): sigue diciendo de
  /// dónde vino, pero «Actualizar» ya no la pisa.
  copied,

  /// Escrita por la persona: una nota —la única sección que la persona escribe
  /// de cero—. Puede llevar el ancla del pasaje del que la sacó, pero su texto
  /// es suyo. Una nota extraída literalmente («Extraer nota» sobre una
  /// selección) es [copied].
  user,
}
