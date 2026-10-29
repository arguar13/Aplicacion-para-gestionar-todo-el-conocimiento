import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_normalize.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';

import '../support/sample_reports.dart';

ReportQuestion _ask(String question, String correct) => ReportQuestion(
  question: question,
  options: [
    ReportOption(text: correct),
    const ReportOption(text: 'Otra cosa'),
  ],
  answer: 0,
);

/// Lo que la app arregla de lo que devolvió la IA antes de guardarlo (F43,
/// paso 10): sin secciones vacías y el glosario en orden alfabético de
/// verdad.
void main() {
  test('las secciones sin nada salen; lo demás queda igual', () {
    final report = sampleReport().copyWith(
      sections: [
        ...sampleReport().sections,
        const ReportSection(title: 'Vacía'),
      ],
    );
    expect(normalizeReport(report, ReportTemplate.studyGuide), sampleReport());
  });

  test(
    'el glosario: todos los términos, sin repetir, en orden y por letra',
    () {
      // Como lo deja unir las partes: desordenado, repetido y con una letra
      // partida en dos.
      const merged = Report(
        title: 'Glosario',
        sections: [
          ReportSection(
            title: 'M',
            entries: [
              ReportEntry(term: 'Moisés', definition: 'El guía.'),
              ReportEntry(term: 'Éxodo', definition: 'La salida.'),
            ],
          ),
          ReportSection(
            title: 'A',
            entries: [
              ReportEntry(term: 'alianza', definition: 'El pacto.'),
              ReportEntry(term: 'Maná', definition: 'El pan.'),
              ReportEntry(term: 'Moisés', definition: 'Repetido.'),
            ],
          ),
          ReportSection(
            title: 'Números',
            entries: [
              ReportEntry(term: '10 mandamientos', definition: 'La ley.'),
            ],
          ),
        ],
      );
      final glossary = normalizeReport(merged, ReportTemplate.glossary);
      expect(glossary.sections.map((s) => s.title), ['#', 'A', 'E', 'M']);
      expect(glossary.sections.last.entries, const [
        ReportEntry(term: 'Maná', definition: 'El pan.'),
        ReportEntry(term: 'Moisés', definition: 'El guía.'),
      ]);
      expect(glossary.sections[1].entries.single.term, 'alianza');
      expect(glossary.sections[2].entries.single.term, 'Éxodo');
    },
  );

  test('un glosario escrito como viñetas también se ordena', () {
    const bullets = Report(
      title: 'Glosario',
      sections: [
        ReportSection(
          title: 'Términos',
          body: '- **Sinaí**: el monte.\n- **Arca** — el cofre.',
        ),
      ],
    );
    final glossary = normalizeReport(bullets, ReportTemplate.glossary);
    expect(glossary.sections.map((s) => s.title), ['A', 'S']);
    expect(
      glossary.sections.first.entries.single,
      const ReportEntry(term: 'Arca', definition: 'el cofre.'),
    );
  });

  test('una introducción en prosa queda arriba, como está', () {
    const report = Report(
      title: 'Glosario',
      sections: [
        ReportSection(title: 'Cómo leerlo', body: 'Los términos del Éxodo.'),
        ReportSection(
          title: 'M',
          entries: [ReportEntry(term: 'Moisés', definition: 'El guía.')],
        ),
      ],
    );
    final glossary = normalizeReport(report, ReportTemplate.glossary);
    expect(glossary.sections.map((s) => s.title), ['Cómo leerlo', 'M']);
  });

  test('cada pregunta va a la letra del término del que habla', () {
    final report = Report(
      title: 'Glosario',
      sections: [
        ReportSection(
          title: 'A',
          entries: const [
            ReportEntry(term: 'Alianza', definition: 'El pacto.'),
            ReportEntry(term: 'Maná', definition: 'El pan.'),
          ],
          questions: [
            _ask('¿Qué es el maná?', 'El pan del desierto'),
            _ask('¿Qué se sella en el Sinaí?', 'La alianza'),
            _ask('¿Qué es la Pascua?', 'Una fiesta'),
          ],
        ),
      ],
    );
    final glossary = normalizeReport(report, ReportTemplate.glossary);
    final byLetter = {
      for (final s in glossary.sections)
        s.title: [for (final q in s.questions) q.question],
    };
    expect(byLetter['M'], ['¿Qué es el maná?']);
    // La que no nombra ningún término queda en la letra donde la puso la IA.
    expect(byLetter['A'], ['¿Qué se sella en el Sinaí?', '¿Qué es la Pascua?']);
  });

  test('las otras plantillas no se reordenan', () {
    final glossaryLike = sampleGlossary().copyWith(
      sections: sampleGlossary().sections.reversed.toList(),
    );
    expect(
      normalizeReport(glossaryLike, ReportTemplate.learningSummary),
      glossaryLike,
    );
  });
}
