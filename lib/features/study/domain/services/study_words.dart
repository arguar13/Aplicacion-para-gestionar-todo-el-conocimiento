import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/util/word_folding.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';

/// Cuántas palabras clave puede tener una oración, como mucho (F36): lo que
/// pidió el usuario —«máximo 4 palabras por oración»—. Vale para las que
/// propone la IA y para las que se eligen a mano.
const kMaxKeywordsPerSentence = 4;

/// Una palabra de un texto: su rango `[start, end)` en el texto guardado y
/// cómo se compara —en minúsculas y sin acentos—.
@immutable
class StudyWord {
  const StudyWord(this.start, this.end, this.folded);

  final int start;
  final int end;
  final String folded;

  /// Si dice algo por sí sola: no es un artículo, una preposición, una
  /// conjunción ni una letra suelta.
  bool get meaningful =>
      (folded.length > 1 || _digits.hasMatch(folded)) && !isCommonWord(folded);

  @override
  bool operator ==(Object other) =>
      other is StudyWord &&
      other.start == start &&
      other.end == end &&
      other.folded == folded;

  @override
  int get hashCode => Object.hash(start, end, folded);

  @override
  String toString() => 'StudyWord($start, $end, $folded)';
}

final _digits = RegExp(r'^\d+$');

/// Las palabras de [content] dentro de `[start, end)`. Une lo que un guion o
/// un apóstrofo juntan dentro de una palabra —«socio-económico», «l'État»—:
/// es una sola cosa para resaltar.
List<StudyWord> studyWordsIn(String content, int start, int end) {
  final words = <StudyWord>[];
  final folded = StringBuffer();
  var wordStart = -1;

  void close(int at) {
    if (wordStart >= 0) words.add(StudyWord(wordStart, at, folded.toString()));
    folded.clear();
    wordStart = -1;
  }

  for (var i = start; i < end; i++) {
    final char = foldWordChar(content.codeUnitAt(i));
    if (char != null) {
      if (wordStart < 0) wordStart = i;
      folded.write(char);
      continue;
    }
    final joiner = _joiners.contains(content[i]);
    final continues =
        joiner &&
        wordStart >= 0 &&
        i + 1 < end &&
        foldWordChar(content.codeUnitAt(i + 1)) != null;
    if (continues) {
      folded.write(content[i] == '-' ? '-' : "'");
    } else {
      close(i);
    }
  }
  close(end);
  return words;
}

const _joiners = {'-', "'", '’'};

/// [text] como se compara: en minúsculas, sin acentos y sin lo que no es una
/// letra ni un número en los bordes.
String foldStudyWord(String text) {
  final words = studyWordsIn(text, 0, text.length);
  return words.map((w) => w.folded).join(' ');
}

/// Las palabras de [sentence] que nombra [proposed], en el orden en que las
/// propuso la IA, sin repetir y hasta [kMaxKeywordsPerSentence].
///
/// La IA a veces propone una frase —«revolución industrial»—: cuenta como
/// sus palabras, una por una. Una palabra que no está en la oración se
/// descarta —la IA no puede marcar algo que el texto no dice—, y también una
/// que no dice nada sola, como «de» o «la». Si está más de una vez, se toma
/// la primera que no se haya tomado.
List<StudyWord> pickKeywords(
  String content,
  StudySentence sentence,
  Iterable<String> proposed,
) {
  final words = studyWordsIn(content, sentence.start, sentence.end);
  final picked = <StudyWord>[];
  for (final phrase in proposed) {
    for (final wanted in foldStudyWord(phrase).split(' ')) {
      if (picked.length == kMaxKeywordsPerSentence) return picked;
      if (wanted.isEmpty) continue;
      final match = words
          .where((w) => w.folded == wanted && w.meaningful)
          .where((w) => !picked.contains(w))
          .firstOrNull;
      if (match != null) picked.add(match);
    }
  }
  return picked;
}

/// La palabra de [content] en [offset], si hay una: lo que se toca al elegir
/// una palabra clave a mano.
StudyWord? studyWordAt(String content, StudySentence sentence, int offset) {
  for (final word in studyWordsIn(content, sentence.start, sentence.end)) {
    if (offset >= word.start && offset < word.end) return word;
  }
  return null;
}
