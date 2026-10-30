import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/community_profile.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/community_links.dart';
import 'package:sinapsis/features/map/domain/services/community_profiler.dart';
import 'package:sinapsis/features/map/domain/services/topic_graph_builder.dart';

import 'insights_fixtures.dart';

/// Lo que se sabe de cada comunidad (F44): su nombre con sus dos temas
/// principales y lo que dice su ficha.
void main() {
  CommunityProfiles profilesOf(TopicGraphInput input, Map<String, int> of) {
    final map = mapOf(input, of);
    return profileCommunities(
      graph: map.graph,
      detection: map.detection,
      adjacency: map.adjacency,
      links: CommunityLinks.of(map.adjacency, map.detection),
      input: input,
    );
  }

  List<String> labelsOf(TopicGraphInput input, CommunityProfile profile) {
    final graph = buildTopicGraph(input);
    return [for (final t in profile.topics) graph.nodes[t].label];
  }

  /// A: a1, a2 y a3 —a3 es un puente hacia B, con diez documentos—; B: b1 y
  /// b2. Por dentro de A, a2 es el más unido (seis: tres documentos y un
  /// vínculo con a1, uno con a3), después a1 (cinco) y al final a3 (uno),
  /// aunque en total a3 sea el más unido (trece) y a1 el menos (nueve).
  TopicGraphInput bridged() => inputOf(
    ['a1', 'a2', 'a3', 'b1', 'b2'],
    [
      ...repeat(3, ['a1', 'a2']),
      ['a2', 'a3'],
      ...repeat(5, ['a3', 'b1']),
      ['b1', 'b2'],
      // i10 a i14: más de a3 hacia B, para que en total sea el más unido.
      ...repeat(5, ['a3', 'b2']),
    ],
    labels: {
      'a1': 'Tomás de Aquino',
      'a2': 'Cristianismo',
      'a3': 'Imperio romano',
    },
    relations: [
      // i0 e i1 son de A: el vínculo queda adentro.
      const TopicRelation(
        fromItemId: 'i0',
        toItemId: 'i1',
        kind: RelationKind.relatedTo,
      ),
      // i0 es de A e i9 de B: une las dos, no queda adentro de ninguna.
      const TopicRelation(
        fromItemId: 'i0',
        toItemId: 'i9',
        kind: RelationKind.relatedTo,
      ),
      // i4 tiene un tema de cada una: el vínculo con i5, que también, queda
      // adentro de las dos.
      const TopicRelation(
        fromItemId: 'i4',
        toItemId: 'i5',
        kind: RelationKind.cites,
      ),
      // Un vínculo de un documento consigo mismo no une nada.
      const TopicRelation(
        fromItemId: 'i1',
        toItemId: 'i1',
        kind: RelationKind.relatedTo,
      ),
    ],
    itemDates: {
      'i0': DateTime(2026, 10),
      'i3': DateTime(2026, 10, 9),
      'i9': DateTime(2026, 10, 20),
    },
  );

  const bridgedCommunities = {'a1': 1, 'a2': 1, 'a3': 1, 'b1': 2, 'b2': 2};

  test('el nombre son sus dos temas más unidos con los DEMÁS de la '
      'comunidad, no con todo el mapa', () {
    final input = bridged();
    final profiles = profilesOf(input, bridgedCommunities);

    final a = profiles.of(1)!;
    expect(a.name, 'Cristianismo · Tomás de Aquino');
    expect(a.nameLabels, ['Cristianismo', 'Tomás de Aquino']);
    // La ficha tiene todos, en el mismo orden.
    expect(labelsOf(input, a), [
      'Cristianismo',
      'Tomás de Aquino',
      'Imperio romano',
    ]);
  });

  test('a igual unión, el de más documentos; y dos temas que se llaman '
      'igual no se repiten en el nombre', () {
    final input = inputOf(
      ['roma1', 'roma2', 'imperio', 'otro'],
      [
        ['roma1', 'roma2'],
        ['roma2', 'imperio'],
        ['roma1', 'imperio'],
        ['imperio'],
        ...repeat(3, ['roma1']),
        ...repeat(2, ['roma2']),
        ['otro'],
      ],
      labels: {'roma1': 'Roma', 'roma2': 'ROMA', 'imperio': 'Imperio'},
    );

    final profiles = profilesOf(input, {
      'roma1': 1,
      'roma2': 1,
      'imperio': 1,
      'otro': 2,
    });

    // Los tres se unen con peso dos; roma1 tiene cinco documentos, roma2
    // cuatro e imperio tres. «ROMA» es «Roma»: el nombre salta a «Imperio».
    final roma = profiles.of(1)!;
    expect(labelsOf(input, roma), ['Roma', 'ROMA', 'Imperio']);
    expect(roma.name, 'Roma · Imperio');
    // Una comunidad de un solo tema tiene un solo nombre.
    expect(profiles.of(2)!.nameLabels, ['Otro']);
  });

  test('cuenta sus documentos una vez, los vínculos que le quedan adentro y '
      'con quién se une', () {
    final profiles = profilesOf(bridged(), bridgedCommunities);

    final a = profiles.of(1)!;
    final b = profiles.of(2)!;
    // A: tres de a1·a2, uno de a2·a3, cinco de a3·b1 y cinco de a3·b2. B: esos
    // diez y b1·b2.
    expect(a.documentCount, 14);
    expect(b.documentCount, 11);
    // i0–i1 y i4–i5 en A; i4–i5 en B. El de i1 consigo mismo no cuenta.
    expect(a.linkCount, 2);
    expect(b.linkCount, 1);
    expect([for (final n in a.neighbors) n.communityId], [2]);
    // Diez documentos de a3 con b1 o b2 (10), el vínculo i4–i5 entre a3 y b1
    // (2) y el de i0 con i9, entre a1 o a2 y b1 o b2 (cuatro pares de 2).
    expect(a.neighbors.single.weight, 20);
    expect([for (final n in b.neighbors) n.communityId], [1]);
  });

  test('lo más reciente es el documento procesado último; sin fechas, '
      'ninguno', () {
    final profiles = profilesOf(bridged(), bridgedCommunities);

    // i9 es el último, pero es solo de B: el de A es i3.
    expect(profiles.of(1)!.latestItemId, 'i3');
    expect(profiles.of(2)!.latestItemId, 'i9');

    final undated = profilesOf(
      inputOf(
        ['a', 'b'],
        [
          ['a', 'b'],
        ],
      ),
      {'a': 1, 'b': 1},
    );
    expect(undated.of(1)!.latestItemId, isNull);
  });

  test('una por comunidad, en el orden de las comunidades, y ninguna de una '
      'comunidad que no existe', () {
    final profiles = profilesOf(bridged(), bridgedCommunities);

    expect([for (final p in profiles.all) p.communityId], [1, 2]);
    expect(profiles.of(99), isNull);
  });
}
