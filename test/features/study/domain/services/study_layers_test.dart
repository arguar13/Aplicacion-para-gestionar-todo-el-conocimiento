import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_layers.dart';

void main() {
  StudyMark mark(String id, StudyMarkKind kind, int start, int end) =>
      StudyMark(
        id: id,
        kind: kind,
        origin: ContentOrigin.ai,
        start: start,
        end: end,
      );

  final study = DocumentStudy(
    marks: [
      mark('s1', StudyMarkKind.summary, 0, 20),
      mark('k1', StudyMarkKind.keyword, 4, 9),
      mark('y1', StudyMarkKind.synthesis, 30, 50),
      mark('k2', StudyMarkKind.keyword, 32, 36),
      mark('k3', StudyMarkKind.keyword, 60, 64),
    ],
    analyzedUntil: 100,
    complete: true,
  );

  List<String> ids(List<StudyMark> marks) => [for (final m in marks) m.id];

  test('las oraciones de los tipos pedidos, en orden', () {
    expect(ids(studySentenceMarks(study, {StudyMarkKind.summary})), ['s1']);
    expect(ids(studySentenceMarks(study, {StudyMarkKind.synthesis})), ['y1']);
    expect(
      ids(
        studySentenceMarks(study, {
          StudyMarkKind.summary,
          StudyMarkKind.synthesis,
        }),
      ),
      ['s1', 'y1'],
    );
    expect(ids(studySentenceMarks(study, const {})), isEmpty);
  });

  test('las palabras clave que caen dentro de esas oraciones', () {
    final summary = studySentenceMarks(study, {StudyMarkKind.summary});
    final both = studySentenceMarks(study, {
      StudyMarkKind.summary,
      StudyMarkKind.synthesis,
    });

    expect(ids(studyKeywordMarksWithin(study, summary)), ['k1']);
    // La k3 no está en ninguna oración: no se ve.
    expect(ids(studyKeywordMarksWithin(study, both)), ['k1', 'k2']);
    expect(ids(studyKeywordMarksWithin(study, const [])), isEmpty);
  });
}
