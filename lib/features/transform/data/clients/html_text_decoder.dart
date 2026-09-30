import 'dart:convert';

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
///    principio del documento. El estándar lo busca en los primeros 1024
///    bytes; acá se mira un poco más, porque hay páginas que lo ponen
///    después de scripts o comentarios largos.
/// 4. Sin nada declarado, UTF-8 —lo que usa casi toda la web actual—, salvo
///    que los bytes no sean UTF-8 válido: entonces es una página vieja sin
///    declarar, y se lee como Windows-1252, que es lo que hacen los
///    navegadores en español.
///
/// Se entienden UTF-8, UTF-16 y las codificaciones latinas de un byte:
/// Windows-1252, ISO-8859-1 e ISO-8859-15. Son las de las páginas en español
/// y en inglés, y se decodifican con una tabla propia en vez de sumar un
/// paquete. Una codificación que no está entre esas —Shift_JIS, KOI8-R— se
/// lee como UTF-8, como antes: sale con caracteres rotos, y hace falta un
/// paquete de codificaciones si algún día importa.
String decodeHtmlBytes(List<int> bytes, {String? contentType}) {
  final fromMark = _byteOrderMark(bytes);
  if (fromMark != null) {
    return _decode(bytes.sublist(fromMark.length), fromMark.encoding);
  }

  final declared =
      _encodingFor(_charsetIn(contentType)) ??
      // Un `<meta>` no puede declarar UTF-16: si pudo leerse como texto
      // latino para encontrarlo, no es UTF-16. El estándar dice leerlo como
      // UTF-8.
      switch (_encodingFor(_metaCharset(bytes))) {
        _Encoding.utf16le || _Encoding.utf16be => _Encoding.utf8,
        final other => other,
      };
  if (declared != null) return _decode(bytes, declared);

  try {
    return utf8.decode(bytes);
  } on FormatException {
    return _decode(bytes, _Encoding.windows1252);
  }
}

enum _Encoding { utf8, utf16le, utf16be, windows1252, iso885915 }

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

final _metaTag = RegExp('<meta[^>]*>', caseSensitive: false);

/// Cuánto del principio del documento se mira para encontrar el `<meta>`.
const _metaScanLength = 8 * 1024;

/// El `charset` que declara un `<meta>` del documento.
///
/// Los bytes se leen como Latin-1 solo para buscar: todas las codificaciones
/// que importan acá escriben las etiquetas en ASCII, y Latin-1 no falla con
/// ningún byte. Sirve para las dos formas —`<meta charset="…">` y
/// `<meta http-equiv="Content-Type" content="text/html; charset=…">`—.
String? _metaCharset(List<int> bytes) {
  final head = latin1.decode(
    bytes.length > _metaScanLength ? bytes.sublist(0, _metaScanLength) : bytes,
  );
  for (final tag in _metaTag.allMatches(head)) {
    final charset = _charsetIn(tag[0]);
    if (charset != null) return charset;
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
_Encoding? _encodingFor(String? label) => switch (label?.trim().toLowerCase()) {
  null => null,
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
  _ => null,
};

String _decode(List<int> bytes, _Encoding encoding) => switch (encoding) {
  _Encoding.utf8 => utf8.decode(bytes, allowMalformed: true),
  _Encoding.utf16le => _utf16(bytes, bigEndian: false),
  _Encoding.utf16be => _utf16(bytes, bigEndian: true),
  _Encoding.windows1252 => String.fromCharCodes(bytes.map(_windows1252)),
  _Encoding.iso885915 => String.fromCharCodes(bytes.map(_iso885915)),
};

String _utf16(List<int> bytes, {required bool bigEndian}) =>
    String.fromCharCodes([
      for (var i = 0; i + 1 < bytes.length; i += 2)
        if (bigEndian)
          bytes[i] << 8 | bytes[i + 1]
        else
          bytes[i + 1] << 8 | bytes[i],
    ]);

/// Windows-1252 es Latin-1 salvo entre 0x80 y 0x9F, donde Latin-1 tiene
/// caracteres de control y Windows-1252 las comillas tipográficas, las rayas,
/// los puntos suspensivos y el euro. Los cinco lugares que Windows-1252 deja
/// sin definir quedan como el carácter de control de Latin-1, igual que en
/// el estándar.
int _windows1252(int byte) =>
    byte >= 0x80 && byte <= 0x9F ? _windows1252High[byte - 0x80] : byte;

const _windows1252High = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, //
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, //
];

/// ISO-8859-15 es Latin-1 con ocho lugares cambiados: el euro, y las letras
/// de francés y de lenguas del norte que Latin-1 no tenía.
int _iso885915(int byte) => switch (byte) {
  0xA4 => 0x20AC,
  0xA6 => 0x0160,
  0xA8 => 0x0161,
  0xB4 => 0x017D,
  0xB8 => 0x017E,
  0xBC => 0x0152,
  0xBD => 0x0153,
  0xBE => 0x0178,
  _ => byte,
};
