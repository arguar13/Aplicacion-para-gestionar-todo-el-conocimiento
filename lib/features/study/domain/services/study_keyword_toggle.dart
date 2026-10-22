import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Qué hace tocar una palabra mientras se eligen las palabras clave (F36).
@immutable
sealed class KeywordToggle {
  const KeywordToggle();
}

/// La palabra pasa a ser clave.
class KeywordToggleAdd extends KeywordToggle {
  const KeywordToggleAdd(this.word);

  final StudyWord word;
}

/// La palabra ya era clave y deja de serlo.
class KeywordToggleRemove extends KeywordToggle {
  const KeywordToggleRemove(this.markId);

  final String markId;
}

/// La oración ya tiene sus [kMaxKeywordsPerSentence] palabras clave.
class KeywordToggleFull extends KeywordToggle {
  const KeywordToggleFull();
}

/// No se tocó una palabra de una oración resaltada, o se tocó una que no dice
/// nada sola —«de», «la»—: no pasa nada.
class KeywordToggleNone extends KeywordToggle {
  const KeywordToggleNone();
}

/// Qué pasa al tocar la posición [offset] de [content] eligiendo palabras
/// clave (F36), con las oraciones de [sentenceKinds] a la vista.
///
/// Solo cuenta una palabra de una oración resaltada: las palabras clave son
/// de una oración, y fuera de ellas no hay a cuál atarla. Un toque cae entre
/// dos letras, así que el que cae justo detrás de la última también es de esa
/// palabra. Como con las que propone la IA, un artículo o una preposición no
/// es una palabra clave.
KeywordToggle keywordToggleAt({
  required String content,
  required DocumentStudy study,
  required Set<StudyMarkKind> sentenceKinds,
  required int offset,
}) {
  final sentence = study.marks
      .where(
        (m) =>
            sentenceKinds.contains(m.kind) &&
            offset >= m.start &&
            offset <= m.end,
      )
      .firstOrNull;
  if (sentence == null) return const KeywordToggleNone();

  final range = StudySentence(sentence.start, sentence.end);
  final word =
      studyWordAt(content, range, offset) ??
      (offset > range.start ? studyWordAt(content, range, offset - 1) : null);
  if (word == null || !word.meaningful) return const KeywordToggleNone();

  final keywords = [
    for (final mark in study.of(StudyMarkKind.keyword))
      if (mark.isWithin(range.start, range.end)) mark,
  ];
  for (final mark in keywords) {
    if (mark.start == word.start && mark.end == word.end) {
      return KeywordToggleRemove(mark.id);
    }
  }
  if (keywords.length >= kMaxKeywordsPerSentence) {
    return const KeywordToggleFull();
  }
  return KeywordToggleAdd(word);
}
