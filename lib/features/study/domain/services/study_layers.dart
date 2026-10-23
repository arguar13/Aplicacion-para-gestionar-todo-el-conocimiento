import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';

/// Las oraciones de [study] de los tipos [kinds], en orden (F36): las del
/// resumen, las de la síntesis o las de los dos.
///
/// Es lo que decide qué oraciones se pintan en el original y qué oraciones se
/// marcan en el documento que se descarga (F38): una sola cuenta para los dos.
List<StudyMark> studySentenceMarks(
  DocumentStudy study,
  Set<StudyMarkKind> kinds,
) => [
  for (final mark in study.marks)
    if (kinds.contains(mark.kind)) mark,
];
