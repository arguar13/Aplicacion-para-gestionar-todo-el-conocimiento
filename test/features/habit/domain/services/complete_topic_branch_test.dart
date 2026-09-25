import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';
import 'package:sinapsis/features/habit/domain/services/complete_topic_branch.dart';

/// La insignia «un tema completo de punta a punta» (F17, D7): pura, sin
/// base.
void main() {
  test('sin ninguna rama asignada, no hay ninguna completa', () {
    final result = hasCompleteTopicBranch(
      temaTree: VocabularyTree(const []),
      sourcesByTema: const {},
      coveredSourceIds: const {},
    );

    expect(result, isFalse);
  });

  group('el piso mínimo (D7, decisión propia)', () {
    final tree = VocabularyTree(const [(id: 'roma', parentId: null)]);

    test('menos del piso, aunque estén todas cubiertas, no alcanza', () {
      final result = hasCompleteTopicBranch(
        temaTree: tree,
        sourcesByTema: {
          'roma': {'s1', 's2'},
        },
        coveredSourceIds: {'s1', 's2'},
      );

      expect(result, isFalse);
    });

    test('justo en el piso, todas cubiertas, alcanza', () {
      final result = hasCompleteTopicBranch(
        temaTree: tree,
        sourcesByTema: {
          'roma': {'s1', 's2', 's3'},
        },
        coveredSourceIds: {'s1', 's2', 's3'},
      );

      expect(result, isTrue);
    });

    test('en el piso, pero una sin cubrir, no alcanza', () {
      final result = hasCompleteTopicBranch(
        temaTree: tree,
        sourcesByTema: {
          'roma': {'s1', 's2', 's3'},
        },
        coveredSourceIds: {'s1', 's2'},
      );

      expect(result, isFalse);
    });
  });

  test('un padre suma las fuentes de sus hijos, no solo las propias', () {
    // Ningún nivel solo tiene el piso por sí mismo, pero juntos sí.
    final tree = VocabularyTree(const [
      (id: 'historia', parentId: null),
      (id: 'roma', parentId: 'historia'),
      (id: 'republica', parentId: 'roma'),
    ]);

    final result = hasCompleteTopicBranch(
      temaTree: tree,
      sourcesByTema: {
        'historia': {'s1'},
        'roma': {'s2'},
        'republica': {'s3'},
      },
      coveredSourceIds: {'s1', 's2', 's3'},
    );

    expect(result, isTrue);
  });

  test('una hoja sin el piso no completa a su padre si el padre tampoco '
      'llega', () {
    final tree = VocabularyTree(const [
      (id: 'historia', parentId: null),
      (id: 'roma', parentId: 'historia'),
    ]);

    final result = hasCompleteTopicBranch(
      temaTree: tree,
      sourcesByTema: {
        'roma': {'s1', 's2'},
      },
      coveredSourceIds: {'s1', 's2'},
    );

    expect(result, isFalse);
  });

  test('varias ramas independientes: alcanza con que UNA esté completa', () {
    final tree = VocabularyTree(const [
      (id: 'historia', parentId: null),
      (id: 'biologia', parentId: null),
    ]);

    final result = hasCompleteTopicBranch(
      temaTree: tree,
      sourcesByTema: {
        'historia': {'s1', 's2'}, // no llega al piso
        'biologia': {'s3', 's4', 's5'}, // completa
      },
      coveredSourceIds: {'s1', 's2', 's3', 's4', 's5'},
    );

    expect(result, isTrue);
  });

  test('un valor hereda las fuentes de su descendiente', () {
    final tree = VocabularyTree(const [
      (id: 'historia', parentId: null),
      (id: 'roma', parentId: 'historia'),
    ]);

    final result = hasCompleteTopicBranch(
      temaTree: tree,
      sourcesByTema: {
        'roma': {'s1', 's2', 's3'},
      },
      coveredSourceIds: {'s1', 's2', 's3'},
    );

    // «historia» hereda las 3 de «roma»: también completa, sin fuentes
    // propias.
    expect(result, isTrue);
  });

  test('una fuente asignada a un valor y también a su hijo no se cuenta '
      'dos veces', () {
    final tree = VocabularyTree(const [
      (id: 'historia', parentId: null),
      (id: 'roma', parentId: 'historia'),
    ]);

    final result = hasCompleteTopicBranch(
      temaTree: tree,
      sourcesByTema: {
        // s1 está asignada a los dos: la rama de «historia» son 2 fuentes
        // DISTINTAS (s1, s2) —si se sumaran las longitudes sin unir por
        // id, parecerían 3 y llegarían al piso; unidas, no—.
        'historia': {'s1', 's2'},
        'roma': {'s1'},
      },
      coveredSourceIds: {'s1', 's2'},
    );

    expect(result, isFalse);
  });
}
