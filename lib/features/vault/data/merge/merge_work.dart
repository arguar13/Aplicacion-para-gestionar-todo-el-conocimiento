import 'package:sinapsis/core/database/app_database.dart';

/// Las tablas temporales que une los pasos de una fusión (F11).
///
/// Viven solo mientras dura la fusión, dentro de su transacción: son la manera
/// de pasar de un paso al siguiente —«estos son los elementos nuevos», «este
/// identificador de la copia es este otro de acá»— sin traer miles de filas a
/// Dart ni repetir la misma consulta. Al terminar, o al fallar, se sueltan.
abstract final class MergeWork {
  /// Los elementos de la copia que esta bóveda no tiene. Lo llena el paso de
  /// los elementos y lo leen los pasos de lo que cuelga de ellos.
  static const newItems = 'temp.merge_new_items';

  /// Los elementos cuyo texto principal hay que volver a procesar: los nuevos y
  /// los que recibieron un texto distinto. De ellos se rehacen los derivados.
  static const touchedItems = 'temp.merge_touched_items';

  /// Formas de la copia que NO entran con el mismo identificador: el texto de
  /// la copia quedó guardado como otra forma —o ya estaba— acá. Los resaltados
  /// que apuntaban a la forma de la copia se re-apuntan a la de acá porque sus
  /// posiciones son de ESE texto; un `local_id` nulo dice «no hay dónde
  /// ponerlos».
  static const renditionMap = 'temp.merge_rendition_map';

  /// Cómo se llama acá cada definición de propiedad y cada valor de la copia.
  static const definitionMap = 'temp.merge_def_map';
  static const valueMap = 'temp.merge_value_map';

  /// Crea las tablas, vacías.
  static Future<void> create(AppDatabase db) async {
    await drop(db);
    for (final table in const [newItems, touchedItems]) {
      await db.customStatement(
        'CREATE TEMP TABLE ${_name(table)} (id TEXT PRIMARY KEY) '
        'WITHOUT ROWID',
      );
    }
    for (final table in const [renditionMap, definitionMap, valueMap]) {
      await db.customStatement(
        'CREATE TEMP TABLE ${_name(table)} '
        '(incoming_id TEXT PRIMARY KEY, local_id TEXT) WITHOUT ROWID',
      );
    }
  }

  /// Las suelta, existan o no.
  static Future<void> drop(AppDatabase db) async {
    for (final table in const [
      newItems,
      touchedItems,
      renditionMap,
      definitionMap,
      valueMap,
    ]) {
      await db.customStatement('DROP TABLE IF EXISTS $table');
    }
  }

  static String _name(String qualified) => qualified.split('.').last;
}
