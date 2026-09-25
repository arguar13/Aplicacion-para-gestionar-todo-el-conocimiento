import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_path.dart';

/// El subdeck de Anki de un elemento (F17, D1/D2): pura, sobre un árbol de
/// Temas ya armado —no arma ninguno acá—.
void main() {
  final tree = VocabularyTree(const [
    (id: 'historia', parentId: null),
    (id: 'roma', parentId: 'historia'),
    (id: 'republica', parentId: 'roma'),
    (id: 'biologia', parentId: null),
  ]);
  const labelOf = {
    'historia': 'Historia',
    'roma': 'Roma',
    'republica': 'República',
    'biologia': 'Biología',
  };

  test('sin ningún tema, va al subdeck fijo «Sin tema» (D1)', () {
    expect(
      ankiDeckPathOf(firstTopicValueId: null, temaTree: tree, labelOf: labelOf),
      'Sinapsis::Sin tema',
    );
  });

  test('un tema raíz, sin ancestros', () {
    expect(
      ankiDeckPathOf(
        firstTopicValueId: 'biologia',
        temaTree: tree,
        labelOf: labelOf,
      ),
      'Sinapsis::Biología',
    );
  });

  test('un tema anidado, de la raíz a la hoja (D2)', () {
    expect(
      ankiDeckPathOf(
        firstTopicValueId: 'republica',
        temaTree: tree,
        labelOf: labelOf,
      ),
      'Sinapsis::Historia::Roma::República',
    );
  });

  test('usa el nombre tal cual del valor, no su id', () {
    final path = ankiDeckPathOf(
      firstTopicValueId: 'roma',
      temaTree: tree,
      labelOf: labelOf,
    );

    expect(path, isNot(contains('roma')));
    expect(path, contains('Roma'));
  });
}
