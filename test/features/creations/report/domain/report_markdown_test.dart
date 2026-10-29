import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_markdown.dart';
import 'package:sinapsis/features/creations/report/domain/report_order.dart';

import '../support/sample_reports.dart';

/// El informe en Markdown (F43, paso 10): exacto, con las palabras clave en
/// negrita, las preguntas con sus opciones y las respuestas al final.
void main() {
  const labels = ReportExportLabels(
    kicker: 'Resumen de aprendizaje · Interactivo',
    sources: 'Fuentes: Éxodo',
  );

  test('el interactivo, entero y exacto', () {
    final report = sampleReport();
    // Las letras de la correcta, en el orden fijo de las opciones.
    String letterOf(ReportQuestion q) =>
        reportOptionLetter(reportOptionOrder(q).indexOf(q.correct));
    String options(ReportQuestion q) => [
      for (final (i, o) in reportOptionOrder(q).indexed)
        '   - ${reportOptionLetter(i)}. ${o.text}',
    ].join('\n');
    final q1 = report.sections[0].questions[0];
    final q2 = report.sections[0].questions[1];
    final q3 = report.sections[1].questions[0];

    expect(
      reportToMarkdown(
        report,
        keywords: ReportKeywords(const ['Moisés', 'Sinaí']),
        labels: labels,
      ),
      '*Resumen de aprendizaje · Interactivo*\n'
      '\n'
      '# Éxodo: liberación y alianza\n'
      '\n'
      '*De la esclavitud en Egipto a la Alianza del Sinaí.*\n'
      '\n'
      'Fuentes: Éxodo\n'
      '\n'
      '## Introducción\n'
      '\n'
      'El libro del **Éxodo** cuenta cómo **Moisés** guía al pueblo fuera de '
      'Egipto.\n'
      '\n'
      '- La esclavitud y el llamado.\n'
      '- Las plagas y la salida.\n'
      '  - El paso del mar.\n'
      '- La llegada al **Sinaí**.\n'
      '\n'
      '### Para probarte\n'
      '\n'
      '1. ¿Quién guía al pueblo fuera de Egipto?\n'
      '${options(q1)}\n'
      '\n'
      '2. ¿A dónde llega el pueblo?\n'
      '${options(q2)}\n'
      '\n'
      '## Moisés y el Faraón\n'
      '\n'
      '### Las plagas\n'
      '\n'
      '1. El agua en sangre.\n'
      '2. Las ranas.\n'
      '\n'
      '> Dejá ir a mi pueblo.\n'
      '\n'
      'El *Faraón* endurece su corazón una y otra vez.\n'
      '\n'
      '### Para probarte\n'
      '\n'
      // Las preguntas, sin rosa ni negrita: no dan pistas.
      '1. ¿Qué pide Moisés al Faraón?\n'
      '${options(q3)}\n'
      '\n'
      '## Conclusión\n'
      '\n'
      'La **Alianza** del **Sinaí** da forma al pueblo.\n'
      '\n'
      '## Respuestas\n'
      '\n'
      '### Introducción\n'
      '\n'
      '1. **${letterOf(q1)}. Moisés** — Moisés recibe el llamado en la zarza '
      'ardiente.\n'
      '2. **${letterOf(q2)}. Al Sinaí** — En el Sinaí se sella la Alianza.\n'
      '\n'
      '### Moisés y el Faraón\n'
      '\n'
      '1. **${letterOf(q3)}. Que deje ir al pueblo**\n',
    );
  });

  test('como documento: sin preguntas ni respuestas', () {
    final markdown = reportToMarkdown(sampleReport(), interactive: false);
    expect(markdown, isNot(contains('Para probarte')));
    expect(markdown, isNot(contains('Respuestas')));
    expect(markdown, startsWith('# Éxodo: liberación y alianza\n'));
  });

  test('el glosario como viñetas «**Término**: definición»', () {
    expect(
      reportToMarkdown(sampleGlossary()),
      '# Glosario del Éxodo\n'
      '\n'
      '## A\n'
      '\n'
      '- **Alianza**: El pacto del Sinaí.\n'
      '\n'
      '## M\n'
      '\n'
      '- **Maná**: El pan del desierto.\n'
      '- **Moisés**: Quien guía al pueblo.\n',
    );
  });

  test('lo que en Markdown tiene otro sentido va escapado', () {
    const report = Report(
      title: 'C*_`',
      sections: [ReportSection(title: '', body: 'Un 5 * 3 y snake_case.')],
    );
    expect(
      reportToMarkdown(report),
      '# C\\*\\_\\`\n'
      '\n'
      '## Sección 1\n'
      '\n'
      'Un 5 \\* 3 y snake\\_case.\n',
    );
  });
}
