import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_extracts.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';

/// Lo que el lector en voz alta lee con cada capa de lo estudiado (F39): las
/// oraciones del resumen, las de la síntesis y las palabras clave, **en el
/// orden del texto** y con **sus posiciones en [content]**, para que lo que
/// suena se resalte en su lugar del texto entero.
///
/// Las tres capas están siempre en el resultado, vacías las que todavía no
/// tienen nada: el reproductor ofrece las tres y apaga las vacías. Las
/// palabras clave son las mismas que las etiquetas de la tarjeta —cada una
/// una vez, la primera que aparece—: lo que se ve es lo que se oye.
///
/// [sourceKey] es el del texto en pantalla —el de su forma—, y [markdown] el
/// de [content] al estudiarlo. Las marcas de tiempo de una transcripción
/// quedan fuera sin hacer nada: ninguna oración las incluye.
Map<ReadScope, List<ReadableSegment>> studyReadScopes({
  required String sourceKey,
  required String content,
  required DocumentStudy study,
  required bool markdown,
}) {
  List<ReadableSegment> within(Iterable<StudyMark> marks) => [
    for (final mark in marks)
      ...buildReadableSegmentsWithin(
        content,
        mark.start,
        mark.end,
        sourceKey: sourceKey,
        markdown: markdown,
      ),
  ];

  return {
    ReadScope.summary: within(study.of(StudyMarkKind.summary)),
    ReadScope.synthesis: within(study.of(StudyMarkKind.synthesis)),
    ReadScope.keywords: within([
      for (final part in studyKeywordParts(content, study)) part.mark,
    ]),
  };
}

/// Con qué id conoce el lector flotante lo que la tarjeta de estudiar ofrece
/// para escuchar el texto de la forma [renditionId] (F39).
String studyReadableId(String renditionId) => 'study:$renditionId';

/// Lo que la tarjeta de estudiar ofrece para escuchar (F39): el texto [text],
/// con [ReadScope.all], y [scopes], lo estudiado. Es el mismo texto, con los
/// mismos pedazos y posiciones, que ofrece el detalle: lo que suena se
/// resalta en su lugar. También la transcripción de un audio o un video, que
/// se escucha entera con la voz del lector si se elige (F40, pedido del
/// dueño).
ReadableDocument studyReadableDocument({
  required StudyText text,
  required String title,
  required Map<ReadScope, List<ReadableSegment>> scopes,
  bool transcript = false,
}) => ReadableDocument(
  id: studyReadableId(text.renditionId),
  title: title,
  segments: buildReadableSegments(
    text.content,
    sourceKey: text.renditionId,
    transcript: transcript,
    markdown: text.markdown,
  ),
  scopes: scopes,
);
