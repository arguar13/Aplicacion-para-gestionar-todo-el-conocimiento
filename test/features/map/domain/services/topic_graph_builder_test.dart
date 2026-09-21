import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/topic_graph_builder.dart';

/// El grafo de temas (F14), armado sin base de datos: qué temas hay, cuánto los
/// une y en qué orden salen.
void main() {
  AtlasValueRow value(String id, {String? parent, String? label}) =>
      AtlasValueRow(id: id, label: label ?? id, parentId: parent);

  TopicItem item(String id, List<String> valueIds) =>
      TopicItem(id: id, valueIds: valueIds);

  TopicRelation relation(
    String from,
    String to, {
    RelationKind kind = RelationKind.relatedTo,
    bool reviewed = false,
  }) => TopicRelation(
    fromItemId: from,
    toItemId: to,
    kind: kind,
    reviewed: reviewed,
  );

  TopicGraph build({
    required List<AtlasValueRow> values,
    List<TopicItem> items = const [],
    List<TopicRelation> relations = const [],
  }) => buildTopicGraph(
    TopicGraphInput(
      definitionId: 'tema',
      definitionName: 'Tema',
      values: values,
      items: items,
      relations: relations,
    ),
  );

  /// La arista entre dos temas, o `null` si no hay.
  TopicEdge? edgeBetween(TopicGraph graph, String x, String y) {
    final a = graph.indexOf(x)!;
    final b = graph.indexOf(y)!;
    final low = a < b ? a : b;
    final high = a < b ? b : a;
    for (final edge in graph.edges) {
      if (edge.a == low && edge.b == high) return edge;
    }
    return null;
  }

  group('los nodos', () {
    test('van por nombre sin acentos ni mayúsculas, y a igual nombre por '
        'identificador', () {
      final graph = build(
        values: [
          value('z', label: 'Zama'),
          value('a1', label: 'Álgebra'),
          value('b', label: 'bizancio'),
          value('a0', label: 'algebra'),
        ],
      );

      expect([for (final n in graph.nodes) n.valueId], ['a0', 'a1', 'b', 'z']);
    });

    test('traen su lugar en la jerarquía: el padre y el nivel', () {
      final graph = build(
        values: [
          value('roma', label: 'Roma'),
          value('republica', label: 'República', parent: 'roma'),
          value('gracos', label: 'Gracos', parent: 'republica'),
        ],
      );

      final roma = graph.nodes[graph.indexOf('roma')!];
      final republica = graph.nodes[graph.indexOf('republica')!];
      final gracos = graph.nodes[graph.indexOf('gracos')!];
      expect(roma.parentId, isNull);
      expect(roma.depth, 0);
      expect(republica.parentId, 'roma');
      expect(republica.depth, 1);
      expect(gracos.parentId, 'republica');
      expect(gracos.depth, 2);
    });

    test('un padre que no está entre los valores deja al hijo en la raíz', () {
      final graph = build(values: [value('hijo', parent: 'no-existe')]);

      expect(graph.nodes.single.parentId, isNull);
      expect(graph.nodes.single.depth, 0);
    });

    test('una jerarquía dañada con un ciclo no cuelga el cálculo', () {
      final graph = build(
        values: [
          value('a', parent: 'b'),
          value('b', parent: 'a'),
        ],
      );

      expect(graph.nodes, hasLength(2));
    });

    test('el tamaño es lo asignado directamente: un elemento en dos temas '
        'cuenta en cada uno, y el de un subtema no cuenta en el padre', () {
      final graph = build(
        values: [
          value('roma'),
          value('republica', parent: 'roma'),
        ],
        items: [
          item('i1', ['roma', 'republica']),
          item('i2', ['republica']),
          item('i3', ['roma']),
        ],
      );

      expect(graph.nodes[graph.indexOf('roma')!].itemCount, 2);
      expect(graph.nodes[graph.indexOf('republica')!].itemCount, 2);
    });

    test('lo asignado a un valor que no es de la categoría no cuenta', () {
      final graph = build(
        values: [value('roma')],
        items: [
          item('i1', ['roma', 'otra-categoria']),
        ],
      );

      expect(graph.nodes.single.itemCount, 1);
      expect(graph.edges, isEmpty);
    });

    test('sin valores, el grafo está vacío', () {
      final graph = build(values: const []);

      expect(graph.nodes, isEmpty);
      expect(graph.edges, isEmpty);
      expect(graph.definitionName, 'Tema');
    });

    test('un tema sin elementos igual es un nodo, y sin aristas', () {
      final graph = build(values: [value('vacio'), value('roma')]);

      expect(graph.nodes, hasLength(2));
      expect(graph.edges, isEmpty);
    });
  });

  group('la coocurrencia', () {
    test('dos temas en un mismo elemento se unen; en dos elementos, suman', () {
      final graph = build(
        values: [value('a'), value('b'), value('c')],
        items: [
          item('i1', ['a', 'b', 'c']),
          item('i2', ['a', 'b']),
        ],
      );

      expect(edgeBetween(graph, 'a', 'b')!.cooccurrence, 2);
      expect(edgeBetween(graph, 'a', 'c')!.cooccurrence, 1);
      expect(edgeBetween(graph, 'b', 'c')!.cooccurrence, 1);
      expect(graph.edges, hasLength(3));
    });

    test('un elemento con un solo tema no une nada', () {
      final graph = build(
        values: [value('a'), value('b')],
        items: [
          item('i1', ['a']),
          item('i2', ['b']),
        ],
      );

      expect(graph.edges, isEmpty);
    });

    test('un valor repetido en un elemento cuenta una vez', () {
      final graph = build(
        values: [value('a'), value('b')],
        items: [
          item('i1', ['a', 'a', 'b', 'b']),
        ],
      );

      expect(graph.nodes[graph.indexOf('a')!].itemCount, 1);
      expect(edgeBetween(graph, 'a', 'b')!.cooccurrence, 1);
    });

    test('un elemento con más de $kMaxTopicsPerItem temas usa los primeros '
        'por orden alfabético, y cuenta en todos', () {
      final ids = [
        for (var i = 0; i < 45; i++) 't${i.toString().padLeft(2, '0')}',
      ];
      final graph = build(
        values: [for (final id in ids) value(id)],
        // Al revés: el recorte no depende del orden en que llegan.
        items: [item('grande', ids.reversed.toList())],
      );

      expect(
        graph.nodes.map((n) => n.itemCount),
        everyElement(1),
        reason: 'el tamaño de un tema cuenta al elemento aunque se recorte',
      );
      // Hay una arista entre dos temas de los 40 primeros...
      expect(edgeBetween(graph, 't00', 't39'), isNotNull);
      // ...y ninguna con los cinco que quedaron afuera.
      expect(edgeBetween(graph, 't00', 't44'), isNull);
      expect(graph.edges, hasLength(40 * 39 ~/ 2));
    });
  });

  group('las relaciones', () {
    test('unen los temas de un elemento con los del otro', () {
      final graph = build(
        values: [value('a'), value('b')],
        items: [
          item('i1', ['a']),
          item('i2', ['b']),
        ],
        relations: [relation('i1', 'i2')],
      );

      final edge = edgeBetween(graph, 'a', 'b')!;
      expect(edge.relations, 1);
      expect(edge.cooccurrence, 0);
      expect(edge.contradictions, 0);
      expect(edge.isTension, isFalse);
    });

    test(
      'no tienen dirección: de A a B y de B a A suman en la misma arista',
      () {
        final graph = build(
          values: [value('a'), value('b')],
          items: [
            item('i1', ['a']),
            item('i2', ['b']),
          ],
          relations: [
            relation('i1', 'i2'),
            relation('i2', 'i1', kind: RelationKind.cites),
          ],
        );

        expect(graph.edges, hasLength(1));
        expect(edgeBetween(graph, 'a', 'b')!.relations, 2);
      },
    );

    test('entre elementos que comparten un tema, no hay una arista del tema '
        'consigo mismo', () {
      final graph = build(
        values: [value('a')],
        items: [
          item('i1', ['a']),
          item('i2', ['a']),
        ],
        relations: [relation('i1', 'i2')],
      );

      expect(graph.edges, isEmpty);
    });

    test(
      'con varios temas en cada extremo, cuenta una vez por par de temas',
      () {
        final graph = build(
          values: [value('a'), value('b'), value('c')],
          items: [
            item('i1', ['a', 'b']),
            item('i2', ['a', 'b', 'c']),
          ],
          relations: [relation('i1', 'i2')],
        );

        // (a, b) sale dos veces al cruzar —a→b y b→a— y cuenta una.
        expect(edgeBetween(graph, 'a', 'b')!.relations, 1);
        expect(edgeBetween(graph, 'a', 'c')!.relations, 1);
        expect(edgeBetween(graph, 'b', 'c')!.relations, 1);
      },
    );

    test('una con un extremo que no es un elemento del grafo se descarta', () {
      final graph = build(
        values: [value('a'), value('b')],
        items: [
          item('i1', ['a']),
        ],
        relations: [relation('i1', 'en-la-papelera')],
      );

      expect(graph.edges, isEmpty);
    });

    test('una a un elemento sin ningún tema de la categoría no une nada', () {
      final graph = build(
        values: [value('a'), value('b')],
        items: [
          item('i1', ['a']),
          item('i2', const []),
        ],
        relations: [relation('i1', 'i2')],
      );

      expect(graph.edges, isEmpty);
    });
  });

  group('las contradicciones', () {
    test('marcan la arista como tensión y cuentan aparte de las demás', () {
      final graph = build(
        values: [value('a'), value('b')],
        items: [
          item('i1', ['a']),
          item('i2', ['b']),
        ],
        relations: [
          relation('i1', 'i2', kind: RelationKind.contradicts),
          relation('i2', 'i1', kind: RelationKind.cites),
        ],
      );

      final edge = edgeBetween(graph, 'a', 'b')!;
      expect(edge.isTension, isTrue);
      expect(edge.contradictions, 1);
      expect(edge.relations, 1, reason: 'contradicts no es una relación común');
    });

    test('las abiertas son las que nadie revisó', () {
      final graph = build(
        values: [value('a'), value('b')],
        items: [
          item('i1', ['a']),
          item('i2', ['b']),
          item('i3', ['b']),
        ],
        relations: [
          relation('i1', 'i2', kind: RelationKind.contradicts, reviewed: true),
          relation('i1', 'i3', kind: RelationKind.contradicts),
        ],
      );

      final edge = edgeBetween(graph, 'a', 'b')!;
      expect(edge.contradictions, 2);
      expect(edge.openContradictions, 1);
    });
  });

  group('los pesos', () {
    test('la contradicción pesa más que la relación, y esta más que compartir '
        'un elemento', () {
      const weights = TopicGraphWeights();
      const shared = TopicEdge(
        a: 0,
        b: 1,
        cooccurrence: 1,
        relations: 0,
        contradictions: 0,
        openContradictions: 0,
      );
      const related = TopicEdge(
        a: 0,
        b: 1,
        cooccurrence: 0,
        relations: 1,
        contradictions: 0,
        openContradictions: 0,
      );
      const contradicted = TopicEdge(
        a: 0,
        b: 1,
        cooccurrence: 0,
        relations: 0,
        contradictions: 1,
        openContradictions: 1,
      );

      expect(weights.of(shared), 1);
      expect(weights.of(related), 2);
      expect(weights.of(contradicted), 3);
      expect(weights.of(contradicted), greaterThan(weights.of(related)));
      expect(weights.of(related), greaterThan(weights.of(shared)));
    });

    test('los pesos se pueden cambiar', () {
      const weights = TopicGraphWeights(
        cooccurrence: 0.5,
        relation: 4,
        contradiction: 10,
      );
      const edge = TopicEdge(
        a: 0,
        b: 1,
        cooccurrence: 2,
        relations: 1,
        contradictions: 1,
        openContradictions: 0,
      );

      expect(weights.of(edge), 2 * 0.5 + 4 + 10);
    });
  });

  group('el orden', () {
    test('el mismo contenido da el mismo grafo, lleguen como lleguen los '
        'elementos', () {
      final values = [value('a'), value('b'), value('c'), value('d')];
      final items = [
        item('i1', ['a', 'b']),
        item('i2', ['c', 'd']),
        item('i3', ['b', 'c']),
        item('i4', ['a', 'd', 'b']),
      ];
      final relations = [
        relation('i1', 'i2'),
        relation('i3', 'i4', kind: RelationKind.contradicts),
      ];

      final forward = build(values: values, items: items, relations: relations);
      final backward = build(
        values: values.reversed.toList(),
        items: items.reversed.toList(),
        relations: relations.reversed.toList(),
      );

      String signature(TopicGraph g) => [
        for (final n in g.nodes) '${n.valueId}:${n.itemCount}',
        for (final e in g.edges)
          '${e.a}-${e.b}:${e.cooccurrence}/${e.relations}/${e.contradictions}',
      ].join(' ');

      expect(signature(backward), signature(forward));
    });

    test('las aristas salen ordenadas por sus extremos', () {
      final graph = build(
        values: [value('a'), value('b'), value('c')],
        items: [
          item('i1', ['b', 'c']),
          item('i2', ['a', 'c']),
          item('i3', ['a', 'b']),
        ],
      );

      final pairs = [for (final e in graph.edges) (e.a, e.b)];
      expect(pairs, [(0, 1), (0, 2), (1, 2)]);
    });
  });
}
