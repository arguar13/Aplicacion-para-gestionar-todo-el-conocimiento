import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';

/// Lo que la página guardada recibe de lo que se ve en la app (F36, F39).
void main() {
  StudyMark mark(String id, StudyMarkKind kind, int start, int end) =>
      StudyMark(
        id: id,
        kind: kind,
        origin: ContentOrigin.ai,
        start: start,
        end: end,
      );

  final marks = [
    mark('s1', StudyMarkKind.summary, 0, 20),
    mark('k1', StudyMarkKind.keyword, 3, 9),
    mark('y1', StudyMarkKind.synthesis, 21, 40),
    mark('k2', StudyMarkKind.keyword, 30, 35),
  ];

  Map<String, Object?> state(StudyView view) =>
      jsonDecode(
            RegExp(
              r'set\((.*)\);$',
            ).firstMatch(webPageStudyState(view, marks))!.group(1)!,
          )
          as Map<String, Object?>;

  test('el resumen y la síntesis, cada uno por su lado: juntos, de a uno o '
      'ninguno', () {
    expect(state(const StudyView(summary: true, synthesis: true)), {
      'summary': true,
      'synthesis': true,
      'keywords': false,
      'picking': false,
      'kw': [3, 30],
    });
    expect(state(const StudyView(synthesis: true)), {
      'summary': false,
      'synthesis': true,
      'keywords': false,
      'picking': false,
      'kw': [3, 30],
    });
    expect(state(const StudyView()), {
      'summary': false,
      'synthesis': false,
      'keywords': false,
      'picking': false,
      'kw': [3, 30],
    });
  });

  test('eligiendo palabras clave, se ven aunque no estén prendidas, y tocar '
      'elige', () {
    expect(state(const StudyView(pick: StudyMarkKind.keyword)), {
      'summary': false,
      'synthesis': false,
      'keywords': true,
      'picking': true,
      'kw': [3, 30],
    });
  });
}
