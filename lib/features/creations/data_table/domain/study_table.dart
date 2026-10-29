import 'package:flutter/foundation.dart';

/// Qué guarda una columna, para ordenarla bien: los números de menor a
/// mayor y las fechas de la más vieja a la más nueva —«1446 a. C.» antes que
/// «30 d. C.»—, no como texto.
enum TableColumnType {
  text('text'),
  number('number'),
  date('date');

  const TableColumnType(this.jsonName);

  /// Lo que se guarda y lo que se le pide a la IA.
  final String jsonName;
}

/// Una columna de la tabla: su nombre y qué guarda.
@immutable
class TableColumn {
  const TableColumn(this.name, {this.type = TableColumnType.text});

  final String name;
  final TableColumnType type;

  bool get isNumeric => type == TableColumnType.number;

  @override
  bool operator ==(Object other) =>
      other is TableColumn && other.name == name && other.type == type;

  @override
  int get hashCode => Object.hash(name, type);

  @override
  String toString() => 'TableColumn($name, ${type.jsonName})';
}

/// Una tabla de datos (F43, punto 5 del plan): columnas con nombre y filas
/// con un valor por columna, como texto —tal como lo escribió la IA, en el
/// idioma pedido—. La IA da los datos (decisión G); el dibujo, el orden y la
/// exportación son de la app.
@immutable
class StudyTable {
  const StudyTable({
    required this.title,
    required this.columns,
    required this.rows,
  });

  final String title;
  final List<TableColumn> columns;

  /// Las filas, cada una con exactamente un valor por columna (vacío si el
  /// material no lo decía), en el orden en que las armó la IA.
  final List<List<String>> rows;

  bool get isEmpty => columns.isEmpty || rows.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is StudyTable &&
      other.title == title &&
      listEquals(other.columns, columns) &&
      other.rows.length == rows.length &&
      Iterable<int>.generate(
        rows.length,
      ).every((i) => listEquals(other.rows[i], rows[i]));

  @override
  int get hashCode => Object.hash(
    title,
    Object.hashAll(columns),
    Object.hashAll(rows.map(Object.hashAll)),
  );

  @override
  String toString() =>
      'StudyTable($title, ${columns.length} columnas, ${rows.length} filas)';
}
