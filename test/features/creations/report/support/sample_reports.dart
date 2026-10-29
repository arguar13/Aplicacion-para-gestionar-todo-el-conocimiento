import 'package:sinapsis/features/creations/report/domain/report.dart';

/// Un informe interactivo de ejemplo, sobre el Éxodo: tres secciones con
/// párrafos, viñetas, una lista numerada, un subtítulo, una cita y negritas,
/// y dos preguntas en la primera y una en la segunda.
Report sampleReport() => const Report(
  title: 'Éxodo: liberación y alianza',
  subtitle: 'De la esclavitud en Egipto a la Alianza del Sinaí.',
  keywords: ['Sinaí', 'Alianza'],
  sections: [
    ReportSection(
      title: 'Introducción',
      body:
          'El libro del **Éxodo** cuenta cómo Moisés guía al pueblo fuera de '
          'Egipto.\n\n'
          '- La esclavitud y el llamado.\n'
          '- Las plagas y la salida.\n'
          '  - El paso del mar.\n'
          '- La llegada al Sinaí.',
      questions: [
        ReportQuestion(
          question: '¿Quién guía al pueblo fuera de Egipto?',
          options: [
            ReportOption(text: 'Moisés', why: 'Es quien recibe el llamado.'),
            ReportOption(text: 'Aarón', why: 'Acompaña, pero no guía.'),
            ReportOption(text: 'Josué', why: 'Viene después.'),
            ReportOption(text: 'El Faraón', why: 'Es quien los retiene.'),
          ],
          answer: 0,
          explanation: 'Moisés recibe el llamado en la zarza ardiente.',
        ),
        ReportQuestion(
          question: '¿A dónde llega el pueblo?',
          options: [
            ReportOption(text: 'Al Sinaí'),
            ReportOption(text: 'A Babilonia'),
            ReportOption(text: 'A Roma'),
          ],
          answer: 0,
          explanation: 'En el Sinaí se sella la Alianza.',
        ),
      ],
    ),
    ReportSection(
      title: 'Moisés y el Faraón',
      body:
          '### Las plagas\n\n'
          '1. El agua en sangre.\n'
          '2. Las ranas.\n\n'
          '> Dejá ir a mi pueblo.\n\n'
          'El *Faraón* endurece su corazón una y otra vez.',
      questions: [
        ReportQuestion(
          question: '¿Qué pide Moisés al Faraón?',
          options: [
            ReportOption(text: 'Que deje ir al pueblo'),
            ReportOption(text: 'Oro y plata', why: 'No es lo que pide.'),
          ],
          answer: 0,
        ),
      ],
    ),
    ReportSection(
      title: 'Conclusión',
      body: 'La **Alianza** del Sinaí da forma al pueblo.',
    ),
  ],
);

/// Un glosario de ejemplo, ya en orden y por letra.
Report sampleGlossary() => const Report(
  title: 'Glosario del Éxodo',
  sections: [
    ReportSection(
      title: 'A',
      entries: [
        ReportEntry(term: 'Alianza', definition: 'El pacto del Sinaí.'),
      ],
    ),
    ReportSection(
      title: 'M',
      entries: [
        ReportEntry(term: 'Maná', definition: 'El pan del desierto.'),
        ReportEntry(term: 'Moisés', definition: 'Quien guía al pueblo.'),
      ],
    ),
  ],
);
