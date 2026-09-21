import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/domain/services/hierarchy_suggestions.dart';
import 'package:sinapsis/features/vocabulary/domain/services/merge_candidates.dart';

/// Las propuestas de jerarquía (F13): «Roma republicana» bajo «Roma».
void main() {
  VocabularyValueStat value(
    String id,
    String label, {
    String? parent,
    int usage = 1,
  }) => VocabularyValueStat(
    id: id,
    label: label,
    definitionId: 'tema',
    definitionName: 'Tema',
    isText: true,
    usage: usage,
    aliasCount: 0,
    parentId: parent,
  );

  List<HierarchySuggestion> suggestionsFor(List<VocabularyValueStat> stats) {
    final groups = groupMergeCandidates(findMergeCandidates(stats));
    return [for (final g in groups) ...hierarchySuggestionsFor(g)];
  }

  Set<String> pairsOf(List<HierarchySuggestion> found) => {
    for (final s in found) '${s.child.id}>${s.parent.id}',
  };

  test('el valor con más palabras es un subtema del que las contiene', () {
    final found = suggestionsFor([
      value('roma', 'Roma'),
      value('republica', 'Roma republicana'),
    ]);

    expect(found, hasLength(1));
    expect(found.single.child.id, 'republica');
    expect(found.single.parent.id, 'roma');
  });

  test('no importa el orden en que vengan', () {
    final found = suggestionsFor([
      value('republica', 'Roma republicana'),
      value('roma', 'Roma'),
    ]);

    expect(pairsOf(found), {'republica>roma'});
  });

  test('por palabras enteras: «Arte» no es el padre de «Artesanía»', () {
    final found = suggestionsFor([
      value('arte', 'Arte'),
      value('artesania', 'Artesanía'),
    ]);

    expect(found, isEmpty);
  });

  test('el mismo texto, o solo parecido, no es una jerarquía', () {
    expect(suggestionsFor([value('a', 'Roma'), value('b', 'roma')]), isEmpty);
    expect(
      suggestionsFor([
        value('a', 'Constantinopla'),
        value('b', 'Constantinopala'),
      ]),
      isEmpty,
    );
  });

  test('con tres valores encadenados, cada uno va bajo el más específico', () {
    final found = suggestionsFor([
      value('roma', 'Roma'),
      value('republica', 'Roma republicana'),
      value('tardia', 'Roma republicana tardía'),
    ]);

    // «Roma republicana tardía» contiene a los dos, pero va bajo el que más
    // se le parece: «Roma republicana», que a su vez va bajo «Roma».
    expect(pairsOf(found), {'republica>roma', 'tardia>republica'});
  });

  test('si el hijo ya está bajo ese padre, no se propone', () {
    final found = suggestionsFor([
      value('roma', 'Roma'),
      value('republica', 'Roma republicana', parent: 'roma'),
    ]);

    expect(found, isEmpty);
  });

  test('un valor que ya tiene padre no se ofrece mover: lo puso alguien', () {
    final found = suggestionsFor([
      value('roma', 'Roma'),
      value('antiguedad', 'Antigüedad'),
      value('republica', 'Roma republicana', parent: 'antiguedad'),
    ]);

    expect(found, isEmpty);
  });

  test('no se propone poner un valor bajo uno que ya es hijo suyo', () {
    final found = suggestionsFor([
      value('roma', 'Roma', parent: 'republica'),
      value('republica', 'Roma republicana'),
    ]);

    expect(found, isEmpty);
  });

  test('dos padres que se escriben igual son uno: se propone el más usado', () {
    final found = suggestionsFor([
      value('roma', 'Roma', usage: 5),
      value('roma-acento', 'Róma', usage: 2),
      value('antigua', 'Roma antigua'),
    ]);

    expect(pairsOf(found), {'antigua>roma'});
  });

  test('dos padres distintos igual de específicos se proponen los dos', () {
    final found = suggestionsFor([
      value('roma-antigua', 'Roma antigua'),
      value('antigua-republica', 'Antigua república'),
      value('todo', 'Roma antigua república'),
    ]);

    expect(pairsOf(found), {'todo>roma-antigua', 'todo>antigua-republica'});
  });

  test('cada par se propone una sola vez', () {
    final found = suggestionsFor([
      value('roma', 'Roma'),
      value('republica', 'Roma republicana'),
    ]);

    expect(pairsOf(found).length, found.length);
  });
}
