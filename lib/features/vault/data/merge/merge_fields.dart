import 'package:sinapsis/core/database/entry_fields.dart';

/// Qué es un campo versionado para la fusión.
enum MergeFieldKind {
  /// Una columna de `item`, `note` o `source`.
  column,

  /// Los datos bibliográficos de una fuente y sus personas (F15): filas de dos
  /// tablas que se versionan juntas.
  reference,

  /// Los temas de un elemento (F37): sus filas de `item_spaces`.
  spaces,
}

/// Dónde vive un campo versionado de un elemento (F11): en qué tabla y en qué
/// columna, para que la fusión lo lea y lo escriba en SQL, de una bóveda a la
/// otra, sin traerlo a Dart.
class MergeField {
  const MergeField._(
    this.name,
    this.table,
    this.column, {
    this.kind = MergeFieldKind.column,
  });

  /// El nombre con el que `field_version` lo registra (`EntryField`).
  final String name;

  /// `item`, `note` o `source`. En un campo [isComposite], la tabla principal.
  final String table;

  /// La columna de esa tabla, tal como está en SQLite. En un campo
  /// [isComposite] es solo la que une la tabla con el elemento.
  final String column;

  final MergeFieldKind kind;

  /// Si el campo no es una columna sino un CONJUNTO de filas que se versiona
  /// junto: los datos bibliográficos con sus personas (F15) o los temas
  /// (F37). La regla de linaje lo decide igual que a los demás; lo que cambia
  /// es cómo se compara y cómo se copia.
  bool get isComposite => kind != MergeFieldKind.column;

  /// Los datos bibliográficos (`ReferenceMergePlanner`): se escriben en el paso
  /// de las referencias de `EntryMergeApplier`, que va DESPUÉS del vocabulario
  /// porque las personas se traducen a los identificadores de acá.
  bool get isReference => kind == MergeFieldKind.reference;

  /// Los temas (`ItemSpacesMergePlanner`): cada uno es un identificador que
  /// puede llamarse distinto en cada bóveda (`SpaceMerge`).
  bool get isSpaces => kind == MergeFieldKind.spaces;

  /// La columna que une la tabla con el elemento: `item` es el elemento.
  String get keyColumn => table == 'item' ? 'id' : 'item_id';

  @override
  String toString() => 'MergeField($name → $table.$column)';
}

/// Los campos de un elemento que se fusionan uno a uno, con la regla de
/// linaje.
///
/// Los datos bibliográficos de una fuente y sus personas son UNO solo
/// ([EntryField.reference]): si dos dispositivos los editan, gana la referencia
/// más nueva entera y no hay un conflicto por editorial y otro por volumen.
/// Los temas de un elemento también son UNO ([EntryField.spaces], F37): gana
/// el conjunto más nuevo entero, no se mezclan los de un lado con los del otro.
///
/// Son los mismos nombres que registra `KnowledgeEntryWriter` en
/// `field_version`, menos el texto de las formas (`rendition:<id>`), que se
/// fusiona aparte porque el texto de una fuente no se pisa nunca.
final kMergeFields = List<MergeField>.unmodifiable(const [
  MergeField._(EntryField.title, 'item', 'title'),
  MergeField._(EntryField.subtitle, 'item', 'subtitle'),
  MergeField._(EntryField.notes, 'item', 'notes'),
  MergeField._(
    EntryField.spaces,
    'item_spaces',
    'item_id',
    kind: MergeFieldKind.spaces,
  ),
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
    kind: MergeFieldKind.reference,
  ),
]);

/// El campo llamado [name], o `null` si no es uno de los que se fusionan así.
MergeField? mergeFieldNamed(String name) {
  for (final field in kMergeFields) {
    if (field.name == name) return field;
  }
  return null;
}
