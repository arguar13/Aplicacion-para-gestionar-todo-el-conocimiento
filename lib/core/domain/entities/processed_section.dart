/// Las secciones de un documento procesado (F41, decisión B), en el orden en
/// que se leen.
///
/// Un documento procesado guarda texto —nunca audio, video ni la ficha
/// bibliográfica—, repartido en estas secciones; si se eligió, la copia del
/// original (`processed_originals`, decisión H), que no es una sección: es un
/// archivo; y las imágenes que se eligen de la fuente ([images]). Cada sección
/// de texto es una lista ordenada de partes (`processed_parts`), y cada parte
/// sabe de dónde salió: es lo que deja elegir, al volver a triar, entre
/// agregar, actualizar, reemplazar y quitar sin adivinar.
enum ProcessedSection {
  /// El texto extraído entero, o la transcripción. Se guarda en páginas —ver
  /// `kProcessedTextPageChars`—: un libro de millones de caracteres nunca viaja
  /// entero a la interfaz ni se reescribe entero por una corrección.
  text,

  /// Las oraciones del resumen elegidas, en el orden del texto.
  summary,

  /// Las oraciones de la síntesis elegidas, en el orden del texto.
  synthesis,

  /// Las palabras clave (ajuste del dueño): cada parte es una oración que
  /// tiene alguna, con los tramos de cada palabra adentro (`spans`). Con eso
  /// se arman las dos vistas: la lista compacta de palabras, en el orden del
  /// texto, y las oraciones con su clave marcada.
  keywords,

  /// Lo que antes era «Extraer nota» (decisión C): lo que la persona escribe.
  notes,

  /// Los pasajes que la persona cortó a mano del original, cada uno con su
  /// ancla para «Abrir en el original».
  fragments,

  /// Las imágenes de la fuente que la persona eligió, una por una (segundo
  /// ajuste del dueño, decisión L): la imagen guardada, o las fotos de una
  /// página o de una publicación. Son la única sección que no es texto: cada
  /// una es **una copia propia del archivo** (`processed_images`), como la
  /// copia del original, y no una parte de `processed_parts`.
  images;

  /// Si la fuente tiene una «versión de ahora» de esta sección que
  /// «Actualizar» pueda traer: su texto, su resumen, su síntesis y sus
  /// palabras clave. Las notas y los fragmentos son de la persona: no hay nada
  /// en la fuente que los renueve, así que solo se agregan, se reemplazan o se
  /// quitan.
  bool get canUpdate => switch (this) {
    text || summary || synthesis || keywords => true,
    // Una imagen tampoco: otro archivo de la fuente es otra imagen.
    notes || fragments || images => false,
  };

  /// Si guarda copias de archivos y no texto: las imágenes. Lo que es texto
  /// —lo que se lee, se escucha, se busca y se pagina— son las demás.
  bool get holdsFiles => switch (this) {
    images => true,
    text || summary || synthesis || keywords || notes || fragments => false,
  };

  /// Si es lo que se estudia (F36): el resumen, la síntesis y las palabras
  /// clave. Son las secciones que se pueden traer de la fuente o estudiar en
  /// el propio procesado (decisión I).
  bool get isStudy => switch (this) {
    summary || synthesis || keywords => true,
    text || notes || fragments || images => false,
  };
}

/// De dónde salió una parte de un documento procesado (F41).
///
/// No es una marca de calidad sino de procedencia, como `ContentOrigin`: dice
/// qué puede renovar «Actualizar» y qué no se toca nunca. Solo [copied] viene
/// de la fuente; todo lo demás es del procesado —«propio»— y «Actualizar» no lo
/// pisa: solo «Reemplazar» (decisión I).
enum ProcessedPartOrigin {
  /// Copiada literalmente de la fuente —una página de su texto, una oración de
  /// su resumen, su síntesis o sus palabras clave, un fragmento cortado—, con
  /// su ancla. Si la persona la edita después queda marcada (`edited`): sigue
  /// diciendo de dónde vino, pero «Actualizar» ya no la pisa.
  copied,

  /// Escrita por la persona: una nota —la única sección que la persona escribe
  /// de cero—. Puede llevar el ancla del pasaje del que la sacó, pero su texto
  /// es suyo. Una nota extraída literalmente («Extraer nota» sobre una
  /// selección) es [copied].
  user,

  /// Estudiada en el propio procesado por la IA —«Resumir», «Sintetizar», las
  /// palabras clave con su respaldo local (decisión I)—: una oración o una
  /// palabra de SU texto. «Volver a analizar» la rehace.
  studied,

  /// Elegida a mano en el propio procesado («Elegir a mano», decisión I):
  /// como [studied], pero de la persona —volver a analizar no la toca—.
  chosen,
}
