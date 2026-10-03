/// Qué dato de un elemento completó la IA en una pasada (F27): su tema de la
/// biblioteca —el espacio— o uno de los datos de su referencia. Ver
/// `AiFieldChanges`.
///
/// Son los que no son filas propias —un vínculo, una tarjeta, una propiedad
/// llevan su pasada en `ai_run_id`—, sino columnas del elemento o de su
/// referencia: lo que se recuerda es el valor de antes y el que puso la IA.
///
/// Uno más, [mapNote], no es un dato sino el elemento entero: la pasada lo
/// creó.
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
  mapNote;

  /// Si es un dato de la referencia —y no el tema ni la nota mapa—.
  bool get isReference => this != space && this != mapNote;
}
