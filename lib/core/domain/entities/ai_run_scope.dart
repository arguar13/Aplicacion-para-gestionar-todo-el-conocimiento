/// Qué le pidieron a una pasada de la IA (`ai_runs.scope`, v37).
enum AiRunScope {
  /// Organizar el elemento: vínculos, tarjetas, temas, etiquetas, propiedades,
  /// el Atlas (F27). Lo de siempre, y lo que tienen todas las pasadas de antes
  /// de v37.
  organize,

  /// Solo tarjetas de repaso (F30): «Para cada documento» en la hoja de
  /// «Tarjetas didácticas» de Repasar (F43, M18; antes, su ✨) o «Llenar con
  /// IA» de un cuaderno. No organizó el elemento, así que para la cola sigue
  /// pendiente: la biblioteca que ya existía se organiza igual con el cargador.
  flashcards,

  /// Revisar lo que hizo la IA en el elemento (F33, «Revisar con otro
  /// modelo»): un modelo mira lo que sigue siendo de la IA y propone
  /// correcciones. No crea nada: lo que la persona acepta se aplica dentro de
  /// esta pasada, y deshacerla lo devuelve a como estaba. No cuenta como
  /// organizar el elemento.
  review,

  /// Analizar un texto para estudiarlo (F36, F39): el resumen, la síntesis y
  /// las palabras clave que la IA marca por partes. Es la historia de lo que
  /// costó —tiempo, tokens, modelo— en «Lo que hizo la IA»: no crea nada que
  /// se deshaga como una pasada, porque lo marcado se rehace con «Volver a
  /// analizar». No cuenta como organizar el elemento.
  study,

  /// Solo buscar las fechas de un elemento para la línea de tiempo (F40):
  /// «Organizar con IA» de la línea o «Buscar fechas con IA» del detalle. Deja
  /// los hechos fechados que puso, que se deshacen con la pasada, pero no
  /// organizó el elemento: para la cola sigue pendiente, y la biblioteca que
  /// ya existía se organiza igual con el cargador.
  dates,
}
