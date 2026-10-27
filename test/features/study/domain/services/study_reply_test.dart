import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// El pedido de una parte y la lectura de lo que contesta el modelo (F36).
void main() {
  const content =
      'La revolución industrial empezó en Inglaterra. '
      'Las fábricas usaban máquinas de vapor. '
      'El trabajo infantil era común. '
      'Hoy se estudia en la escuela.';
  final part = splitStudySentences(content, markdown: false);

  String textOf(StudySentence s) => content.substring(s.start, s.end);
  String wordOf(StudyWord w) => content.substring(w.start, w.end);

  group('el pedido', () {
    test('las oraciones numeradas desde 1, una por renglón', () {
      expect(
        buildStudyPrompt(content, part),
        'Oraciones del documento:\n'
        '[1] La revolución industrial empezó en Inglaterra.\n'
        '[2] Las fábricas usaban máquinas de vapor.\n'
        '[3] El trabajo infantil era común.\n'
        '[4] Hoy se estudia en la escuela.\n'
        '\nEscribí la línea CLAVE de cada una de las 4 oraciones, de la 1 a la '
        '4, cada una con al menos una palabra.',
      );
    });

    test('sin marcado de Markdown ni saltos de línea', () {
      const md = 'Ver **[[Vapor]]** y [la nota](https://x.y)\nde `hoy`.';
      final sentences = splitStudySentences(md, markdown: true);
      expect(
        buildStudyPrompt(md, sentences),
        'Oraciones del documento:\n[1] Ver Vapor y la nota de hoy.\n'
        '\nEscribí la línea CLAVE de la oración 1, con al menos una palabra.',
      );
    });
  });

  group('la respuesta', () {
    test('el resumen, la síntesis y las palabras de cada oración', () {
      final marks = parseStudyReply(
        'RESUMEN: 1, 2, 3\n'
        'SINTESIS: 1\n'
        'CLAVE 1: revolución, industrial, Inglaterra\n'
        'CLAVE 2: fábricas | vapor\n'
        'CLAVE 3: trabajo infantil',
        content: content,
        part: part,
      )!;

      expect(marks.summary.map(textOf), [
        'La revolución industrial empezó en Inglaterra.',
        'Las fábricas usaban máquinas de vapor.',
        'El trabajo infantil era común.',
      ]);
      expect(marks.synthesis.map(textOf), [
        'La revolución industrial empezó en Inglaterra.',
      ]);
      expect(marks.keywords.map(wordOf), [
        'revolución',
        'industrial',
        'Inglaterra',
        'fábricas',
        'vapor',
        'trabajo',
        'infantil',
      ]);
    });

    test('con lo que un modelo chico cambia: acentos, negritas, viñetas, '
        'rangos', () {
      final marks = parseStudyReply(
        'Claro, acá va:\n'
        '- **Resumen:** 1-3\n'
        '* Síntesis = [2]\n'
        '**Clave [2]:** Vapor; FÁBRICAS',
        content: content,
        part: part,
      )!;

      expect(marks.summary, [part[0], part[1], part[2]]);
      expect(marks.synthesis, [part[1]]);
      expect(marks.keywords.map(wordOf), ['vapor', 'fábricas']);
    });

    test('un número fuera de la parte o repetido no cuenta', () {
      final marks = parseStudyReply(
        'RESUMEN: 0, 2, 2, 9, 4\nSINTESIS: 7',
        content: content,
        part: part,
      )!;

      expect(marks.summary, [part[1], part[3]]);
      expect(marks.synthesis, isEmpty);
    });

    test('un rango al revés no cuenta', () {
      final marks = parseStudyReply(
        'RESUMEN: 3-1\nSINTESIS: 2',
        content: content,
        part: part,
      )!;
      expect(marks.summary, isEmpty);
      expect(marks.synthesis, [part[1]]);
    });

    test('«ninguna» es una respuesta en el formato, sin nada marcado', () {
      final marks = parseStudyReply(
        'RESUMEN: ninguna\nSINTESIS: ninguna',
        content: content,
        part: part,
      )!;
      expect(marks.summary, isEmpty);
      expect(marks.synthesis, isEmpty);
      expect(marks.keywords, isEmpty);
    });

    test('sin línea de resumen ni de síntesis no hay respuesta: null', () {
      expect(
        parseStudyReply(
          'La revolución industrial fue muy importante.',
          content: content,
          part: part,
        ),
        isNull,
      );
      expect(
        parseStudyReply('CLAVE 1: revolución', content: content, part: part),
        isNull,
      );
    });

    test('solo la síntesis, sin resumen, ya es una respuesta', () {
      final marks = parseStudyReply(
        'SINTESIS: 1',
        content: content,
        part: part,
      )!;
      expect(marks.summary, isEmpty);
      expect(marks.synthesis, [part[0]]);
    });

    test('las palabras clave van en todas las oraciones, estén o no en el '
        'resumen o la síntesis, en el orden del texto (F39)', () {
      final marks = parseStudyReply(
        'RESUMEN: 1\nSINTESIS: 1\n'
        'CLAVE 4: escuela\n'
        'CLAVE 1: Inglaterra\n'
        'CLAVE 2: vapor\n'
        'CLAVE 3: trabajo',
        content: content,
        part: part,
      )!;
      expect(marks.keywords.map(wordOf), [
        'Inglaterra',
        'vapor',
        'trabajo',
        'escuela',
      ]);
    });

    test('las palabras de una oración que no es de la parte no cuentan', () {
      final marks = parseStudyReply(
        'RESUMEN: ninguna\nSINTESIS: ninguna\n'
        'CLAVE 0: revolución\n'
        'CLAVE 5: escuela\n'
        'CLAVE 4: escuela',
        content: content,
        part: part,
      )!;
      expect(marks.keywords.map(wordOf), ['escuela']);
    });

    test('una palabra que no está en su oración no cuenta', () {
      final marks = parseStudyReply(
        'RESUMEN: 2\nSINTESIS: 2\nCLAVE 2: carbón, vapor, Inglaterra',
        content: content,
        part: part,
      )!;
      expect(marks.keywords.map(wordOf), ['vapor']);
    });

    test('hasta 4 palabras por oración, aunque proponga más', () {
      final marks = parseStudyReply(
        'RESUMEN: 1\nSINTESIS: 1\n'
        'CLAVE 1: revolución, industrial, empezó, Inglaterra\n'
        'CLAVE 1: revolución',
        content: content,
        part: part,
      )!;
      expect(marks.keywords, hasLength(kMaxKeywordsPerSentence));
    });

    test(
      'las palabras de una oración que está en los dos se toman una vez',
      () {
        final marks = parseStudyReply(
          'RESUMEN: 2\nSINTESIS: 2\nCLAVE 2: vapor',
          content: content,
          part: part,
        )!;
        expect(marks.keywords.map(wordOf), ['vapor']);
      },
    );
  });

  group('las partes', () {
    final sentences = [
      for (var i = 0; i < 10; i++) StudySentence(i * 20, i * 20 + 13),
    ];

    test('entran las que caben en el presupuesto, cada una con lo que '
        'contesta por ella', () {
      // Cada una ocupa 13 + 7 de su número y su renglón + 55 de su línea
      // CLAVE en la respuesta = 75.
      expect(studyPartEnd(sentences, 0, charBudget: 225), 3);
      expect(studyPartEnd(sentences, 0, charBudget: 224), 2);
      expect(studyPartEnd(sentences, 3, charBudget: 225), 6);
      expect(studyPartEnd(sentences, 9, charBudget: 225), 10);
    });

    test('al menos una, aunque no quepa', () {
      expect(studyPartEnd(sentences, 4, charBudget: 5), 5);
      expect(studyPartEnd(sentences, 4, charBudget: 74), 5);
    });

    test('hasta el tope de oraciones por parte', () {
      final many = [
        for (var i = 0; i < 300; i++) StudySentence(i * 3, i * 3 + 2),
      ];
      expect(
        studyPartEnd(many, 0, charBudget: 1 << 20),
        kMaxStudyPartSentences,
      );
    });

    test('lo que puede escribir crece con la parte —una línea CLAVE por '
        'oración—, con piso y techo', () {
      expect(studyReplyTokens(1), 192);
      expect(studyReplyTokens(60), 60 * 22 + 96);
      expect(studyReplyTokens(kMaxStudyPartSentences), 2736);
      expect(studyReplyTokens(500), 3072);
    });
  });
}
