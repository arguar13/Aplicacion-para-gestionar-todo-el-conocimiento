import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/util/windows_1252.dart';
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
    final text = decodePlainText(await source.readAll());

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

/// Los bytes de un archivo de texto, como texto. Lo usa también el lector de
/// Word, con el texto suelto que un documento trae incrustado (F22).
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
/// 3. **UTF-8**, si hay al menos un carácter de más de un byte bien formado
///    y los bytes que no encajan en ninguno no son más que ellos. Un byte
///    suelto roto en medio —un archivo cortado, un carácter dañado, una "ñ"
///    de Windows pegada en un texto en UTF-8— no convierte el resto en
///    "canciÃ³n": **ese byte** se lee como Windows-1252, que es casi siempre
///    lo que era (F22). Antes quedaba como `�`, y un empate entre bien
///    formados y rotos mandaba el archivo entero a Windows-1252.
/// 4. Si no, **Windows-1252**: lo que escriben los programas viejos de
///    Windows, y un superconjunto de Latin-1 en todo lo que se escribe.
String decodePlainText(Uint8List bytes) {
  if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
    // La marca dice UTF-8 sin dudas: se lee así aunque haya bytes rotos.
    return _readUtf8(bytes, 3).text;
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

  // Sin ningún carácter de más de un byte no hay nada que decidir: cada byte
  // roto ya se lee como Windows-1252, y un texto solo ASCII es el mismo en
  // las dos.
  final asUtf8 = _readUtf8(bytes, 0);
  if (asUtf8.invalid > asUtf8.valid) return decodeWindows1252(bytes);
  return asUtf8.text;
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

/// Los bytes desde [start] leídos como UTF-8, con cuántos caracteres de más
/// de un byte estaban bien formados y cuántos bytes no encajaban en ninguno.
///
/// Un archivo en Windows-1252 casi nunca forma por casualidad una secuencia
/// válida de UTF-8: la "ñ" es 0xF1, que en UTF-8 anuncia cuatro bytes, y la
/// "o" que le sigue no es uno de ellos.
///
/// Es un decodificador propio, y no `utf8.decode` con `allowMalformed`,
/// porque ese cambia cada byte roto por `�` y el carácter se pierde. Acá
/// cada byte que no encaja se lee solo, como Windows-1252 —el 0xF1 de
/// "a⟨F1⟩o" es la "ñ" de "año"—, y la lectura sigue en el byte siguiente
/// (F22).
({String text, int valid, int invalid}) _readUtf8(Uint8List bytes, int start) {
  final buffer = StringBuffer();
  var valid = 0;
  var invalid = 0;
  var i = start;
  while (i < bytes.length) {
    final lead = bytes[i];
    if (lead < 0x80) {
      buffer.writeCharCode(lead);
      i++;
      continue;
    }

    final length = switch (lead) {
      >= 0xC2 && <= 0xDF => 2,
      >= 0xE0 && <= 0xEF => 3,
      >= 0xF0 && <= 0xF4 => 4,
      _ => 0,
    };
    var ok = length > 0 && i + length <= bytes.length;
    if (ok) {
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
      ok = second >= low && second <= high;
      for (var k = 2; ok && k < length; k++) {
        ok = bytes[i + k] & 0xC0 == 0x80;
      }
    }

    if (!ok) {
      buffer.write(decodeWindows1252([lead]));
      invalid++;
      i++;
      continue;
    }

    // Los bits del primer byte que quedan después de la marca de longitud,
    // y seis por cada byte de continuación.
    var code = lead & (0xFF >> (length + 1));
    for (var k = 1; k < length; k++) {
      code = (code << 6) | (bytes[i + k] & 0x3F);
    }
    buffer.writeCharCode(code);
    valid++;
    i += length;
  }
  return (text: buffer.toString(), valid: valid, invalid: invalid);
}
