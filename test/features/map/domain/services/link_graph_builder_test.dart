import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/services/link_graph_builder.dart';

/// Qué dibuja la vista «Vínculos» (F28) cuando los vinculados no entran: el
/// foco y su vecindario, lo más reciente y lo más vinculado, en ese orden.
void main() {
  var minute = 0;
  LinkRow link(String from, String to, {int? at}) => LinkRow(
    fromId: from,
    toId: to,
    kind: RelationKind.relatedTo,
    createdAt: DateTime(2026, 10).add(Duration(minutes: at ?? minute++)),
  );

  setUp(() => minute = 0);

  test('si entran todos, van todos, los más vinculados primero', () {
    final selection = selectLinkGraph([
      link('a', 'b'),
      link('a', 'c'),
      link('d', 'e'),
    ]);

    expect(selection.ids.first, 'a');
    expect(selection.ids.toSet(), {'a', 'b', 'c', 'd', 'e'});
    expect(selection.linkedCount, 5);
  });

  test('un vínculo de un elemento consigo mismo no cuenta', () {
    final selection = selectLinkGraph([link('a', 'a')]);

    expect(selection.ids, isEmpty);
    expect(selection.linkedCount, 0);
  });

  test('lo vinculado hace poco entra aunque tenga un solo vínculo', () {
    // Un centro muy vinculado, viejo, y un par recién vinculado.
    final rows = [
      for (var i = 0; i < 6; i++) link('centro', 'h$i', at: i),
      link('nueva', 'vieja', at: 100),
    ];

    final selection = selectLinkGraph(rows, limit: 4, recent: 2);

    expect(selection.ids.take(2), ['nueva', 'vieja']);
    // Lo que queda, por cuántos vínculos tiene: el centro primero.
    expect(selection.ids[2], 'centro');
    expect(selection.ids, hasLength(4));
    expect(selection.linkedCount, 9);
  });

  test('el foco entra primero, con sus vecinos directos antes que los de dos '
      'saltos', () {
    final rows = [
      link('foco', 'v1', at: 0),
      link('foco', 'v2', at: 1),
      link('v1', 'lejos', at: 2),
      link('x', 'y', at: 50),
      link('z', 'w', at: 60),
    ];

    final selection = selectLinkGraph(
      rows,
      focusId: 'foco',
      limit: 3,
      recent: 0,
    );

    expect(selection.ids.first, 'foco');
    expect(selection.ids.toSet(), {'foco', 'v1', 'v2'});
  });

  test('un foco sin vínculos no cambia nada', () {
    final rows = [
      for (var i = 0; i < 3; i++) link('centro', 'h$i', at: i),
      link('x', 'y', at: 10),
    ];

    final selection = selectLinkGraph(
      rows,
      focusId: 'suelto',
      limit: 2,
      recent: 0,
    );

    expect(selection.ids.first, 'centro');
  });

  test('no depende del orden en que llegan los vínculos', () {
    final rows = [
      link('a', 'b', at: 1),
      link('c', 'd', at: 1),
      link('e', 'f', at: 2),
      link('a', 'c', at: 0),
    ];

    final forward = selectLinkGraph(rows, limit: 3, recent: 2);
    final backward = selectLinkGraph(
      rows.reversed.toList(),
      limit: 3,
      recent: 2,
    );

    expect(forward.ids, backward.ids);
  });
}
