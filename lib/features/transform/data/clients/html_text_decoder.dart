import 'dart:convert';

import 'package:sinapsis/core/util/single_byte_encodings.dart';
import 'package:sinapsis/core/util/windows_1252.dart';

/// Convierte los bytes de una página en texto con la codificación que la
/// página declara (F22).
///
/// Antes se pedía la página como texto y `Dio` la decodificaba siempre como
/// UTF-8, sin mirar lo que dijera el servidor: una página en Latin-1 perdía
/// cada tilde y cada eñe ("a�o"), y ese texto roto era lo que se guardaba.
///
/// Se decide como lo decide un navegador, en este orden:
///
/// 1. La marca de orden de bytes al principio del archivo, si la hay: es lo
///    más confiable que existe.
/// 2. El `charset` del encabezado `Content-Type` de la respuesta.
/// 3. Un `<meta charset>` o un `<meta http-equiv="Content-Type">` en el
///    principio del documento, sin contar los que están dentro de un
///    comentario o de un script. El estándar lo busca en los primeros 1024
///    bytes; acá se mira un poco más, porque hay páginas que lo ponen
///    después de scripts o comentarios largos.
/// 4. Sin nada declarado, UTF-8 —lo que usa casi toda la web actual—. Solo
///    si los bytes no tienen ni una secuencia de UTF-8 de más de un byte y sí
///    alguna inválida, es una página vieja sin declarar, y se lee como
///    Windows-1252, que es lo que hacen los navegadores en español.
///
/// **Un byte suelto no manda la página entera a otra codificación.** Una
/// página en UTF-8 con un solo byte que no lo es —un pie de página pegado
/// de otro sistema, un carácter cortado— antes se leía entera como
/// Windows-1252, y cada tilde del resto salía como dos letras ("aÃ±o"). Ahora
/// se lee como UTF-8 y solo ese byte se toma como Windows-1252, que es casi
/// siempre de donde vino: en vez de un "�" queda la letra que era.
///
/// Se entienden UTF-8, UTF-16, Windows-1252 (con ISO-8859-1 y ASCII, que los
/// navegadores leen igual), ISO-8859-15, ISO-8859-2, Windows-1251 y KOI8-R:
/// las de las páginas en español y en inglés, y las de un byte más comunes
/// de Europa central y de Rusia, con tablas propias en vez de sumar un
/// paquete. Una codificación que no está entre esas —Shift_JIS, GBK,
/// EUC-KR— se avisa a [onUnsupportedCharset] con el nombre declarado, y la
/// página se lee como si no declarara nada: UTF-8, o Windows-1252 si no lo
/// es. El texto puede salir roto, pero queda registrado por qué.
String decodeHtmlBytes(
  List<int> bytes, {
  String? contentType,
  void Function(String charset)? onUnsupportedCharset,
}) {
  final fromMark = _byteOrderMark(bytes);
  if (fromMark != null) {
    return _decode(bytes.sublist(fromMark.length), fromMark.encoding);
  }

  _Encoding? recognized(String? label) {
    if (label == null) return null;
    final encoding = _encodingFor(label);
    if (encoding == null) onUnsupportedCharset?.call(label);
    return encoding;
  }

  final declared =
      recognized(_charsetIn(contentType)) ??
      // Un `<meta>` no puede declarar UTF-16: si pudo leerse como texto
      // latino para encontrarlo, no es UTF-16. El estándar dice leerlo como
      // UTF-8.
      switch (recognized(_metaCharset(bytes))) {
        _Encoding.utf16le || _Encoding.utf16be => _Encoding.utf8,
        final other => other,
      };
  if (declared != null) return _decode(bytes, declared);

  final read = _utf8WithFallback(bytes);
  if (read.invalid > 0 && read.multibyte == 0) {
    return decodeWindows1252(bytes);
  }
  return read.text;
}

/// [bytes] leídos con la codificación que se llama [charset], o `null` si
/// no es una de las que se entienden.
///
/// Para los archivos que declaran su codificación por su cuenta, como el
/// `<?xml encoding="…"?>` de un capítulo de EPUB: la misma tabla de nombres
/// y los mismos decodificadores que una página. Igual que con un `<meta>`,
/// una declaración que pudo leerse como texto latino no puede ser UTF-16, y
/// se lee como UTF-8.
String? decodeDeclaredCharset(List<int> bytes, String charset) =>
    switch (_encodingFor(charset)) {
      null => null,
      _Encoding.utf16le || _Encoding.utf16be => _decode(bytes, _Encoding.utf8),
      final encoding => _decode(bytes, encoding),
    };

enum _Encoding {
  utf8,
  utf16le,
  utf16be,
  windows1252,
  iso885915,
  iso88592,
  windows1251,
  koi8r,
}

({_Encoding encoding, int length})? _byteOrderMark(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return (encoding: _Encoding.utf8, length: 3);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return (encoding: _Encoding.utf16be, length: 2);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return (encoding: _Encoding.utf16le, length: 2);
  }
  return null;
}

final _charsetParameter = RegExp(
  r'''charset\s*=\s*["']?\s*([A-Za-z0-9_:.+-]+)''',
  caseSensitive: false,
);

/// El `charset=` de un `Content-Type`, o de un `<meta>` que lo repite.
String? _charsetIn(String? declaration) =>
    declaration == null ? null : _charsetParameter.firstMatch(declaration)?[1];

/// Lo que no cuenta al buscar el `<meta>`: un comentario, o un script o un
/// estilo con su contenido. Un `<meta charset>` escrito adentro de un
/// comentario —código viejo desactivado— o de una cadena de JavaScript no
/// declara nada; tomarlo leía la página entera con la codificación
/// equivocada (F22).
final _notMarkup = RegExp(
  r'<!--[\s\S]*?(?:-->|$)|<(script|style)\b[\s\S]*?(?:</\1\s*>|$)',
  caseSensitive: false,
);

final _metaTag = RegExp(r'<meta\b[^>]*>', caseSensitive: false);

final _attribute = RegExp(
  r'''([^\s"'<>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?''',
);

/// Cuánto del principio del documento se mira para encontrar el `<meta>`.
const _metaScanLength = 8 * 1024;

/// El `charset` que declara un `<meta>` del documento.
///
/// Los bytes se leen como Latin-1 solo para buscar: todas las codificaciones
/// que importan acá escriben las etiquetas en ASCII, y Latin-1 no falla con
/// ningún byte. Declara una codificación el `<meta>` que tiene un atributo
/// `charset`, o uno `http-equiv="Content-Type"` con el `charset=` en su
/// `content`. Un "charset=" en cualquier otro atributo —la descripción de
/// una página que habla de codificaciones— no declara nada.
String? _metaCharset(List<int> bytes) {
  final head = latin1
      .decode(
        bytes.length > _metaScanLength
            ? bytes.sublist(0, _metaScanLength)
            : bytes,
      )
      .replaceAll(_notMarkup, '');
  for (final tag in _metaTag.allMatches(head)) {
    final attributes = {
      for (final attribute in _attribute.allMatches(tag[0]!.substring(5)))
        attribute[1]!.toLowerCase():
            attribute[2] ?? attribute[3] ?? attribute[4] ?? '',
    };
    final charset = attributes['charset']?.trim();
    if (charset != null && charset.isNotEmpty) return charset;
    if (attributes['http-equiv']?.trim().toLowerCase() == 'content-type') {
      final fromContent = _charsetIn(attributes['content']);
      if (fromContent != null) return fromContent;
    }
  }
  return null;
}

/// Los nombres con que se declara cada codificación, según el estándar de
/// codificaciones de la web (WHATWG).
///
/// Uno importante: `iso-8859-1`, `latin1` y `us-ascii` se leen como
/// Windows-1252, no como Latin-1 estricto. Es lo que hacen todos los
/// navegadores, porque las páginas que dicen `iso-8859-1` casi siempre usan
/// comillas tipográficas, rayas y el signo del euro de Windows-1252, que en
/// Latin-1 estricto serían caracteres de control invisibles.
_Encoding? _encodingFor(String label) => switch (label.trim().toLowerCase()) {
  'utf-8' ||
  'utf8' ||
  'unicode-1-1-utf-8' ||
  'unicode11utf8' ||
  'unicode20utf8' ||
  'x-unicode20utf8' => _Encoding.utf8,
  'utf-16' ||
  'utf-16le' ||
  'ucs-2' ||
  'unicode' ||
  'csunicode' ||
  'iso-10646-ucs-2' ||
  'unicodefeff' => _Encoding.utf16le,
  'utf-16be' || 'unicodefffe' => _Encoding.utf16be,
  'windows-1252' ||
  'cp1252' ||
  'x-cp1252' ||
  'iso-8859-1' ||
  'iso8859-1' ||
  'iso88591' ||
  'iso_8859-1' ||
  'iso_8859-1:1987' ||
  'iso-ir-100' ||
  'csisolatin1' ||
  'latin1' ||
  'l1' ||
  'cp819' ||
  'ibm819' ||
  'ascii' ||
  'us-ascii' ||
  'ansi_x3.4-1968' => _Encoding.windows1252,
  'iso-8859-15' ||
  'iso8859-15' ||
  'iso885915' ||
  'iso_8859-15' ||
  'csisolatin9' ||
  'latin9' ||
  'l9' => _Encoding.iso885915,
  'iso-8859-2' ||
  'iso8859-2' ||
  'iso88592' ||
  'iso_8859-2' ||
  'iso_8859-2:1987' ||
  'iso-ir-101' ||
  'csisolatin2' ||
  'latin2' ||
  'l2' => _Encoding.iso88592,
  'windows-1251' || 'cp1251' || 'x-cp1251' => _Encoding.windows1251,
  'koi8-r' || 'koi8_r' || 'koi8' || 'koi' || 'cskoi8r' => _Encoding.koi8r,
  _ => null,
};

String _decode(List<int> bytes, _Encoding encoding) => switch (encoding) {
  _Encoding.utf8 => _utf8WithFallback(bytes).text,
  _Encoding.utf16le => _utf16(bytes, bigEndian: false),
  _Encoding.utf16be => _utf16(bytes, bigEndian: true),
  _Encoding.windows1252 => decodeWindows1252(bytes),
  _Encoding.iso885915 => SingleByteEncoding.iso885915.decode(bytes),
  _Encoding.iso88592 => SingleByteEncoding.iso88592.decode(bytes),
  _Encoding.windows1251 => SingleByteEncoding.windows1251.decode(bytes),
  _Encoding.koi8r => SingleByteEncoding.koi8r.decode(bytes),
};

String _utf16(List<int> bytes, {required bool bigEndian}) =>
    String.fromCharCodes([
      for (var i = 0; i + 1 < bytes.length; i += 2)
        if (bigEndian)
          bytes[i] << 8 | bytes[i + 1]
        else
          bytes[i + 1] << 8 | bytes[i],
    ]);

/// [bytes] leídos como UTF-8, con cada byte que no forma una secuencia
/// válida leído como Windows-1252 en vez de reemplazado por "�".
///
/// Cuenta además las secuencias de más de un byte que sí eran válidas y los
/// bytes que no: con eso [decodeHtmlBytes] decide si la página sin declarar
/// era UTF-8 con algún byte suelto o Windows-1252 de punta a punta.
({String text, int multibyte, int invalid}) _utf8WithFallback(List<int> bytes) {
  try {
    return (text: utf8.decode(bytes), multibyte: 0, invalid: 0);
  } on FormatException {
    // Hay algo inválido: se recorre byte por byte.
  }

  final buffer = StringBuffer();
  var multibyte = 0;
  var invalid = 0;
  var i = 0;
  while (i < bytes.length) {
    final lead = bytes[i];
    if (lead < 0x80) {
      buffer.writeCharCode(lead);
      i++;
      continue;
    }
    final length = _sequenceLength(bytes, i);
    if (length == 0) {
      buffer.write(decodeWindows1252([lead]));
      invalid++;
      i++;
      continue;
    }
    buffer.write(utf8.decode(bytes.sublist(i, i + length)));
    multibyte++;
    i += length;
  }
  return (text: buffer.toString(), multibyte: multibyte, invalid: invalid);
}

/// Cuántos bytes ocupa la secuencia de UTF-8 que empieza en [start], o 0 si
/// no es una secuencia válida: los rangos exactos del estándar, que dejan
/// afuera las formas demasiado largas, los sustitutos y lo que pasa de
/// U+10FFFF.
int _sequenceLength(List<int> bytes, int start) {
  final lead = bytes[start];
  final (length, low, high) = switch (lead) {
    >= 0xC2 && <= 0xDF => (2, 0x80, 0xBF),
    0xE0 => (3, 0xA0, 0xBF),
    0xED => (3, 0x80, 0x9F),
    >= 0xE1 && <= 0xEF => (3, 0x80, 0xBF),
    0xF0 => (4, 0x90, 0xBF),
    >= 0xF1 && <= 0xF3 => (4, 0x80, 0xBF),
    0xF4 => (4, 0x80, 0x8F),
    _ => (0, 0, 0),
  };
  if (length == 0 || start + length > bytes.length) return 0;
  final second = bytes[start + 1];
  if (second < low || second > high) return 0;
  for (var k = 2; k < length; k++) {
    final next = bytes[start + k];
    if (next < 0x80 || next > 0xBF) return 0;
  }
  return length;
}
