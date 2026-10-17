/// Qué corrige una sugerencia de corrección (F33, «Revisar con otro modelo»):
/// algo que hizo la IA y que sigue siendo suyo.
///
/// La columna `suggestions.kind` dice que es una corrección; esto, sobre qué.
/// Va en el `payload_json`, así que sumar uno no cambia el esquema.
enum CorrectionSubject {
  /// Una tarjeta de repaso que hizo la IA: su pregunta y su respuesta.
  flashcard,

  /// Un vínculo que hizo la IA: su tipo y la frase que dice por qué. Solo los
  /// que son una opinión sobre dos elementos, no la estructura —una extracción
  /// o un índice—.
  relation,

  /// Una etiqueta o una propiedad que puso la IA: el valor de su categoría.
  /// Se corrige por otro valor que ya esté en esa categoría —inventar
  /// vocabulario se mira en «Para revisar»—, o se saca.
  property,

  /// El tema de la biblioteca que le puso la IA al elemento —su espacio—:
  /// se corrige por otro tema que ya exista, o se saca.
  space,
}

/// Los datos de una tarjeta en el antes y el después de una corrección.
abstract final class FlashcardCorrectionField {
  static const front = 'front';
  static const back = 'back';
}

/// Los datos de un vínculo en el antes y el después de una corrección: el tipo
/// (`RelationKind.name`) y la frase, vacía si no tiene.
abstract final class RelationCorrectionField {
  static const kind = 'kind';
  static const note = 'note';
}

/// Los datos de una etiqueta o propiedad en el antes y el después: su
/// categoría —para mostrarla; no cambia— y su valor.
abstract final class PropertyCorrectionField {
  static const category = 'category';
  static const value = 'value';
}

/// Cuál es la asignación del valor [valueId] a [itemId] en una corrección:
/// es lo que identifica una etiqueta o propiedad puesta, que no tiene id
/// propio.
String propertyCorrectionSubjectId(String itemId, String valueId) =>
    '$itemId/$valueId';

/// Los datos del tema en el antes y el después: cuál es (su id; vacío si no
/// tiene) y cómo se llama, para mostrarlo.
abstract final class SpaceCorrectionField {
  static const id = 'id';
  static const name = 'name';
}
