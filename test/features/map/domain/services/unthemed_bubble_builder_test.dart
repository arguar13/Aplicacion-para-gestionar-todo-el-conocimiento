import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/unthemed_bubble.dart';
import 'package:sinapsis/features/map/domain/services/map_search_builder.dart';
import 'package:sinapsis/features/map/domain/services/unthemed_bubble_builder.dart';

import 'insights_fixtures.dart';

/// La burbuja «Sin tema» (F44): los documentos sin ningún valor de lo que se
/// mira, dibujados y no solo contados.
void main() {
  TopicItem loose(String id, {DateTime? at, bool isNote = false}) => TopicItem(
    id: id,
    valueIds: const [],
    title: 'Suelto $id',
    isNote: isNote,
    createdAt: at,
  );

  TopicRelation link(
    String from,
    String to, {
    RelationKind kind = RelationKind.relatedTo,
  }) => TopicRelation(fromItemId: from, toItemId: to, kind: kind);

  UnthemedBubble bubbleOf(TopicGraphInput input, {int limit = 200}) {
    final map = mapOf(input, {'roma': 1, 'grecia': 2});
    return buildUnthemedBubble(
      input: input,
      search: buildMapSearchIndex(
        graph: map.graph,
        detection: map.detection,
        input: input,
      ),
      limit: limit,
    );
  }

  /// i0 es de Roma e i1 de Grecia; los sueltos, de ninguno.
  TopicGraphInput vault({
    required List<TopicItem> unassigned,
    List<TopicRelation> relations = const [],
  }) => inputOf(
    ['roma', 'grecia'],
    [
      ['roma'],
      ['grecia'],
    ],
    unassigned: unassigned,
    relations: relations,
  );

  test('sus documentos, los procesados más recientemente primero y los sin '
      'fecha al final, con su título y su rol', () {
    final bubble = bubbleOf(
      vault(
        unassigned: [
          loose('sin-fecha'),
          loose('viejo', at: DateTime(2026)),
          loose('nuevo', at: DateTime(2026, 10), isNote: true),
          loose('a-sin-fecha'),
        ],
      ),
    );

    expect(bubble.count, 4);
    expect(bubble.isEmpty, isFalse);
    expect(bubble.items.valueId, kUnthemedBubbleId);
    expect(
      [for (final i in bubble.items.items) i.id],
      ['nuevo', 'viejo', 'a-sin-fecha', 'sin-fecha'],
    );
    expect(bubble.items.items.first.title, 'Suelto nuevo');
    expect(bubble.items.items.first.isNote, isTrue);
    expect(bubble.items.truncated, isFalse);
  });

  test('con más que el tope, dibuja los más nuevos y avisa que hay más', () {
    final bubble = bubbleOf(
      vault(
        unassigned: [
          for (var day = 1; day <= 5; day++)
            loose('d$day', at: DateTime(2026, 10, day)),
        ],
      ),
      limit: 2,
    );

    expect(bubble.count, 5);
    expect([for (final i in bubble.items.items) i.id], ['d5', 'd4']);
    expect(bubble.items.truncated, isTrue);
  });

  test('los vínculos entre sus documentos se dibujan; los que van a uno con '
      'tema la unen con su comunidad', () {
    final bubble = bubbleOf(
      vault(
        unassigned: [
          loose('a', at: DateTime(2026, 10, 3)),
          loose('b', at: DateTime(2026, 10, 2)),
          loose('c', at: DateTime(2026, 10)),
          loose('solo'),
        ],
        relations: [
          link('a', 'b', kind: RelationKind.cites),
          // Un extremo con tema: hacia Roma, dos; hacia Grecia, uno.
          link('a', 'i0'),
          link('i0', 'c'),
          link('b', 'i1'),
          // Entre dos con tema: no es de la burbuja.
          link('i0', 'i1'),
          // Consigo mismo: no une nada.
          link('solo', 'solo'),
        ],
      ),
    );

    final edge = bubble.items.edges.single;
    expect(bubble.items.items[edge.a].id, 'a');
    expect(bubble.items.items[edge.b].id, 'b');
    expect(edge.kind, RelationKind.cites);
    expect([for (final c in bubble.communities) c.communityId], [1, 2]);
    expect([for (final c in bubble.communities) c.weight], [2, 1]);
    expect(bubble.linkedCount, 3);
  });

  test(
    'un vínculo con un documento que no se dibuja no se dibuja a medias',
    () {
      final bubble = bubbleOf(
        vault(
          unassigned: [
            loose('nuevo', at: DateTime(2026, 10, 2)),
            loose('viejo', at: DateTime(2026, 10)),
          ],
          relations: [link('nuevo', 'viejo')],
        ),
        limit: 1,
      );

      expect(bubble.items.edges, isEmpty);
      expect(bubble.linkedCount, 2);
    },
  );

  test('sin documentos sin tema, la burbuja está vacía', () {
    final bubble = bubbleOf(vault(unassigned: const []));

    expect(bubble.isEmpty, isTrue);
    expect(bubble.items.items, isEmpty);
    expect(bubble.communities, isEmpty);
  });
}
