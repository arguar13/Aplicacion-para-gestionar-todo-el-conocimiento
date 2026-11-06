import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/services/index_outline.dart';
import 'package:sinapsis/features/index/domain/services/index_print.dart';

import '../../../support/fake_index_repository.dart';

/// «Descargar el índice» (F46, paso 4), lo puro: los renglones de lo que se
/// está mirando —con sus niveles, lo abierto a mano y la numeración— y su
/// Markdown.
void main() {
  final labels = IndexPrintLabels(
    topicName: (topic) => topic.isUntopiced ? 'Sin tema' : topic.name,
    entryTitle: (entry) => switch (entry.origin) {
      IndexEntryOrigin.wholeText => 'Texto completo',
      IndexEntryOrigin.image when entry.title.isEmpty =>
        'Imagen ${entry.position + 1}',
      _ => entry.title,
    },
    entryPage: (entry) => entry.isWholeText
        ? null
        : entry.isImage
        ? 'img. ${entry.position + 1}'
        : entry.pdfPage != null
        ? 'p. ${entry.pdfPage}'
        : 'pág. ${entry.textPage}',
    topicsNote: (ids, {required listed}) => ids.isEmpty
        ? null
        : '${listed ? 'en' : 'también en'} ${ids.join(', ')}',
  );

  const roma = IndexTopic(spaceId: 'roma', name: 'Roma', documentCount: 2);
  const egipto = IndexTopic(
    spaceId: 'egipto',
    name: 'Egipto',
    documentCount: 1,
  );
  final historia = indexDocument(
    'historia',
    'Historia de Roma',
    spaces: ['roma'],
  );
  final cleopatra = indexDocument(
    'cleopatra',
    'Cleopatra',
    spaces: ['egipto', 'roma'],
  );
  final entries = {
    'historia': [
      ...indexChapters('historia', [
        (1, 'La Monarquía'),
        (2, 'Rómulo'),
        (3, 'La loba'),
        (1, 'La República'),
      ]),
      indexImage('historia', 9, position: 0),
    ],
    'cleopatra': [indexWholeText('cleopatra', 20)],
  };

  String shownLine(IndexPrintLine line) {
    final indent = '  ' * (line.level > 0 ? line.level - 1 : 0);
    final number = line.number == null ? '' : '${line.number} ';
    final page = line.page == null ? '' : ' … ${line.page}';
    final note = line.note == null ? '' : ' (${line.note})';
    return '${line.kind.name}:$indent$number${line.title}$page$note';
  }

  List<String> shown(List<IndexPrintLine> lines) => [
    for (final line in lines) shownLine(line),
  ];

  group('el árbol', () {
    test('por tema: cada tema, sus documentos —uno con dos temas bajo los '
        'dos, con «también en»— y sus entradas hasta los niveles', () {
      final lines = indexPrintTree(
        groups: [
          (topic: egipto, documents: [cleopatra]),
          (topic: roma, documents: [cleopatra, historia]),
        ],
        entries: entries,
        depth: 2,
        labels: labels,
      );
      expect(shown(lines), [
        'topic:Egipto',
        'document:Cleopatra (también en roma)',
        'wholeText:Texto completo',
        'topic:Roma',
        'document:Cleopatra (también en egipto)',
        'wholeText:Texto completo',
        'document:Historia de Roma',
        'chapter:La Monarquía … pág. 1',
        'chapter:  Rómulo … pág. 2',
        'chapter:La República … pág. 4',
        'image:Imagen 1 … img. 1',
      ]);
    });

    test('«Todo», numerado, y lo abierto o cerrado a mano en un documento', () {
      final all = indexPrintTree(
        groups: [
          (topic: null, documents: [historia]),
        ],
        entries: entries,
        depth: null,
        numbered: true,
        labels: labels,
      );
      expect(shown(all), [
        'document:Historia de Roma (en roma)',
        'chapter:1 La Monarquía … pág. 1',
        'chapter:  1.1 Rómulo … pág. 2',
        'chapter:    1.1.1 La loba … pág. 3',
        'chapter:2 La República … pág. 4',
        'image:Imagen 1 … img. 1',
      ]);

      // «Niveles: 1», con «La Monarquía» abierta a mano y «Rómulo» cerrado:
      // lo que el Índice muestra (`indexOutline`).
      final folds = {
        'historia': {1: true, 2: false},
      };
      final folded = indexPrintTree(
        groups: [
          (topic: null, documents: [historia]),
        ],
        entries: entries,
        depth: 1,
        folds: folds,
        labels: labels,
      );
      expect(shown(folded), [
        'document:Historia de Roma (en roma)',
        'chapter:La Monarquía … pág. 1',
        'chapter:  Rómulo … pág. 2',
        'chapter:La República … pág. 4',
        'image:Imagen 1 … img. 1',
      ]);
      expect(
        [
          for (final line in folded)
            if (line.kind == IndexPrintKind.chapter) line.title,
        ],
        [
          for (final row in indexOutline(
            entries['historia']!,
            depth: 1,
            folds: folds['historia']!,
          ))
            if (!row.entry.isImage) row.entry.title,
        ],
      );
    });

    test('un documento sin entradas todavía —sin indexar— va solo con su '
        'título', () {
      final lines = indexPrintTree(
        groups: [
          (topic: null, documents: [indexDocument('nuevo', 'Recién llegado')]),
        ],
        entries: const {},
        depth: 3,
        labels: labels,
      );
      expect(shown(lines), ['document:Recién llegado']);
    });
  });

  group('la búsqueda', () {
    test('los documentos que coinciden y lo encontrado con sus padres, más '
        'tenues', () {
      final chapters = entries['historia']!;
      final lines = indexPrintSearch(
        documents: [cleopatra],
        groups: groupIndexSearch([
          IndexSearchHit(
            entry: chapters[2],
            documentTitle: 'Historia de Roma',
            sourceKind: historia.sourceKind,
            spaceIds: const ['roma'],
            ancestors: [chapters[0], chapters[1]],
          ),
        ]),
        labels: labels,
      );
      expect(shown(lines), [
        'document:Cleopatra (en egipto, roma)',
        'document:Historia de Roma (en roma)',
        'chapter:La Monarquía … pág. 1',
        'chapter:  Rómulo … pág. 2',
        'chapter:    La loba … pág. 3',
      ]);
      expect([for (final l in lines.skip(2)) l.context], [true, true, false]);
    });
  });

  group('el Markdown', () {
    test('el título, lo descargado, los temas, los documentos y una lista '
        'con sangría, número y página', () {
      final markdown = indexMarkdown(
        IndexPrint(
          title: 'Índice',
          subtitle: 'Por tema · hasta el nivel 2',
          lines: indexPrintTree(
            groups: [
              (topic: roma, documents: [historia]),
            ],
            entries: entries,
            depth: 2,
            numbered: true,
            labels: labels,
          ),
        ),
      );
      expect(markdown, '''
# Índice

*Por tema · hasta el nivel 2*

## Roma

### Historia de Roma

- 1 La Monarquía — pág. 1
  - 1.1 Rómulo — pág. 2
- 2 La República — pág. 4
- Imagen 1 — img. 1
''');
    });

    test('sin temas, los documentos son `##`; «Texto completo» va en '
        'cursiva', () {
      final markdown = indexMarkdown(
        IndexPrint(
          title: 'Índice',
          subtitle: 'Por documento',
          lines: indexPrintTree(
            groups: [
              (topic: null, documents: [cleopatra]),
            ],
            entries: entries,
            depth: 3,
            labels: labels,
          ),
        ),
      );
      expect(markdown, contains('\n## Cleopatra\n\n*en egipto, roma*\n'));
      expect(markdown, contains('\n- *Texto completo*\n'));
    });

    test('lo que Markdown leería como marca se ve tal cual', () {
      final markdown = indexMarkdown(
        const IndexPrint(
          title: 'Índice',
          subtitle: 'x',
          lines: [
            IndexPrintLine(
              kind: IndexPrintKind.chapter,
              title: r'C# y *punteros* [1] <b>_x_</b> | a\b',
              level: 1,
            ),
          ],
        ),
      );
      expect(
        markdown,
        endsWith(
          r'- C\# y \*punteros\* \[1\] \<b\>\_x\_\</b\> \| a\\b'
          '\n',
        ),
      );
    });
  });
}
