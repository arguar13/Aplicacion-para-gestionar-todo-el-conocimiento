import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

/// Lee un archivo de texto suelto o de Markdown.
///
/// No hay nada que interpretar: los bytes ya son el contenido. Existe igual
/// porque sin él un `.txt` arrastrado a la app quedaría guardado y mudo — con
/// su archivo a salvo pero sin una línea de texto buscable, que es justamente
/// lo que se venía a resolver.
///
/// Lo único que hay que averiguar es **en qué codificación** están esos
/// bytes (F22). Antes se leían siempre como UTF-8, y un `.txt` guardado en
/// Latin-1 por un editor viejo salía "a�o", y uno en UTF-16 —lo que escribe
/// el Bloc de notas de Windows al elegir "Unicode"— salía ilegible. El texto
/// se guarda después tal cual: sin recortar espacios ni saltos del final.
class PlainTextParser implements DocumentParser {
  const PlainTextParser();

  @override
  bool canParse(FileFormat format) =>
      format == FileFormat.plainText || format == FileFormat.markdown;

  @override
  Future<ParsedDocument> parse(
    DocumentSource source, {
    DocumentParseSession session = DocumentParseSession.detached,
  }) async {
    final text = _decode(await source.readAll());

    return ParsedDocument(markdown: text, title: _firstHeading(text));
  }

  /// El título de un Markdown, si su primera línea con contenido es uno.
  ///
  /// Solo eso: en un archivo de texto suelto, la primera línea puede ser
  /// cualquier cosa, y el nombre del archivo suele decir más. En un Markdown
  /// que empieza con `# Algo`, ese `Algo` es el título de verdad.
  String? _firstHeading(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(trimmed);
      return heading?.group(1)?.trim();
    }
    return null;
  }
}

/// Los bytes de un archivo de texto, como texto.
///
/// En este orden, de lo seguro a lo supuesto:
///
/// 1. **La marca de orden de bytes** (BOM), si la trae, dice la codificación
///    sin dudas: UTF-8, UTF-16 o UTF-32, en cualquiera de los dos órdenes.
///    La marca no es texto —es invisible, pero cuenta como carácter y un
///    `﻿# Título` dejaría de ser un encabezado—, así que no se guarda.
/// 2. **UTF-16 sin marca** se reconoce por sus ceros: un texto en un
///    alfabeto latino tiene un byte en cero en casi todos los caracteres,
///    siempre del mismo lado. Un texto de verdad en cualquier otra
///    codificación no tiene ceros.
/// 3. **UTF-8**, si los bytes lo son. Con un byte suelto roto en medio —un
///    archivo cortado, un carácter dañado— se sigue leyendo como UTF-8 y ese
///    carácter queda como `�`: lo que decide es que haya más caracteres de
///    UTF-8 bien formados que rotos.
/// 4. Si no, **Windows-1252**: lo que escriben los programas viejos de
///    Windows, y un superconjunto de Latin-1 en todo lo que se escribe.
String _decode(Uint8List bytes) {
  if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  // UTF-32 antes que UTF-16: la marca de UTF-32 LE empieza con la de
  // UTF-16 LE.
  if (_startsWith(bytes, const [0xFF, 0xFE, 0x00, 0x00])) {
    return _decodeUtf32(bytes, 4, littleEndian: true);
  }
  if (_startsWith(bytes, const [0x00, 0x00, 0xFE, 0xFF])) {
    return _decodeUtf32(bytes, 4, littleEndian: false);
  }
  if (_startsWith(bytes, const [0xFF, 0xFE])) {
    return _decodeUtf16(bytes, 2, littleEndian: true);
  }
  if (_startsWith(bytes, const [0xFE, 0xFF])) {
    return _decodeUtf16(bytes, 2, littleEndian: false);
  }

  final utf16 = _utf16WithoutMark(bytes);
  if (utf16 != null) return _decodeUtf16(bytes, 0, littleEndian: utf16);

  final (:valid, :invalid) = _utf8Sequences(bytes);
  if (invalid == 0 || valid > invalid) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  return _decodeWindows1252(bytes);
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// `true` si parece UTF-16 LE sin marca, `false` si UTF-16 BE, `null` si no
/// parece UTF-16.
///
/// Un tercio de los caracteres con el byte alto en cero, y casi ninguno con
/// el bajo: en un texto latino en UTF-16 son casi todos, y en UTF-8 o
/// Windows-1252 un cero es un carácter nulo, que un texto no tiene.
bool? _utf16WithoutMark(Uint8List bytes) {
  final pairs = bytes.length ~/ 2;
  if (pairs == 0) return null;

  var evenZeros = 0;
  var oddZeros = 0;
  for (var i = 0; i < pairs * 2; i += 2) {
    if (bytes[i] == 0) evenZeros++;
    if (bytes[i + 1] == 0) oddZeros++;
  }

  bool many(int zeros) => zeros * 3 >= pairs;
  bool few(int zeros) => zeros * 20 <= pairs;
  if (many(oddZeros) && few(evenZeros)) return true;
  if (many(evenZeros) && few(oddZeros)) return false;
  return null;
}

String _decodeUtf16(Uint8List bytes, int start, {required bool littleEndian}) {
  final units = <int>[
    for (var i = start; i + 1 < bytes.length; i += 2)
      if (littleEndian)
        bytes[i] | (bytes[i + 1] << 8)
      else
        (bytes[i] << 8) | bytes[i + 1],
  ];
  // Un byte suelto al final es medio carácter: se marca, no se descarta.
  final truncated = (bytes.length - start).isOdd;
  // Las cadenas de Dart son UTF-16: los pares sustitutos se arman solos.
  return String.fromCharCodes(units) + (truncated ? '\uFFFD' : '');
}

String _decodeUtf32(Uint8List bytes, int start, {required bool littleEndian}) {
  final buffer = StringBuffer();
  for (var i = start; i + 3 < bytes.length; i += 4) {
    final code = littleEndian
        ? bytes[i] |
              (bytes[i + 1] << 8) |
              (bytes[i + 2] << 16) |
              (bytes[i + 3] << 24)
        : (bytes[i] << 24) |
              (bytes[i + 1] << 16) |
              (bytes[i + 2] << 8) |
              bytes[i + 3];
    final valid = code <= 0x10FFFF && (code < 0xD800 || code > 0xDFFF);
    buffer.writeCharCode(valid ? code : 0xFFFD);
  }
  if ((bytes.length - start) % 4 != 0) buffer.write('\uFFFD');
  return buffer.toString();
}

/// Cuántos caracteres de más de un byte de UTF-8 están bien formados, y
/// cuántos bytes no encajan en ninguno.
///
/// Un archivo en Windows-1252 casi nunca forma por casualidad una secuencia
/// válida de UTF-8: la "ñ" es 0xF1, que en UTF-8 anuncia cuatro bytes, y la
/// "o" que le sigue no es uno de ellos.
({int valid, int invalid}) _utf8Sequences(Uint8List bytes) {
  var valid = 0;
  var invalid = 0;
  var i = 0;
  while (i < bytes.length) {
    final lead = bytes[i];
    if (lead < 0x80) {
      i++;
      continue;
    }

    final length = switch (lead) {
      >= 0xC2 && <= 0xDF => 2,
      >= 0xE0 && <= 0xEF => 3,
      >= 0xF0 && <= 0xF4 => 4,
      _ => 0,
    };
    if (length == 0 || i + length > bytes.length) {
      invalid++;
      i++;
      continue;
    }

    // El segundo byte tiene un rango más estrecho en algunos casos: sin
    // esto pasarían por válidas las formas largas y los sustitutos.
    final second = bytes[i + 1];
    final (low, high) = switch (lead) {
      0xE0 => (0xA0, 0xBF),
      0xED => (0x80, 0x9F),
      0xF0 => (0x90, 0xBF),
      0xF4 => (0x80, 0x8F),
      _ => (0x80, 0xBF),
    };
    var ok = second >= low && second <= high;
    for (var k = 2; ok && k < length; k++) {
      ok = bytes[i + k] & 0xC0 == 0x80;
    }

    if (ok) {
      valid++;
      i += length;
    } else {
      invalid++;
      i++;
    }
  }
  return (valid: valid, invalid: invalid);
}

/// Windows-1252: Latin-1, salvo del 0x80 al 0x9F, donde Windows puso las
/// comillas tipográficas, la raya, el euro y compañía.
String _decodeWindows1252(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.writeCharCode(
      byte >= 0x80 && byte <= 0x9F ? _windows1252High[byte - 0x80] : byte,
    );
  }
  return buffer.toString();
}

/// Del 0x80 al 0x9F. Los cinco que Windows-1252 deja sin definir (0x81,
/// 0x8D, 0x8F, 0x90, 0x9D) quedan con su mismo código, como hace Windows: un
/// byte no se pierde aunque no tenga letra.
// dart format off
const _windows1252High = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
];
// dart format on
