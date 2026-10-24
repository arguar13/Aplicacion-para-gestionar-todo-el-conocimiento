import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';

void main() {
  const content =
      '# Título\n\n'
      'La **revolución** industrial cambió todo. Nada más.\n\n'
      'Hubo [fábricas](https://x.org) nuevas. El vapor movía las máquinas.\n'
      '- Una viñeta con vapor.\n'
      'En 1850 pasó. 3. Luego otra cosa.';

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

  DocumentStudy studyOf(List<StudyMark> marks) => DocumentStudy(
    marks: [...marks]..sort((a, b) => a.start.compareTo(b.start)),
    analyzedUntil: content.length,
    complete: true,
  );

  Map<ReadScope, List<ReadableSegment>> scopesOf(DocumentStudy study) =>
      studyReadScopes(
        sourceKey: 'r1',
        content: content,
        study: study,
        markdown: true,
      );

  List<String> visible(List<ReadableSegment> segments) => [
    for (final segment in segments)
      content.substring(segment.start, segment.end),
  ];

  group('studyReadScopes', () {
    final study = studyOf([
      mark(StudyMarkKind.summary, 'La **revolución** industrial cambió todo.'),
      mark(StudyMarkKind.summary, 'El vapor movía las máquinas.'),
      mark(StudyMarkKind.synthesis, 'Hubo [fábricas](https://x.org) nuevas.'),
      mark(StudyMarkKind.keyword, '**revolución**'),
      mark(StudyMarkKind.keyword, 'fábricas'),
      mark(StudyMarkKind.keyword, 'vapor', from: 100),
    ]);

    test('el resumen: sus oraciones, en el orden del texto, con sus '
        'posiciones en el texto entero', () {
      final summary = scopesOf(study)[ReadScope.summary]!;

      expect(visible(summary), [
        'La **revolución** industrial cambió todo.',
        'El vapor movía las máquinas.',
      ]);
      expect(summary.map((s) => s.spoken), [
        'La revolución industrial cambió todo.',
        'El vapor movía las máquinas.',
      ]);
      expect(summary.every((s) => s.sourceKey == 'r1'), isTrue);
    });

    test('la síntesis es otra lista, sin el resumen', () {
      final synthesis = scopesOf(study)[ReadScope.synthesis]!;

      expect(synthesis.map((s) => s.spoken), ['Hubo fábricas nuevas.']);
      expect(visible(synthesis), ['Hubo [fábricas](https://x.org) nuevas.']);
    });

    test('las palabras clave: una tras otra, en el orden del texto', () {
      final keywords = scopesOf(study)[ReadScope.keywords]!;

      expect(keywords.map((s) => s.spoken), [
        'revolución',
        'fábricas',
        'vapor',
      ]);
      expect(visible(keywords), ['**revolución**', 'fábricas', 'vapor']);
      expect(
        keywords.map((s) => s.start).toList(),
        ([...keywords.map((s) => s.start)]..sort()),
      );
    });

    test('una palabra clave repetida se lee una vez: la de la primera '
        'aparición, como la etiqueta de la tarjeta', () {
      final repeated = studyOf([
        mark(StudyMarkKind.keyword, 'vapor'),
        mark(StudyMarkKind.keyword, 'vapor', from: content.indexOf('viñeta')),
      ]);

      final keywords = scopesOf(repeated)[ReadScope.keywords]!;

      expect(keywords, hasLength(1));
      expect(keywords.single.start, content.indexOf('vapor'));
    });

    test('sin nada estudiado, las tres capas están y vacías: el '
        'reproductor las ofrece apagadas', () {
      final scopes = scopesOf(DocumentStudy.notStarted);

      expect(scopes.keys, [
        ReadScope.summary,
        ReadScope.synthesis,
        ReadScope.keywords,
      ]);
      expect(scopes.values.every((segments) => segments.isEmpty), isTrue);
    });

    test('una oración que empieza una línea pierde su viñeta; una que '
        'empieza a mitad de línea no pierde nada', () {
      final scopes = scopesOf(
        studyOf([
          mark(StudyMarkKind.summary, '- Una viñeta con vapor.'),
          mark(StudyMarkKind.summary, '3. Luego otra cosa.'),
          mark(StudyMarkKind.synthesis, '# Título'),
        ]),
      );

      expect(scopes[ReadScope.summary]!.map((s) => s.spoken), [
        'Una viñeta con vapor.',
        '3. Luego otra cosa.',
      ]);
      expect(scopes[ReadScope.synthesis]!.map((s) => s.spoken), ['Título']);
    });

    test('una oración muy larga se lee de a tramos, todos adentro de ella', () {
      final long = '${List.filled(30, 'Una frase larga sin punto').join(' ')}.';
      final raw = 'Antes. $long Después.';
      final start = raw.indexOf(long);

      final summary = studyReadScopes(
        sourceKey: 'r1',
        content: raw,
        study: DocumentStudy(
          marks: [
            StudyMark(
              id: 'l',
              kind: StudyMarkKind.summary,
              origin: ContentOrigin.ai,
              start: start,
              end: start + long.length,
            ),
          ],
          analyzedUntil: raw.length,
          complete: true,
        ),
        markdown: false,
      )[ReadScope.summary]!;

      expect(summary.length, greaterThan(1));
      expect(summary.first.start, start);
      expect(summary.last.end, start + long.length);
      expect(summary.every((s) => s.start >= start), isTrue);
    });
  });

  group('studyReadableDocument', () {
    const text = (
      itemId: 'i1',
      renditionId: 'r1',
      content: 'Una línea.\nOtra línea.',
      markdown: false,
    );
    final scopes = {
      ReadScope.summary: [
        const ReadableSegment(
          sourceKey: 'r1',
          start: 0,
          end: 10,
          spoken: 'Una línea.',
        ),
      ],
      ReadScope.synthesis: const <ReadableSegment>[],
      ReadScope.keywords: const <ReadableSegment>[],
    };

    test('el texto entero y lo estudiado, con el id de la tarjeta', () {
      final document = studyReadableDocument(
        text: text,
        title: 'Un libro',
        scopes: scopes,
      );

      expect(document.id, 'study:r1');
      expect(document.id, studyReadableId('r1'));
      expect(document.title, 'Un libro');
      expect(document.segments.map((s) => s.spoken), [
        'Una línea.',
        'Otra línea.',
      ]);
      expect(document.segments.every((s) => s.sourceKey == 'r1'), isTrue);
      expect(document.scopes, scopes);
    });

    test('con el texto en su propio audio, solo lo estudiado', () {
      final document = studyReadableDocument(
        text: text,
        title: 'Un audio',
        scopes: scopes,
        includeText: false,
      );

      expect(document.segments, isEmpty);
      expect(document.offers(ReadScope.all), isFalse);
      expect(document.offers(ReadScope.summary), isTrue);
    });
  });
}
