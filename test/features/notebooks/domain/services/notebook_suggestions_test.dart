import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';

/// Qué cuadernos se sugieren, y cómo se leen los nombres que propone la IA
/// (F30).
void main() {
  final now = DateTime(2026, 10, 8);

  NotebookTopic space(String id, String name, int count) => NotebookTopic(
    kind: NotebookTopicKind.space,
    id: id,
    name: name,
    itemCount: count,
  );

  NotebookTopic tag(String id, String name, int count, {String? parent}) =>
      NotebookTopic(
        kind: NotebookTopicKind.tag,
        id: id,
        name: name,
        itemCount: count,
        parentId: parent,
      );

  Notebook notebook(String name, {LibraryQuery? query}) => Notebook(
    id: 'nb-$name',
    name: name,
    mode: query == null ? NotebookMode.manual : NotebookMode.query,
    query: query,
    createdAt: now,
    updatedAt: now,
  );

  group('suggestNotebooks', () {
    test('los temas y las etiquetas con elementos de sobra, de los de más a '
        'los de menos y, a igual cantidad, los temas antes', () {
      final suggestions = suggestNotebooks(
        topics: [
          space('s1', 'Roma', 5),
          tag('t1', 'Filosofía', 9),
          space('s2', 'Poco', 2),
          tag('t2', 'Grecia', 5),
        ],
        existing: const [],
      );

      expect(suggestions.map((s) => s.topic.name), [
        'Filosofía',
        'Roma',
        'Grecia',
      ]);
    });

    test('cada una es por consulta: el tema, o la etiqueta con sus ramas', () {
      final suggestions = suggestNotebooks(
        topics: [space('s1', 'Roma', 5), tag('t1', 'Filosofía', 9)],
        existing: const [],
      );

      expect(suggestions[0].query, const LibraryQuery(tagIds: {'t1'}));
      expect(suggestions[1].query, const LibraryQuery(spaceId: 's1'));
      expect(suggestions.map((s) => s.key), ['tag:t1', 'space:s1']);
    });

    test('sin duplicar: ni el que ya existe por esa consulta, ni uno con el '
        'mismo nombre, sin mirar mayúsculas ni acentos', () {
      final suggestions = suggestNotebooks(
        topics: [
          space('s1', 'Roma', 5),
          space('s2', 'Grecia', 5),
          tag('t1', 'Filosofía', 5),
        ],
        existing: [
          // El mismo tema con otro nombre y otro orden.
          notebook(
            'Mi tesis',
            query: const LibraryQuery(
              spaceId: 's1',
              sortBy: LibrarySort.title,
              descending: false,
            ),
          ),
          // El mismo nombre, a mano.
          notebook('filosofia'),
        ],
      );

      expect(suggestions.map((s) => s.topic.name), ['Grecia']);
    });

    test('una etiqueta con los mismos elementos que la de arriba no suma: '
        'sería el mismo cuaderno', () {
      final suggestions = suggestNotebooks(
        topics: [
          tag('t1', 'Historia', 8),
          tag('t2', 'Roma', 8, parent: 't1'),
          tag('t3', 'Grecia', 4, parent: 't1'),
        ],
        existing: const [],
      );

      expect(suggestions.map((s) => s.topic.name), ['Historia', 'Grecia']);
    });

    test('un tema y una etiqueta con el mismo nombre dan uno solo, el de más '
        'elementos', () {
      final suggestions = suggestNotebooks(
        topics: [space('s1', 'Roma', 4), tag('t1', 'Roma', 7)],
        existing: const [],
      );

      expect(suggestions.single.key, 'tag:t1');
    });

    test('sin los que la persona descartó, y con un tope', () {
      final topics = [for (var i = 0; i < 12; i++) space('s$i', 'Tema $i', 10)];

      final suggestions = suggestNotebooks(
        topics: topics,
        existing: const [],
        dismissed: {'space:s0'},
        max: 4,
      );

      expect(suggestions, hasLength(4));
      expect(suggestions.map((s) => s.key), isNot(contains('space:s0')));
    });

    test('lo que entra después se sugiere aunque se haya dicho «ahora no» de '
        'lo anterior', () {
      final before = suggestNotebooks(
        topics: [space('s1', 'Roma', 5)],
        existing: const [],
        dismissed: {'space:s1'},
      );
      final after = suggestNotebooks(
        topics: [space('s1', 'Roma', 5), space('s2', 'Grecia', 3)],
        existing: const [],
        dismissed: {'space:s1'},
      );

      expect(before, isEmpty);
      expect(after.map((s) => s.topic.name), ['Grecia']);
    });
  });

  group('parseNotebookNames', () {
    test('nombre y descripción de cada tema, por su número desde 0', () {
      final names = parseNotebookNames(
        'CUADERNO: 1 | La república romana | Fuentes sobre su política\n'
        'CUADERNO: 3 | Filosofía griega |',
        count: 3,
      );

      expect(names[0]?.name, 'La república romana');
      expect(names[0]?.description, 'Fuentes sobre su política');
      expect(names[2]?.name, 'Filosofía griega');
      expect(names[2]?.description, isNull);
      expect(names.containsKey(1), isFalse);
    });

    test('tolera Markdown, comillas y texto alrededor', () {
      final names = parseNotebookNames(
        'Acá van:\n**CUADERNO:** 1 | «Roma» | "Una línea"\nListo.',
        count: 1,
      );

      expect(names[0]?.name, 'Roma');
      expect(names[0]?.description, 'Una línea');
    });

    test('descarta lo que no sirve: un número que no está, un nombre vacío o '
        'enorme, una descripción enorme, un número repetido', () {
      final names = parseNotebookNames(
        [
          'CUADERNO: 9 | Fuera de la lista | x',
          'CUADERNO: 1 |  | sin nombre',
          'CUADERNO: 2 | ${'a' * 61} | nombre enorme',
          'CUADERNO: 3 | Bien | ${'b' * 161}',
          'CUADERNO: 4 | Primero | uno',
          'CUADERNO: 4 | Segundo | dos',
        ].join('\n'),
        count: 4,
      );

      expect(names.keys, unorderedEquals([2, 3]));
      expect(names[2]?.description, isNull);
      expect(names[3]?.name, 'Primero');
    });

    test('sin ninguna línea, nada', () {
      expect(parseNotebookNames('No sé.', count: 2), isEmpty);
    });
  });
}
