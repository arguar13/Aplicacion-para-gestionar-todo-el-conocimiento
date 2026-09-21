import 'dart:math';

import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// Los temas de una bóveda con la FORMA que tiene una de verdad: los
/// elementos se juntan por área de conocimiento, y lo que se vincula suele ser
/// de la misma área.
///
/// La bóveda sintética (`synthetic_vault.dart`) reparte los valores de cada
/// elemento al azar, sin relación entre unos y otros: sirve para medir
/// búsquedas y lecturas, pero su grafo de temas es una maraña al azar de 94.000
/// uniones sin estructura, en la que el detector encuentra UNA sola comunidad y
/// el panorama es un solo nodo. Eso mide el peor coste de construir el grafo,
/// pero no dice nada de cuántas comunidades salen, de cuánto se mueven tras un
/// cambio ni de cómo se ve y se recorre el panorama.
///
/// Esta función conserva el ÁRBOL de temas de [vault] —los mismos valores, con
/// sus mismos padres— y rehace lo que se les asigna:
///
/// - cada elemento tiene un área, que es una rama de primer nivel, elegida con
///   más probabilidad cuanto más grande es la rama, y de 1 a 4 temas de esa
///   área, con preferencia por los primeros de la rama —los más generales—;
/// - una parte de los elementos tiene además un tema de OTRA área: los puentes,
///   sin los cuales cada área sería una isla;
/// - la mayoría de los vínculos unen elementos de la misma área.
///
/// Es determinista: la misma semilla da siempre lo mismo.
TopicGraphInput structuredTopicInput(
  TopicGraphInput vault, {
  int items = 10000,
  int relations = 25000,
  int seed = 14,
  double bridgeShare = 0.08,
  double intraAreaLinkShare = 0.85,
}) {
  final random = Random(seed);
  final values = vault.values;

  // La rama de primer nivel de cada valor.
  final parentOf = {for (final v in values) v.id: v.parentId};
  String rootOf(String id) {
    var current = id;
    while (parentOf[current] != null) {
      current = parentOf[current]!;
    }
    return current;
  }

  final areas = <String, List<String>>{};
  for (final value in values) {
    areas.putIfAbsent(rootOf(value.id), () => []).add(value.id);
  }
  final areaIds = areas.keys.toList()..sort();

  // Elegir un área con probabilidad proporcional a su tamaño.
  final cumulative = <int>[];
  var total = 0;
  for (final id in areaIds) {
    total += areas[id]!.length;
    cumulative.add(total);
  }
  String pickArea() {
    final roll = random.nextInt(total);
    return areaIds[cumulative.indexWhere((edge) => roll < edge)];
  }

  /// Un tema del área, con preferencia por los primeros: el cuadrado de un
  /// número entre 0 y 1 apila las elecciones hacia el principio.
  String pickTopic(List<String> members) =>
      members[(pow(random.nextDouble(), 2) * members.length).floor()];

  final itemAreas = <String>[];
  final itemsByArea = <String, List<int>>{};
  final topicItems = <TopicItem>[];
  for (var i = 0; i < items; i++) {
    final area = pickArea();
    final members = areas[area]!;
    final count = switch (random.nextDouble()) {
      < 0.20 => 1,
      < 0.55 => 2,
      < 0.85 => 3,
      _ => 4,
    };
    final chosen = <String>{for (var k = 0; k < count; k++) pickTopic(members)};
    if (areaIds.length > 1 && random.nextDouble() < bridgeShare) {
      String other;
      do {
        other = pickArea();
      } while (other == area);
      chosen.add(pickTopic(areas[other]!));
    }
    itemAreas.add(area);
    (itemsByArea[area] ??= []).add(i);
    topicItems.add(TopicItem(id: 'e$i', valueIds: chosen.toList()));
  }

  RelationKind pickKind() => switch (random.nextDouble()) {
    < 0.45 => RelationKind.relatedTo,
    < 0.70 => RelationKind.cites,
    < 0.80 => RelationKind.continues,
    < 0.88 => RelationKind.summarizes,
    < 0.96 => RelationKind.extractedFrom,
    _ => RelationKind.contradicts,
  };

  final topicRelations = <TopicRelation>[];
  final seen = <String>{};
  var attempts = 0;
  while (topicRelations.length < relations && attempts < relations * 4) {
    attempts++;
    final from = random.nextInt(items);
    final int to;
    if (random.nextDouble() < intraAreaLinkShare) {
      final sameArea = itemsByArea[itemAreas[from]]!;
      to = sameArea[random.nextInt(sameArea.length)];
    } else {
      to = random.nextInt(items);
    }
    if (from == to) continue;
    final kind = pickKind();
    if (!seen.add('$from|$to|${kind.name}')) continue;
    topicRelations.add(
      TopicRelation(
        fromItemId: 'e$from',
        toItemId: 'e$to',
        kind: kind,
        reviewed: kind == RelationKind.contradicts && random.nextDouble() < 0.3,
      ),
    );
  }

  return TopicGraphInput(
    definitionId: vault.definitionId,
    definitionName: vault.definitionName,
    values: values,
    items: topicItems,
    relations: topicRelations,
  );
}
