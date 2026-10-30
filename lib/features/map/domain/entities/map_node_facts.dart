import 'package:meta/meta.dart';

/// Un nodo del lienzo del Mapa por lo que es, no por cómo se dibuja (F44, paso
/// 4): lo que abre la ficha, lo que se centra con «Centrar aquí» y adónde lleva
/// un vecino de la ficha. Es el mismo en la red, en Radial y Árbol y en la
/// lista.
@immutable
sealed class MapNodeRef {
  const MapNodeRef();

  /// Lo que es el nodo de la escena con la clave [key] —`overview:3`,
  /// `topic:roma`, `item:i1`—, o `null` si no es ninguno de los tres.
  static MapNodeRef? ofSceneKey(String key) {
    final colon = key.indexOf(':');
    if (colon <= 0 || colon == key.length - 1) return null;
    final id = key.substring(colon + 1);
    return switch (key.substring(0, colon)) {
      'overview' => switch (int.tryParse(id)) {
        final index? => MapCommunityRef(index),
        null => null,
      },
      'topic' => MapTopicRef(id),
      'item' => MapDocumentRef(id),
      _ => null,
    };
  }

  /// Su clave en la escena del lienzo (`GraphScene`).
  String get sceneKey;
}

/// Un nodo de lejos: una comunidad o lo que junta varias —el desborde, los
/// aislados—, por su posición en el panorama (`CommunityOverview.nodes`).
final class MapCommunityRef extends MapNodeRef {
  const MapCommunityRef(this.index);

  final int index;

  @override
  String get sceneKey => 'overview:$index';

  @override
  bool operator ==(Object other) =>
      other is MapCommunityRef && other.index == index;

  @override
  int get hashCode => Object.hash(MapCommunityRef, index);

  @override
  String toString() => 'MapCommunityRef($index)';
}

/// Un tema, por su valor.
final class MapTopicRef extends MapNodeRef {
  const MapTopicRef(this.valueId);

  final String valueId;

  @override
  String get sceneKey => 'topic:$valueId';

  @override
  bool operator ==(Object other) =>
      other is MapTopicRef && other.valueId == valueId;

  @override
  int get hashCode => Object.hash(MapTopicRef, valueId);

  @override
  String toString() => 'MapTopicRef($valueId)';
}

/// Un documento procesado, por su identificador.
final class MapDocumentRef extends MapNodeRef {
  const MapDocumentRef(this.itemId);

  final String itemId;

  @override
  String get sceneKey => 'item:$itemId';

  @override
  bool operator ==(Object other) =>
      other is MapDocumentRef && other.itemId == itemId;

  @override
  int get hashCode => Object.hash(MapDocumentRef, itemId);

  @override
  String toString() => 'MapDocumentRef($itemId)';
}

/// Qué es el nodo de una ficha.
enum MapNodeKind {
  /// Una comunidad de temas.
  community,

  /// Lo que junta varias comunidades: las más chicas, o los temas aislados.
  group,

  /// Un tema (o una etiqueta, o un valor).
  topic,

  /// Una fuente procesada.
  source,

  /// Una nota.
  note,
}

/// Algo que la ficha nombra y que se puede tocar para ir ahí: un vecino de
/// «Une con», «Lo más reciente» o el tema de un documento.
@immutable
class MapNodeNeighbor {
  const MapNodeNeighbor({
    required this.ref,
    required this.label,
    String? shortLabel,
  }) : shortLabel = shortLabel ?? label;

  final MapNodeRef ref;

  /// Cómo se muestra: una comunidad, con sus dos temas principales.
  final String label;

  /// Cómo se lo nombra en una frase —la pregunta al chat—: una comunidad, por
  /// su tema principal.
  final String shortLabel;

  @override
  bool operator ==(Object other) =>
      other is MapNodeNeighbor &&
      other.ref == ref &&
      other.label == label &&
      other.shortLabel == shortLabel;

  @override
  int get hashCode => Object.hash(ref, label, shortLabel);
}

/// Lo que dice la ficha de un nodo del lienzo (F44, paso 4): qué es, cuánto
/// tiene, con qué se une y lo más reciente. Sale de lo que el lienzo ya tiene
/// —el grafo, lo que sabe el motor (`MapInsights`) y lo que se dibuja—, sin la
/// base: abrir la ficha no recalcula nada.
@immutable
class MapNodeFacts {
  const MapNodeFacts({
    required this.ref,
    required this.kind,
    required this.title,
    this.group,
    this.nameLabels = const [],
    this.topicNames = const [],
    this.topicCount = 0,
    this.documentCount,
    this.linkCount,
    this.neighbors = const [],
    this.latest,
    this.place,
    this.within,
  });

  final MapNodeRef ref;
  final MapNodeKind kind;

  /// El nombre: el de una comunidad dice sus dos temas principales. Vacío en
  /// un grupo, que se rotula con su clase.
  final String title;

  /// La identidad de la comunidad —la propia o la del tema—, para el color.
  final int? group;

  /// De una comunidad, los nombres de sus temas principales, por separado:
  /// así se nombra en una frase.
  final List<String> nameLabels;

  /// De una comunidad, sus temas del más importante al menos, los primeros
  /// `kMapNodeTopicNames`: «en la ficha, todos».
  final List<String> topicNames;

  /// De una comunidad o un grupo, cuántos temas junta; de un tema, con cuántos
  /// se une.
  final int topicCount;

  /// De una comunidad, cuántos documentos tiene; de un tema, cuántos tiene
  /// asignados directamente. `null` si no se sabe.
  final int? documentCount;

  /// De una comunidad, cuántos vínculos unen dos de sus documentos; de un
  /// documento dibujado, cuántos vínculos suyos se ven. `null` si no se sabe.
  final int? linkCount;

  /// «Une con»: los vecinos más fuertes, del más al menos, como mucho
  /// `kMapNodeNeighbors`.
  final List<MapNodeNeighbor> neighbors;

  /// De una comunidad, su documento procesado más recientemente.
  final MapNodeNeighbor? latest;

  /// De un documento, el tema por el que se llega a él en el Mapa.
  final MapNodeNeighbor? place;

  /// De un tema, el nombre de su comunidad.
  final String? within;

  bool get isDocument => kind == MapNodeKind.source || kind == MapNodeKind.note;

  /// Si tiene una altura más cerca a la que bajar: «Entrar».
  bool get canEnter => !isDocument;
}
