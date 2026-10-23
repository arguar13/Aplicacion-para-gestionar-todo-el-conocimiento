import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_options.dart';
import 'package:sinapsis/features/export/domain/services/document_marks_builder.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';

void main() {
  const content =
      'Primera oración del resumen. Segunda oración de síntesis. '
      'Tercera libre.';
  const first = 'Primera oración del resumen.';
  const second = 'Segunda oración de síntesis.';

  const colors = DocumentMarkColors(
    summary: 0xFF000001,
    synthesis: 0xFF000002,
    keyword: 0xFF000003,
    highlights: {HighlightColor.violet: 0xFF00000A},
    defaultHighlight: 0xFF00000B,
  );

  StudyMark mark(String id, StudyMarkKind kind, String part) {
    final start = content.indexOf(part);
    return StudyMark(
      id: id,
      kind: kind,
      origin: ContentOrigin.ai,
      start: start,
      end: start + part.length,
    );
  }

  // La primera oración está en el resumen y en la síntesis; la segunda, solo
  // en la síntesis. Tres palabras clave: una en cada oración y una suelta.
  final study = DocumentStudy(
    marks: [
      mark('s1', StudyMarkKind.summary, first),
      mark('y1', StudyMarkKind.synthesis, first),
      mark('k1', StudyMarkKind.keyword, 'Primera'),
      mark('y2', StudyMarkKind.synthesis, second),
      mark('k2', StudyMarkKind.keyword, 'síntesis'),
      mark('k3', StudyMarkKind.keyword, 'Tercera'),
    ],
    analyzedUntil: content.length,
    complete: true,
  );

  Highlight highlight(
    String id,
    String part, {
    int minute = 0,
    HighlightColor? color,
    HighlightStyle style = HighlightStyle.fill,
    String? note,
  }) {
    final start = content.indexOf(part);
    return Highlight(
      id: id,
      renditionId: 'r1',
      startOffset: start,
      endOffset: start + part.length,
      excerpt: part,
      createdAt: DateTime(2026, 10, 22, 10, minute),
      color: color,
      style: style,
      note: note,
    );
  }

  List<(int, int, int)> spans(
    MarkedDocumentOptions options, [
    List<Highlight> highlights = const [],
  ]) => [
    for (final m in buildDocumentMarks(
      content: content,
      options: options,
      study: study,
      highlights: highlights,
      colors: colors,
    ))
      (m.start, m.end, m.color),
  ];

  int at(String part) => content.indexOf(part);

  test('sin nada elegido no hay tramos', () {
    expect(spans(const MarkedDocumentOptions()), isEmpty);
  });

  test('el resumen marca solo sus oraciones, con su color y su texto', () {
    final marks = buildDocumentMarks(
      content: content,
      options: const MarkedDocumentOptions(summary: true),
      study: study,
      highlights: const [],
      colors: colors,
    );

    expect(marks, hasLength(1));
    expect(marks.single.start, 0);
    expect(marks.single.end, first.length);
    expect(marks.single.excerpt, first);
    expect(marks.single.color, colors.summary);
    expect(marks.single.style, HighlightStyle.fill);
  });

  test('la síntesis marca las suyas, con el color de la síntesis', () {
    expect(spans(const MarkedDocumentOptions(synthesis: true)), [
      (0, first.length, colors.synthesis),
      (at(second), at(second) + second.length, colors.synthesis),
    ]);
  });

  test('el resumen y la síntesis juntos: la síntesis queda arriba', () {
    // La oración de las dos tiene una marca de cada una: la de la síntesis
    // tiene que venir después para ganar, y no por dónde cae en el texto.
    expect(spans(const MarkedDocumentOptions(summary: true, synthesis: true)), [
      (0, first.length, colors.summary),
      (0, first.length, colors.synthesis),
      (at(second), at(second) + second.length, colors.synthesis),
    ]);
  });

  test('las palabras clave solas son las de las oraciones del resumen y de '
      'la síntesis: la suelta no se marca', () {
    expect(spans(const MarkedDocumentOptions(keywords: true)), [
      (at('Primera'), at('Primera') + 'Primera'.length, colors.keyword),
      (at('síntesis'), at('síntesis') + 'síntesis'.length, colors.keyword),
    ]);
  });

  test('con el resumen, solo las palabras clave de sus oraciones', () {
    expect(spans(const MarkedDocumentOptions(summary: true, keywords: true)), [
      (0, first.length, colors.summary),
      (at('Primera'), at('Primera') + 'Primera'.length, colors.keyword),
    ]);
  });

  test('mis resaltados llevan su color, su estilo y su nota; sin color, el '
      'de siempre', () {
    final marks = buildDocumentMarks(
      content: content,
      options: const MarkedDocumentOptions(myHighlights: true),
      study: study,
      highlights: [
        highlight(
          'h1',
          'Tercera libre.',
          color: HighlightColor.violet,
          style: HighlightStyle.underline,
          note: 'ojo',
        ),
        highlight('h2', 'Segunda', minute: 1),
      ],
      colors: colors,
    );

    expect(marks, hasLength(2));
    expect(marks[0].excerpt, 'Tercera libre.');
    expect(marks[0].color, colors.highlights[HighlightColor.violet]);
    expect(marks[0].style, HighlightStyle.underline);
    expect(marks[0].note, 'ojo');
    expect(marks[1].excerpt, 'Segunda');
    expect(marks[1].color, colors.defaultHighlight);
    expect(marks[1].style, HighlightStyle.fill);
    expect(marks[1].note, isNull);
  });

  test('de dos subrayados que se pisan, el más reciente viene después', () {
    final marks = buildDocumentMarks(
      content: content,
      options: const MarkedDocumentOptions(myHighlights: true),
      study: study,
      highlights: [
        highlight('nuevo', 'oración del', minute: 5),
        highlight('viejo', 'Primera oración', minute: 1),
      ],
      colors: colors,
    );

    expect(marks.map((m) => m.excerpt), ['Primera oración', 'oración del']);
  });

  test('un subrayado que ya no cabe en el texto se deja afuera', () {
    final stale = Highlight(
      id: 'viejo',
      renditionId: 'r1',
      startOffset: content.length - 3,
      endOffset: content.length + 20,
      excerpt: 'texto de otra versión',
      createdAt: DateTime(2026, 10, 22),
    );

    expect(
      spans(const MarkedDocumentOptions(myHighlights: true), [stale]),
      isEmpty,
    );
  });

  test('todo junto, en el orden de las capas: oraciones, mis resaltados y '
      'palabras clave arriba', () {
    final marks = buildDocumentMarks(
      content: content,
      options: const MarkedDocumentOptions(
        summary: true,
        synthesis: true,
        keywords: true,
        myHighlights: true,
      ),
      study: study,
      highlights: [highlight('h1', 'oración del')],
      colors: colors,
    );

    expect(marks.map((m) => m.color), [
      colors.summary,
      colors.synthesis,
      colors.synthesis,
      colors.defaultHighlight,
      colors.keyword,
      colors.keyword,
    ]);
  });

  group('availableMarkedOptions', () {
    test('un documento sin analizar y sin subrayados no tiene nada', () {
      final available = availableMarkedOptions(
        content: content,
        study: DocumentStudy.notStarted,
        highlights: const [],
      );

      expect(available.isEmpty, isTrue);
    });

    test('dice qué de las cuatro cosas hay', () {
      final onlySummary = DocumentStudy(
        marks: [mark('s1', StudyMarkKind.summary, first)],
        analyzedUntil: content.length,
        complete: true,
      );

      expect(
        availableMarkedOptions(
          content: content,
          study: onlySummary,
          highlights: [highlight('h1', 'Tercera')],
        ),
        const MarkedDocumentOptions(summary: true, myHighlights: true),
      );
      expect(
        availableMarkedOptions(
          content: content,
          study: study,
          highlights: const [],
        ),
        const MarkedDocumentOptions(
          summary: true,
          synthesis: true,
          keywords: true,
        ),
      );
    });
  });
}
