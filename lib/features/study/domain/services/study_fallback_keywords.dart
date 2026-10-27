/// El respaldo local de las palabras clave: cuando el modelo no marcó
/// ninguna en una oración, la app elige sola las que más dicen, sin IA y sin
/// red.
///
/// ## Qué es una «oración con contenido»
///
/// La que tiene **al menos una palabra que dice algo sola**
/// —`StudyWord.meaningful`: no es un artículo, una preposición, una
/// conjunción ni una letra suelta; un número sí—. Esas son las únicas
/// oraciones a las que la garantía de «toda oración tiene sus palabras clave»
/// obliga. Las que no la cumplen —«Y.»,
/// «Es de él.»— no tienen nada que marcar, y `splitStudySentences` ya descarta
/// las que no tienen ni una letra ni un número —una raya, una página en
/// blanco—.
///
/// ## Qué palabras elige
///
/// De las palabras de la oración que pueden ser clave (`meaningful`), las que
/// más dicen en **este documento**:
///
/// - Las **raras** antes que las comunes: una palabra que casi no aparece en
///   el resto del texto identifica a la oración; una que está en cada página,
///   no. Es la frecuencia en el documento ([StudyWordStats]).
/// - Los **nombres propios** —con mayúscula en medio de la oración—.
/// - Las **largas** antes que las cortas.
/// - Las palabras vacías de castellano y de inglés —«you», «may», «además»,
///   «cuando»— solo si no hay otra cosa; los números, igual.
///
/// Cuántas: una por cada tres palabras con algo para decir, entre una y
/// [kMaxKeywordsPerSentence].
///
/// La elección es determinista: la misma oración del mismo documento da
/// siempre las mismas palabras, y las posiciones son las exactas del texto.
library;

import 'dart:math' as math;

import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Cuántas veces aparece cada palabra en un documento: la frecuencia con la
/// que se decide cuál dice más.
class StudyWordStats {
  StudyWordStats._(this._counts, this.total);

  /// Cuenta las palabras de [content].
  factory StudyWordStats.of(String content) {
    final counts = <String, int>{};
    final words = studyWordsIn(content, 0, content.length);
    for (final word in words) {
      counts.update(word.folded, (n) => n + 1, ifAbsent: () => 1);
    }
    return StudyWordStats._(counts, words.length);
  }

  final Map<String, int> _counts;

  /// Cuántas palabras tiene el documento.
  final int total;

  /// Cuántas veces aparece [folded]; al menos una.
  int countOf(String folded) => math.max(1, _counts[folded] ?? 1);

  /// Cuánto dice [folded] en el documento: el logaritmo de cuántas veces
  /// menos aparece que el total de palabras. Una palabra única vale lo máximo.
  double rarity(String folded) =>
      math.log((total + 1) / countOf(folded)).clamp(0, double.infinity);
}

/// Las palabras clave de respaldo de [sentence]: ver la explicación arriba.
/// Vacío si la oración no tiene contenido.
List<StudyWord> fallbackKeywordsFor(
  String content,
  StudySentence sentence,
  StudyWordStats stats,
) {
  final words = studyWordsIn(content, sentence.start, sentence.end);

  // La primera aparición de cada palabra: repetirla no la hace decir más.
  final seen = <String>{};
  final candidates = <_Candidate>[];
  for (final (index, word) in words.indexed) {
    if (!word.meaningful || !seen.add(word.folded)) continue;
    candidates.add(_candidate(content, word, index, stats));
  }
  if (candidates.isEmpty) return const [];

  final real = candidates.where((c) => c.tier == _Tier.word).length;
  final wanted = ((real + 2) ~/ 3).clamp(1, kMaxKeywordsPerSentence);
  candidates.sort((a, b) {
    final byTier = b.tier.index.compareTo(a.tier.index);
    if (byTier != 0) return byTier;
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  final picked = candidates.take(wanted).toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  return [for (final c in picked) c.word];
}

/// De qué clase es una palabra a la hora de elegir: una vacía o un número no
/// compiten con una palabra de verdad.
enum _Tier { stop, number, word }

class _Candidate {
  const _Candidate(this.word, this.index, this.tier, this.score);

  final StudyWord word;

  /// Su lugar entre las palabras de la oración.
  final int index;
  final _Tier tier;

  /// Cuánto dice, entre las de su clase.
  final double score;
}

_Candidate _candidate(
  String content,
  StudyWord word,
  int index,
  StudyWordStats stats,
) {
  final base =
      stats.rarity(word.folded) + math.min(word.folded.length, 14) / 14;
  if (_extraCommonWords.contains(word.folded)) {
    return _Candidate(word, index, _Tier.stop, base);
  }
  if (_digitsOnly.hasMatch(word.folded) ||
      _roman.hasMatch(content.substring(word.start, word.end))) {
    return _Candidate(word, index, _Tier.number, base);
  }
  // Con mayúscula y no al empezar la oración: un nombre propio. La del
  // comienzo no dice nada, la tiene cualquier palabra.
  final first = content[word.start];
  final proper =
      index > 0 && first != first.toLowerCase() && first == first.toUpperCase();
  return _Candidate(word, index, _Tier.word, base + (proper ? 1.5 : 0));
}

final _digitsOnly = RegExp(r'^\d+$');

/// Un número romano en mayúsculas —el «II» de «Capítulo II»—: cuenta como un
/// número.
final _roman = RegExp(r'^[IVXLCDM]{2,}$');

/// Las oraciones de [sentences] que no tienen ninguna palabra clave en
/// [keywordRanges] —los `[start, end)` de las palabras clave ya marcadas— y
/// las que les da el respaldo: lo que falta para que **toda** oración con
/// contenido tenga las suyas.
///
/// [sentences] va en orden, como las deja `splitStudySentences`.
List<StudyWord> missingKeywords({
  required String content,
  required List<StudySentence> sentences,
  required Iterable<(int, int)> keywordRanges,
  required StudyWordStats stats,
}) {
  final ranges = keywordRanges.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  final filled = <StudyWord>[];
  var next = 0;
  for (final sentence in sentences) {
    while (next < ranges.length && ranges[next].$1 < sentence.start) {
      next++;
    }
    final covered =
        next < ranges.length &&
        ranges[next].$1 < sentence.end &&
        ranges[next].$2 <= sentence.end;
    if (!covered) filled.addAll(fallbackKeywordsFor(content, sentence, stats));
  }
  return filled;
}

/// Palabras que no dicen nada del tema aunque `isCommonWord` las deje pasar:
/// pronombres, verbos auxiliares, adverbios y conectores, en castellano y en
/// inglés. Ya plegadas. Solo sirven para ordenar —una palabra clave de la IA
/// o elegida a mano sigue valiendo—: pasan a ser el último recurso.
const _extraCommonWords = {
  // Castellano.
  'yo', 'tu', 'vos', 'ella', 'nosotros', 'nosotras', 'ustedes', 'ellos',
  'ellas', 'me', 'te', 'nos', 'os', 'mi', 'mis', 'tus', 'mio', 'mia', 'tuyo',
  'suyo', 'suya', 'nuestro', 'nuestra', 'nuestros', 'nuestras', 'vuestro',
  'estos', 'estas', 'esos', 'esas', 'aquel', 'aquella', 'aquellos', 'aquellas',
  'aquello', 'algo', 'alguien', 'alguno', 'alguna', 'algunos', 'algunas',
  'ninguno', 'ninguna', 'nada', 'nadie', 'otro', 'otra', 'otros', 'otras',
  'mismo', 'misma', 'mismos', 'mismas', 'todo', 'toda', 'todos', 'todas',
  'cada', 'varios', 'varias', 'mucho', 'mucha', 'muchos', 'muchas', 'poco',
  'poca', 'pocos', 'pocas', 'tan', 'tanto', 'tanta', 'tantos', 'tantas',
  'bien', 'mal', 'asi', 'aqui', 'alli', 'alla', 'aca', 'ahi', 'ahora', 'antes',
  'despues', 'luego', 'entonces', 'siempre', 'nunca', 'jamas', 'tampoco',
  'solo', 'solamente', 'casi', 'apenas', 'aun', 'todavia', 'ademas', 'incluso',
  'quien', 'quienes', 'cuyo', 'cuya', 'cuyos', 'cuyas', 'cuanto', 'cuanta',
  'cuantos', 'cuantas', 'porque', 'pues', 'aunque', 'sino', 'mientras',
  'segun', 'hacia', 'tras', 'contra', 'mediante', 'bajo', 'soy', 'eres',
  'somos', 'sois', 'estoy', 'estamos', 'estan', 'estaba', 'estaban', 'estado',
  'estar', 'estuvo', 'sido', 'siendo', 'seria', 'serian', 'sera', 'seran',
  'sea', 'sean', 'fuera', 'fuese', 'he', 'has', 'hemos', 'habia', 'habian',
  'habra', 'haber', 'hay', 'hubo', 'hacer', 'hace', 'hizo', 'hacen', 'puede',
  'pueden', 'podia', 'poder', 'debe', 'deben', 'tiene', 'tienen', 'tenia',
  'tener', 'tengo', 'va', 'van', 'iba', 'voy', 'vamos', 'dijo', 'dice',
  'decir', 'vio', 'veo', 'lo', 'les', 'cual', 'cuales', 'quizas',
  'acaso', 'tal', 'tales', 'vez', 'veces', 'dos', 'tres', 'uno', 'una',
  // Inglés.
  'i', 'you', 'she', 'we', 'they', 'him', 'her', 'us', 'them',
  'my', 'your', 'his', 'our', 'mine', 'yours', 'hers', 'ours', 'theirs',
  'myself', 'yourself', 'himself', 'herself', 'itself', 'ourselves',
  'themselves', 'these', 'those', 'who', 'whom', 'whose', 'what', 'where',
  'when', 'why', 'how', 'all', 'any', 'both', 'each', 'few', 'more', 'most',
  'other', 'some', 'such', 'nor', 'not', 'only', 'own', 'same', 'so', 'than',
  'too', 'very', 'can', 'will', 'just', 'should', 'now', 'do', 'does', 'did',
  'doing', 'done', 'am', 'been', 'being', 'would', 'could', 'may', 'might',
  'must', 'shall', 'also', 'if', 'then', 'there', 'here', 'about', 'above',
  'after', 'again', 'against', 'before', 'below', 'between', 'into', 'through',
  'under', 'until', 'up', 'down', 'out', 'off', 'over', 'once', 'while',
  'because', 'but', 'yet', 'either', 'neither', 'whether', 'upon', 'within',
  'without', 'among', 'per', 'via', 'let', 'get', 'got', 'make', 'made',
  'anyone', 'anywhere', 'anything', 'everyone', 'everything', 'someone',
  'something', 'nothing', 'nobody', 'whatsoever', 'however', 'therefore',
  'thus', 'hence', 'many', 'much', 'several', 'still', 'even', 'ever', 'never',
  'always', 'often', 'one', 'two', 'three',
};
