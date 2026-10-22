import 'dart:convert';

/// Los campos de un elemento cuya última modificación se registra en
/// `field_version` (F11), por su nombre.
///
/// Son los mismos nombres que usa la fusión de bóvedas para decidir campo a
/// campo qué versión queda. Solo lo que un dispositivo puede cambiar de un
/// elemento y que el otro puede cambiar distinto; lo derivado —los hashes, los
/// chunks, los enlaces— se rehace y no se versiona.
abstract final class EntryField {
  // `item`.
  static const title = 'title';
  static const subtitle = 'subtitle';
  static const notes = 'notes';

  /// Los temas del elemento (F37): UN campo aunque sean varios —ver
  /// `item_spaces`—. Se llama `spaceId` porque así quedó guardado en
  /// `field_version` y en los conflictos de cuando era uno solo.
  static const spaces = 'spaceId';

  static const state = 'state';
  static const deletedAt = 'deletedAt';

  // `note`.
  static const noteKind = 'noteKind';
  static const maturity = 'maturity';

  // `source`: de dónde salió lo capturado.
  static const originUrl = 'originUrl';
  static const authorName = 'authorName';
  static const authorUrl = 'authorUrl';
  static const publishedAt = 'publishedAt';
  static const originalBlobPath = 'originalBlobPath';
  static const language = 'language';

  /// Los datos bibliográficos de una fuente (F15) y sus personas, JUNTOS: es un
  /// solo campo de linaje aunque vivan en dos tablas. Si dos dispositivos la
  /// editan, gana la más nueva entera y el conflicto se muestra con la cita
  /// ya armada; no hay un conflicto por editorial y otro por volumen.
  static const reference = 'reference';

  /// Los campos de `item` que son texto o valores simples, para las pantallas
  /// que muestran un conflicto.
  static const itemFields = [title, subtitle, notes, spaces, state, deletedAt];

  static const _renditionPrefix = 'rendition:';

  /// El campo que registra el texto de la forma [renditionId].
  static String rendition(String renditionId) =>
      '$_renditionPrefix$renditionId';

  /// Si [fieldName] es el texto de una forma.
  static bool isRendition(String fieldName) =>
      fieldName.startsWith(_renditionPrefix);

  /// El id de la forma de un campo `rendition:<id>`.
  static String renditionIdOf(String fieldName) =>
      fieldName.substring(_renditionPrefix.length);
}

/// Los temas [spaceIds] como los guarda un conflicto de fusión (F37): los
/// identificadores en orden, o `null` si no hay ninguno.
String? encodeSpaceIds(Set<String> spaceIds) =>
    spaceIds.isEmpty ? null : jsonEncode(spaceIds.toList()..sort());

/// Lo contrario de [encodeSpaceIds], o `null` si [text] no es eso. Un
/// conflicto de antes de F37 guardaba un identificador solo, sin lista: es ese
/// tema.
Set<String>? decodeSpaceIds(String? text) {
  if (text == null || text.isEmpty) return const {};
  if (!text.startsWith('[')) return {text};
  try {
    final decoded = jsonDecode(text);
    if (decoded is! List || decoded.any((id) => id is! String)) return null;
    return {...decoded.cast<String>()};
  } on FormatException {
    return null;
  }
}
