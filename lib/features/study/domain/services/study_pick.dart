import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Qué hace tocar el texto mientras se elige a mano el resumen, la síntesis
/// o las palabras clave (F36, F39).
@immutable
sealed class StudyPickToggle {
  const StudyPickToggle();
}

/// `[start, end)` pasa a ser del resumen, de la síntesis o una palabra clave.
class StudyPickAdd extends StudyPickToggle {
  const StudyPickAdd(this.kind, this.start, this.end);

  final StudyMarkKind kind;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is StudyPickAdd &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => 'StudyPickAdd($kind, $start, $end)';
}

/// Ya estaba —la eligió la IA o la persona— y sale.
class StudyPickRemove extends StudyPickToggle {
  const StudyPickRemove(this.markId);

  final String markId;

  @override
  bool operator ==(Object other) =>
      other is StudyPickRemove && other.markId == markId;

  @override
  int get hashCode => markId.hashCode;

  @override
  String toString() => 'StudyPickRemove($markId)';
}

/// La oración ya tiene sus [kMaxKeywordsPerSentence] palabras clave.
class StudyPickFull extends StudyPickToggle {
  const StudyPickFull();
}

/// No se tocó una oración, o se tocó una palabra que no dice nada sola —«de»,
/// «la»—: no pasa nada.
class StudyPickNone extends StudyPickToggle {
  const StudyPickNone();
}

/// Qué pasa al tocar la posición [offset] de [content] eligiendo a mano lo de
/// [kind] (F39).
///
/// - **El resumen o la síntesis**: la oración tocada entra; si ya estaba,
///   sale. Las oraciones son las mismas en que la IA parte el texto, así que
///   lo elegido a mano y lo de la IA se ven igual.
/// - **Las palabras clave**: la palabra tocada, de **cualquier** oración
///   —haya o no resumen—, hasta [kMaxKeywordsPerSentence] por oración. Un
///   toque cae entre dos letras, así que el que cae justo detrás de la última
///   también es de esa palabra. Como con las que propone la IA, un artículo o
///   una preposición no es una palabra clave.
StudyPickToggle studyPickAt({
  required String content,
  required bool markdown,
  required DocumentStudy study,
  required StudyMarkKind kind,
  required int offset,
}) {
  final sentence = _sentenceAt(content, markdown, offset);
  if (sentence == null) return const StudyPickNone();

  if (kind != StudyMarkKind.keyword) {
    // La que ya está en esa oración sale, aunque la IA la haya partido un
    // poco distinto en un análisis de antes.
    for (final mark in study.of(kind)) {
      if (mark.start < sentence.end && mark.end > sentence.start) {
        return StudyPickRemove(mark.id);
      }
    }
    return StudyPickAdd(kind, sentence.start, sentence.end);
  }

  final word =
      studyWordAt(content, sentence, offset) ??
      (offset > sentence.start
          ? studyWordAt(content, sentence, offset - 1)
          : null);
  if (word == null || !word.meaningful) return const StudyPickNone();

  final keywords = [
    for (final mark in study.of(StudyMarkKind.keyword))
      if (mark.isWithin(sentence.start, sentence.end)) mark,
  ];
  for (final mark in keywords) {
    if (mark.start == word.start && mark.end == word.end) {
      return StudyPickRemove(mark.id);
    }
  }
  if (keywords.length >= kMaxKeywordsPerSentence) return const StudyPickFull();
  return StudyPickAdd(StudyMarkKind.keyword, word.start, word.end);
}

/// La oración de [content] en [offset]; el toque justo detrás de su última
/// letra también es de ella.
StudySentence? _sentenceAt(String content, bool markdown, int offset) {
  final sentences = _sentencesOf(content, markdown);
  var low = 0;
  var high = sentences.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (sentences[mid].end < offset) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  if (low == sentences.length) return null;
  final sentence = sentences[low];
  return offset >= sentence.start ? sentence : null;
}

/// Las oraciones del último texto que se tocó: partir un libro entero en cada
/// toque sería trabajo de más, y se toca muchas veces seguidas el mismo.
List<StudySentence> _sentencesOf(String content, bool markdown) {
  final last = _last;
  if (last != null && identical(last.$1, content) && last.$2 == markdown) {
    return last.$3;
  }
  final sentences = splitStudySentences(content, markdown: markdown);
  _last = (content, markdown, sentences);
  return sentences;
}

(String, bool, List<StudySentence>)? _last;
