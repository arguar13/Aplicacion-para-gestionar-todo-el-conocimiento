import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/schema_layout.dart';

/// Cuántos nodos dibuja el esquema, como máximo: pasado eso, lo que falta queda
/// sin mostrar. Un esquema de miles de nodos no se puede leer.
const kMaxSchemaNodes = 120;

/// El esquema armado: el árbol para el layout y lo que se dibuja de cada nodo.
class SchemaTree {
  const SchemaTree({
    required this.root,
    required this.entries,
    required this.truncated,
  });

  /// El árbol para [layoutRadial] y [layoutTree].
  final SchemaNode root;

  /// Cada nodo por su clave (`SchemaRef.key`), en el orden en que se armaron:
  /// la raíz primero.
  final Map<String, SchemaEntry> entries;

  /// Si quedaron nodos sin dibujar por el tope [kMaxSchemaNodes].
  final bool truncated;
}

/// Arma el esquema que parte de [root] (F14, D6): los hijos de cada nodo
/// desplegado, sin repetir ninguno.
///
/// Los subtemas de un tema salen de la jerarquía de [graph]; las notas mapa
/// de un tema y los vínculos de una nota los trajo la base y llegan en [links],
/// por la clave del nodo. Un nodo entra una sola vez, donde primero se lo
/// encuentra (por niveles), y el esquema tiene a lo sumo [maxNodes]. Un tema se
/// llama como en [graph]; un elemento raíz, [rootTitle].
///
/// Es puro: dos veces con lo mismo da el mismo árbol.
SchemaTree buildSchemaTree({
  required SchemaRef root,
  required TopicGraph graph,
  required Set<String> expanded,
  required Map<String, List<SchemaLink>> links,
  String? rootTitle,
  int maxNodes = kMaxSchemaNodes,
}) {
  // Los hijos directos de cada tema en la jerarquía, por posición: el orden de
  // los nodos del grafo es por nombre.
  final childrenOf = <String, List<TopicNode>>{};
  for (final node in graph.nodes) {
    final parent = node.parentId;
    if (parent != null) (childrenOf[parent] ??= []).add(node);
  }
  String titleOfTopic(String valueId) {
    final index = graph.indexOf(valueId);
    return index == null ? valueId : graph.nodes[index].label;
  }

  final entries = <String, SchemaEntry>{};
  final children = <String, List<String>>{};
  var truncated = false;

  void addEntry(SchemaEntry entry) {
    entries[entry.key] = entry;
  }

  addEntry(
    SchemaEntry(
      ref: root,
      title: root.kind == SchemaNodeKind.topic
          ? titleOfTopic(root.id)
          : rootTitle ?? root.id,
      depth: 0,
      expanded: expanded.contains(root.key),
      canExpand: _canExpand(root, childrenOf, links),
    ),
  );

  // Por niveles: lo más cercano a la raíz entra primero si el tope no da para
  // tanto.
  var level = [root];
  while (level.isNotEmpty) {
    final next = <SchemaRef>[];
    for (final parent in level) {
      if (!expanded.contains(parent.key)) continue;
      final parentEntry = entries[parent.key]!;
      final candidates = <SchemaLink>[
        if (parent.kind == SchemaNodeKind.topic)
          for (final sub in childrenOf[parent.id] ?? const <TopicNode>[])
            SchemaLink(
              target: SchemaRef.topic(sub.valueId),
              title: sub.label,
              edge: SchemaEdgeKind.subtopic,
            ),
        ...?links[parent.key],
      ];
      for (final link in candidates) {
        if (entries.containsKey(link.target.key)) continue;
        if (entries.length >= maxNodes) {
          truncated = true;
          continue;
        }
        addEntry(
          SchemaEntry(
            ref: link.target,
            title: link.title,
            depth: parentEntry.depth + 1,
            expanded: expanded.contains(link.target.key),
            canExpand: _canExpand(link.target, childrenOf, links),
            edge: link.edge,
            relation: link.relation,
            outgoing: link.outgoing,
            isNote: link.isNote || link.edge == SchemaEdgeKind.mapNote,
            parentKey: parent.key,
          ),
        );
        (children[parent.key] ??= []).add(link.target.key);
        next.add(link.target);
      }
    }
    level = next;
  }

  SchemaNode build(String key) => SchemaNode(
    key,
    children: [
      for (final child in children[key] ?? const <String>[]) build(child),
    ],
  );

  return SchemaTree(
    root: build(root.key),
    entries: entries,
    truncated: truncated,
  );
}

/// Si el nodo puede tener hijos: un tema con subtemas sí; un nodo cuyos
/// vínculos no se pidieron todavía, se supone que sí; uno cuyos vínculos se
/// pidieron y vinieron vacíos, no.
bool _canExpand(
  SchemaRef ref,
  Map<String, List<TopicNode>> childrenOf,
  Map<String, List<SchemaLink>> links,
) {
  if (ref.kind == SchemaNodeKind.topic &&
      (childrenOf[ref.id]?.isNotEmpty ?? false)) {
    return true;
  }
  final fetched = links[ref.key];
  return fetched == null || fetched.isNotEmpty;
}
