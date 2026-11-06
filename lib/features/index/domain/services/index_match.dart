import 'package:sinapsis/core/util/word_folding.dart';

/// Un tramo de un texto, en unidades de código: `[start, end)`.
typedef IndexMatchRange = ({int start, int end});

/// Las palabras de lo que se escribió en el buscador del Índice (F46),
/// plegadas: sin mayúsculas ni acentos, cortadas donde no hay letra ni
/// número. Es como lo lee el índice de texto (`remove_diacritics 2`): «Nicéa,
/// 325» son `nicea` y `325`.
List<String> indexQueryWords(String query) => [
  for (final word in _words(query)) word.folded,
];

/// Si [title] tiene todas las palabras de [query] —el comienzo de una de sus
/// palabras alcanza, sin mayúsculas ni acentos—: lo mismo que pide la
/// búsqueda de capítulos a la base, para filtrar los títulos de los
/// documentos sobre la lista que la pantalla ya tiene. Sin palabras, nada
/// coincide.
bool indexTitleMatches(String title, String query) {
  final wanted = indexQueryWords(query);
  if (wanted.isEmpty) return false;
  final words = [for (final word in _words(title)) word.folded];
  return wanted.every((w) => words.any((word) => word.startsWith(w)));
}

/// Dónde resaltar [query] en [title]: el comienzo de cada palabra de [title]
/// que empieza con alguna de las de [query], tan largo como la más larga que
/// le cabe, en el orden del texto y sin pisarse. Se mide sobre el título como
/// está escrito, así que una tilde o una mayúscula quedan adentro del tramo.
List<IndexMatchRange> indexMatchRanges(String title, String query) {
  final wanted = indexQueryWords(query);
  if (wanted.isEmpty) return const [];
  final ranges = <IndexMatchRange>[];
  for (final word in _words(title)) {
    var longest = 0;
    for (final w in wanted) {
      if (w.length > longest && word.folded.startsWith(w)) longest = w.length;
    }
    if (longest == 0) continue;
    ranges.add((start: word.start, end: word.endOfFolded(longest)));
  }
  return ranges;
}

/// Una palabra de un texto: dónde empieza, cómo se lee plegada y dónde
/// termina en el texto cada letra plegada.
class _Word {
  _Word(this.start);

  final int start;
  final _folded = StringBuffer();

  /// Para cada letra plegada, dónde termina en el texto la letra que la dio:
  /// una letra se puede plegar en más de una («ǅ» → «dž»).
  final _ends = <int>[];

  String get folded => _folded.toString();

  void add(String folded, int end) {
    _folded.write(folded);
    for (var i = 0; i < folded.length; i++) {
      _ends.add(end);
    }
  }

  /// Dónde termina en el texto lo que dan las primeras [length] letras
  /// plegadas.
  int endOfFolded(int length) => _ends[length - 1];
}

/// Las palabras de [text]: las tiradas de letras y números, como las corta
/// el índice de texto.
List<_Word> _words(String text) {
  final words = <_Word>[];
  _Word? current;
  var at = 0;
  for (final rune in text.runes) {
    final width = rune > 0xFFFF ? 2 : 1;
    final folded = foldWordChar(rune);
    if (folded == null) {
      current = null;
    } else {
      if (current == null) {
        current = _Word(at);
        words.add(current);
      }
      current.add(folded, at + width);
    }
    at += width;
  }
  return words;
}
