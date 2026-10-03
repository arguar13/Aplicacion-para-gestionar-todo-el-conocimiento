/// Qué dato de un elemento completó la IA en una pasada (F27): su tema de la
/// biblioteca —el espacio— o uno de los datos de su referencia. Ver
/// `AiFieldChanges`.
///
/// Son los que no son filas propias —un vínculo, una tarjeta, una propiedad
/// llevan su pasada en `ai_run_id`—, sino columnas del elemento o de su
/// referencia: lo que se recuerda es el valor de antes y el que puso la IA.
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
  publishedAt;

  /// Si es un dato de la referencia —y no el tema—.
  bool get isReference => this != space;
}
