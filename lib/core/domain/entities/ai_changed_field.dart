/// Qué dato de un elemento completó la IA en una pasada (F27): su tema de la
/// biblioteca —el espacio— o uno de los datos de su referencia. Ver
/// `AiFieldChanges`.
///
/// Son los que no son filas propias —un vínculo, una tarjeta, una propiedad
/// llevan su pasada en `ai_run_id`—, sino columnas del elemento o de su
/// referencia: lo que se recuerda es el valor de antes y el que puso la IA.
///
/// Uno más, [mapNote], no es un dato sino el elemento entero: la pasada lo
/// creó. Y [flashcardsOnly] tampoco es un dato: es una marca de la pasada.
enum AiChangedField {
  /// El tema de la biblioteca (`item.space_id`).
  space,

  /// Qué clase de obra es (`source_reference.reference_type`).
  referenceType,

  /// Las personas de la obra, con su rol y su orden (`source_contributor`).
  contributors,

  containerTitle,
  publisher,
  publisherPlace,
  edition,
  volume,
  issue,
  pages,
  isbn,
  issn,
  doi,

  /// Cuándo se publicó (`source.published_at`), con su exactitud
  /// (`source_reference.publication_precision`): van juntas, porque una sin
  /// la otra no dice nada.
  publishedAt,

  /// La nota mapa entera (el Atlas): la pasada la creó como el índice de un
  /// tema, y su elemento es el de la pasada. Antes no existía
  /// (`before_value` nulo); lo que puso es el tema del que es índice
  /// (`after_value`, el id del valor). Con esto deshacer la pasada la manda a
  /// la papelera —si la persona no la hizo suya—, y la IA sabe que ese tema
  /// ya tuvo su nota mapa aunque hoy no la tenga.
  mapNote,

  /// No es un dato: la pasada fue un pedido de **solo tarjetas** (F30), el ✨
  /// «Crear tarjetas con IA» de Repasar. No organizó el elemento —ni
  /// vínculos, ni temas, ni etiquetas—, así que para la cola sigue
  /// pendiente: la biblioteca que ya existía se organiza igual con el
  /// cargador. Va acá, y no en una columna de `ai_runs`, para no cambiar el
  /// esquema: es una fila por pasada, viaja con ella en la fusión de bóvedas
  /// y se va con ella. `after_value` es [kFlashcardsOnlyMark]; deshacer no
  /// tiene nada que devolver.
  flashcardsOnly;

  /// Si es un dato de la referencia —y no el tema, la nota mapa ni la marca
  /// de solo tarjetas—.
  bool get isReference =>
      this != space && this != mapNote && this != flashcardsOnly;
}

/// Lo que guarda la marca [AiChangedField.flashcardsOnly] como valor: la
/// columna no admite vacío, y no hay nada más que decir.
const kFlashcardsOnlyMark = 'flashcards';
