import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';

/// Qué es un nodo del esquema (F14, D6).
enum SchemaNodeKind {
  /// Un valor de la categoría que se mira.
  topic,

  /// Un elemento —una nota, o una fuente que una nota reúne o cita—.
  item,
}

/// A qué se refiere un nodo del esquema: un tema o un elemento, por su
/// identificador.
@immutable
class SchemaRef {
  const SchemaRef.topic(this.id) : kind = SchemaNodeKind.topic;
  const SchemaRef.item(this.id) : kind = SchemaNodeKind.item;

  final SchemaNodeKind kind;
  final String id;

  /// Una clave única entre temas y elementos, para el conjunto de los
  /// desplegados y para el árbol.
  String get key => '${kind.name}:$id';

  @override
  bool operator ==(Object other) =>
      other is SchemaRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Cómo se une un nodo del esquema con su padre.
enum SchemaEdgeKind {
  /// El tema es un subtema del padre en la jerarquía.
  subtopic,

  /// La nota mapa está asignada al tema.
  mapNote,

  /// Hay un vínculo entre los dos elementos: ver [SchemaLink.relation].
  relation,
}

/// Un hijo posible de un nodo del esquema, tal como lo entrega la base: a qué
/// apunta, cómo se llama y por qué se une con el padre.
class SchemaLink {
  const SchemaLink({
    required this.target,
    required this.title,
    required this.edge,
    this.relation,
    this.outgoing = true,
    this.isNote = false,
  });

  final SchemaRef target;
  final String title;
  final SchemaEdgeKind edge;

  /// El tipo de vínculo, cuando [edge] es [SchemaEdgeKind.relation].
  final RelationKind? relation;

  /// Si el vínculo sale del padre hacia este nodo, o llega desde él.
  final bool outgoing;

  /// Si el elemento es una nota; si no, es una fuente.
  final bool isNote;
}

/// Un nodo del esquema ya armado: lo que se dibuja de él.
class SchemaEntry {
  const SchemaEntry({
    required this.ref,
    required this.title,
    required this.depth,
    required this.expanded,
    required this.canExpand,
    this.edge,
    this.relation,
    this.outgoing = true,
    this.isNote = false,
    this.parentKey,
  });

  final SchemaRef ref;
  final String title;
  final int depth;

  /// Si sus hijos están a la vista.
  final bool expanded;

  /// Si tiene algo que mostrar al desplegarlo: todavía no se sabe de un nodo
  /// cuyos vínculos no se pidieron.
  final bool canExpand;

  /// Cómo se une con su padre; `null` en la raíz.
  final SchemaEdgeKind? edge;
  final RelationKind? relation;
  final bool outgoing;

  /// Si es una nota (o un tema con una nota mapa por padre): lo usa el color.
  final bool isNote;

  /// La clave del padre, o `null` en la raíz.
  final String? parentKey;

  String get key => ref.key;
}
