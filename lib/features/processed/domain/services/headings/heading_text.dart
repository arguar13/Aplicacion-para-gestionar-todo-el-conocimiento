/// Lo que comparten los lectores de títulos del Índice (F46, paso 1): el
/// título tal como se lee, la forma de compararlo y los niveles corridos.
library;

/// Un título encontrado en un texto, antes de correr sus niveles: `level` es
/// el que trae —el de `###`, el de «1.2.3»—, y `[start, end)` su tramo en el
/// texto.
typedef RawHeading = ({int level, String title, int start, int end});

/// Los niveles de [levels] —en el orden del documento— **corridos**: el
/// primero es el 1 y ninguno salta uno respecto del que lo contiene.
///
/// Cada título cuelga del último anterior que tenga un nivel menor que el
/// suyo, y queda un nivel más abajo que él; sin ninguno, va en el nivel 1.
/// Así:
///
/// - `#` seguido de `###` queda en 1 y 2: el salto no deja un nivel vacío;
/// - un documento que empieza en `###` empieza en 1;
/// - `##`, `####`, `###` queda en 1, 2, 2: los dos cuelgan del `##`.
///
/// Es lo que necesita un árbol: con los niveles tal cual, un `###` debajo de
/// un `#` sería un nieto sin padre. Lineal: cada nivel entra y sale de la
/// pila una sola vez.
List<int> runningLevels(Iterable<int> levels) {
  final open = <int>[];
  final running = <int>[];
  for (final level in levels) {
    while (open.isNotEmpty && open.last >= level) {
      open.removeLast();
    }
    running.add(open.length + 1);
    open.add(level);
  }
  return running;
}

/// [raw], un título escrito en Markdown, como se lee: sin las marcas.
///
/// - un enlace es su texto, y una imagen su texto alternativo;
/// - sin `*`, `**`, `~~`, ni los `_` que marcan énfasis —los de adentro de una
///   palabra, como en `var_uno`, quedan—, ni las comillas invertidas del
///   código;
/// - sin etiquetas de HTML —un `<br>` es un espacio— ni llamadas a notas al
///   pie (`[^1]`);
/// - los caracteres escapados (`\#`, `\*`) y las entidades (`&amp;`) son lo
///   que escriben;
/// - los espacios y renglones, uno solo.
String plainHeadingText(String raw) {
  // Lo escapado se aparta antes de sacar las marcas —un `\*` es un asterisco
  // de verdad— y vuelve al final.
  var text = raw.replaceAllMapped(
    _escaped,
    (match) => String.fromCharCode(_escapeBase + match[1]!.codeUnitAt(0)),
  );
  text = text
      .replaceAllMapped(_image, (match) => match[1]!)
      .replaceAllMapped(_link, (match) => match[1]!)
      .replaceAllMapped(_referenceLink, (match) => match[1]!)
      .replaceAll(_footnoteCall, '')
      .replaceAllMapped(_codeSpan, (match) => match[2]!)
      .replaceAll(_lineBreakTag, ' ')
      .replaceAll(_htmlTag, '')
      .replaceAll(_asterisks, '')
      .replaceAll(_strike, '')
      .replaceAll(_emphasisUnderscores, '');
  text = text.replaceAllMapped(_entity, (match) => _decodeEntity(match[0]!));
  text = String.fromCharCodes(
    text.runes.map(
      (rune) => rune >= _escapeBase && rune < _escapeBase + 0x80
          ? rune - _escapeBase
          : rune,
    ),
  );
  return text.replaceAll(_whitespace, ' ').trim();
}

/// Si [title] tiene algo que leer: al menos una letra o un número. Un título
/// que es solo marcas o puntuación —`# ***`, `## · · ·`— es ruido.
bool hasReadableText(String title) => _readable.hasMatch(title);

/// La forma de comparar dos títulos: en minúsculas, sin acentos —escritos
/// juntos o como letra y marca aparte, como los deja a veces un PDF— y sin
/// puntuación, con las palabras separadas por un espacio.
///
/// «Capítulo 1: El origen», «CAPÍTULO 1 — EL ORIGEN» y «Capitulo 1⏎El
/// origen» dan lo mismo: `capitulo 1 el origen`.
String headingKey(String text) {
  final folded = StringBuffer();
  for (final unit in text.toLowerCase().codeUnits) {
    // Las marcas que acompañan a una letra (U+0300 a U+036F): la «a» de una
    // «á» escrita en dos.
    if (unit >= 0x0300 && unit <= 0x036F) continue;
    folded.writeCharCode(_folding[unit] ?? unit);
  }
  return _keyWord
      .allMatches(folded.toString())
      .map((match) => match[0])
      .join(' ');
}

/// Dónde empiezan los caracteres escapados apartados: un tramo de uso
/// privado de Unicode, que ningún texto trae.
const _escapeBase = 0xE000;

final _escaped = RegExp(r'\\([!-/:-@\[-`{-~])');
final _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final _referenceLink = RegExp(r'\[([^\]]+)\]\[[^\]]*\]');
final _footnoteCall = RegExp(r'\[\^[^\]]+\]');
final _codeSpan = RegExp(r'(`+)([^`]*)\1');
final _lineBreakTag = RegExp(r'<br\s*/?>', caseSensitive: false);
final _htmlTag = RegExp('</?[A-Za-z][^>]*>');
final _asterisks = RegExp(r'\*+');
final _strike = RegExp('~~');
final _emphasisUnderscores = RegExp(
  r'(?<![\p{L}\p{N}])_+|_+(?![\p{L}\p{N}])',
  unicode: true,
);
final _entity = RegExp(r'&(#\d{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,8});');
final _whitespace = RegExp(r'\s+');
final _readable = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _keyWord = RegExp(r'[\p{L}\p{N}]+', unicode: true);

const _namedEntities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

String _decodeEntity(String entity) {
  final body = entity.substring(1, entity.length - 1);
  if (body.startsWith('#')) {
    final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
    final code = int.tryParse(
      hex ? body.substring(2) : body.substring(1),
      radix: hex ? 16 : 10,
    );
    if (code == null || code == 0 || code > 0x10FFFF) return entity;
    return String.fromCharCode(code);
  }
  return _namedEntities[body] ?? entity;
}

/// Las letras con acento y sus parientes, a su letra sola. La ñ y la ç
/// también, como el índice de la búsqueda (`remove_diacritics 2`).
final Map<int, int> _folding = () {
  const groups = <String, String>{
    'a': 'áàâäãåā',
    'e': 'éèêëēė',
    'i': 'íìîïī',
    'o': 'óòôöõøō',
    'u': 'úùûüū',
    'y': 'ýÿ',
    'n': 'ñ',
    'c': 'ç',
  };
  return {
    for (final entry in groups.entries)
      for (final unit in entry.value.codeUnits) unit: entry.key.codeUnitAt(0),
  };
}();
