import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';

/// Lo que la página guardada recibe de lo que se ve en la app (F36, F39).
void main() {
  Map<String, Object?> state(StudyView view) =>
      jsonDecode(
            RegExp(
              r'set\((.*)\);$',
            ).firstMatch(webPageStudyState(view))!.group(1)!,
          )
          as Map<String, Object?>;

  test('el resumen y la síntesis, cada uno por su lado: juntos, de a uno o '
      'ninguno', () {
    expect(state(const StudyView(summary: true, synthesis: true)), {
      'summary': true,
      'synthesis': true,
      'keywords': false,
      'picking': false,
    });
    expect(state(const StudyView(synthesis: true)), {
      'summary': false,
      'synthesis': true,
      'keywords': false,
      'picking': false,
    });
    expect(state(const StudyView()), {
      'summary': false,
      'synthesis': false,
      'keywords': false,
      'picking': false,
    });
  });

  test('eligiendo palabras clave, se ven aunque no estén prendidas, y tocar '
      'elige', () {
    expect(state(const StudyView(pick: StudyMarkKind.keyword)), {
      'summary': false,
      'synthesis': false,
      'keywords': true,
      'picking': true,
    });
  });

  test('eligiendo el resumen a mano, tocar elige sin prender las palabras', () {
    expect(state(const StudyView(summary: true, pick: StudyMarkKind.summary)), {
      'summary': true,
      'synthesis': false,
      'keywords': false,
      'picking': true,
    });
  });
}
