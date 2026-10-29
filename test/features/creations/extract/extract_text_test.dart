import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_markdown.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_text.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';

/// Lo puro de las tres de extraer (F43, paso 7): cómo se parte lo que se
/// muestra y cómo se escribe su archivo.
void main() {
  var ids = 0;
  StudyMark mark(String content, String passage, StudyMarkKind kind) {
    final start = content.indexOf(passage);
    expect(start, isNonNegative, reason: passage);
    return StudyMark(
      id: 'm${ids++}',
      kind: kind,
      origin: ContentOrigin.ai,
      start: start,
      end: start + passage.length,
    );
  }

  DocumentStudy studyOf(String content, Map<String, StudyMarkKind> marks) {
    final list = [
      for (final entry in marks.entries) mark(content, entry.key, entry.value),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return DocumentStudy(
      marks: list,
      analyzedUntil: content.length,
      complete: true,
    );
  }

  String textOf(String content, ExtractBlock block) => [
    for (final piece in block.pieces) content.substring(piece.start, piece.end),
  ].join(' ');

  group('qué necesita cada una', () {
    test('el texto completo, las palabras clave; el resumen y la síntesis, '
        'sus oraciones; las demás no son de extraer', () {
      expect(extractNeeds(StudyCreationKind.fullText), StudyMarkKind.keyword);
      expect(extractNeeds(StudyCreationKind.summary), StudyMarkKind.summary);
      expect(
        extractNeeds(StudyCreationKind.synthesis),
        StudyMarkKind.synthesis,
      );
      expect(() => extractNeeds(StudyCreationKind.quiz), throwsArgumentError);
    });
  });

  group('el texto entero en bloques', () {
    test('cada bloque es un tramo tal cual del texto, sin los separadores de '
        'página de un PDF, y juntos lo cubren en orden', () {
      const content = 'Página uno.\n\n---\n\nPágina dos, con más.';
      final blocks = extractTextBlocks(content);
      expect(
        [for (final b in blocks) textOf(content, b)],
        ['Página uno.', 'Página dos, con más.'],
      );
      expect(blocks.first.start, 0);
      expect(blocks.last.end, content.length);
    });

    test('un libro se junta en bloques de unos mil doscientos caracteres, '
        'sin partir un párrafo que entra', () {
      final paragraph = 'a' * 500;
      final content = List.filled(10, paragraph).join('\n\n');
      final blocks = extractTextBlocks(content);
      expect(blocks.length, greaterThan(3));
      for (final block in blocks) {
        expect(block.end - block.start, lessThanOrEqualTo(kExtractBlockChars));
        expect(textOf(content, block).replaceAll('\n', '').length % 500, 0);
      }
    });

    test('en otro hilo da lo mismo', () async {
      final content = List.filled(
        200,
        'Una oración de prueba. ' * 20,
      ).join('\n\n');
      expect(await extractTextBlocksOff(content), extractTextBlocks(content));
    });
  });

  group('las oraciones en párrafos', () {
    const content =
        'Roma fundó colonias. Cartago perdió.\n\n'
        'Aníbal cruzó los Alpes. Escipión volvió.\n'
        '# Después\n'
        'Vino el imperio.';

    test('las del mismo párrafo van juntas; un renglón en blanco abre otro; '
        'en Markdown, un título también', () {
      final study = studyOf(content, {
        'Roma fundó colonias.': StudyMarkKind.summary,
        'Cartago perdió.': StudyMarkKind.summary,
        'Aníbal cruzó los Alpes.': StudyMarkKind.summary,
        'Escipión volvió.': StudyMarkKind.summary,
        '# Después': StudyMarkKind.summary,
        'Vino el imperio.': StudyMarkKind.summary,
        'Roma': StudyMarkKind.keyword,
      });
      final blocks = extractSentenceBlocks(
        content,
        study,
        StudyMarkKind.summary,
        markdown: true,
      );
      expect(
        [for (final b in blocks) textOf(content, b)],
        [
          'Roma fundó colonias. Cartago perdió.',
          'Aníbal cruzó los Alpes. Escipión volvió.',
          '# Después',
          'Vino el imperio.',
        ],
      );
    });

    test('sin Markdown, un salto de renglón no separa', () {
      final study = studyOf(content, {
        'Escipión volvió.': StudyMarkKind.summary,
        '# Después': StudyMarkKind.summary,
      });
      final blocks = extractSentenceBlocks(
        content,
        study,
        StudyMarkKind.summary,
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.pieces, hasLength(2));
    });

    test('solo las de su clase, y un párrafo largo se parte', () {
      final long = List.filled(
        40,
        'Esta es una oración larga de prueba.',
      ).join(' ');
      final study = DocumentStudy(
        marks: [
          for (var i = 0; i < 40; i++)
            StudyMark(
              id: 's$i',
              kind: StudyMarkKind.synthesis,
              origin: ContentOrigin.ai,
              start: i * 37,
              end: i * 37 + 36,
            ),
          const StudyMark(
            id: 'r',
            kind: StudyMarkKind.summary,
            origin: ContentOrigin.ai,
            start: 0,
            end: 36,
          ),
        ]..sort((a, b) => a.start.compareTo(b.start)),
        analyzedUntil: long.length,
        complete: true,
      );
      final blocks = extractSentenceBlocks(
        long,
        study,
        StudyMarkKind.synthesis,
      );
      expect(blocks.length, greaterThan(1));
      expect(blocks.fold<int>(0, (sum, b) => sum + b.pieces.length), 40);
      for (final block in blocks) {
        expect(
          block.end - block.start,
          lessThanOrEqualTo(kExtractBlockChars + 40),
        );
      }
    });
  });

  test('las palabras clave de un tramo', () {
    const content = 'Roma fundó colonias. Cartago perdió.';
    final study = studyOf(content, {
      'Roma': StudyMarkKind.keyword,
      'Cartago': StudyMarkKind.keyword,
      'Roma fundó colonias.': StudyMarkKind.summary,
    });
    expect(
      [
        for (final m in keywordsWithin(study.of(StudyMarkKind.keyword), 0, 20))
          m.start,
      ],
      [0],
    );
    expect(
      keywordsWithin(study.of(StudyMarkKind.keyword), 21, content.length),
      hasLength(1),
    );
  });

  group('el archivo Markdown', () {
    const content =
        'La república **romana** cayó. César cruzó el Rubicón.\n\n'
        '## Después\n'
        'Escipión volvió a [Roma](https://roma.it).';

    test('el resumen: el título, el documento y sus oraciones en párrafos, '
        'sin el formato y con las palabras clave en negrita', () {
      final study = studyOf(content, {
        'César cruzó el Rubicón.': StudyMarkKind.summary,
        'La república **romana** cayó.': StudyMarkKind.summary,
        'Escipión volvió a [Roma](https://roma.it).': StudyMarkKind.summary,
        'César': StudyMarkKind.keyword,
        'Roma': StudyMarkKind.keyword,
      });
      final markdown = extractMarkdown(
        title: 'Resumen de Roma',
        kind: StudyCreationKind.summary,
        sections: [
          ExtractExportSection(
            title: 'Roma',
            content: content,
            markdown: true,
            study: study,
          ),
        ],
      );
      expect(
        markdown,
        '# Resumen de Roma\n\n## Roma\n\n'
        'La república romana cayó. **César** cruzó el Rubicón.\n\n'
        'Escipión volvió a **Roma**.\n',
      );
    });

    test('el texto completo, tal cual con su formato, con las palabras clave '
        'en negrita donde no rompen nada', () {
      final study = studyOf(content, {
        'César': StudyMarkKind.keyword,
        'romana': StudyMarkKind.keyword,
      });
      final markdown = extractMarkdown(
        title: 'Texto',
        kind: StudyCreationKind.fullText,
        sections: [
          ExtractExportSection(
            title: 'Roma',
            content: content,
            markdown: true,
            study: study,
          ),
        ],
      );
      expect(
        markdown,
        contains('La república **romana** cayó. **César** cruzó'),
      );
      expect(markdown, isNot(contains('****')));
      expect(markdown, contains('## Después\nEscipión volvió a [Roma]'));
    });

    test('con las palabras clave ocultas, sin negritas; lo que falta, con su '
        'nota', () {
      final study = studyOf(content, {
        'César cruzó el Rubicón.': StudyMarkKind.summary,
        'César': StudyMarkKind.keyword,
      });
      final markdown = extractMarkdown(
        title: 'Resumen',
        kind: StudyCreationKind.summary,
        sections: [
          ExtractExportSection(
            title: 'Roma',
            content: content,
            markdown: true,
            study: study,
            keywordsShown: false,
          ),
          const ExtractExportSection(title: 'Grecia', note: 'Fuente borrada'),
          const ExtractExportSection(
            title: 'Cartago',
            content: content,
            note: 'Todavía no tiene resumen',
          ),
        ],
      );
      expect(markdown, contains('## Roma\n\nCésar cruzó el Rubicón.\n'));
      expect(markdown, isNot(contains('**')));
      expect(markdown, contains('## Grecia\n\n_Fuente borrada_\n'));
      expect(markdown, contains('## Cartago\n\n_Todavía no tiene resumen_\n'));
    });
  });
}
