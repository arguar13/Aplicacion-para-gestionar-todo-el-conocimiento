import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Lo que se extrae del resumen o de la síntesis (F36): sus oraciones, en
/// orden y como texto corrido, y cuántas oraciones y palabras son.
typedef StudySentencesExtract = ({String text, int sentences, int words});

/// Una oración del resumen o de la síntesis, sin marcado, con la marca de la
/// que salió: dónde está en el texto.
typedef StudySentencePart = ({StudyMark mark, String text});

/// Las oraciones de [kind] de [study] sacadas de [content], en orden y sin
/// marcado; las que quedan vacías, fuera. De acá salen el texto que se copia
/// (F36) y la oración que se resalta mientras suena (F39): una sola cuenta.
List<StudySentencePart> studySentenceParts(
  String content,
  DocumentStudy study,
  StudyMarkKind kind,
) => [
  for (final mark in study.of(kind))
    if (studyPlainText(content.substring(mark.start, mark.end)) case final text
        when text.isNotEmpty)
      (mark: mark, text: text),
];

/// Las oraciones de [kind] de [study] sacadas de [content], sin marcado.
StudySentencesExtract studySentencesExtract(
  String content,
  DocumentStudy study,
  StudyMarkKind kind,
) {
  final parts = studySentenceParts(content, study, kind);
  final text = [for (final part in parts) part.text].join(' ');
  return (
    text: text,
    sentences: parts.length,
    words: studyWordsIn(text, 0, text.length).length,
  );
}

/// Una palabra clave, sin marcado, con la marca de la que salió.
typedef StudyKeywordPart = ({StudyMark mark, String word});

/// Las palabras clave de [study] sacadas de [content], en el orden en que
/// aparecen y cada una una vez: la misma palabra en dos oraciones, o con y
/// sin mayúscula, es una sola etiqueta, y la que cuenta es la primera. Las
/// etiquetas de la tarjeta y lo que se lee en voz alta salen de acá (F39).
List<StudyKeywordPart> studyKeywordParts(String content, DocumentStudy study) {
  final seen = <String>{};
  return [
    for (final mark in study.of(StudyMarkKind.keyword))
      if (studyPlainText(content.substring(mark.start, mark.end))
          case final word when word.isNotEmpty && seen.add(foldStudyWord(word)))
        (mark: mark, word: word),
  ];
}

/// Las palabras clave de [study] sacadas de [content]: ver
/// [studyKeywordParts].
List<String> studyKeywordsExtract(String content, DocumentStudy study) => [
  for (final part in studyKeywordParts(content, study)) part.word,
];

/// [raw] en un solo renglón y sin marcado: un `[[Título]]` o un
/// `[texto](dirección)` quedan en su texto, y se van `**`, `__` y los
/// acentos graves. Lo que se lee, para el modelo o para copiar.
String studyPlainText(String raw) => raw
    .replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
