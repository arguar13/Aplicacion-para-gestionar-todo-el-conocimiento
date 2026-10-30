import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/schema_layout.dart';

/// Cuántos nodos dibuja el árbol del lienzo, como máximo: pasado eso, lo que
/// falta queda sin mostrar. Un esquema de miles de nodos no se puede leer.
const kMaxCanvasTreeNodes = 120;

/// Qué es un nodo del árbol del lienzo (F44, paso 2): lo que el Esquema
/// desplegaba —temas y elementos— y, arriba, lo que junta: todo lo que se mira,
/// una comunidad o lo vinculado.
enum CanvasTreeKind {
  /// Lo que se mira, entero: la raíz del árbol de las comunidades.
  all,

  /// Una comunidad de temas, o varias juntas: la raíz del árbol de sus temas.
  community,

  /// Los documentos vinculados entre sí, tengan o no tema.
  links,

  /// Un valor de la categoría que se mira.
  topic,

  /// Un documento: una nota o una fuente.
  item,
}

/// A qué se refiere un nodo del árbol del lienzo.
///
/// Los temas y los documentos son los mismos del Esquema ([schemaRef]); los
/// otros tres no están en la base: los arma el lienzo con lo que ya sabe.
@immutable
class CanvasTreeRef {
  const CanvasTreeRef.all() : kind = CanvasTreeKind.all, id = '';
  const CanvasTreeRef.links() : kind = CanvasTreeKind.links, id = '';
  const CanvasTreeRef.community(this.id) : kind = CanvasTreeKind.community;
  const CanvasTreeRef.topic(this.id) : kind = CanvasTreeKind.topic;
  const CanvasTreeRef.item(this.id) : kind = CanvasTreeKind.item;

  /// El nodo del Esquema que es [ref].
  factory CanvasTreeRef.of(SchemaRef ref) => switch (ref.kind) {
    SchemaNodeKind.topic => CanvasTreeRef.topic(ref.id),
    SchemaNodeKind.item => CanvasTreeRef.item(ref.id),
  };

  final CanvasTreeKind kind;
  final String id;

  /// Lo que la base sabe desplegar de este nodo: un tema o un documento.
  /// `null` en los que arma el lienzo.
  SchemaRef? get schemaRef => switch (kind) {
    CanvasTreeKind.topic => SchemaRef.topic(id),
    CanvasTreeKind.item => SchemaRef.item(id),
    _ => null,
  };

  /// Si lo arma el lienzo y no la base: sus hijos llegan ya sabidos.
  bool get isVirtual => schemaRef == null;

  /// Una clave única entre todos los nodos, para los desplegados y el árbol.
  String get key => '${kind.name}:$id';

  @override
  bool operator ==(Object other) =>
      other is CanvasTreeRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Cómo se une un nodo del árbol con su padre.
enum CanvasTreeEdge {
  /// Es parte de lo que el padre junta: una comunidad de todo, un tema de su
  /// comunidad, un documento de su tema.
  member,

  /// El tema es un subtema del padre en la jerarquía.
  subtopic,

  /// La nota mapa está asignada al tema.
  mapNote,

  /// Hay un vínculo entre los dos documentos: ver [CanvasTreeLink.relation].
  relation,
}

/// Un hijo posible de un nodo del árbol: a qué apunta, cómo se llama y por qué
/// se une con el padre.
class CanvasTreeLink {
  const CanvasTreeLink({
    required this.target,
    required this.title,
    required this.edge,
    this.relation,
    this.outgoing = true,
    this.isNote = false,
    this.group,
    this.count = 0,
  });

  /// El hijo tal como lo entrega la base para el Esquema.
  factory CanvasTreeLink.fromSchema(SchemaLink link) => CanvasTreeLink(
    target: CanvasTreeRef.of(link.target),
    title: link.title,
    edge: switch (link.edge) {
      SchemaEdgeKind.subtopic => CanvasTreeEdge.subtopic,
      SchemaEdgeKind.mapNote => CanvasTreeEdge.mapNote,
      SchemaEdgeKind.relation => CanvasTreeEdge.relation,
    },
    relation: link.relation,
    outgoing: link.outgoing,
    isNote: link.isNote,
  );

  final CanvasTreeRef target;
  final String title;
  final CanvasTreeEdge edge;

  /// El tipo de vínculo, cuando [edge] es [CanvasTreeEdge.relation].
  final RelationKind? relation;

  /// Si el vínculo sale del padre hacia este nodo, o llega desde él.
  final bool outgoing;

  /// Si el documento es una nota; si no, es una fuente.
  final bool isNote;

  /// La identidad de la comunidad, para el color; `null` si no tiene.
  final int? group;

  /// Cuántos temas junta, en una comunidad.
  final int count;
}

/// Un nodo del árbol ya armado: lo que se dibuja de él.
class CanvasTreeEntry {
  const CanvasTreeEntry({
    required this.ref,
    required this.title,
    required this.depth,
    required this.expanded,
    required this.canExpand,
    this.edge,
    this.relation,
    this.outgoing = true,
    this.isNote = false,
    this.group,
    this.count = 0,
    this.parentKey,
  });

  final CanvasTreeRef ref;
  final String title;
  final int depth;

  /// Si sus hijos están a la vista.
  final bool expanded;

  /// Si tiene algo que mostrar al desplegarlo: de un tema o un documento cuyos
  /// hijos todavía no se pidieron, se supone que sí.
  final bool canExpand;

  /// Cómo se une con su padre; `null` en la raíz.
  final CanvasTreeEdge? edge;
  final RelationKind? relation;
  final bool outgoing;

  /// Si es una nota —o una nota mapa—: lo usa el color.
  final bool isNote;

  /// La comunidad, para el color; `null` si no tiene una.
  final int? group;

  /// Cuántos temas junta, en una comunidad.
  final int count;

  /// La clave del padre, o `null` en la raíz.
  final String? parentKey;

  String get key => ref.key;
}

/// El árbol armado: la forma para [layoutRadial] y [layoutTree], y lo que se
/// dibuja de cada nodo.
class CanvasTree {
  const CanvasTree({
    required this.root,
    required this.entries,
    required this.truncated,
  });

  final SchemaNode root;

  /// Cada nodo por su clave, en el orden en que se armaron: la raíz primero.
  final Map<String, CanvasTreeEntry> entries;

  /// Si quedaron nodos sin dibujar por el tope.
  final bool truncated;
}

/// Arma el árbol del lienzo que parte de [root] (F44, paso 2): el despliegue
/// nodo a nodo del Esquema (F14, D6), sobre lo que se esté mirando.
///
/// Los hijos de cada nodo desplegado son, en este orden, los subtemas de la
/// jerarquía de [graph] —si es un tema— y lo que llega en [links] por su clave:
/// lo que el lienzo ya sabe de los nodos que arma él (las comunidades, los
/// temas de una comunidad, lo vinculado), y lo que la base trajo de un tema o
/// de un documento (sus notas mapa, sus documentos, sus vínculos). Un nodo
/// entra una sola vez, donde primero se lo encuentra (por niveles), y el árbol
/// tiene a lo sumo [maxNodes].
///
/// Un tema se llama como en [graph] y se colorea con [groupOf]; la raíz que no
/// es un tema se llama [rootTitle].
///
/// Es puro: dos veces con lo mismo da el mismo árbol.
CanvasTree buildCanvasTree({
  required CanvasTreeRef root,
  required TopicGraph graph,
  required Set<String> expanded,
  required Map<String, List<CanvasTreeLink>> links,
  String? rootTitle,
  int? rootGroup,
  int rootCount = 0,
  int? Function(String valueId)? groupOf,
  int maxNodes = kMaxCanvasTreeNodes,
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

  bool canExpand(CanvasTreeRef ref) {
    if (ref.kind == CanvasTreeKind.topic &&
        (childrenOf[ref.id]?.isNotEmpty ?? false)) {
      return true;
    }
    final known = links[ref.key];
    // Lo que arma el lienzo llega con sus hijos: sin ellos, no tiene. Lo que
    // trae la base se supone desplegable hasta pedirlo.
    if (known == null) return !ref.isVirtual;
    return known.isNotEmpty;
  }

  final entries = <String, CanvasTreeEntry>{};
  final children = <String, List<String>>{};
  var truncated = false;

  entries[root.key] = CanvasTreeEntry(
    ref: root,
    title: root.kind == CanvasTreeKind.topic
        ? titleOfTopic(root.id)
        : rootTitle ?? root.id,
    depth: 0,
    expanded: expanded.contains(root.key),
    canExpand: canExpand(root),
    group: root.kind == CanvasTreeKind.topic
        ? groupOf?.call(root.id) ?? rootGroup
        : rootGroup,
    count: rootCount,
  );

  // Por niveles: lo más cercano a la raíz entra primero si el tope no da para
  // tanto.
  var level = [root];
  while (level.isNotEmpty) {
    final next = <CanvasTreeRef>[];
    for (final parent in level) {
      if (!expanded.contains(parent.key)) continue;
      final parentEntry = entries[parent.key]!;
      final candidates = <CanvasTreeLink>[
        if (parent.kind == CanvasTreeKind.topic)
          for (final sub in childrenOf[parent.id] ?? const <TopicNode>[])
            CanvasTreeLink(
              target: CanvasTreeRef.topic(sub.valueId),
              title: sub.label,
              edge: CanvasTreeEdge.subtopic,
            ),
        ...?links[parent.key],
      ];
      for (final link in candidates) {
        if (entries.containsKey(link.target.key)) continue;
        if (entries.length >= maxNodes) {
          truncated = true;
          continue;
        }
        final target = link.target;
        entries[target.key] = CanvasTreeEntry(
          ref: target,
          title: link.title,
          depth: parentEntry.depth + 1,
          expanded: expanded.contains(target.key),
          canExpand: canExpand(target),
          edge: link.edge,
          relation: link.relation,
          outgoing: link.outgoing,
          isNote: link.isNote || link.edge == CanvasTreeEdge.mapNote,
          group: target.kind == CanvasTreeKind.topic
              ? groupOf?.call(target.id) ?? link.group
              : link.group,
          count: link.count,
          parentKey: parent.key,
        );
        (children[parent.key] ??= []).add(target.key);
        next.add(target);
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

  return CanvasTree(
    root: build(root.key),
    entries: entries,
    truncated: truncated,
  );
}

/// Los temas de [members] que no cuelgan de otro de [members]: las raíces de
/// lo que se mira, del que tiene más elementos al que menos —a igual número,
/// por nombre—. Lo de abajo sale al desplegarlos, por la jerarquía.
List<int> rootTopicsAmong(TopicGraph graph, Iterable<int> members) {
  final inside = {for (final m in members) graph.nodes[m].valueId};
  return [
    for (final m in members)
      if (!inside.contains(graph.nodes[m].parentId)) m,
  ]..sort((x, y) {
    final bySize = graph.nodes[y].itemCount.compareTo(graph.nodes[x].itemCount);
    return bySize != 0 ? bySize : x.compareTo(y);
  });
}
