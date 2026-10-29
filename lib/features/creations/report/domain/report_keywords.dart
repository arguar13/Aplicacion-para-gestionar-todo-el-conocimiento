import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Cuántas palabras clave de las fuentes se buscan en un informe, como
/// mucho: las que más se marcaron. Con la garantía de la decisión 85 un libro
/// tiene palabras clave en todas sus oraciones —miles—; buscarlas todas
/// pintaría de rosa medio informe. Las más marcadas son las que el documento
/// repite: sus nombres y sus conceptos.
const kReportKeywordsMax = 150;

/// Cuántas palabras puede tener una palabra clave que se busca: las que se
/// eligen a mano pueden ser una frase («Mar Rojo»).
const kReportKeywordMaxWords = 4;

/// Las palabras clave que se pintan de rosa en un informe (decisión 85): las
/// de las fuentes, comparadas como las lee una persona —sin mayúsculas ni
/// tildes, palabra entera—, porque el informe es un texto nuevo y no tiene
/// las posiciones de las marcas.
@immutable
class ReportKeywords {
  factory ReportKeywords(Iterable<String> phrases) {
    final folded = _fold(phrases);
    final longest = folded.fold(
      0,
      (most, p) => math.max(most, ' '.allMatches(p).length + 1),
    );
    return ReportKeywords._(folded, longest);
  }

  const ReportKeywords._(this._phrases, this._maxWords);

  static const empty = ReportKeywords._(<String>{}, 0);

  final Set<String> _phrases;

  /// Cuántas palabras tiene la más larga.
  final int _maxWords;

  static Set<String> _fold(Iterable<String> phrases) {
    final folded = <String>{};
    for (final phrase in phrases) {
      final words = studyWordsIn(phrase, 0, phrase.length);
      if (words.isEmpty || words.length > kReportKeywordMaxWords) continue;
      // Una palabra sola que no dice nada —«de», «la»— no se pinta nunca.
      if (words.length == 1 && !words.single.meaningful) continue;
      folded.add(words.map((w) => w.folded).join(' '));
    }
    return folded;
  }

  bool get isEmpty => _phrases.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ReportKeywords && setEquals(other._phrases, _phrases);

  @override
  int get hashCode => Object.hashAllUnordered(_phrases);

  int get length => _phrases.length;

  /// Si [phrase] es una de ellas.
  bool contains(String phrase) => _phrases.contains(foldStudyWord(phrase));

  /// Dónde están en [text], `[start, end)`, en orden y sin pisarse: la frase
  /// más larga gana («Mar Rojo» antes que «Mar»).
  List<(int, int)> rangesIn(String text) {
    if (_phrases.isEmpty || text.isEmpty) return const [];
    final words = studyWordsIn(text, 0, text.length);
    final ranges = <(int, int)>[];
    var i = 0;
    while (i < words.length) {
      var matched = 0;
      for (var n = math.min(_maxWords, words.length - i); n >= 1; n--) {
        final phrase = n == 1
            ? words[i].folded
            : words.sublist(i, i + n).map((w) => w.folded).join(' ');
        if (_phrases.contains(phrase)) {
          matched = n;
          break;
        }
      }
      if (matched == 0) {
        i++;
        continue;
      }
      ranges.add((words[i].start, words[i + matched - 1].end));
      i += matched;
    }
    return ranges;
  }
}

/// Las palabras clave más marcadas de [counts] —cada una con cuántas veces se
/// marcó en las fuentes—, hasta [max]: primero las más marcadas y, a igual
/// cuenta, las más largas.
List<String> rankReportKeywords(
  Map<String, int> counts, {
  int max = kReportKeywordsMax,
}) {
  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      final byLength = b.key.length.compareTo(a.key.length);
      return byLength != 0 ? byLength : a.key.compareTo(b.key);
    });
  return [for (final entry in ranked.take(max)) entry.key];
}
