import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/util/word_folding.dart';

/// Una oración del texto de un documento (F36): el rango `[start, end)` en
/// el texto **guardado** —el mismo en que se guardan los subrayados—, sin los
/// espacios de los bordes ni las marcas de comienzo de renglón —un `#`, una
/// viñeta—.
///
/// Es la unidad de lo que se resalta: la IA elige oraciones por número, y el
/// número es su lugar en la lista que arma [splitStudySentences]. Así lo
/// resaltado es siempre una oración del autor, tal cual está en el texto.
@immutable
class StudySentence {
  const StudySentence(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  /// Si [offset] cae dentro de la oración.
  bool contains(int offset) => offset >= start && offset < end;

  @override
  bool operator ==(Object other) =>
      other is StudySentence && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'StudySentence($start, $end)';
}

/// Cuánto puede medir una oración antes de partirla en sus renglones: una
/// tabla o una lista sin puntos de un PDF llega como un solo bloque sin
/// ningún signo de cierre, y resaltarla entera sería resaltar media página.
const kMaxStudySentenceChars = 600;

/// Las oraciones de [content], en orden y sin pisarse.
///
/// Primero se parte en bloques —un párrafo, un título, un ítem de una lista,
/// una página de un PDF—, y cada bloque en oraciones:
///
/// - **Termina una oración** un `.`, `!`, `?` o `…` —con las comillas o los
///   paréntesis que lo cierren— seguido de un espacio o un salto de línea,
///   **si lo que sigue no empieza en minúscula**: «etc. y luego» sigue siendo
///   una sola.
/// - **No la termina** el punto de una abreviatura conocida —«Sr.», «p. ej.»,
///   «art.», «EE. UU.»— ni el de una inicial —«J. R. R. Tolkien»—.
/// - **Un salto de línea solo no corta**: en un PDF cada renglón termina con
///   uno, en medio de la oración. Corta un renglón en blanco, el separador de
///   páginas (`---`) y un renglón que empieza un título o un ítem.
/// - **Una lista de renglones sí**: un índice o una lista sin puntos ni
///   viñetas —«Capítulo I», «Que trata de…», «Capítulo II»…— es un bloque
///   donde **todos** los renglones siguientes empiezan con mayúscula o con un
///   número y ninguno anterior queda a medias —con una coma, un guion—. Cada
///   renglón es su oración: si no, el bloque entero sería una sola con sus
///   cuatro palabras clave. Un párrafo de prosa partido por el ancho de la
///   página no cumple eso en todos sus renglones.
///
/// Con [markdown], las marcas de bloque —`#`, `>`, `-`, `1.`— quedan afuera
/// de la oración; sin él —un PDF, un `.txt`—, las viñetas de una lista
/// (`•`, `-`, `–`). La marca de tiempo de un renglón de una transcripción
/// —`[3:15]`— queda afuera siempre (F39): no es algo que se dijo.
List<StudySentence> splitStudySentences(
  String content, {
  required bool markdown,
}) {
  final sentences = <StudySentence>[];
  for (final block in _blocksOf(content, markdown: markdown)) {
    for (final (start, end) in _lineItems(content, block.$1, block.$2)) {
      for (final sentence in _sentencesIn(content, start, end)) {
        sentences.addAll(_splitLong(content, sentence));
      }
    }
  }
  return sentences;
}

/// El bloque `[start, end)` en sus renglones si es una lista de renglones
/// —ver [splitStudySentences]—; si no, el bloque entero.
List<(int, int)> _lineItems(String content, int start, int end) {
  final breaks = <int>[];
  for (var i = start; i < end; i++) {
    if (content.codeUnitAt(i) == 0x0a) breaks.add(i);
  }
  if (breaks.isEmpty) return [(start, end)];

  var lineStart = start;
  final lines = <(int, int)>[];
  for (final lineBreak in [...breaks, end]) {
    lines.add((lineStart, lineBreak));
    lineStart = lineBreak + 1;
  }
  for (var i = 0; i < lines.length - 1; i++) {
    final before = content.substring(lines[i].$1, lines[i].$2).trimRight();
    final after = content
        .substring(lines[i + 1].$1, lines[i + 1].$2)
        .trimLeft();
    if (before.isEmpty || after.isEmpty) return [(start, end)];
    if (_unfinishedEnd.contains(before[before.length - 1])) {
      return [(start, end)];
    }
    final first = after[0];
    final startsAnItem =
        _isDigit(first) ||
        (first != first.toLowerCase() && first == first.toUpperCase());
    if (!startsAnItem) return [(start, end)];
  }
  return lines;
}

/// Con qué puede terminar un renglón que sigue en el de abajo.
const _unfinishedEnd = {',', ';', ':', '-', '–', '—', '(', '/'};

bool _isDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

/// Los bloques de [content]: `[inicio, fin)`, ya sin la marca del comienzo.
List<(int, int)> _blocksOf(String content, {required bool markdown}) {
  final blocks = <(int, int)>[];
  int? blockStart;
  var blockEnd = 0;

  void close() {
    if (blockStart != null && blockEnd > blockStart!) {
      blocks.add((blockStart!, blockEnd));
    }
    blockStart = null;
  }

  var lineStart = 0;
  while (lineStart <= content.length) {
    var lineEnd = content.indexOf('\n', lineStart);
    if (lineEnd < 0) lineEnd = content.length;
    final line = content.substring(lineStart, lineEnd);
    final trimmed = line.trim();

    if (trimmed.isEmpty || _separator.hasMatch(trimmed)) {
      close();
    } else if (markdown && trimmed.startsWith('![')) {
      // Una imagen sola en su renglón: no hay nada que leer.
      close();
    } else {
      final marker =
          _timestampLabel.firstMatch(line) ??
          (markdown ? _markdownMarker : _plainMarker).firstMatch(line);
      final heading = markdown && _heading.hasMatch(line);
      if (marker != null || heading) close();
      final textStart = lineStart + (marker?.end ?? _leadingSpaces(line));
      blockStart ??= textStart;
      blockEnd = lineEnd;
      // Un título es un bloque entero: lo que sigue es otro.
      if (heading) close();
    }

    if (lineEnd == content.length) break;
    lineStart = lineEnd + 1;
  }
  close();
  return blocks;
}

int _leadingSpaces(String line) => line.length - line.trimLeft().length;

/// Un separador de páginas o una raya horizontal.
final _separator = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');

/// Lo que empieza un título, una cita o un ítem de Markdown.
final _markdownMarker = RegExp(
  r'^\s*(#{1,6}\s+|>\s?|[-*+]\s+(\[[ xX]\]\s+)?|\d{1,3}[.)]\s+)',
);

final _heading = RegExp(r'^\s*#{1,6}\s');

/// La marca de tiempo con que empieza un renglón de una transcripción: cada
/// renglón es su propio bloque, como un ítem de una lista.
final _timestampLabel = RegExp(r'^\s*\[\d{1,2}(?::\d{2}){1,2}\]\s*');

/// La viñeta de una lista en un texto sin Markdown.
final _plainMarker = RegExp(r'^\s*([•·▪◦‣\-–—*]\s+|\d{1,3}[.)]\s+)');

/// Las oraciones del bloque `[start, end)` de [content].
Iterable<StudySentence> _sentencesIn(String content, int start, int end) sync* {
  var sentenceStart = start;
  var i = start;
  while (i < end) {
    final char = content[i];
    if (!_terminators.contains(char)) {
      i++;
      continue;
    }
    // El signo entero —«...», «?!»— y lo que lo cierra —comillas,
    // paréntesis, el `**` de una negrita—.
    var after = i + 1;
    while (after < end && _terminators.contains(content[after])) {
      after++;
    }
    while (after < end && _closers.contains(content[after])) {
      after++;
    }
    final endsHere =
        (after >= end || _isSpace(content[after])) &&
        !(char == '.' && _isAbbreviation(content, i, sentenceStart)) &&
        !_nextStartsLowercase(content, after, end);
    if (endsHere) {
      final sentence = _trimmed(content, sentenceStart, after);
      if (sentence != null) yield sentence;
      sentenceStart = after;
    }
    i = after;
  }
  final last = _trimmed(content, sentenceStart, end);
  if (last != null) yield last;
}

const _terminators = {'.', '!', '?', '…'};
const _closers = {'"', '”', '’', "'", '»', ')', ']', '*', '_'};

bool _isSpace(String char) =>
    char == ' ' || char == '\n' || char == '\t' || char == ' ';

/// Si lo que sigue a [from], salteando espacios, empieza con una minúscula:
/// entonces el punto no terminaba la oración.
bool _nextStartsLowercase(String content, int from, int end) {
  var i = from;
  while (i < end && _isSpace(content[i])) {
    i++;
  }
  if (i >= end) return false;
  final char = content[i];
  return char != char.toUpperCase() && char == char.toLowerCase();
}

/// Si el punto en [dot] es el de una abreviatura o una inicial: la palabra
/// que lo precede —sin salir de la oración— es una letra sola o una de las
/// conocidas.
bool _isAbbreviation(String content, int dot, int sentenceStart) {
  var wordStart = dot;
  while (wordStart > sentenceStart &&
      foldWordChar(content.codeUnitAt(wordStart - 1)) != null) {
    wordStart--;
  }
  if (wordStart == dot) return false;
  final word = content.substring(wordStart, dot);
  if (word.length == 1 && word != word.toLowerCase()) return true;
  final folded = StringBuffer();
  for (final unit in word.codeUnits) {
    folded.write(foldWordChar(unit) ?? '');
  }
  return _abbreviations.contains(folded.toString());
}

/// Las abreviaturas que van seguidas de un nombre o un número, en castellano
/// y en inglés, ya plegadas: después de ellas viene una mayúscula sin que
/// termine nada.
const _abbreviations = {
  // Castellano.
  'sr', 'sra', 'srta', 'sres', 'dr', 'dra', 'dres', 'lic', 'ing', 'prof',
  'arq', 'gral', 'cnel', 'tte', 'sto', 'sta', 'ud', 'uds', 'vd', 'vds',
  'art', 'arts', 'cap', 'caps', 'pag', 'pags', 'num', 'nro', 'vol', 'vols',
  'fig', 'figs', 'ej', 'ed', 'eds', 'trad', 'ee', 'uu', 'av', 'avda',
  'aprox', 'cf', 'op', 'cit', 'ibid',
  // Inglés. Sin «no.» —«No. 5»—: en castellano «…dijo que no. Luego…»
  // termina la oración.
  'mr', 'mrs', 'ms', 'jr', 'st', 'vs', 'eg', 'ie', 'approx', 'dept', 'univ',
};

/// `[start, end)` sin espacios en los bordes, o `null` si no tiene ni una
/// letra ni un número.
StudySentence? _trimmed(String content, int start, int end) {
  var s = start;
  var e = end;
  while (s < e && _isSpace(content[s])) {
    s++;
  }
  while (e > s && _isSpace(content[e - 1])) {
    e--;
  }
  for (var i = s; i < e; i++) {
    if (foldWordChar(content.codeUnitAt(i)) != null) {
      return StudySentence(s, e);
    }
  }
  return null;
}

/// [sentence] en pedazos de hasta [kMaxStudySentenceChars]: primero por sus
/// renglones —una tabla o una lista sin puntos— y, el renglón que sigue
/// siendo más largo —un índice o una enumeración de una sola línea—, en sus
/// cláusulas (ver [_splitAtClauses]).
Iterable<StudySentence> _splitLong(
  String content,
  StudySentence sentence,
) sync* {
  if (sentence.length <= kMaxStudySentenceChars) {
    yield sentence;
    return;
  }
  var pieceStart = sentence.start;
  var lastBreak = -1;
  final pieces = <StudySentence>[];
  for (var i = sentence.start; i < sentence.end; i++) {
    if (content[i] == '\n') lastBreak = i;
    if (i - pieceStart >= kMaxStudySentenceChars && lastBreak > pieceStart) {
      final piece = _trimmed(content, pieceStart, lastBreak);
      if (piece != null) pieces.add(piece);
      pieceStart = lastBreak + 1;
      lastBreak = -1;
    }
  }
  final rest = _trimmed(content, pieceStart, sentence.end);
  if (rest != null) pieces.add(rest);

  for (final piece in pieces) {
    if (piece.length <= kMaxStudySentenceChars) {
      yield piece;
    } else {
      yield* _splitAtClauses(content, piece);
    }
  }
}

/// [sentence], más larga que [kMaxStudySentenceChars] y sin renglones donde
/// cortar, en pedazos que no la pasen: cada uno termina en la última cláusula
/// —un `;` o un `:`—, o en la última coma, o en el último espacio que entra,
/// en la segunda mitad del pedazo. Una «palabra» más larga que eso —una
/// dirección, datos pegados— se corta en el primer espacio que viene.
Iterable<StudySentence> _splitAtClauses(
  String content,
  StudySentence sentence,
) sync* {
  var start = sentence.start;
  while (sentence.end - start > kMaxStudySentenceChars) {
    final limit = start + kMaxStudySentenceChars;
    final floor = start + kMaxStudySentenceChars ~/ 2;
    var cut =
        _lastCut(content, floor, limit, const {';', ':'}) ??
        _lastCut(content, floor, limit, const {','}) ??
        _lastCut(content, floor, limit, const {' ', '\t'}, after: false);
    if (cut == null) {
      // Una «palabra» más larga que el pedazo: hasta el primer espacio.
      var space = limit;
      while (space < sentence.end && !_isSpace(content[space])) {
        space++;
      }
      if (space >= sentence.end) break;
      cut = space;
    }
    final piece = _trimmed(content, start, cut);
    if (piece != null) yield piece;
    start = cut;
  }
  final rest = _trimmed(content, start, sentence.end);
  if (rest != null) yield rest;
}

/// Dónde cortar entre [floor] y [limit]: después del último de [marks]
/// seguido de un espacio —o, con `after: false`, en el espacio mismo—; `null`
/// si no hay ninguno.
int? _lastCut(
  String content,
  int floor,
  int limit,
  Set<String> marks, {
  bool after = true,
}) {
  for (var i = limit - 1; i >= floor; i--) {
    if (!marks.contains(content[i])) continue;
    if (!after) return i;
    if (i + 1 < content.length && _isSpace(content[i + 1])) return i + 1;
  }
  return null;
}
