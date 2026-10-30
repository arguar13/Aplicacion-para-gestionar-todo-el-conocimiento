import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/map/domain/entities/map_recent.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/map_recent_builder.dart';
import 'package:sinapsis/features/map/domain/services/map_search_builder.dart';

import 'insights_fixtures.dart';

/// Lo nuevo del mapa (F44): lo procesado y lo vinculado de la semana y del
/// mes, y cuánto cambiaron las cifras.
void main() {
  final now = DateTime(2026, 10, 30, 12);

  TopicRelation link(String from, String to, DateTime? at) => TopicRelation(
    fromItemId: from,
    toItemId: to,
    kind: RelationKind.relatedTo,
    createdAt: at,
  );

  MapRecent recentOf(TopicGraphInput input, {int communitiesBefore = 0}) {
    final map = mapOf(input, {for (final value in input.values) value.id: 1});
    return buildMapRecent(
      input: input,
      graph: map.graph,
      detection: map.detection,
      search: buildMapSearchIndex(
        graph: map.graph,
        detection: map.detection,
        input: input,
      ),
      communitiesBefore: communitiesBefore,
    );
  }

  /// i0 se procesó esta semana, i1 este mes, i2 hace meses e i3 no se sabe;
  /// «suelto», sin tema, esta semana. El tema «nuevo» se creó este mes.
  TopicGraphInput vault({DateTime? readAt}) {
    final base = inputOf(
      ['roma', 'grecia', 'nuevo'],
      [
        ['roma'],
        ['grecia'],
        ['roma', 'grecia'],
        ['roma'],
      ],
      itemDates: {
        'i0': DateTime(2026, 10, 29),
        'i1': DateTime(2026, 10, 10),
        'i2': DateTime(2026, 8),
      },
      unassigned: [
        TopicItem(
          id: 'suelto',
          valueIds: const [],
          title: 'Suelto',
          createdAt: DateTime(2026, 10, 25),
        ),
      ],
      relations: [
        link('i2', 'i3', DateTime(2026, 8, 2)),
        link('i0', 'i1', DateTime(2026, 10, 28)),
        link('i1', 'i2', DateTime(2026, 10, 5)),
        // Con fecha vieja pero con un documento de este mes —llegó con una
        // importación—: hace un mes no podía estar.
        link('i1', 'i3', DateTime(2026, 8, 3)),
        // Consigo mismo: no es un vínculo entre dos documentos.
        link('i3', 'i3', DateTime(2026, 10, 29)),
      ],
      readAt: readAt,
    );
    return TopicGraphInput(
      definitionId: base.definitionId,
      definitionName: base.definitionName,
      values: base.values,
      items: base.items,
      relations: base.relations,
      unassigned: base.unassigned,
      valueCreatedAt: {
        'grecia': DateTime(2026, 5),
        'nuevo': DateTime(2026, 10, 15),
      },
      readAt: base.readAt,
    );
  }

  List<String> idsOf(RecentWindow window) => [
    for (final entry in window.processed) entry.id,
  ];

  test('la semana y el mes: lo procesado y lo vinculado, lo más nuevo '
      'primero, con tema o sin él', () {
    final recent = recentOf(vault(readAt: now));

    expect(recent.at, now);
    expect(recent.week.days, kRecentWeekDays);
    expect(recent.week.processedCount, 2);
    expect(idsOf(recent.week), ['i0', 'suelto']);
    expect(recent.week.linkedCount, 1);
    expect(recent.week.linked.single.from.id, 'i0');
    expect(recent.week.linked.single.to.id, 'i1');

    expect(recent.month.days, kRecentMonthDays);
    expect(recent.month.processedCount, 3);
    expect(idsOf(recent.month), ['i0', 'suelto', 'i1']);
    expect(recent.month.linkedCount, 2);
    expect(
      [for (final l in recent.month.linked) l.at],
      [DateTime(2026, 10, 28), DateTime(2026, 10, 5)],
    );
  });

  test('cada documento nuevo sale con su lugar, para verlo en el mapa', () {
    final recent = recentOf(vault(readAt: now));

    final i0 = recent.week.processed.first;
    expect(i0.communityId, 1);
    expect(i0.topicValueId, 'roma');
    expect(recent.week.processed.last.isUnthemed, isTrue);
  });

  test('las cifras, con lo que valían hace un mes: lo que no tiene fecha es '
      'de siempre, y un vínculo existía si sus dos documentos también', () {
    final recent = recentOf(vault(readAt: now), communitiesBefore: 3);
    final figures = recent.figures;

    // Cuatro con tema y uno sin; hace un mes, i2 e i3.
    expect((figures.documents.now, figures.documents.before), (5, 2));
    expect(figures.documents.delta, 3);
    // «nuevo» es de este mes; roma no tiene fecha.
    expect((figures.topics.now, figures.topics.before), (3, 2));
    // Cuatro entre dos documentos; hace un mes, solo i2–i3.
    expect((figures.links.now, figures.links.before), (4, 1));
    // Una comunidad con uniones hoy, tres antes: el cambio es negativo.
    expect((figures.communities.now, figures.communities.before), (1, 3));
    expect(figures.communities.delta, -2);
  });

  test('el borde de la ventana es parte de ella', () {
    final since = recentSince(now, kRecentWeekDays);
    final recent = recentOf(
      inputOf(
        ['roma'],
        [
          ['roma'],
          ['roma'],
        ],
        itemDates: {
          'i0': since,
          'i1': since.subtract(const Duration(seconds: 1)),
        },
        readAt: now,
      ),
    );

    expect(idsOf(recent.week), ['i0']);
  });

  test('nombra los más nuevos hasta el tope, y cuenta todos', () {
    final recent = recentOf(
      inputOf(
        ['roma'],
        repeat(12, ['roma']),
        itemDates: {
          for (var i = 0; i < 12; i++) 'i$i': DateTime(2026, 10, 25, i),
        },
        relations: [
          for (var i = 0; i < 11; i++)
            link('i$i', 'i${i + 1}', DateTime(2026, 10, 26, i)),
        ],
        readAt: now,
      ),
    );

    expect(recent.week.processedCount, 12);
    expect(recent.week.processed, hasLength(kRecentListLength));
    expect(recent.week.processed.first.id, 'i11');
    expect(recent.week.linkedCount, 11);
    expect(recent.week.linked, hasLength(kRecentListLength));
    expect(recent.week.linked.first.from.id, 'i10');
  });

  test('sin la hora de la lectura nada es nuevo y las cifras no cambian', () {
    final recent = recentOf(vault(), communitiesBefore: 9);

    expect(recent.at, isNull);
    expect(recent.week.isEmpty, isTrue);
    expect(recent.month.isEmpty, isTrue);
    expect(recent.figures.documents.delta, 0);
    expect(recent.figures.topics.delta, 0);
    expect(recent.figures.links.delta, 0);
    expect(recent.figures.communities.delta, 0);
  });

  test('connectedCommunities no cuenta los temas aislados', () {
    final map = mapOf(
      const TopicGraphInput(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: [
          AtlasValueRow(id: 'a', label: 'A'),
          AtlasValueRow(id: 'b', label: 'B'),
          AtlasValueRow(id: 'solo', label: 'Solo'),
        ],
        items: [
          TopicItem(id: 'x', valueIds: ['a', 'b']),
        ],
        relations: [],
      ),
      {'a': 1, 'b': 1, 'solo': 2},
    );

    expect(connectedCommunities(map.detection), 1);
  });
}
