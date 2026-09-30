import 'package:sinapsis/core/database/entry_fields.dart';

/// Dónde vive un campo versionado de un elemento (F11): en qué tabla y en qué
/// columna, para que la fusión lo lea y lo escriba en SQL, de una bóveda a la
/// otra, sin traerlo a Dart.
class MergeField {
  const MergeField._(
    this.name,
    this.table,
    this.column, {
    this.isComposite = false,
  });

  /// El nombre con el que `field_version` lo registra (`EntryField`).
  final String name;

  /// `item`, `note` o `source`. En un campo [isComposite], la tabla principal.
  final String table;

  /// La columna de esa tabla, tal como está en SQLite. En un campo
  /// [isComposite] es solo la que une la tabla con el elemento.
  final String column;

  /// Si el campo no es una columna sino un CONJUNTO de filas de varias tablas
  /// que se versiona junto (F15): los datos bibliográficos y sus personas. La
  /// regla de linaje lo decide igual que a los demás; lo que cambia es cómo se
  /// compara y cómo se copia (`ReferenceMergePlanner`, y el paso de las
  /// referencias de `EntryMergeApplier`, que va DESPUÉS del vocabulario porque
  /// las personas se traducen a los identificadores de acá).
  final bool isComposite;

  /// La columna que une la tabla con el elemento: `item` es el elemento.
  String get keyColumn => table == 'item' ? 'id' : 'item_id';

  /// El campo que apunta a un espacio: su valor es un identificador que puede
  /// llamarse distinto en cada bóveda.
  bool get isSpace => name == EntryField.spaceId;

  @override
  String toString() => 'MergeField($name → $table.$column)';
}

/// Los campos de un elemento que se fusionan uno a uno, con la regla de
/// linaje.
///
/// Los datos bibliográficos de una fuente y sus personas son UNO solo
/// ([EntryField.reference]): si dos dispositivos los editan, gana la referencia
/// más nueva entera y no hay un conflicto por editorial y otro por volumen.
///
/// Son los mismos nombres que registra `KnowledgeEntryWriter` en
/// `field_version`, menos el texto de las formas (`rendition:<id>`), que se
/// fusiona aparte porque el texto de una fuente no se pisa nunca.
final kMergeFields = List<MergeField>.unmodifiable(const [
  MergeField._(EntryField.title, 'item', 'title'),
  MergeField._(EntryField.subtitle, 'item', 'subtitle'),
  MergeField._(EntryField.notes, 'item', 'notes'),
  MergeField._(EntryField.spaceId, 'item', 'space_id'),
  MergeField._(EntryField.state, 'item', 'state'),
  MergeField._(EntryField.deletedAt, 'item', 'deleted_at'),
  MergeField._(EntryField.noteKind, 'note', 'note_kind'),
  MergeField._(EntryField.maturity, 'note', 'maturity'),
  MergeField._(EntryField.originUrl, 'source', 'origin_url'),
  MergeField._(EntryField.authorName, 'source', 'author_name'),
  MergeField._(EntryField.authorUrl, 'source', 'author_url'),
  MergeField._(EntryField.publishedAt, 'source', 'published_at'),
  MergeField._(EntryField.originalBlobPath, 'source', 'original_blob_path'),
  MergeField._(EntryField.language, 'source', 'language'),
  MergeField._(
    EntryField.reference,
    'source_reference',
    'item_id',
    isComposite: true,
  ),
]);

/// El campo llamado [name], o `null` si no es uno de los que se fusionan así.
MergeField? mergeFieldNamed(String name) {
  for (final field in kMergeFields) {
    if (field.name == name) return field;
  }
  return null;
}
