/// Sacar una tabla de datos de la app (F43): «Copiar» —para pegarla en una
/// planilla— y «Exportar a CSV» —un archivo que abre bien en Excel y en
/// Google Sheets—.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';

/// [table] como texto separado por tabulaciones, con los encabezados en la
/// primera línea y las filas en [order] (sin él, el de la IA): lo que Excel,
/// Sheets y Numbers pegan en celdas, una por valor.
///
/// En TSV no hay comillas que valgan en todos lados: una tabulación o un
/// salto de línea dentro de una celda la partiría, así que pasan a ser un
/// espacio.
String tableToTsv(StudyTable table, {List<int>? order}) {
  String cell(String value) =>
      value.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  final lines = [
    [for (final column in table.columns) cell(column.name)].join('\t'),
    for (final index in order ?? _identity(table))
      [for (final value in table.rows[index]) cell(value)].join('\t'),
  ];
  return lines.join('\n');
}

/// [table] como CSV, listo para guardar (RFC 4180), con las filas en [order]
/// (sin él, el de la IA):
///
/// - **UTF-8 con BOM**: sin la marca del principio, Excel en Windows lo lee
///   en la página de códigos del sistema y «Éxodo» se ve «Ã‰xodo». Sheets y
///   Numbers la ignoran;
/// - **líneas con CRLF**, como pide la norma;
/// - **entre comillas** el valor que trae el separador, comillas, un salto de
///   línea o espacios al borde, con las comillas de adentro duplicadas;
/// - el **separador** es [separator] —ver [csvSeparatorFor]—;
/// - un valor que Excel tomaría por una **fórmula** —el que empieza con «=»,
///   «+», «-» o «@» y no es un número— va con un apóstrofo adelante, como
///   recomienda OWASP: abrir el archivo nunca ejecuta nada. «-12» y «+5 %»
///   quedan como están.
Uint8List tableToCsv(
  StudyTable table, {
  required String separator,
  List<int>? order,
}) {
  String field(String value) {
    final safe = _defused(value);
    final quoted =
        safe.contains(separator) ||
        safe.contains('"') ||
        safe.contains('\n') ||
        safe.contains('\r') ||
        safe != safe.trim();
    return quoted ? '"${safe.replaceAll('"', '""')}"' : safe;
  }

  final buffer = StringBuffer()
    ..write(
      [for (final column in table.columns) field(column.name)].join(separator),
    )
    ..write('\r\n');
  for (final index in order ?? _identity(table)) {
    buffer
      ..write(
        [for (final value in table.rows[index]) field(value)].join(separator),
      )
      ..write('\r\n');
  }
  return Uint8List.fromList([..._bom, ...utf8.encode(buffer.toString())]);
}

/// El separador de CSV para quien usa la app en [locale]: `;` donde la coma
/// es el separador decimal —el castellano, el portugués, el francés, el
/// alemán…—, `,` donde es el punto.
///
/// Es lo que hace Excel: al abrir un CSV con doble clic usa el «separador de
/// listas» del sistema, que en esos idiomas es `;` justamente porque la coma
/// está en los números. Con `,` en una computadora en castellano, todo
/// quedaría en la primera columna. Google Sheets reconoce cualquiera de los
/// dos al importar. La línea `sep=;` que Excel entiende no se usa: con ella
/// Excel deja de leer el BOM y vuelven las letras rotas, y Sheets la muestra
/// como una fila más.
String csvSeparatorFor(String locale) {
  try {
    final symbols = NumberFormat.decimalPattern(locale).symbols;
    return symbols.DECIMAL_SEP == ',' ? ';' : ',';
    // Un idioma que intl no conoce: el de la norma.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return ',';
  }
}

/// La marca de orden de bytes de UTF-8.
const _bom = [0xEF, 0xBB, 0xBF];

/// [value] sin que Excel lo tome por una fórmula.
String _defused(String value) {
  if (value.isEmpty) return value;
  final first = value[0];
  if (first == '=' || first == '@') return "'$value";
  if (first == '+' || first == '-') {
    // Un número con signo («-12», «+5 %», «- 3») se deja; lo demás («-foo»,
    // «+A1»), no.
    final rest = value.substring(1).trimLeft();
    if (rest.isEmpty || RegExp(r'^[\d.,]').hasMatch(rest)) return value;
    return "'$value";
  }
  return value;
}

Iterable<int> _identity(StudyTable table) =>
    Iterable<int>.generate(table.rows.length);
