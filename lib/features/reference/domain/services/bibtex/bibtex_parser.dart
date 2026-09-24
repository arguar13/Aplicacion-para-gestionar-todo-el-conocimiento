import 'package:sinapsis/core/domain/entities/bibtex_entry.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/services/bibliographic_identifiers.dart';
import 'package:sinapsis/core/domain/services/person_name_parser.dart';
import 'package:sinapsis/features/reference/domain/services/bibtex/latex_accents.dart';

/// Una entrada de un `.bib` que el analizador no supo convertir: un tipo que
/// no está entre los nueve de la app —una patente, un programa— o cualquier
/// tipo estándar de BibTeX que la app no define. Se informa y se salta, en
/// vez de adivinar (D4).
class BibtexSkippedEntry {
  const BibtexSkippedEntry({
    required this.key,
    required this.type,
    required this.reason,
  });

  final String key;
  final String type;
  final String reason;
}

/// Lo que salió de leer un archivo `.bib` entero: las entradas que se
/// entendieron y las que no.
class BibtexParseResult {
  const BibtexParseResult({required this.entries, required this.skipped});

  final List<BibtexEntry> entries;
  final List<BibtexSkippedEntry> skipped;
}

/// Lee un archivo `.bib` entero (F15, commit 13).
///
/// A diferencia de un analizador ingenuo por líneas o expresiones regulares
/// simples —que se rompe con un título que trae una coma entre llaves, o con
/// una entrada que ocupa varias líneas—, este sigue la gramática real de
/// BibTeX: cuenta el anidamiento de `{}` para encontrar dónde termina cada
/// entrada y cada valor, distingue una llave de una comilla como delimitador,
/// resuelve las macros de `@string` (incluidas las que se referencian entre
/// sí) y la concatenación con `#`, y decodifica los acentos de LaTeX —ver
/// [decodeLatexAccents]—.
///
/// Lo que hay fuera de una entrada (`@tipo{...}`) es comentario y se ignora,
/// como en BibTeX de verdad. `@comment` y `@preamble` también se ignoran.
BibtexParseResult parseBibtex(String source) {
  final macros = <String, String>{};
  final entries = <BibtexEntry>[];
  final skipped = <BibtexSkippedEntry>[];

  var pos = 0;
  while (pos < source.length) {
    final at = source.indexOf('@', pos);
    if (at < 0) break;

    var i = at + 1;
    final typeStart = i;
    while (i < source.length && _isIdentChar(source[i])) {
      i++;
    }
    final type = source.substring(typeStart, i).toLowerCase();
    i = _skipWs(source, i);

    if (type.isEmpty || i >= source.length || source[i] != '{') {
      pos = at + 1;
      continue;
    }

    final bodyStart = i + 1;
    final bodyEnd = _findClosingBrace(source, bodyStart);
    final body = source.substring(bodyStart, bodyEnd);
    pos = bodyEnd + 1;

    if (type == 'comment' || type == 'preamble') continue;
    if (type == 'string') {
      _defineMacros(body, macros);
      continue;
    }

    final parts = _splitTopLevel(body, ',');
    final key = parts.first.trim();
    final resolvedRaw = <String, String>{};
    for (final part in parts.skip(1)) {
      if (part.trim().isEmpty) continue;
      final eq = _splitTopLevel(part, '=');
      if (eq.length < 2) continue;
      final name = eq.first.trim().toLowerCase();
      final valueText = eq.skip(1).join('=').trim();
      if (name.isEmpty || valueText.isEmpty) continue;
      resolvedRaw[name] = _resolveValue(valueText, macros);
    }

    final entry = _toEntry(type: type, key: key, resolvedRaw: resolvedRaw);
    if (entry == null) {
      skipped.add(
        BibtexSkippedEntry(
          key: key,
          type: type,
          reason: 'tipo no reconocido: @$type',
        ),
      );
    } else {
      entries.add(entry);
    }
  }

  return BibtexParseResult(entries: entries, skipped: skipped);
}

// ---------------------------------------------------------------------------
// De campos resueltos a BibtexEntry.
// ---------------------------------------------------------------------------

/// Los tipos estándar de BibTeX que la app entiende, y a cuál de los nueve
/// tipos propios corresponden por defecto (D4). `@inproceedings` entra como
/// artículo con el contenedor del congreso, tal como pide el plan. Lo que no
/// está acá —una patente (`@patent`), un programa (`@software`)— se salta.
const _typeFromBibtex = {
  'article': ReferenceType.article,
  'book': ReferenceType.book,
  'booklet': ReferenceType.book,
  'inbook': ReferenceType.chapter,
  'incollection': ReferenceType.chapter,
  'inproceedings': ReferenceType.article,
  'conference': ReferenceType.article,
  'proceedings': ReferenceType.book,
  'manual': ReferenceType.other,
  'mastersthesis': ReferenceType.thesis,
  'phdthesis': ReferenceType.thesis,
  'misc': ReferenceType.other,
  'techreport': ReferenceType.other,
  'unpublished': ReferenceType.other,
  'online': ReferenceType.website,
  'electronic': ReferenceType.website,
};

BibtexEntry? _toEntry({
  required String type,
  required String key,
  required Map<String, String> resolvedRaw,
}) {
  final mapped = _typeFromBibtex[type];
  if (mapped == null) return null;

  String? decoded(String name) {
    final raw = resolvedRaw[name];
    if (raw == null) return null;
    final value = decodeLatexAccents(raw).trim();
    return value.isEmpty ? null : value;
  }

  // `sinapsis-type`/`sinapsis-undated` son campos propios, ignorados por
  // cualquier otro lector de BibTeX, que solo existen para que la IDA Y
  // VUELTA por este mismo exportador no pierda un tipo sin equivalente
  // nativo (documental, fuente primaria, publicación en red) ni la
  // diferencia entre «sin tipo» y «otro» —ver [_toEntry]/`sinapsis-type` en
  // el exportador—.
  final typeHint = decoded('sinapsis-type');
  final refType = typeHint == null
      ? mapped
      : (typeHint == 'none' ? null : (_typeFromName(typeHint) ?? mapped));

  final contributors = <Contributor>[];
  final authorRaw = resolvedRaw['author'];
  if (authorRaw != null && authorRaw.trim().isNotEmpty) {
    for (final parsed in parseNameList(
      authorRaw,
      decode: decodeLatexAccents,
    ).names) {
      contributors.add(Contributor(name: parsed.name));
    }
  }
  final editorRaw = resolvedRaw['editor'];
  if (editorRaw != null && editorRaw.trim().isNotEmpty) {
    for (final parsed in parseNameList(
      editorRaw,
      decode: decodeLatexAccents,
    ).names) {
      contributors.add(
        Contributor(name: parsed.name, role: ContributorRole.editor),
      );
    }
  }

  final (publishedAt, precision) = _dateFrom(decoded);
  final pages = decoded('pages')?.replaceAll(RegExp('-{2,}'), '-');
  final isbn = decoded('isbn');
  final issn = decoded('issn');
  final doi = decoded('doi');
  final url = decoded('url') ?? _urlLike(decoded('howpublished'));

  return BibtexEntry(
    title: decoded('title'),
    url: url,
    publishedAt: publishedAt,
    publicationPrecision: precision,
    reference: ReferenceData(
      type: refType,
      contributors: contributors,
      containerTitle: decoded('journal') ?? decoded('booktitle'),
      publisher:
          decoded('publisher') ?? decoded('school') ?? decoded('institution'),
      publisherPlace: decoded('address'),
      edition: decoded('edition'),
      volume: decoded('volume'),
      issue: decoded('number'),
      pages: pages,
      isbn: isbn == null ? null : normalizeIsbn(isbn),
      issn: issn == null ? null : normalizeIssn(issn),
      doi: doi == null ? null : normalizeDoi(doi),
      accessedAt: _parseIsoDate(decoded('urldate')),
      citationKey: key.isEmpty ? null : key,
    ),
  );
}

ReferenceType? _typeFromName(String name) {
  for (final type in ReferenceType.values) {
    if (type.name == name) return type;
  }
  return null;
}

(DateTime?, PublicationPrecision?) _dateFrom(String? Function(String) decoded) {
  if (decoded('sinapsis-undated') != null) {
    return (null, PublicationPrecision.undated);
  }

  final dateField = decoded('date');
  if (dateField != null) {
    final day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateField);
    if (day != null) {
      return (
        DateTime(
          int.parse(day.group(1)!),
          int.parse(day.group(2)!),
          int.parse(day.group(3)!),
        ),
        PublicationPrecision.day,
      );
    }
    final month = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(dateField);
    if (month != null) {
      return (
        DateTime(int.parse(month.group(1)!), int.parse(month.group(2)!)),
        PublicationPrecision.month,
      );
    }
  }

  final yearField = decoded('year');
  final yearMatch = yearField == null
      ? null
      : RegExp(r'\d{4}').firstMatch(yearField);
  if (yearMatch == null) return (null, null);
  final year = int.parse(yearMatch.group(0)!);

  final monthNumber = _monthNumber(decoded('month'));
  if (monthNumber != null) {
    return (DateTime(year, monthNumber), PublicationPrecision.month);
  }
  return (DateTime(year), PublicationPrecision.year);
}

const _monthNames = {
  'jan': 1,
  'january': 1,
  'enero': 1,
  'feb': 2,
  'february': 2,
  'febrero': 2,
  'mar': 3,
  'march': 3,
  'marzo': 3,
  'apr': 4,
  'april': 4,
  'abril': 4,
  'may': 5,
  'mayo': 5,
  'jun': 6,
  'june': 6,
  'junio': 6,
  'jul': 7,
  'july': 7,
  'julio': 7,
  'aug': 8,
  'august': 8,
  'agosto': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'septiembre': 9,
  'oct': 10,
  'october': 10,
  'octubre': 10,
  'nov': 11,
  'november': 11,
  'noviembre': 11,
  'dec': 12,
  'december': 12,
  'diciembre': 12,
};

int? _monthNumber(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  final asNumber = int.tryParse(trimmed);
  if (asNumber != null && asNumber >= 1 && asNumber <= 12) return asNumber;
  return _monthNames[trimmed];
}

String? _urlLike(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  return RegExp('^https?://').hasMatch(trimmed) ? trimmed : null;
}

DateTime? _parseIsoDate(String? text) {
  if (text == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

// ---------------------------------------------------------------------------
// Macros (`@string`) y resolución de valores.
// ---------------------------------------------------------------------------

void _defineMacros(String body, Map<String, String> macros) {
  for (final part in _splitTopLevel(body, ',')) {
    if (part.trim().isEmpty) continue;
    final eq = _splitTopLevel(part, '=');
    if (eq.length < 2) continue;
    final name = eq.first.trim().toLowerCase();
    final valueText = eq.skip(1).join('=').trim();
    if (name.isEmpty) continue;
    macros[name] = _resolveValue(valueText, macros);
  }
}

/// Un valor de campo, con sus partes unidas por `#` resueltas: cada parte es
/// un grupo `{…}`, una cadena `"…"` o una macro (una palabra ya definida con
/// `@string`, o un número). Las llaves internas de cada parte se conservan
/// —hacen falta para leer un nombre entre llaves como una institución— y se
/// decodifican recién donde el texto se usa, no acá.
String _resolveValue(String valueExpr, Map<String, String> macros) {
  final buffer = StringBuffer();
  for (final rawToken in _splitTopLevel(valueExpr, '#')) {
    final token = rawToken.trim();
    if (token.isEmpty) continue;
    buffer.write(_resolveToken(token, macros));
  }
  return buffer.toString();
}

String _resolveToken(String token, Map<String, String> macros) {
  if (token.length >= 2 && token.startsWith('{') && token.endsWith('}')) {
    return token.substring(1, token.length - 1);
  }
  if (token.length >= 2 && token.startsWith('"') && token.endsWith('"')) {
    return token.substring(1, token.length - 1);
  }
  if (RegExp(r'^-?\d+$').hasMatch(token)) return token;
  return macros[token.toLowerCase()] ?? token;
}

// ---------------------------------------------------------------------------
// El escáner: nada de expresiones regulares sobre el archivo entero —cuenta
// llaves y comillas de verdad, como pide un analizador estricto.
// ---------------------------------------------------------------------------

final _identChar = RegExp(r'[A-Za-z0-9_:\-+.]');

bool _isIdentChar(String ch) => _identChar.hasMatch(ch);

bool _isBibWhitespace(String ch) =>
    ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

int _skipWs(String s, int i) {
  var j = i;
  while (j < s.length && _isBibWhitespace(s[j])) {
    j++;
  }
  return j;
}

/// [start] apunta justo después de la `{` que abre la entrada: el índice de
/// la `}` que la cierra, contando el anidamiento. Una entrada sin cerrar
/// llega hasta el final del archivo en vez de romper todo el análisis.
int _findClosingBrace(String s, int start) {
  var depth = 1;
  var i = start;
  while (i < s.length) {
    final ch = s[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return s.length;
}

/// Parte [s] en [sep], sin cortar lo que está dentro de `{}` o de `"…"` —una
/// coma dentro de un título entre llaves no separa nada—.
List<String> _splitTopLevel(String s, String sep) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  var inQuotes = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '{') depth++;
    if (ch == '}' && depth > 0) depth--;
    if (ch == '"' && depth == 0) inQuotes = !inQuotes;
    if (ch == sep && depth == 0 && !inQuotes) {
      parts.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  parts.add(buffer.toString());
  return parts;
}
