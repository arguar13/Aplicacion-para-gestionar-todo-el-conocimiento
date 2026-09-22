import 'dart:convert';
import 'dart:typed_data';

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

String? _xmpBlock(String text) {
  final start = text.indexOf('<x:xmpmeta');
  if (start < 0) return null;
  const closing = '</x:xmpmeta>';
  final end = text.indexOf(closing, start);
  if (end < 0) return null;
  return text.substring(start, end + closing.length);
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

String _unescapeXml(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

// ---------------------------------------------------------------------------
// Diccionario Info
// ---------------------------------------------------------------------------

ExtractedMetadata _fromInfoDict(String text) {
  final body = _infoDictBody(text);
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
  final refs = RegExp(r'/Info\s+(\d+)\s+0\s+R').allMatches(text).toList();
  if (refs.isEmpty) return null;
  final objNum = refs.last.group(1)!;

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

/// Los bytes de una cadena de PDF como texto: UTF-16BE si empiezan con su
/// marca (`\xFE\xFF`) —lo que escribe casi todo lo que no es ASCII puro—, o
/// PDFDocEncoding, que en el rango imprimible coincide con Latin-1: lo
/// bastante para un nombre o un título en español.
String _decodeTextBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    final text = String.fromCharCodes(units).trim();
    return text;
  }
  final text = latin1.decode(bytes, allowInvalid: true).trim();
  return text;
}

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
