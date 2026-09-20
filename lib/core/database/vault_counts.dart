import 'package:sinapsis/core/database/app_database.dart';

/// Cuántas filas hay en cada tabla de lo que el usuario creó, para comprobar
/// que una migración no perdió ni inventó nada.
///
/// Es la compuerta de las migraciones de F10: se toma antes y después de
/// reconstruir tablas, y si algún conteo cambió la migración lanza y SQLite
/// revierte. Comparar filas, y no confiar en que `INSERT ... SELECT` las copió
/// a todas, es lo que separa "la migración terminó" de "la bóveda quedó
/// intacta".
class VaultCounts {
  const VaultCounts(this.rows);

  /// Las tablas de lo que el usuario creó, por su nombre SQL. Quedan afuera el
  /// modelo nuevo `item`/`source`/`note` —el paso v18 puede completarlo con lo
  /// que faltaba, y se compara aparte contra `items`—, el modelo viejo que F10
  /// retira y los índices de búsqueda, que se reconstruyen.
  static const userDataTables = <String>[
    'renditions',
    'highlights',
    'relations',
    'inline_link',
    'flashcards',
    'item_property_values',
    'property_definitions',
    'property_values',
    'property_aliases',
    'spaces',
    'chunks',
    'embeddings',
    'conversations',
    'chat_messages',
    'suggestions',
    'merged_provenances',
  ];

  /// Filas por tabla.
  final Map<String, int> rows;

  /// Las tablas cuya cantidad de filas difiere entre `this` —el antes— y
  /// [after]: nombre, antes y después. Vacío si la migración dejó todo como
  /// estaba.
  Map<String, (int before, int after)> differencesWith(VaultCounts after) => {
    for (final entry in rows.entries)
      if (after.rows[entry.key] != entry.value)
        entry.key: (entry.value, after.rows[entry.key] ?? 0),
  };

  /// Un resumen para un mensaje de error o un registro, sin contenido de
  /// ninguna fila.
  String summary() => [
    for (final entry in rows.entries) '${entry.key}: ${entry.value}',
  ].join(', ');
}

/// Cuenta las filas de cada tabla de [tables].
///
/// Los nombres salen de una lista fija del código, nunca de un dato: se
/// interpolan en el SQL porque una tabla no se puede pasar como parámetro.
Future<VaultCounts> captureVaultCounts(
  AppDatabase db, {
  Iterable<String> tables = VaultCounts.userDataTables,
}) async {
  final rows = <String, int>{};
  for (final table in tables) {
    final row = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    rows[table] = row.read<int>('n');
  }
  return VaultCounts(rows);
}
