import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';

/// El árbol del lienzo (F44, paso 2): el despliegue nodo a nodo del Esquema
/// sobre lo que se mira —todo, una comunidad, un tema o lo vinculado—.
void main() {
  /// roma ─ república ─ gracos, roma ─ imperio; grecia sola.
  TopicGraph graph() {
    TopicNode node(
      String id,
      String label, {
      String? parent,
      int depth = 0,
      int items = 1,
    }) => TopicNode(
      valueId: id,
      label: label,
      parentId: parent,
      depth: depth,
      itemCount: items,
    );
    return TopicGraph(
      definitionId: 'tema',
      definitionName: 'Tema',
      nodes: [
        node('gracos', 'Gracos', parent: 'republica', depth: 2),
        node('grecia', 'Grecia', items: 3),
        node('imperio', 'Imperio', parent: 'roma', depth: 1),
        node('republica', 'República', parent: 'roma', depth: 1),
        node('roma', 'Roma', items: 5),
      ],
      edges: const [],
    );
  }

  const all = CanvasTreeRef.all();
  const roma = CanvasTreeRef.topic('roma');

  CanvasTreeLink community(String id, String title, {int group = 0}) =>
      CanvasTreeLink(
        target: CanvasTreeRef.community(id),
        title: title,
        edge: CanvasTreeEdge.member,
        group: group,
        count: 2,
      );

  CanvasTreeLink topic(String id, String title) => CanvasTreeLink(
    target: CanvasTreeRef.topic(id),
    title: title,
    edge: CanvasTreeEdge.member,
  );

  CanvasTreeLink document(String id, String title, {bool note = false}) =>
      CanvasTreeLink(
        target: CanvasTreeRef.item(id),
        title: title,
        edge: CanvasTreeEdge.member,
        isNote: note,
      );

  CanvasTree build({
    CanvasTreeRef root = all,
    String? rootTitle = 'Todo',
    Set<String> expanded = const {},
    Map<String, List<CanvasTreeLink>> links = const {},
    int maxNodes = kMaxCanvasTreeNodes,
    int? Function(String valueId)? groupOf,
  }) => buildCanvasTree(
    root: root,
    rootTitle: rootTitle,
    graph: graph(),
    expanded: expanded,
    links: links,
    maxNodes: maxNodes,
    groupOf: groupOf,
  );

  List<String> titles(CanvasTree tree) => [
    for (final entry in tree.entries.values) entry.title,
  ];

  group('lo que arma el lienzo', () {
    final overview = {
      all.key: [community('0', 'Roma', group: 7), community('1', 'Grecia')],
      'community:0': [topic('roma', 'Roma')],
      'community:1': [topic('grecia', 'Grecia')],
    };

    test('todo, desplegado: las comunidades alrededor, con su color y cuántos '
        'temas juntan, y plegadas', () {
      final tree = build(expanded: {all.key}, links: overview);

      expect(titles(tree), ['Todo', 'Roma', 'Grecia']);
      final first = tree.entries['community:0']!;
      expect(first.group, 7);
      expect(first.count, 2);
      expect(first.depth, 1);
      expect(first.parentKey, all.key);
      expect(first.expanded, isFalse);
      expect(first.canExpand, isTrue);
      expect(tree.root.children.map((c) => c.id), [
        'community:0',
        'community:1',
      ]);
    });

    test('una comunidad desplegada muestra sus temas, y un tema con subtemas '
        'se despliega por la jerarquía', () {
      final tree = build(
        expanded: {all.key, 'community:0', roma.key},
        links: overview,
      );

      expect(titles(tree), [
        'Todo',
        'Roma',
        'Grecia',
        'Roma',
        'Imperio',
        'República',
      ]);
      expect(tree.entries['topic:imperio']!.edge, CanvasTreeEdge.subtopic);
      expect(tree.entries['topic:republica']!.parentKey, roma.key);
    });

    test('lo que arma el lienzo sin hijos no se despliega; un tema o un '
        'documento sin pedir, sí', () {
      final tree = build(
        expanded: {all.key},
        links: {
          all.key: [community('0', 'Vacía'), document('d1', 'Livio')],
          'community:0': const [],
        },
      );

      expect(tree.entries['community:0']!.canExpand, isFalse);
      expect(tree.entries['item:d1']!.canExpand, isTrue);
    });

    test('lo que el lienzo no conoce no se despliega aunque esté en los '
        'desplegados', () {
      final tree = build(
        root: const CanvasTreeRef.links(),
        rootTitle: 'Vínculos',
        expanded: {'links:'},
      );

      expect(tree.entries['links:']!.canExpand, isFalse);
      expect(titles(tree), ['Vínculos']);
    });

    test('el color de un tema es el de su comunidad', () {
      final tree = build(
        expanded: {all.key, 'community:0'},
        links: overview,
        groupOf: (id) => id == 'roma' ? 3 : null,
      );

      expect(tree.entries[roma.key]!.group, 3);
    });
  });

  group('lo que trae la base', () {
    test('un tema raíz se llama como en el grafo y trae sus notas mapa y sus '
        'documentos después de los subtemas', () {
      final tree = build(
        root: roma,
        rootTitle: null,
        expanded: {roma.key},
        links: {
          roma.key: [
            CanvasTreeLink.fromSchema(
              const SchemaLink(
                target: SchemaRef.item('m1'),
                title: 'Mapa de Roma',
                edge: SchemaEdgeKind.mapNote,
              ),
            ),
            document('d1', 'Livio'),
          ],
        },
      );

      expect(titles(tree), [
        'Roma',
        'Imperio',
        'República',
        'Mapa de Roma',
        'Livio',
      ]);
      // Una nota mapa es una nota, aunque la base no lo diga.
      expect(tree.entries['item:m1']!.isNote, isTrue);
      expect(tree.entries['item:m1']!.edge, CanvasTreeEdge.mapNote);
    });

    test(
      'un documento desplegado trae sus vínculos con el tipo y el sentido',
      () {
        final tree = build(
          root: const CanvasTreeRef.item('d1'),
          rootTitle: 'Livio',
          expanded: {'item:d1'},
          links: {
            'item:d1': [
              CanvasTreeLink.fromSchema(
                const SchemaLink(
                  target: SchemaRef.item('d2'),
                  title: 'Tácito',
                  edge: SchemaEdgeKind.relation,
                  relation: RelationKind.contradicts,
                  outgoing: false,
                ),
              ),
            ],
          },
        );

        final entry = tree.entries['item:d2']!;
        expect(entry.relation, RelationKind.contradicts);
        expect(entry.outgoing, isFalse);
        expect(entry.edge, CanvasTreeEdge.relation);
      },
    );

    test('un documento cuyos vínculos vinieron vacíos ya no se despliega', () {
      final tree = build(
        root: const CanvasTreeRef.item('d1'),
        rootTitle: 'Livio',
        expanded: {'item:d1'},
        links: {'item:d1': const []},
      );

      expect(tree.entries['item:d1']!.canExpand, isFalse);
    });
  });

  test('un nodo entra una sola vez, donde primero se lo encuentra', () {
    final tree = build(
      expanded: {all.key, 'community:0', 'community:1'},
      links: {
        all.key: [community('0', 'Roma'), community('1', 'Grecia')],
        'community:0': [topic('roma', 'Roma')],
        // El mismo tema, otra vez.
        'community:1': [topic('roma', 'Roma'), topic('grecia', 'Grecia')],
      },
    );

    expect(tree.entries[roma.key]!.parentKey, 'community:0');
    expect(tree.root.children[1].children.map((c) => c.id), ['topic:grecia']);
  });

  test('con el tope, lo más cercano a la raíz entra primero y se avisa', () {
    final tree = build(
      expanded: {all.key, 'community:0'},
      links: {
        all.key: [community('0', 'Roma'), community('1', 'Grecia')],
        'community:0': [topic('roma', 'Roma')],
      },
      maxNodes: 3,
    );

    expect(titles(tree), ['Todo', 'Roma', 'Grecia']);
    expect(tree.truncated, isTrue);
    expect(build(expanded: {all.key}).truncated, isFalse);
  });

  test('es puro: dos veces con lo mismo da el mismo árbol', () {
    Map<String, List<CanvasTreeLink>> links() => {
      all.key: [community('0', 'Roma')],
      'community:0': [topic('roma', 'Roma')],
    };
    final a = build(expanded: {all.key, 'community:0'}, links: links());
    final b = build(expanded: {all.key, 'community:0'}, links: links());

    expect(titles(a), titles(b));
    expect(a.entries.keys, b.entries.keys);
  });

  test('las raíces de unos temas: los que no cuelgan de otro de ellos, del de '
      'más elementos al de menos', () {
    final g = graph();
    int at(String id) => g.indexOf(id)!;

    expect(rootTopicsAmong(g, [at('roma'), at('imperio'), at('grecia')]), [
      at('roma'),
      at('grecia'),
    ]);
    // Sin su padre entre ellos, un subtema es raíz.
    expect(rootTopicsAmong(g, [at('gracos'), at('imperio')]), [
      at('gracos'),
      at('imperio'),
    ]);
  });

  test('la clave de cada nodo es única entre los cinco tipos', () {
    expect({
      const CanvasTreeRef.all().key,
      const CanvasTreeRef.links().key,
      const CanvasTreeRef.community('x').key,
      const CanvasTreeRef.topic('x').key,
      const CanvasTreeRef.item('x').key,
    }, hasLength(5));
    expect(
      const CanvasTreeRef.topic('x'),
      CanvasTreeRef.of(const SchemaRef.topic('x')),
    );
    expect(const CanvasTreeRef.community('x').schemaRef, isNull);
    expect(const CanvasTreeRef.item('x').schemaRef, const SchemaRef.item('x'));
  });
}
