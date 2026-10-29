import 'dart:convert';

import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_values.dart';
import 'package:sinapsis/features/creations/domain/services/structured_json.dart';

/// Los topes de una tabla: lo que no entra se corta. Una tabla de estudio
/// rara vez pasa de unas decenas de filas; esto le pone un límite a lo que
/// una IA desbocada puede devolver y a lo que la pantalla mide.
abstract final class StudyTableLimits {
  static const int columns = 12;
  static const int rows = 300;
  static const int title = 140;
  static const int columnName = 80;
  static const int cell = 1200;
}

/// El JSON de una tabla de datos, en los dos sentidos (F43, decisión G).
///
/// [read] lee con tolerancia lo que devuelve la IA —y [decode], lo
/// guardado—:
///
/// - las columnas como lista de nombres o de objetos (`name`, `nombre`,
///   `header`…, con su `type`), bajo `columns`, `columnas`, `headers`,
///   `encabezados`…;
/// - las filas como listas (un valor por columna) o como objetos (columna →
///   valor), bajo `rows`, `filas`, `data`, `datos`…; con objetos y sin
///   columnas, las columnas son sus claves, en el orden en que aparecen;
/// - una lista sola: de objetos (las filas) o de listas (la primera, los
///   encabezados);
/// - los valores como texto, número o lo que sea: todo se guarda como
///   texto; una fila más corta se completa con vacíos y una más larga se
///   corta; una fila vacía no entra;
/// - el tipo de cada columna como lo diga la IA (`number`, `número`,
///   `fecha`, `year`…) o, si no lo dice, deducido de sus valores: si casi
///   todos son números, es de números; si casi todos son fechas, de fechas.
///
/// [encode] escribe la forma canónica, la que se guarda y la que describe
/// `dataTableSchemaPrompt`.
abstract final class StudyTableJson {
  /// La tabla de [source] —un `Map`, una lista o el texto que devolvió la
  /// IA—. Lanza [FormatException] con un motivo corto —el que se le dice a
  /// la IA al pedirle que la corrija— si no tiene columnas o filas.
  static StudyTable read(Object? source) {
    var json = source is String ? extractJsonValue(source) : source;
    if (json is Map) {
      final map = _normalize(json);
      // `{"table": {...}}`: la tabla envuelta.
      final inner = map['table'];
      if (inner is Map && !map.containsKey('rows')) json = inner;
    }

    String title;
    Object? rawColumns;
    Object? rawRows;
    if (json is List) {
      title = '';
      rawRows = json;
    } else if (json is Map) {
      final map = _normalize(json);
      title = _text(map['title'], StudyTableLimits.title);
      rawColumns = map['columns'];
      rawRows = map['rows'];
    } else {
      throw const FormatException(
        'No hay ninguna tabla: falta un objeto con "columns" y "rows".',
      );
    }

    final columns = <_Column>[];
    if (rawColumns is List) {
      for (final raw in rawColumns) {
        final column = _column(raw);
        if (column != null) columns.add(column);
      }
    }
    final rowsIn = rawRows is List ? rawRows : const <Object?>[];
    var bodyRows = rowsIn;
    // Una lista de listas sin columnas: la primera, si es toda texto, son los
    // encabezados.
    if (columns.isEmpty &&
        rowsIn.isNotEmpty &&
        rowsIn.first is List &&
        (rowsIn.first! as List).every((v) => v is String)) {
      for (final name in rowsIn.first! as List) {
        columns.add(_Column(_text(name, StudyTableLimits.columnName)));
      }
      bodyRows = rowsIn.sublist(1);
    }

    final rows = <List<String>>[];
    for (final raw in bodyRows) {
      if (rows.length >= StudyTableLimits.rows) break;
      final List<String> cells;
      if (raw is List) {
        cells = [for (final value in raw) _cell(value)];
      } else if (raw is Map) {
        cells = List.filled(columns.length, '', growable: true);
        for (final entry in raw.entries) {
          final name = _text(entry.key, StudyTableLimits.columnName);
          var index = columns.indexWhere((c) => _fold(c.name) == _fold(name));
          if (index < 0) {
            if (columns.length >= StudyTableLimits.columns) continue;
            columns.add(_Column(name));
            cells.add('');
            index = columns.length - 1;
          }
          cells[index] = _cell(entry.value);
        }
      } else {
        continue;
      }
      if (cells.every((c) => c.isEmpty)) continue;
      rows.add(cells);
    }

    // Tantas columnas como pida la fila más larga, con nombre vacío si la IA
    // no lo dio; nunca más que el tope.
    var width = columns.length;
    for (final row in rows) {
      if (row.length > width) width = row.length;
    }
    if (width > StudyTableLimits.columns) width = StudyTableLimits.columns;
    while (columns.length < width) {
      columns.add(_Column(''));
    }
    if (columns.length > width) columns.removeRange(width, columns.length);

    if (columns.isEmpty) {
      throw const FormatException(
        'La tabla no tiene columnas: falta "columns".',
      );
    }
    if (rows.isEmpty) {
      throw const FormatException('La tabla no tiene filas: falta "rows".');
    }
    final fitted = [
      for (final row in rows)
        [...row.take(width), for (var i = row.length; i < width; i++) ''],
    ];
    final names = _distinct([for (final c in columns) c.name]);
    return StudyTable(
      title: title,
      columns: [
        for (final (i, column) in columns.indexed)
          TableColumn(
            names[i],
            type: column.type ?? _infer([for (final row in fitted) row[i]]),
          ),
      ],
      rows: fitted,
    );
  }

  /// Como [read], o `null` si ahí no hay una tabla que leer.
  static StudyTable? tryDecode(Object? source) {
    try {
      return read(source);
    } on FormatException {
      return null;
    }
  }

  /// Lo guardado en una creación: como [tryDecode], pero sin tabla devuelve
  /// una vacía en vez de `null`.
  static StudyTable decode(Object? source) =>
      tryDecode(source) ?? const StudyTable(title: '', columns: [], rows: []);

  static Map<String, Object?> encode(StudyTable table) => {
    'title': table.title,
    'columns': [
      for (final column in table.columns)
        {'name': column.name, 'type': column.type.jsonName},
    ],
    'rows': table.rows,
  };

  static String encodeString(StudyTable table) => jsonEncode(encode(table));

  static _Column? _column(Object? raw) {
    if (raw is String || raw is num) {
      return _Column(_text(raw, StudyTableLimits.columnName));
    }
    if (raw is! Map) return null;
    final map = _normalize(raw);
    final name = _text(map['name'], StudyTableLimits.columnName);
    return _Column(name, _type(map['type']));
  }

  /// El tipo como lo escribió la IA, o `null` si no lo dijo (o no se
  /// entiende): ahí se deduce de los valores.
  static TableColumnType? _type(Object? raw) {
    if (raw is! String) return null;
    return switch (_fold(raw)) {
      'number' ||
      'numero' ||
      'numeric' ||
      'numerico' ||
      'integer' ||
      'int' ||
      'entero' ||
      'float' ||
      'decimal' ||
      'currency' ||
      'moneda' ||
      'percent' ||
      'percentage' ||
      'porcentaje' ||
      'amount' ||
      'cantidad' => TableColumnType.number,
      'date' ||
      'fecha' ||
      'datetime' ||
      'year' ||
      'ano' ||
      'time' ||
      'epoca' ||
      'periodo' => TableColumnType.date,
      'text' || 'texto' || 'string' || 'cadena' => TableColumnType.text,
      _ => null,
    };
  }

  /// De qué es una columna, por sus valores: de fechas o de números si al
  /// menos cuatro de cada cinco valores no vacíos lo son; si no, de texto.
  ///
  /// Un año solo («1446») es número y fecha a la vez, y los dos lo ordenan
  /// igual: una columna es de fechas si además alguno se escribe como fecha
  /// —con su era, su mes o sus barras—.
  static TableColumnType _infer(List<String> cells) {
    final filled = [
      for (final c in cells)
        if (c.isNotEmpty) c,
    ];
    if (filled.isEmpty) return TableColumnType.text;
    bool most(bool Function(String) test) =>
        filled.where(test).length * 5 >= filled.length * 4;
    if (most((c) => TableValues.date(c) != null) &&
        filled.any(_writtenAsDate)) {
      return TableColumnType.date;
    }
    if (most((c) => TableValues.number(c) != null)) {
      return TableColumnType.number;
    }
    return TableColumnType.text;
  }

  static bool _writtenAsDate(String cell) =>
      TableValues.date(cell) != null &&
      RegExp(r'[a-zA-Z/]|\d-\d').hasMatch(cell);

  /// [names] sin repetidos: el segundo «Año» pasa a ser «Año (2)».
  static List<String> _distinct(List<String> names) {
    final seen = <String, int>{};
    return [
      for (final name in names)
        if (name.isEmpty)
          name
        else
          () {
            final count = seen.update(
              _fold(name),
              (n) => n + 1,
              ifAbsent: () => 1,
            );
            return count == 1 ? name : '$name ($count)';
          }(),
    ];
  }

  static String _cell(Object? value) {
    if (value == null) return '';
    if (value is String) return _clean(value, StudyTableLimits.cell);
    if (value is int) return '$value';
    if (value is double) {
      if (!value.isFinite) return '';
      return value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
    }
    if (value is bool) return '$value';
    if (value is List) {
      return _clean(
        value.map(_cell).where((v) => v.isNotEmpty).join(', '),
        StudyTableLimits.cell,
      );
    }
    if (value is Map) {
      // `{"value": …}` o `{"text": …}`: el valor envuelto.
      final map = _normalize(value);
      return _cell(map['value'] ?? map['name'] ?? map['title']);
    }
    return _clean(value.toString(), StudyTableLimits.cell);
  }

  static Map<String, Object?> _normalize(Map<Object?, Object?> raw) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final folded = _fold(entry.key.toString());
      final key = _aliases[folded] ?? folded;
      out.putIfAbsent(key, () => entry.value);
    }
    return out;
  }

  static const _aliases = <String, String>{
    'titulo': 'title',
    'nombre': 'name',
    'label': 'name',
    'etiqueta': 'name',
    'header': 'name',
    'encabezado': 'name',
    'columna': 'name',
    'column': 'name',
    'key': 'name',
    'field': 'name',
    'campo': 'name',
    'tipo': 'type',
    'kind': 'type',
    'columnas': 'columns',
    'headers': 'columns',
    'encabezados': 'columns',
    'fields': 'columns',
    'campos': 'columns',
    'cols': 'columns',
    'filas': 'rows',
    'data': 'rows',
    'datos': 'rows',
    'items': 'rows',
    'records': 'rows',
    'registros': 'rows',
    'entries': 'rows',
    'tabla': 'table',
    'valor': 'value',
    'text': 'value',
    'texto': 'value',
  };
}

class _Column {
  _Column(this.name, [this.type]);

  final String name;
  final TableColumnType? type;
}

String _fold(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[áàâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp('[^a-z0-9]'), '');

String _text(Object? raw, int limit) =>
    raw is String || raw is num ? _clean(raw.toString(), limit) : '';

/// [text] sin espacios de más —los saltos de línea de adentro quedan— y
/// cortado en [limit], en la última palabra entera y con «…».
String _clean(String text, int limit) {
  final cleaned = text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' ?\n ?'), '\n')
      .trim();
  if (cleaned.length <= limit) return cleaned;
  final cut = cleaned.substring(0, limit - 1);
  final space = cut.lastIndexOf(' ');
  final head = space > limit * 0.6 ? cut.substring(0, space) : cut;
  return '${head.replaceFirst(RegExp(r'[\s,;:.—-]+$'), '')}…';
}
