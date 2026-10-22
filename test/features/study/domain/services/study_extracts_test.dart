import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_extracts.dart';

void main() {
  const content =
      'La **revolución** industrial cambió todo.\n\n'
      'Hubo [fábricas](https://x.org) nuevas. Nada más.\n\n'
      'El Vapor movía las máquinas.';

  StudyMark mark(StudyMarkKind kind, String text, {int from = 0}) {
    final start = content.indexOf(text, from);
    return StudyMark(
      id: '$kind$start',
      kind: kind,
      origin: ContentOrigin.ai,
      start: start,
      end: start + text.length,
    );
  }

  final study = DocumentStudy(
    marks: [
      mark(StudyMarkKind.summary, 'La **revolución** industrial cambió todo.'),
      mark(StudyMarkKind.keyword, '**revolución**'),
      mark(StudyMarkKind.synthesis, 'Hubo [fábricas](https://x.org) nuevas.'),
      mark(StudyMarkKind.keyword, 'fábricas'),
      mark(StudyMarkKind.summary, 'El Vapor movía las máquinas.'),
      mark(StudyMarkKind.keyword, 'Vapor'),
    ]..sort((a, b) => a.start.compareTo(b.start)),
    analyzedUntil: content.length,
    complete: true,
  );

  group('las oraciones del resumen o de la síntesis', () {
    test('en orden, como texto corrido y sin marcado, con cuántas oraciones '
        'y palabras son', () {
      final summary = studySentencesExtract(
        content,
        study,
        StudyMarkKind.summary,
      );

      expect(
        summary.text,
        'La revolución industrial cambió todo. El Vapor movía las máquinas.',
      );
      expect(summary.sentences, 2);
      expect(summary.words, 10);
    });

    test('un enlace queda en su texto, sin la dirección', () {
      final synthesis = studySentencesExtract(
        content,
        study,
        StudyMarkKind.synthesis,
      );

      expect(synthesis.text, 'Hubo fábricas nuevas.');
      expect(synthesis.sentences, 1);
      expect(synthesis.words, 3);
    });

    test('sin analizar, nada', () {
      final none = studySentencesExtract(
        content,
        DocumentStudy.notStarted,
        StudyMarkKind.summary,
      );

      expect(none, (text: '', sentences: 0, words: 0));
    });
  });

  test('las palabras clave, en el orden en que aparecen y cada una una vez: '
      'con o sin mayúscula o tilde es la misma', () {
    const repeated = 'El vapor. Más vapor. Otro Vapor y una fábrica.';
    StudyMark keyword(String text, int from) {
      final start = repeated.indexOf(text, from);
      return StudyMark(
        id: '$start',
        kind: StudyMarkKind.keyword,
        origin: ContentOrigin.user,
        start: start,
        end: start + text.length,
      );
    }

    final words = studyKeywordsExtract(
      repeated,
      DocumentStudy(
        marks: [
          keyword('vapor', 0),
          keyword('vapor', 10),
          keyword('Vapor', 20),
          keyword('fábrica', 0),
        ],
        analyzedUntil: repeated.length,
        complete: true,
      ),
    );

    expect(words, ['vapor', 'fábrica']);
    expect(studyKeywordsExtract(content, study), [
      'revolución',
      'fábricas',
      'Vapor',
    ]);
  });

  test('el texto sin marcado: un renglón, sin negritas ni enlaces', () {
    expect(
      studyPlainText('Un **dato**\n y [[Roma]], `código` y [x](http://a).'),
      'Un dato y Roma, código y x.',
    );
  });
}
