import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Lo que se extrae del resumen o de la síntesis (F36): sus oraciones, en
/// orden y como texto corrido, y cuántas oraciones y palabras son.
typedef StudySentencesExtract = ({String text, int sentences, int words});

/// Las oraciones de [kind] de [study] sacadas de [content], sin marcado.
StudySentencesExtract studySentencesExtract(
  String content,
  DocumentStudy study,
  StudyMarkKind kind,
) {
  final sentences = [
    for (final mark in study.of(kind))
      studyPlainText(content.substring(mark.start, mark.end)),
  ].where((s) => s.isNotEmpty).toList();
  final text = sentences.join(' ');
  return (
    text: text,
    sentences: sentences.length,
    words: studyWordsIn(text, 0, text.length).length,
  );
}

/// Las palabras clave de [study] sacadas de [content], en el orden en que
/// aparecen y cada una una vez: la misma palabra en dos oraciones, o con y
/// sin mayúscula, es una sola etiqueta.
List<String> studyKeywordsExtract(String content, DocumentStudy study) {
  final seen = <String>{};
  return [
    for (final mark in study.of(StudyMarkKind.keyword))
      if (studyPlainText(content.substring(mark.start, mark.end))
          case final word when word.isNotEmpty && seen.add(foldStudyWord(word)))
        word,
  ];
}

/// [raw] en un solo renglón y sin marcado: un `[[Título]]` o un
/// `[texto](dirección)` quedan en su texto, y se van `**`, `__` y los
/// acentos graves. Lo que se lee, para el modelo o para copiar.
String studyPlainText(String raw) => raw
    .replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
