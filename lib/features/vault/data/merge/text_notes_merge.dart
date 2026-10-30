import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';

/// Las columnas de las notas en el texto (F45, mejora 19, v49) que copia la
/// unión por conjuntos (`SetUnionMerge`): todas menos `row_key`, la clave
/// local del índice de texto, que cada base numera.
const kTextNoteColumns = [
  'id',
  'target',
  'item_id',
  'rendition_id',
  'creation_id',
  'start_offset',
  'end_offset',
  'excerpt',
  'note',
  'color',
  'created_at',
  'updated_at',
];

/// Las notas en el texto (F45, mejora 19) en la unión de bóvedas: cuáles de la
/// copia entran y, de las que las dos tienen, cuál versión queda.
///
/// Una sola fuente de la regla para quien escribe —`SetUnionMerge`— y para
/// quien cuenta sin escribir —la vista previa—, como `SetUnionRules`.
class TextNotesMerge {
  const TextNotesMerge(this._db);

  final AppDatabase _db;

  static const _incoming = kIncomingSchema;

  /// Las notas de la copia que entran: las que acá no están, por id, cuyo
  /// dueño —la fuente, el documento procesado o la creación— está acá, vivo o
  /// en la papelera. Lo están siempre: los elementos y lo creado entran antes,
  /// todos. Se mira igual, porque sin su dueño la nota no tendría de quién ser.
  ///
  /// La forma de texto de una nota del original de la Biblioteca va a la que
  /// le toca si la fusión la juntó con otra de acá (`rm`, el mapa de formas);
  /// si no, queda la suya. Como no tiene clave foránea, la nota entra aunque
  /// esa forma no esté: queda sin lugar hasta que vuelva, nunca se pierde.
  ///
  /// [dryRun] es para contar sin escribir: los dueños nuevos todavía no están
  /// acá, así que «está» se lee también de la copia, y no hace falta el mapa.
  static String from({bool dryRun = false}) {
    String owner(String table, String column) => dryRun
        ? '(EXISTS (SELECT 1 FROM main.$table o WHERE o.id = x.$column) '
              'OR EXISTS (SELECT 1 FROM $_incoming.$table o '
              'WHERE o.id = x.$column))'
        : 'EXISTS (SELECT 1 FROM main.$table o WHERE o.id = x.$column)';
    return '''
      FROM $_incoming.text_notes x
      ${dryRun ? '' : 'LEFT JOIN ${MergeWork.renditionMap} rm ON rm.incoming_id = x.rendition_id'}
     WHERE (x.item_id IS NULL OR ${owner('item', 'item_id')})
       AND (x.creation_id IS NULL OR ${owner('study_creations', 'creation_id')})
       AND NOT EXISTS (SELECT 1 FROM main.text_notes m WHERE m.id = x.id)''';
  }

  /// Cómo entra la forma de texto de una nota: ver [from].
  static const renditionOf = 'COALESCE(rm.local_id, x.rendition_id)';

  /// De una nota que las dos tienen, queda lo que la persona escribió y el
  /// color de la versión editada más tarde. El lugar no se toca: es el del
  /// texto de cada bóveda, y lo reubica cada una. Devuelve cuántas cambiaron.
  Future<int> adoptNewer() => _db.customUpdate(
    '''
    UPDATE main.text_notes SET
      note = x.note,
      color = x.color,
      updated_at = x.updated_at
     FROM $_incoming.text_notes x
    WHERE x.id = text_notes.id
      AND x.updated_at > text_notes.updated_at''',
    updates: {_db.textNotes},
  );
}
