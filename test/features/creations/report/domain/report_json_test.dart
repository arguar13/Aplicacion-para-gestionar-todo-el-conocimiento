import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_generator.dart';
import 'package:sinapsis/features/creations/report/domain/report_json.dart';

import '../support/sample_reports.dart';

/// El JSON de un informe (F43, paso 10): se lee con tolerancia —lo que
/// devuelve una IA chica no siempre tiene la forma pedida— y se escribe en
/// su forma canónica.
void main() {
  group('lee con tolerancia', () {
    test('la forma pedida, tal cual', () {
      final report = ReportJson.tryDecode({
        'title': 'Éxodo',
        'subtitle': 'De Egipto al Sinaí.',
        'sections': [
          {
            'title': 'Introducción',
            'body': 'El **Éxodo**.\n\n- Uno.\n- Dos.',
            'questions': [
              {
                'question': '¿Quién guía?',
                'options': [
                  {'text': 'Aarón', 'correct': false, 'why': 'Acompaña.'},
                  {'text': 'Moisés', 'correct': true, 'why': 'Él guía.'},
                ],
                'explanation': 'Lo dice el capítulo 3.',
              },
            ],
          },
        ],
        'keywords': ['Moisés', 'moises', 'Sinaí'],
      })!;
      expect(report.title, 'Éxodo');
      expect(report.subtitle, 'De Egipto al Sinaí.');
      final section = report.sections.single;
      expect(section.title, 'Introducción');
      expect(section.body, 'El **Éxodo**.\n\n- Uno.\n- Dos.');
      final question = section.questions.single;
      expect(question.answer, 1);
      expect(question.correct.text, 'Moisés');
      expect(question.options.first.why, 'Acompaña.');
      expect(question.explanation, 'Lo dice el capítulo 3.');
      // Sin repetir sin tildes ni mayúsculas.
      expect(report.keywords, ['Moisés', 'Sinaí']);
    });

    test('claves en castellano, en camelCase y en snake_case', () {
      final report = ReportJson.tryDecode({
        'Título': 'Informe',
        'secciones': [
          {
            'titulo': 'Uno',
            'contenido': 'Texto.',
            'preguntas': [
              {
                'pregunta': '¿Cuál?',
                'opciones': ['A', 'B', 'C'],
                'respuesta_correcta': 'B',
                'explicación': 'Porque sí.',
              },
            ],
          },
        ],
        'palabrasClave': ['Uno'],
      })!;
      expect(report.title, 'Informe');
      expect(report.sections.single.body, 'Texto.');
      expect(report.sections.single.questions.single.answer, 1);
      expect(report.sections.single.questions.single.explanation, 'Porque sí.');
      expect(report.keywords, ['Uno']);
    });

    test('el texto como lista de párrafos o como viñetas sueltas', () {
      final report = ReportJson.tryDecode({
        'sections': [
          {
            'title': 'Ideas',
            'paragraphs': ['Primero.', 'Segundo.'],
            'bullets': ['Una', '- Otra'],
          },
        ],
      })!;
      expect(
        report.sections.single.body,
        'Primero.\n\nSegundo.\n\n- Una\n- Otra',
      );
    });

    test('el glosario como lista, como objeto o como texto suelto', () {
      final list = ReportJson.tryDecode({
        'sections': [
          {
            'title': 'A',
            'terms': [
              {'término': 'Alianza', 'definición': 'El pacto.'},
              'Arca: el cofre.',
              '**Aarón** — el hermano.',
              {'term': 'alianza', 'definition': 'Repetida.'},
            ],
          },
        ],
      })!;
      expect(list.sections.single.entries, const [
        ReportEntry(term: 'Alianza', definition: 'El pacto.'),
        ReportEntry(term: 'Arca', definition: 'el cofre.'),
        ReportEntry(term: 'Aarón', definition: 'el hermano.'),
      ]);
      final map = ReportJson.tryDecode({
        'sections': [
          {
            'title': 'M',
            'glosario': {'Maná': 'El pan.', 'Moisés': 'El guía.'},
          },
        ],
      })!;
      expect(map.sections.single.entries.map((e) => e.term), [
        'Maná',
        'Moisés',
      ]);
    });

    test('la correcta, dicha de todas las maneras', () {
      ReportQuestion ask(Object? answer, {List<Object?>? options}) =>
          ReportJson.decodeQuestion({
            'question': '¿Cuál?',
            'options': options ?? ['Uno', 'Dos', 'Tres', 'Cuatro'],
            'answer': answer,
          })!;
      expect(ask(2).answer, 2, reason: 'desde 0, como pide el esquema');
      expect(ask(4).answer, 3, reason: 'igual a la cantidad: desde 1');
      expect(ask('1').answer, 1);
      expect(ask('C').answer, 2);
      expect(ask('d)').answer, 3);
      expect(ask('Opción B').answer, 1);
      expect(ask('tres').answer, 2, reason: 'por el texto, sin mayúsculas');
      expect(ask(['Dos']).answer, 1);
      expect(ask({'text': 'Cuatro'}).answer, 3);
      // Una opción repetida sale, y el número cuenta sobre lo que escribió.
      final repeated = ask(3, options: ['Uno', 'uno', 'Dos', 'Tres']);
      expect(repeated.options.map((o) => o.text), ['Uno', 'Dos', 'Tres']);
      expect(repeated.correct.text, 'Tres');
    });

    test('los porqués, también en una lista aparte', () {
      final question = ReportJson.decodeQuestion({
        'question': '¿Cuál?',
        'options': ['Uno', 'Dos'],
        'answer': 0,
        'why_not': null,
        'explicaciones': ['Es la uno.', 'No es la dos.'],
      })!;
      expect(question.options.map((o) => o.why), [
        'Es la uno.',
        'No es la dos.',
      ]);
    });

    test('una pregunta incompleta se deja afuera, sin tumbar el informe', () {
      final report = ReportJson.tryDecode({
        'sections': [
          {
            'title': 'Uno',
            'body': 'Texto.',
            'questions': [
              {'question': '¿Sin opciones?'},
              {
                'question': '¿Una sola?',
                'options': ['Sí'],
                'answer': 0,
              },
              {
                'question': '¿Sin correcta?',
                'options': ['Sí', 'No'],
              },
              {
                'question': '¿Fuera de rango?',
                'options': ['Sí', 'No'],
                'answer': 7,
              },
              {
                'options': ['Sí', 'No'],
                'answer': 0,
              },
              {
                'question': '¿Esta sí?',
                'options': ['Sí', 'No'],
                'answer': 0,
              },
            ],
          },
        ],
      })!;
      expect(report.sections.single.questions.map((q) => q.question), [
        '¿Esta sí?',
      ]);
    });

    test('a lo sumo tres preguntas por sección y cinco opciones', () {
      final report = ReportJson.tryDecode({
        'sections': [
          {
            'title': 'Uno',
            'body': 'Texto.',
            'questions': [
              for (var i = 0; i < 6; i++)
                {
                  'question': '¿$i?',
                  'options': [for (var o = 0; o < 8; o++) 'Opción $o'],
                  'answer': 0,
                },
            ],
          },
        ],
      })!;
      final questions = report.sections.single.questions;
      expect(questions, hasLength(ReportLimits.questions));
      expect(questions.first.options, hasLength(ReportLimits.options));
    });

    test('un texto desbocado se corta en la última palabra, con «…»', () {
      final report = ReportJson.tryDecode({
        'title': 'palabra ' * 100,
        'sections': [
          {'title': 'Uno', 'body': 'Texto.'},
        ],
      })!;
      expect(report.title.length, lessThanOrEqualTo(ReportLimits.title));
      expect(report.title, endsWith('palabra…'));
    });

    test('una lista suelta de secciones, envuelto o como texto', () {
      expect(
        ReportJson.tryDecode([
          {'title': 'Uno', 'body': 'Texto.'},
        ])!.sections.single.title,
        'Uno',
      );
      expect(
        ReportJson.tryDecode({
          'informe': {
            'título': 'Envuelto',
            'secciones': [
              {'título': 'Uno', 'texto': 'Texto.'},
            ],
          },
        })!.title,
        'Envuelto',
      );
      expect(
        ReportJson.tryDecode(
          '¡Claro! Acá va:\n```json\n{"title": "T", "sections": '
          '[{"title": "Uno", "body": "Texto.",}]}\n```',
        )!.title,
        'T',
      );
    });

    test('sin ninguna sección con algo para leer, no hay informe', () {
      expect(ReportJson.tryDecode(null), isNull);
      expect(ReportJson.tryDecode('no es JSON'), isNull);
      expect(ReportJson.tryDecode({'title': 'Solo título'}), isNull);
      expect(
        ReportJson.tryDecode({
          'sections': [
            {'title': 'Vacía'},
            {
              'title': 'Solo preguntas',
              'questions': [
                {
                  'question': '¿?',
                  'options': ['a', 'b'],
                  'answer': 0,
                },
              ],
            },
          ],
        }),
        isNull,
        reason: 'unas preguntas sin nada que leer no son un informe',
      );
      expect(ReportJson.decode(null), const Report(title: ''));
    });

    test('lo que contestó la IA: un motivo corto si no se puede leer', () {
      expect(
        () => parseReportReply({'title': 'Nada'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'motivo',
            contains('sections'),
          ),
        ),
      );
      expect(
        parseReportReply({
          'sections': [
            {'title': 'Uno', 'body': 'Texto.'},
          ],
        }).sections,
        hasLength(1),
      );
    });
  });

  test('se escribe en su forma canónica y se vuelve a leer igual', () {
    final report = sampleReport();
    final encoded = ReportJson.encodeString(report);
    expect(ReportJson.decode(encoded), report);
    expect(ReportJson.decode(jsonDecode(encoded)), report);
    expect(
      ReportJson.decode(ReportJson.encodeString(sampleGlossary())),
      sampleGlossary(),
    );
    final json = ReportJson.encode(report);
    final question =
        ((json['sections']! as List).first as Map)['questions'] as List;
    expect((question.first as Map)['answer'], 0);
    expect(((question.first as Map)['options'] as List).first, {
      'text': 'Moisés',
      'why': 'Es quien recibe el llamado.',
    });
  });
}
