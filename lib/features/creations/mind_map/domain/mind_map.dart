import 'package:flutter/foundation.dart';

/// De dónde sale una idea del mapa: el documento procesado y, si la IA lo
/// dio, el pasaje —unas palabras literales del material— que la sostiene.
@immutable
class MindMapSource {
  const MindMapSource({this.documentId, this.documentTitle, this.quote});

  /// El documento procesado, si se reconoció el título que dio la IA entre
  /// las fuentes del material; `null` si no.
  final String? documentId;

  /// El título tal como lo escribió la IA (o el de la fuente, si se
  /// reconoció).
  final String? documentTitle;

  /// Unas palabras literales del material: con ellas «Ver en el documento»
  /// abre la lectura parada en el pasaje.
  final String? quote;

  bool get isEmpty =>
      documentId == null &&
      (documentTitle == null || documentTitle!.isEmpty) &&
      (quote == null || quote!.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is MindMapSource &&
      other.documentId == documentId &&
      other.documentTitle == documentTitle &&
      other.quote == quote;

  @override
  int get hashCode => Object.hash(documentId, documentTitle, quote);

  @override
  String toString() => 'MindMapSource($documentId, «$quote»)';
}

/// Una idea del mapa mental, con las que cuelgan de ella.
///
/// [id] es el camino desde la raíz —`0`, `0.2`, `0.2.1`—: estable para el
/// mismo contenido, que es lo que recuerda qué ramas están abiertas.
@immutable
class MindMapNode {
  const MindMapNode({
    required this.id,
    required this.label,
    this.note,
    this.source,
    this.children = const [],
  });

  final String id;

  /// El nombre de la idea: corto, lo que se ve en el nodo.
  final String label;

  /// Una frase que la explica, si la IA la dio: se ve al tocar el nodo.
  final String? note;

  final MindMapSource? source;
  final List<MindMapNode> children;

  bool get hasChildren => children.isNotEmpty;

  /// Cuántas ideas hay de acá para abajo, esta incluida.
  int get size => children.fold(1, (sum, child) => sum + child.size);

  /// Cuántos niveles hay de acá para abajo: 1 si es una hoja.
  int get depth => children.isEmpty
      ? 1
      : 1 + children.map((c) => c.depth).reduce((a, b) => a > b ? a : b);

  /// Esta y todas las de abajo, en preorden.
  Iterable<MindMapNode> get descendants sync* {
    yield this;
    for (final child in children) {
      yield* child.descendants;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MindMapNode &&
      other.id == id &&
      other.label == label &&
      other.note == note &&
      other.source == source &&
      listEquals(other.children, children);

  @override
  int get hashCode =>
      Object.hash(id, label, note, source, Object.hashAll(children));

  @override
  String toString() => 'MindMapNode($id, $label, ${children.length} ramas)';
}

/// Un mapa mental (F43, punto 5 del plan): un árbol de ideas, de lo general a
/// lo particular, con una sola raíz. La IA da los datos (decisión G); el
/// dibujo —el árbol horizontal, los colores, cómo se abre— es de la app.
@immutable
class MindMap {
  const MindMap({required this.title, required this.root});

  /// El título de la creación: el de la raíz si la IA no dio otro.
  final String title;
  final MindMapNode root;

  /// Cuántas ideas tiene, la raíz incluida.
  int get size => root.size;

  /// La idea [id], o `null` si no está.
  MindMapNode? find(String id) {
    for (final node in root.descendants) {
      if (node.id == id) return node;
    }
    return null;
  }

  /// El camino de la raíz hasta [id], los dos incluidos; vacío si no está.
  List<MindMapNode> pathTo(String id) {
    final path = <MindMapNode>[];
    bool walk(MindMapNode node) {
      path.add(node);
      if (node.id == id) return true;
      for (final child in node.children) {
        if (walk(child)) return true;
      }
      path.removeLast();
      return false;
    }

    walk(root);
    return path;
  }

  @override
  bool operator ==(Object other) =>
      other is MindMap && other.title == title && other.root == root;

  @override
  int get hashCode => Object.hash(title, root);
}
