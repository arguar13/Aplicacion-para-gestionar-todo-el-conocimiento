import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/services/bibliographic_identifiers.dart';
import 'package:sinapsis/core/domain/services/person_name_parser.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/flexible_date.dart';

/// Lee los metadatos bibliográficos de un PDF (F15, D12), buscando en sus
/// bytes crudos y no con `pdfrx`: la librería no expone el diccionario
/// `Info` ni el paquete XMP —solo texto y páginas—, así que la única forma
/// de llegar a ellos es leyendo la estructura del archivo directamente.
///
/// «A ojo» y sin dependencias nuevas, con dos fuentes:
///
/// - **XMP** —el paquete `<x:xmpmeta>`, en XML, obligatoriamente sin
///   comprimir por la norma PDF/A—: `dc:title`, `dc:creator`, y en un
///   artículo académico casi siempre `prism:publicationName`,
///   `prism:volume`, `prism:number`, `prism:startingPage`/`endingPage` y la
///   fecha. Es la fuente que se prefiere: sus etiquetas no significan otra
///   cosa en ningún otro lugar del archivo.
/// - **El diccionario `Info`** —`/Title`, `/Author`, `/CreationDate`—: más
///   viejo, y más ambiguo, porque `/Title` también nombra una entrada de un
///   índice. Por eso no se busca cualquier `/Title`: se seguye la referencia
///   `/Info N 0 R` del `trailer` hasta el objeto N, y solo se lee lo que hay
///   dentro de ÉL.
///
/// Ninguna de las dos existe siempre —un PDF armado a mano, o exportado por
/// un programa que no las escribe—, y entonces esto no encuentra nada:
/// [ExtractedMetadata.isEmpty] es cierto, y no hay sugerencia que ofrecer.
ExtractedMetadata readPdfMetadata(Uint8List bytes) {
  // Un byte por posición de texto: es una traducción reversible —Latin-1—,
  // no una decodificación real. Sirve para buscar tokens de la sintaxis del
  // PDF, que son siempre ASCII, sea cual sea el texto que llevan adentro.
  final text = String.fromCharCodes(bytes);
  return mergeExtractedMetadata([_fromXmp(text), _fromInfoDict(text)]);
}

/// Hasta este tamaño, [readPdfMetadataFrom] lee el PDF entero: es lo más
/// completo, y un artículo o un libro de texto pesan pocos megas.
const pdfMetadataWholeReadLimit = 16 * 1024 * 1024;

/// Cuánto se lee del principio y del final de un PDF más grande.
const _pdfMetadataWindow = 1024 * 1024;

/// Lo mismo que [readPdfMetadata], para un PDF de cualquier tamaño, sin
/// traerlo entero a memoria (F21): convertido a texto, un libro escaneado de
/// 300 MB ocupaba 900 MB.
///
/// Por encima de [pdfMetadataWholeReadLimit] lee solo el principio y el
/// final, que es donde un PDF guarda el `trailer`, la tabla de referencias
/// y —casi siempre— el paquete XMP. Si el objeto `Info` está en el medio, la
/// tabla dice dónde, y se lee solo ese tramo. Lo que quede fuera de eso —una
/// tabla comprimida, un XMP a mitad del archivo— no se encuentra, igual que
/// no lo encuentra la lectura completa cuando está comprimido.
Future<ExtractedMetadata> readPdfMetadataFrom({
  required int size,
  required Future<Uint8List> Function(int start, int length) readRange,
}) async {
  if (size <= pdfMetadataWholeReadLimit) {
    return readPdfMetadata(await readRange(0, size));
  }

  final head = String.fromCharCodes(await readRange(0, _pdfMetadataWindow));
  final tailStart = size - _pdfMetadataWindow;
  final tail = String.fromCharCodes(
    await readRange(tailStart, _pdfMetadataWindow),
  );

  // Cada tramo por separado: juntarlos inventaría un bloque que empieza en
  // uno y termina en el otro.
  final xmp = _fromXmp(head);
  final fromXmp = xmp.isEmpty ? _fromXmp(tail) : xmp;

  final objNum = _infoObjectNumber(tail) ?? _infoObjectNumber(head);
  String? body;
  if (objNum != null) {
    body = _objectBody(tail, objNum) ?? _objectBody(head, objNum);
    if (body == null) {
      final offset = _xrefOffsetOf(tail, objNum);
      if (offset != null && offset < size) {
        body = _objectBody(
          String.fromCharCodes(await readRange(offset, 64 * 1024)),
          objNum,
        );
      }
    }
  }

  return mergeExtractedMetadata([fromXmp, _fromInfoBody(body)]);
}

/// Dónde empieza el objeto [objNum] según la tabla de referencias clásica
/// (`xref`) que haya en [text] —la última, si hay varias—, o `null` si no
/// figura. Una tabla comprimida (PDF 1.5 en adelante) no se lee: es un flujo
/// comprimido, no texto.
int? _xrefOffsetOf(String text, int objNum) {
  // Precedida de cualquier espacio, no solo de un fin de línea: hay
  // generadores que la pegan a lo anterior. `startxref` no cuenta.
  final tables = RegExp(r'(?:^|\s)xref\s*[\r\n]').allMatches(text).toList();
  for (final table in tables.reversed) {
    var position = table.end;
    final subsection = RegExp(r'(\d+)\s+(\d+)\s*[\r\n]+');
    while (true) {
      final header = subsection.matchAsPrefix(text, position);
      if (header == null) break;
      final first = int.parse(header.group(1)!);
      final count = int.parse(header.group(2)!);
      position = header.end;

      // Cada entrada mide 20 bytes: `oooooooooo ggggg n` más el fin de
      // línea, por norma.
      if (objNum >= first && objNum < first + count) {
        final entryStart = position + (objNum - first) * 20;
        if (entryStart + 18 > text.length) return null;
        final entry = RegExp(
          r'(\d{10}) \d{5} n',
        ).matchAsPrefix(text, entryStart);
        return entry == null ? null : int.parse(entry.group(1)!);
      }
      position += count * 20;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// XMP
// ---------------------------------------------------------------------------

ExtractedMetadata _fromXmp(String text) {
  final block = _xmpBlock(text);
  if (block == null) return const ExtractedMetadata();

  final dateText =
      _xmpSingle(block, 'prism:publicationDate') ??
      _xmpSingle(block, 'dc:date') ??
      _xmpSingle(block, 'xmp:CreateDate');
  final date = dateText == null ? null : parseFlexibleDate(dateText);
  final isbn = _xmpSingle(block, 'prism:isbn');

  return ExtractedMetadata(
    title: _xmpSingle(block, 'dc:title'),
    publishedAt: date?.date,
    publicationPrecision: date?.precision,
    reference: ReferenceData(
      contributors: _contributorsFromRawAuthor(
        _xmpList(block, 'dc:creator').join('; '),
      ),
      containerTitle: _xmpSingle(block, 'prism:publicationName'),
      publisher:
          _xmpSingle(block, 'dc:publisher') ??
          _xmpSingle(block, 'prism:publisher'),
      volume: _xmpSingle(block, 'prism:volume'),
      issue: _xmpSingle(block, 'prism:number'),
      pages: _pagesOf(
        _xmpSingle(block, 'prism:startingPage'),
        _xmpSingle(block, 'prism:endingPage'),
      ),
      isbn: isbn == null ? null : normalizeIsbn(isbn),
      doi: _firstDoi(text),
    ),
  );
}

/// El paquete XMP, ya como texto. [text] es el archivo con un byte por
/// letra (ver [readPdfMetadata]), pero el paquete es XML en UTF-8: leído así,
/// cada tilde salía como dos letras —«DeclaraciÃ³n»— (F43, M7). Se vuelve a
/// leer como UTF-8; si no lo es —un generador que escribió Latin-1, contra la
/// norma—, queda como estaba, que para ese caso es lo correcto.
String? _xmpBlock(String text) {
  final start = text.indexOf('<x:xmpmeta');
  if (start < 0) return null;
  const closing = '</x:xmpmeta>';
  final end = text.indexOf(closing, start);
  if (end < 0) return null;
  final block = text.substring(start, end + closing.length);
  try {
    return const Utf8Decoder().convert(latin1.encode(block));
  } on FormatException {
    return block;
  }
}

/// El texto de `<tag>...</tag>`, o del primer `<rdf:li>` si es un contenedor
/// `rdf:Alt`/`rdf:Seq`/`rdf:Bag` —lo que XMP usa para un título o una fecha
/// con idioma, aunque solo traiga uno—.
String? _xmpSingle(String block, String tag) {
  final container = RegExp(
    '<$tag>(.*?)</$tag>',
    dotAll: true,
  ).firstMatch(block);
  if (container == null) return null;
  final inner = container.group(1)!;

  final li = RegExp(
    '<rdf:li[^>]*>(.*?)</rdf:li>',
    dotAll: true,
  ).firstMatch(inner);
  final raw = li?.group(1) ?? (inner.contains('<') ? null : inner);
  if (raw == null) return null;
  final clean = _unescapeXml(raw.trim());
  return clean.isEmpty ? null : clean;
}

/// Cada `<rdf:li>` de `<tag>...</tag>` —una lista de autores, `dc:creator`—.
List<String> _xmpList(String block, String tag) {
  final container = RegExp(
    '<$tag>(.*?)</$tag>',
    dotAll: true,
  ).firstMatch(block);
  if (container == null) return const [];
  return [
    for (final li in RegExp(
      '<rdf:li[^>]*>(.*?)</rdf:li>',
      dotAll: true,
    ).allMatches(container.group(1)!))
      _unescapeXml(li.group(1)!.trim()),
  ].where((s) => s.isNotEmpty).toList();
}

/// Las entidades de XML: las cinco con nombre y las numéricas —`&#243;`,
/// `&#xF3;`—, que algunos generadores usan para lo que no es ASCII. `&amp;`
/// va última: `&amp;#243;` dice «&#243;» al pie de la letra, no «ó».
String _unescapeXml(String text) => text
    .replaceAllMapped(RegExp('&#(?:x([0-9A-Fa-f]{1,6})|([0-9]{1,7}));'), (m) {
      final hex = m[1];
      final code = hex != null ? int.parse(hex, radix: 16) : int.parse(m[2]!);
      return code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : m[0]!;
    })
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

// ---------------------------------------------------------------------------
// Diccionario Info
// ---------------------------------------------------------------------------

ExtractedMetadata _fromInfoDict(String text) =>
    _fromInfoBody(_infoDictBody(text));

ExtractedMetadata _fromInfoBody(String? body) {
  if (body == null) return const ExtractedMetadata();

  final title = _infoValue(body, 'Title');
  final author = _infoValue(body, 'Author');
  final dateText = _infoValue(body, 'CreationDate');
  final date = dateText == null ? null : _parsePdfDate(dateText);

  return ExtractedMetadata(
    title: title,
    publishedAt: date?.date,
    publicationPrecision: date?.precision,
    reference: ReferenceData(
      contributors: author == null
          ? const []
          : _contributorsFromRawAuthor(author),
    ),
  );
}

/// El cuerpo del objeto que nombra `/Info N 0 R` en el `trailer` —el último,
/// si el archivo se guardó más de una vez—, entre su `N 0 obj` y su
/// `endobj`. `null` si no se lo encuentra: puede estar comprimido dentro de
/// un `ObjStm`, donde esta búsqueda de texto no llega.
String? _infoDictBody(String text) {
  final objNum = _infoObjectNumber(text);
  return objNum == null ? null : _objectBody(text, objNum);
}

/// El número del objeto que nombra `/Info N 0 R` —el último, si el archivo
/// se guardó más de una vez—, o `null`.
int? _infoObjectNumber(String text) {
  final refs = RegExp(r'/Info\s+(\d+)\s+0\s+R').allMatches(text).toList();
  return refs.isEmpty ? null : int.parse(refs.last.group(1)!);
}

/// Lo que hay entre `N 0 obj` y su `endobj` en [text], o `null`.
String? _objectBody(String text, int objNum) {
  final objStart = RegExp(
    '(?:^|[\\r\\n])\\s*$objNum\\s+0\\s+obj',
  ).firstMatch(text);
  if (objStart == null) return null;

  final end = text.indexOf('endobj', objStart.end);
  if (end < 0) return null;
  return text.substring(objStart.end, end);
}

String? _infoValue(String body, String key) {
  final match = RegExp('/$key\\b').firstMatch(body);
  if (match == null) return null;
  return _pdfStringAt(body, match.end);
}

/// El valor de texto que sigue a una clave del diccionario, a partir de
/// donde empieza —`(...)`, con sus escapes, o `<...>` en hexadecimal—. No se
/// usa una única expresión regular porque un paréntesis sin escapar dentro
/// del texto —poco común, pero legal— abre un nivel, y cortar en el primer
/// `)` partiría el título a la mitad.
String? _pdfStringAt(String text, int start) {
  var i = start;
  while (i < text.length && RegExp(r'\s').hasMatch(text[i])) {
    i++;
  }
  if (i >= text.length) return null;

  if (text[i] == '(') {
    // Empieza en 1: el paréntesis que se acaba de leer ya abrió el primer
    // nivel, y no es parte del texto.
    var depth = 1;
    final body = StringBuffer();
    for (i++; i < text.length; i++) {
      final char = text[i];
      if (char == r'\' && i + 1 < text.length) {
        body
          ..write(char)
          ..write(text[i + 1]);
        i++;
        continue;
      }
      if (char == '(') depth++;
      if (char == ')') {
        depth--;
        if (depth == 0) break;
      }
      body.write(char);
    }
    return _decodeTextBytes(_decodeLiteralBody(body.toString()));
  }

  if (text[i] == '<') {
    final end = text.indexOf('>', i);
    if (end < 0) return null;
    return _decodeTextBytes(_decodeHexBody(text.substring(i + 1, end)));
  }

  return null;
}

/// El cuerpo de una cadena literal de PDF, ya sin sus paréntesis de afuera,
/// con sus escapes resueltos: `\(`, `\)`, `\\`, `\n`/`\r`/`\t` como espacio,
/// `\b`/`\f` descartados, un octal `\ddd`, y un `\` al final de renglón, que
/// no agrega nada —es la continuación de línea de la norma—.
Uint8List _decodeLiteralBody(String body) {
  final out = <int>[];
  for (var i = 0; i < body.length; i++) {
    final char = body[i];
    if (char != r'\') {
      out.add(body.codeUnitAt(i) & 0xFF);
      continue;
    }
    if (i + 1 >= body.length) break;
    final next = body[i + 1];
    switch (next) {
      case 'n' || 'r' || 't':
        out.add(0x20);
        i++;
      case 'b' || 'f':
        i++;
      case '(' || ')' || r'\':
        out.add(next.codeUnitAt(0));
        i++;
      case '\r':
        i++;
        if (i + 1 < body.length && body[i + 1] == '\n') i++;
      case '\n':
        i++;
      default:
        if (RegExp('[0-7]').hasMatch(next)) {
          final octal = StringBuffer(next);
          var j = i + 2;
          while (octal.length < 3 &&
              j < body.length &&
              RegExp('[0-7]').hasMatch(body[j])) {
            octal.write(body[j]);
            j++;
          }
          out.add(int.parse(octal.toString(), radix: 8) & 0xFF);
          i = j - 1;
        } else {
          out.add(next.codeUnitAt(0));
          i++;
        }
    }
  }
  return Uint8List.fromList(out);
}

Uint8List _decodeHexBody(String body) {
  final clean = body.replaceAll(RegExp(r'\s'), '');
  final padded = clean.length.isOdd ? '${clean}0' : clean;
  final out = <int>[];
  for (var i = 0; i + 1 < padded.length; i += 2) {
    final byte = int.tryParse(padded.substring(i, i + 2), radix: 16);
    if (byte == null) return Uint8List(0);
    out.add(byte);
  }
  return Uint8List.fromList(out);
}

/// Los bytes de una cadena de PDF como texto, como dice la norma (7.9.2.2):
///
/// - UTF-16BE si empiezan con su marca (`FE FF`) —lo que escribe casi todo lo
///   que no es ASCII puro—;
/// - UTF-8 si empiezan con la suya (`EF BB BF`), lo que permite PDF 2.0;
/// - y si no, PDFDocEncoding.
///
/// Con una excepción, que es lo que hace un lector de PDF de verdad: bytes
/// sin marca que forman UTF-8 válido —con alguna letra de más de un byte— se
/// leen como UTF-8. Hay generadores que lo escriben así, contra la norma, y
/// leídos como PDFDocEncoding daban «DeclaraciÃ³n» (F43, M7). Un título
/// escrito de verdad en PDFDocEncoding casi nunca es UTF-8 válido: la «ó»
/// sola (`F3`) seguida de una letra no lo es.
String _decodeTextBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    final text = String.fromCharCodes(units).trim();
    return text;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true).trim();
  }
  if (bytes.any((byte) => byte >= 0x80)) {
    try {
      return const Utf8Decoder().convert(bytes).trim();
    } on FormatException {
      // No es UTF-8: es PDFDocEncoding, como dice la norma.
    }
  }
  return decodePdfDocEncoding(bytes).trim();
}

/// [bytes] en PDFDocEncoding, la codificación de un byte de las cadenas de
/// texto de un PDF (norma, anexo D). Coincide con Latin-1 salvo en dos
/// tramos: del `0x18` al `0x1F`, los acentos sueltos (˘ ˇ ˆ ˙ ˝ ˛ ˚ ˜), y del
/// `0x80` al `0xA0`, las comillas tipográficas, las rayas, las ligaduras
/// «ﬁ» y «ﬂ», algunas letras de Europa central y el euro —donde Latin-1 tiene
/// controles—. Los lugares que la norma deja sin definir quedan con su mismo
/// código: un byte no se pierde aunque no tenga letra.
@visibleForTesting
String decodePdfDocEncoding(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.writeCharCode(switch (byte) {
      >= 0x18 && <= 0x1F => _pdfDocLow[byte - 0x18],
      >= 0x80 && <= 0xA0 => _pdfDocHigh[byte - 0x80],
      _ => byte,
    });
  }
  return buffer.toString();
}

// dart format off
/// Del `0x18` al `0x1F`.
const _pdfDocLow = [
  0x02D8, 0x02C7, 0x02C6, 0x02D9, 0x02DD, 0x02DB, 0x02DA, 0x02DC,
];

/// Del `0x80` al `0xA0`; el `0x9F` no está definido.
const _pdfDocHigh = [
  0x2022, 0x2020, 0x2021, 0x2026, 0x2014, 0x2013, 0x0192, 0x2044,
  0x2039, 0x203A, 0x2212, 0x2030, 0x201E, 0x201C, 0x201D, 0x2018,
  0x2019, 0x201A, 0x2122, 0xFB01, 0xFB02, 0x0141, 0x0152, 0x0160,
  0x0178, 0x017D, 0x0131, 0x0142, 0x0153, 0x0161, 0x017E, 0x009F,
  0x20AC,
];
// dart format on

/// `D:AAAAMMDDhhmmss...`, la fecha del diccionario `Info`. El huso al final
/// —`+02'00'`— no importa: la cita nunca llega a la hora.
({DateTime date, PublicationPrecision precision})? _parsePdfDate(String raw) {
  final match = RegExp(r'^D:(\d{4})(\d{2})?(\d{2})?').firstMatch(raw.trim());
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final monthText = match.group(2);
  if (monthText == null) {
    return (date: DateTime(year), precision: PublicationPrecision.year);
  }
  final month = int.parse(monthText);
  if (month < 1 || month > 12) return null;

  final dayText = match.group(3);
  if (dayText == null) {
    return (date: DateTime(year, month), precision: PublicationPrecision.month);
  }
  final day = int.parse(dayText);
  final date = DateTime(year, month, day);
  if (date.month != month) return null;
  return (date: date, precision: PublicationPrecision.day);
}

// ---------------------------------------------------------------------------
// Compartido
// ---------------------------------------------------------------------------

/// El primer DOI que aparece en todo el archivo, normalizado —el `Producer`
/// de muchos lectores lo deja también fuera de `Info` y de XMP, suelto en
/// alguna anotación—. `normalizeDoi` descarta cualquier cosa que no tenga
/// la forma de uno, así que buscarlo en el archivo entero no trae basura.
String? _firstDoi(String text) {
  final match = RegExp(r'10\.\d{4,9}/[^\s()<>"\\]+').firstMatch(text);
  return match == null ? null : normalizeDoi(match.group(0)!);
}

String? _pagesOf(String? first, String? last) {
  final f = first?.trim();
  final l = last?.trim();
  if (f == null || f.isEmpty) return null;
  if (l == null || l.isEmpty || l == f) return f;
  return '$f-$l';
}

/// Las personas de `/Author` o de `dc:creator`: si trae `;`, una por
/// segmento; si trae « and » o `&`, la lista al estilo BibTeX —que sabe leer
/// «Apellido, Nombre» de cada una—; si no, todo el texto como un único
/// nombre —lo más seguro cuando no hay separador: partir por una coma
/// suelta convertiría «García Márquez, Gabriel» en dos personas—.
List<Contributor> _contributorsFromRawAuthor(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];

  if (trimmed.contains(';')) {
    return [
      for (final part in trimmed.split(';'))
        if (parseName(part.trim()) case final parsed?)
          Contributor(name: parsed.name),
    ];
  }

  if (RegExp(r'\band\b|&', caseSensitive: false).hasMatch(trimmed)) {
    return [
      for (final name in parseNameList(trimmed).names)
        Contributor(name: name.name),
    ];
  }

  final single = parseName(trimmed);
  return single == null ? const [] : [Contributor(name: single.name)];
}
