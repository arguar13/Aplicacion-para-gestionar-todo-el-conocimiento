import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_values.dart';

/// Por qué columna se ordena una tabla, y hacia dónde.
@immutable
class TableSort {
  const TableSort(this.column, {this.ascending = true});

  /// Tocar el encabezado de [column]: si ya ordenaba por ella, al revés; si
  /// no, por ella de menor a mayor.
  factory TableSort.toggled(TableSort? current, int column) =>
      current?.column == column
      ? TableSort(column, ascending: !current!.ascending)
      : TableSort(column);

  final int column;
  final bool ascending;

  @override
  bool operator ==(Object other) =>
      other is TableSort &&
      other.column == column &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(column, ascending);

  @override
  String toString() => 'TableSort($column, ${ascending ? '↑' : '↓'})';
}

/// En qué orden se muestran las filas de [table] con [sort]: los índices de
/// sus filas. Sin [sort], el de la IA.
///
/// - Una columna de **números** se ordena por su valor («9» antes que «10»,
///   «1.250,5» después que «999»); una de **fechas**, de la más vieja a la
///   más nueva; una de **texto**, con [collator] —como un diccionario del
///   idioma de la tabla—.
/// - Lo que en una columna de números o de fechas no se puede leer como tal
///   va después de lo que sí, ordenado como texto.
/// - Las celdas vacías van siempre al final, en los dos sentidos —como en
///   una planilla—.
/// - Es estable: dos filas que empatan quedan en el orden de la IA.
List<int> tableRowOrder(
  StudyTable table,
  TableSort? sort,
  TableCollator collator,
) {
  final order = List<int>.generate(table.rows.length, (i) => i);
  if (sort == null || sort.column < 0 || sort.column >= table.columns.length) {
    return order;
  }
  final type = table.columns[sort.column].type;
  final cells = [for (final row in table.rows) row[sort.column]];
  final values = [
    for (final cell in cells)
      switch (type) {
        TableColumnType.number => TableValues.number(cell),
        TableColumnType.date => TableValues.date(cell),
        TableColumnType.text => null,
      },
  ];
  final direction = sort.ascending ? 1 : -1;

  int compare(int a, int b) {
    final ca = cells[a];
    final cb = cells[b];
    // Lo vacío, al final siempre.
    if (ca.isEmpty != cb.isEmpty) return ca.isEmpty ? 1 : -1;
    if (ca.isEmpty) return a.compareTo(b);
    final va = values[a];
    final vb = values[b];
    int result;
    if (va != null && vb != null) {
      result = va.compareTo(vb);
    } else if (va != null || vb != null) {
      // Lo que no se lee como número o fecha, después de lo que sí.
      return va != null ? -1 : 1;
    } else {
      result = collator.compare(ca, cb);
    }
    if (result != 0) return result * direction;
    return a.compareTo(b);
  }

  order.sort(compare);
  return order;
}
