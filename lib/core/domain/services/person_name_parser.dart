import 'package:sinapsis/core/domain/entities/person_name.dart';

/// Un nombre leído de un texto, y si hubo que deducir cuál es el apellido.
class ParsedName {
  const ParsedName(this.name, {required this.orderInferred});

  final PersonName name;

  /// `true` si el texto no decía cuál era el apellido —«Gabriel García
  /// Márquez», sin coma ni llaves— y se tomó la última palabra, que es lo que
  /// hace BibTeX y acierta con «Thomas Piketty» y falla con «García Márquez».
  /// Quien importa lo cuenta para avisar: con una coma («García Márquez,
  /// Gabriel») no hay nada que deducir.
  final bool orderInferred;
}

/// Una lista de nombres leída de un texto.
class ParsedNameList {
  const ParsedNameList(this.names, {this.hasOthers = false});

  final List<ParsedName> names;

  /// Si la lista terminaba en «and others» / «et al.»: había más autores que
  /// los que se nombraron.
  final bool hasOthers;
}

/// Lee una lista de nombres como la escribe BibTeX: separados por « and », con
/// `Apellido, Nombre` o con `Nombre Apellido`.
///
/// Las llaves protegen: `{Barnes and Noble}` es un nombre y no dos, y
/// `{{Organización Mundial de la Salud}}` es una institución. [decode] limpia
/// cada parte ya separada —el importador de BibTeX le pasa el que convierte
/// los acentos de LaTeX—; sin él, solo se quitan las llaves.
ParsedNameList parseNameList(String raw, {String Function(String)? decode}) {
  final tokens = _tokens(raw);
  final groups = <List<String>>[[]];
  for (final token in tokens) {
    if (token.toLowerCase() == 'and') {
      groups.add([]);
    } else {
      groups.last.add(token);
    }
  }

  var hasOthers = false;
  final names = <ParsedName>[];
  for (var i = 0; i < groups.length; i++) {
    final text = groups[i].join(' ');
    if (text.isEmpty) continue;
    if (i == groups.length - 1 && text.toLowerCase() == 'others') {
      hasOthers = true;
      continue;
    }
    final parsed = parseName(text, decode: decode);
    if (parsed != null) names.add(parsed);
  }
  return ParsedNameList(names, hasOthers: hasOthers);
}

/// Lee UN nombre con las tres formas de BibTeX:
///
/// - `Nombre von Apellido` —sin coma—: el apellido es la última palabra, con
///   la partícula en minúscula que la precede;
/// - `von Apellido, Nombre`: todo lo que precede a la coma es el apellido;
/// - `von Apellido, Jr., Nombre` o `Apellido, Nombre, Jr.`: con sufijo.
///
/// Un nombre todo entre llaves es una institución. Devuelve `null` si no hay
/// nada que leer. No adivina más de lo que BibTeX adivina: ver
/// [ParsedName.orderInferred].
ParsedName? parseName(String raw, {String Function(String)? decode}) {
  final finish = decode ?? _stripBraces;
  String clean(String text) => _collapse(finish(text));

  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final wholeBraced = _wholeBraced(trimmed);
  if (wholeBraced != null) {
    final name = clean(wholeBraced);
    if (name.isEmpty) return null;
    return ParsedName(PersonName.institution(name), orderInferred: false);
  }

  final parts = [for (final part in _splitTopLevel(trimmed, ',')) part.trim()];

  if (parts.length == 1) return _parseWithoutComma(parts[0], clean);
  if (parts.length == 2) {
    final family = clean(parts[0]);
    if (family.isEmpty) return null;
    return ParsedName(
      PersonName(family: family, given: clean(parts[1])),
      orderInferred: false,
    );
  }

  // Tres partes o más: `Apellido, Sufijo, Nombre` (BibTeX) o
  // `Apellido, Nombre, Sufijo` (lo que escribe la mayoría de la gente).
  final family = clean(parts[0]);
  if (family.isEmpty) return null;
  final middle = clean(parts[1]);
  final last = clean(parts.skip(2).join(' '));
  final suffixLast = _isSuffix(last);
  return ParsedName(
    PersonName(
      family: family,
      given: suffixLast && !_isSuffix(middle) ? middle : last,
      suffix: suffixLast && !_isSuffix(middle) ? last : middle,
    ),
    orderInferred: false,
  );
}

/// `Nombre von Apellido`: la forma sin coma.
ParsedName? _parseWithoutComma(String text, String Function(String) clean) {
  final tokens = _tokens(text);
  if (tokens.isEmpty) return null;
  if (tokens.length == 1) {
    final family = clean(tokens.single);
    if (family.isEmpty) return null;
    return ParsedName(PersonName(family: family), orderInferred: false);
  }

  var suffix = '';
  if (tokens.length > 2 && _isSuffix(tokens.last)) {
    suffix = clean(tokens.removeLast());
  }

  final last = tokens.last;
  final rest = tokens.sublist(0, tokens.length - 1);

  // El apellido empieza en la primera palabra en minúscula —la partícula— y
  // llega hasta el final: «Miguel de Cervantes Saavedra» → «de Cervantes
  // Saavedra». Sin partícula, es la última palabra.
  final firstLower = rest.indexWhere(_startsLowercase);
  final given = firstLower < 0 ? rest : rest.sublist(0, firstLower);
  final familyTokens = firstLower < 0
      ? [last]
      : [...rest.sublist(firstLower), last];

  final family = clean(familyTokens.join(' '));
  if (family.isEmpty) return null;
  return ParsedName(
    PersonName(family: family, given: clean(given.join(' ')), suffix: suffix),
    orderInferred: true,
  );
}

/// Si [token] es un sufijo de nombre: «Jr.», «Sr.», «II», «III», «IV».
bool _isSuffix(String token) {
  final normalized = token.trim().toLowerCase().replaceAll('.', '');
  return const {'jr', 'sr', 'ii', 'iii', 'iv'}.contains(normalized);
}

/// Si la primera letra de [token] es minúscula, a la manera de BibTeX: las
/// llaves protegen —`{van}` no cuenta— y `{\'e}` se lee como la letra `e`.
bool _startsLowercase(String token) {
  if (token.startsWith('{') && !token.startsWith(r'{\')) return false;
  for (final rune in token.runes) {
    final char = String.fromCharCode(rune);
    if (char.toLowerCase() == char.toUpperCase()) continue;
    return char == char.toLowerCase();
  }
  return false;
}

/// Si TODO [text] es un solo grupo entre llaves, su contenido; si no, `null`.
String? _wholeBraced(String text) {
  if (!text.startsWith('{') || !text.endsWith('}')) return null;
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    // Se cerró el grupo de la primera llave antes del final: hay más afuera.
    if (depth == 0 && i < text.length - 1) return null;
  }
  return depth == 0 ? text.substring(1, text.length - 1) : null;
}

/// Parte [text] en las palabras separadas por espacios que no están dentro de
/// llaves.
List<String> _tokens(String text) {
  final tokens = <String>[];
  final current = StringBuffer();
  var depth = 0;
  for (final char in text.split('')) {
    if (char == '{') depth++;
    if (char == '}' && depth > 0) depth--;
    if (depth == 0 && RegExp(r'\s').hasMatch(char)) {
      if (current.isNotEmpty) {
        tokens.add(current.toString());
        current.clear();
      }
    } else {
      current.write(char);
    }
  }
  if (current.isNotEmpty) tokens.add(current.toString());
  return tokens;
}

/// Parte [text] en [separator], sin cortar lo que está dentro de llaves.
List<String> _splitTopLevel(String text, String separator) {
  final parts = <String>[];
  final current = StringBuffer();
  var depth = 0;
  for (final char in text.split('')) {
    if (char == '{') depth++;
    if (char == '}' && depth > 0) depth--;
    if (depth == 0 && char == separator) {
      parts.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  parts.add(current.toString());
  return parts;
}

String _stripBraces(String text) =>
    text.replaceAll('{', '').replaceAll('}', '');

String _collapse(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');
