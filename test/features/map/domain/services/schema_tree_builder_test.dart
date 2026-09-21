import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/schema_tree_builder.dart';

/// El esquema (F14, D6) como árbol: qué se ve al desplegar un tema o una nota.
void main() {
  /// roma ─ república ─ gracos, roma ─ imperio; grecia sola.
  TopicGraph graph() {
    TopicNode node(String id, String label, {String? parent, int depth = 0}) =>
        TopicNode(
          valueId: id,
          label: label,
          parentId: parent,
          depth: depth,
          itemCount: 1,
        );
    return TopicGraph(
      definitionId: 'tema',
      definitionName: 'Tema',
      nodes: [
        node('gracos', 'Gracos', parent: 'republica', depth: 2),
        node('grecia', 'Grecia'),
        node('imperio', 'Imperio', parent: 'roma', depth: 1),
        node('republica', 'República', parent: 'roma', depth: 1),
        node('roma', 'Roma'),
      ],
      edges: const [],
    );
  }

  const roma = SchemaRef.topic('roma');
  const republica = SchemaRef.topic('republica');

  SchemaLink mapNote(String id, String title) => SchemaLink(
    target: SchemaRef.item(id),
    title: title,
    edge: SchemaEdgeKind.mapNote,
    isNote: true,
  );

  SchemaLink relation(
    String id,
    String title,
    RelationKind kind, {
    bool outgoing = true,
    bool note = false,
  }) => SchemaLink(
    target: SchemaRef.item(id),
    title: title,
    edge: SchemaEdgeKind.relation,
    relation: kind,
    outgoing: outgoing,
    isNote: note,
  );

  SchemaTree build({
    SchemaRef root = roma,
    String? rootTitle,
    Set<String> expanded = const {},
    Map<String, List<SchemaLink>> links = const {},
    int maxNodes = kMaxSchemaNodes,
  }) => buildSchemaTree(
    root: root,
    rootTitle: rootTitle,
    graph: graph(),
    expanded: expanded,
    links: links,
    maxNodes: maxNodes,
  );

  List<String> titles(SchemaTree tree) => [
    for (final entry in tree.entries.values) entry.title,
  ];

  test('sin desplegar nada, solo la raíz, y se puede desplegar', () {
    final tree = build();

    expect(titles(tree), ['Roma']);
    expect(tree.entries['topic:roma']!.canExpand, isTrue);
    expect(tree.entries['topic:roma']!.expanded, isFalse);
    expect(tree.root.children, isEmpty);
    expect(tree.truncated, isFalse);
  });

  test('desplegar un tema muestra sus subtemas, por nombre', () {
    final tree = build(expanded: {roma.key});

    expect(titles(tree), ['Roma', 'Imperio', 'República']);
    final imperio = tree.entries['topic:imperio']!;
    expect(imperio.depth, 1);
    expect(imperio.edge, SchemaEdgeKind.subtopic);
    expect(imperio.parentKey, 'topic:roma');
    expect(
      [for (final c in tree.root.children) c.id],
      ['topic:imperio', 'topic:republica'],
    );
  });

  test('las notas mapa del tema cuelgan de él, con su marca de nota', () {
    final tree = build(
      expanded: {roma.key},
      links: {
        roma.key: [mapNote('n1', 'Mapa de Roma')],
      },
    );

    final note = tree.entries['item:n1']!;
    expect(note.edge, SchemaEdgeKind.mapNote);
    expect(note.isNote, isTrue);
    expect(note.title, 'Mapa de Roma');
    // Los subtemas primero, después las notas.
    expect(titles(tree), ['Roma', 'Imperio', 'República', 'Mapa de Roma']);
  });

  test('cada nivel se despliega por separado, y el árbol lo refleja', () {
    final tree = build(expanded: {roma.key, republica.key});

    expect(titles(tree), ['Roma', 'Imperio', 'República', 'Gracos']);
    expect(tree.entries['topic:gracos']!.depth, 2);
    expect(tree.entries['topic:gracos']!.parentKey, 'topic:republica');
    final republicaNode = tree.root.children.last;
    expect(republicaNode.children.single.id, 'topic:gracos');
  });

  test('un vínculo trae su tipo, su dirección y si es una nota', () {
    const note = SchemaRef.item('n1');
    final tree = build(
      root: note,
      rootTitle: 'Mapa de Roma',
      expanded: {note.key},
      links: {
        note.key: [
          relation('s1', 'Livio', RelationKind.indexes),
          relation('s2', 'Polibio', RelationKind.contradicts, outgoing: false),
          relation('n2', 'Nota viva', RelationKind.relatedTo, note: true),
        ],
      },
    );

    expect(tree.entries['item:n1']!.title, 'Mapa de Roma');
    final polibio = tree.entries['item:s2']!;
    expect(polibio.relation, RelationKind.contradicts);
    expect(polibio.outgoing, isFalse);
    expect(polibio.isNote, isFalse);
    expect(tree.entries['item:s1']!.relation, RelationKind.indexes);
    expect(tree.entries['item:n2']!.isNote, isTrue);
  });

  test('un nodo aparece una sola vez, donde primero se lo encuentra', () {
    final tree = build(
      expanded: {roma.key, republica.key},
      links: {
        roma.key: [mapNote('n1', 'Mapa')],
        // La misma nota, colgada también de República.
        republica.key: [mapNote('n1', 'Mapa')],
      },
    );

    expect(tree.entries.keys.where((k) => k == 'item:n1'), hasLength(1));
    expect(tree.entries['item:n1']!.parentKey, 'topic:roma');
  });

  test('con un tope de nodos, lo más cercano a la raíz entra primero y se '
      'avisa de lo que falta', () {
    final tree = build(
      expanded: {roma.key, republica.key},
      links: {
        roma.key: [mapNote('n1', 'Mapa')],
      },
      maxNodes: 3,
    );

    // Raíz y sus dos subtemas; ni la nota ni Gracos entran.
    expect(titles(tree), ['Roma', 'Imperio', 'República']);
    expect(tree.truncated, isTrue);
  });

  group('si se puede desplegar', () {
    test('un tema con subtemas sí; uno sin ellos y sin vínculos pedidos, se '
        'supone que sí; uno con vínculos pedidos y vacíos, no', () {
      final open = build(expanded: {roma.key});
      // Imperio no tiene subtemas y sus notas no se pidieron.
      expect(open.entries['topic:imperio']!.canExpand, isTrue);
      // República tiene a Gracos.
      expect(open.entries['topic:republica']!.canExpand, isTrue);

      final asked = build(
        expanded: {roma.key},
        links: {'topic:imperio': const []},
      );
      expect(asked.entries['topic:imperio']!.canExpand, isFalse);
      expect(asked.entries['topic:republica']!.canExpand, isTrue);
    });
  });

  test('una raíz que no está en el grafo se llama por su identificador', () {
    final tree = build(root: const SchemaRef.topic('borrado'));

    expect(titles(tree), ['borrado']);
  });

  test('el mismo pedido da el mismo árbol', () {
    final a = build(expanded: {roma.key, republica.key});
    final b = build(expanded: {roma.key, republica.key});

    expect(titles(b), titles(a));
    expect(b.entries.keys.toList(), a.entries.keys.toList());
  });

  test('temas y elementos con el mismo identificador no se confunden', () {
    const topic = SchemaRef.topic('x');
    const item = SchemaRef.item('x');

    expect(topic == item, isFalse);
    expect(topic.key, isNot(item.key));
    expect(const SchemaRef.topic('x'), topic);
  });
}
