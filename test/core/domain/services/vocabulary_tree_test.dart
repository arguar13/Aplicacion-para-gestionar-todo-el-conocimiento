import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/vocabulary_hierarchy.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';

/// El árbol de una categoría del vocabulario (F13): quién es padre de quién,
/// sin base ni pantalla.
void main() {
  /// roma
  /// ├─ republica
  /// │  └─ gracos
  /// └─ imperio
  /// grecia (raíz sola)
  final tree = VocabularyTree([
    (id: 'roma', parentId: null),
    (id: 'republica', parentId: 'roma'),
    (id: 'gracos', parentId: 'republica'),
    (id: 'imperio', parentId: 'roma'),
    (id: 'grecia', parentId: null),
  ]);

  test('las raíces son los valores sin padre, en el orden dado', () {
    expect(tree.roots, ['roma', 'grecia']);
  });

  test('padre e hijos directos', () {
    expect(tree.parentOf('gracos'), 'republica');
    expect(tree.parentOf('roma'), isNull);
    expect(tree.childrenOf('roma'), ['republica', 'imperio']);
    expect(tree.childrenOf('gracos'), isEmpty);
  });

  test('los descendientes, sin contarse y los padres antes que los hijos', () {
    expect(tree.descendantsOf('roma'), ['republica', 'imperio', 'gracos']);
    expect(tree.descendantsOf('republica'), ['gracos']);
    expect(tree.descendantsOf('grecia'), isEmpty);
  });

  test('los ancestros, del más cercano a la raíz', () {
    expect(tree.ancestorsOf('gracos'), ['republica', 'roma']);
    expect(tree.ancestorsOf('roma'), isEmpty);
  });

  test('el nivel, la altura y el tamaño de una rama', () {
    expect(tree.depthOf('gracos'), 2);
    expect(tree.depthOf('roma'), 0);
    expect(tree.heightOf('roma'), 2);
    expect(tree.heightOf('gracos'), 0);
    expect(tree.sizeOf('roma'), 4);
    expect(tree.sizeOf('grecia'), 1);
  });

  test('un padre que no está en la lista deja al valor como raíz', () {
    final loose = VocabularyTree([(id: 'a', parentId: 'no-esta')]);

    expect(loose.roots, ['a']);
    expect(loose.parentOf('a'), isNull);
  });

  test('un valor que es su propio padre es una raíz, no un ciclo', () {
    final self = VocabularyTree([(id: 'a', parentId: 'a')]);

    expect(self.roots, ['a']);
    expect(self.descendantsOf('a'), isEmpty);
  });

  test('un ciclo que la base no admitiría no cuelga el recorrido', () {
    final cyclic = VocabularyTree([
      (id: 'a', parentId: 'b'),
      (id: 'b', parentId: 'a'),
    ]);

    // Nadie es raíz, así que no hay por dónde entrar; y nada se cuelga.
    expect(cyclic.roots, isEmpty);
    expect(cyclic.descendantsOf('a'), ['b']);
    expect(cyclic.ancestorsOf('a'), ['b']);
  });

  group('mover una rama', () {
    test('a la raíz siempre se puede', () {
      expect(tree.problemMoving('gracos', null), isNull);
    });

    test('a un lugar libre se puede', () {
      expect(tree.problemMoving('republica', 'grecia'), isNull);
      expect(tree.problemMoving('gracos', 'imperio'), isNull);
    });

    test('bajo sí mismo o bajo un descendiente es un ciclo', () {
      expect(tree.problemMoving('roma', 'roma'), VocabularyMoveProblem.cycle);
      expect(tree.problemMoving('roma', 'gracos'), VocabularyMoveProblem.cycle);
      expect(
        tree.problemMoving('republica', 'gracos'),
        VocabularyMoveProblem.cycle,
      );
    });

    test('con una rama que pasaría del tope, no se puede', () {
      // grecia > a > b > c > d: cuatro niveles debajo de la raíz.
      final deep = VocabularyTree([
        (id: 'grecia', parentId: null),
        (id: 'a', parentId: 'grecia'),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'b'),
        (id: 'd', parentId: 'c'),
        (id: 'roma', parentId: null),
        (id: 'republica', parentId: 'roma'),
        (id: 'gracos', parentId: 'republica'),
      ]);
      expect(kVocabularyMaxDepth, 4);

      // `roma` (altura 2) bajo `d` (nivel 4) dejaría a `gracos` en el nivel 7.
      expect(deep.problemMoving('roma', 'd'), VocabularyMoveProblem.tooDeep);
      // Una hoja bajo `c` (nivel 3) queda en el 4: el último que entra.
      expect(deep.problemMoving('gracos', 'c'), isNull);
      // Y bajo `d` (nivel 4) quedaría en el 5: no entra.
      expect(deep.problemMoving('gracos', 'd'), VocabularyMoveProblem.tooDeep);
    });
  });
}
