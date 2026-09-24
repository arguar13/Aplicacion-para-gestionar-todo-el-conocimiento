/// Decodifica los acentos de LaTeX de un campo de BibTeX (F15, commit 13):
/// `\'e`, `\'{e}` y `{\'e}` se vuelven «é», `\c{c}` se vuelve «ç», `\ss` se
/// vuelve «ß», y así con el resto de la tabla de abajo.
///
/// BibTeX no define un juego de caracteres: un archivo viejo, o uno armado a
/// mano, escribe los acentos así porque el TeX de los 80 no tenía otra forma.
/// Uno moderno (BibLaTeX, Zotero, JabRef) ya exporta UTF-8 directo, que pasa
/// sin tocar —esta función no rompe nada que ya sea una letra acentuada—.
///
/// También quita las llaves que sobreviven a los reemplazos: en BibTeX
/// protegen mayúsculas («Fue en {P}arís») o marcan una institución, y no
/// significan nada al mostrarse. Un `~` suelto (el espacio irrompible de
/// LaTeX, «Fig.~1») se vuelve un espacio normal.
String decodeLatexAccents(String raw) {
  var text = raw;
  // `\i`/`\j` —la i/j «sin punto»— van primero: son el paso previo a
  // acentuar («\'\i» es «í», porque un acento sobre una «i» con su punto
  // quedaría mal), y sin acento encima son, ya, la letra normal.
  text = text.replaceAllMapped(_dotlessLetter, (match) => match.group(1)!);
  // Van primero, y por texto exacto (con el espacio que a veces los separa
  // de la letra siguiente: TeX se lo come): para no confundirse con
  // [_accentCommand] —una `s` de `\ss` no es una letra a acentuar—.
  text = text.replaceAllMapped(
    _literalCommand,
    (match) => _literalCommands[match.group(1)!]!,
  );
  text = text.replaceAllMapped(_accentCommand, (match) {
    final mark = match.group(1)!;
    final letter = match.group(2)!;
    return _accentTables[mark]?[letter] ?? letter;
  });
  text = text.replaceAllMapped(_escapedSpecial, (match) => match.group(1)!);
  return text.replaceAll('~', ' ').replaceAll('{', '').replaceAll('}', '');
}

/// `\i`, `\j`, sin otra letra pegada atrás (para no cortar un comando más
/// largo que nadie definió acá).
final _dotlessLetter = RegExp(r'\\([ij])(?![A-Za-z])');

/// `\<marca><letra>`, con la letra sola o entre llaves: `\'e`, `\'{e}`. La
/// marca de agudo y la de diéresis se escriben con `\u0027`/`\u0022` —el
/// código de `'` y de `"`— porque ninguna comilla de Dart puede contener a
/// la otra dentro de la misma cadena cruda.
final _accentCommand = RegExp(r'\\([`\u0027^~=.vkcH\u0022])\{?([A-Za-z])\}?');

/// `\&`, `\%`, `\_`, `\#`, `\$`: caracteres que LaTeX escapa por ser
/// especiales en su propia sintaxis, sin nada especial en un campo de texto.
final _escapedSpecial = RegExp(r'\\([&%_#$])');

/// Comandos que no toman una letra como parámetro. El espacio opcional al
/// final es el que TeX se come después de un comando de solo letras —«\ss
/// e» se lee «ße», no «ß e»—; los de dos letras van antes que su prefijo de
/// una (`OE` antes que `O`), o la alternativa más corta ganaría siempre.
final _literalCommand = RegExp(r'\\(ss|AE|ae|OE|oe|AA|aa|O|o|L|l) ?');

const _literalCommands = {
  'ss': 'ß',
  'AE': 'Æ',
  'ae': 'æ',
  'OE': 'Œ',
  'oe': 'œ',
  'AA': 'Å',
  'aa': 'å',
  'O': 'Ø',
  'o': 'ø',
  'L': 'Ł',
  'l': 'ł',
};

const _accentTables = {
  // Agudo: \'e -> é
  "'": {
    'a': 'á',
    'e': 'é',
    'i': 'í',
    'o': 'ó',
    'u': 'ú',
    'y': 'ý',
    'n': 'ń',
    'c': 'ć',
    's': 'ś',
    'z': 'ź',
    'A': 'Á',
    'E': 'É',
    'I': 'Í',
    'O': 'Ó',
    'U': 'Ú',
    'Y': 'Ý',
    'N': 'Ń',
    'C': 'Ć',
    'S': 'Ś',
    'Z': 'Ź',
  },
  // Grave: \`e -> è
  '`': {
    'a': 'à',
    'e': 'è',
    'i': 'ì',
    'o': 'ò',
    'u': 'ù',
    'A': 'À',
    'E': 'È',
    'I': 'Ì',
    'O': 'Ò',
    'U': 'Ù',
  },
  // Diéresis: \"o -> ö (código ": ver [_accentCommand])
  '"': {
    'a': 'ä',
    'e': 'ë',
    'i': 'ï',
    'o': 'ö',
    'u': 'ü',
    'y': 'ÿ',
    'A': 'Ä',
    'E': 'Ë',
    'I': 'Ï',
    'O': 'Ö',
    'U': 'Ü',
  },
  // Circunflejo: \^a -> â
  '^': {
    'a': 'â',
    'e': 'ê',
    'i': 'î',
    'o': 'ô',
    'u': 'û',
    'A': 'Â',
    'E': 'Ê',
    'I': 'Î',
    'O': 'Ô',
    'U': 'Û',
  },
  // Tilde: \~n -> ñ
  '~': {'a': 'ã', 'n': 'ñ', 'o': 'õ', 'A': 'Ã', 'N': 'Ñ', 'O': 'Õ'},
  // Cedilla: \c{c} -> ç
  'c': {'c': 'ç', 'C': 'Ç', 's': 'ş', 'S': 'Ş'},
  // Macrón: \=a -> ā
  '=': {
    'a': 'ā',
    'e': 'ē',
    'i': 'ī',
    'o': 'ō',
    'u': 'ū',
    'A': 'Ā',
    'E': 'Ē',
    'I': 'Ī',
    'O': 'Ō',
    'U': 'Ū',
  },
  // Háček: \v{c} -> č
  'v': {
    'c': 'č',
    's': 'š',
    'z': 'ž',
    'e': 'ě',
    'r': 'ř',
    'C': 'Č',
    'S': 'Š',
    'Z': 'Ž',
    'E': 'Ě',
    'R': 'Ř',
  },
  // Ogonek: \k{a} -> ą
  'k': {'a': 'ą', 'e': 'ę', 'A': 'Ą', 'E': 'Ę'},
  // Punto arriba: \.z -> ż
  '.': {'z': 'ż', 'Z': 'Ż'},
  // Doble agudo húngaro: \H{o} -> ő
  'H': {'o': 'ő', 'u': 'ű', 'O': 'Ő', 'U': 'Ű'},
};
