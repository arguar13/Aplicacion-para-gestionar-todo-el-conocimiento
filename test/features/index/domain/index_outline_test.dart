import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/services/index_outline.dart';

import '../../../support/fake_index_repository.dart';
import '../../../support/time_growth.dart';

/// Cómo se ven las entradas de un documento desplegado en el Índice (F46,
/// paso 3): los niveles de Word, lo plegado a mano, la numeración, y lo
/// encontrado con lo que lo contiene.
void main() {
  /// Un libro con dos partes, la primera con capítulos y uno con secciones.
  final book = indexChapters('libro', [
    (1, 'Primera parte'), //     1
    (2, 'Roma'), //              2
    (3, 'La República'), //      3
    (3, 'El Imperio'), //        4
    (2, 'Grecia'), //            5
    (1, 'Segunda parte'), //     6
  ]);

  List<String> titles(List<IndexOutlineRow> rows) => [
    for (final row in rows) row.entry.title,
  ];

  group('los niveles, como en Word', () {
    test('«Niveles: 2» deja ver los de nivel 1 y 2: los de 2 con hijos '
        'quedan plegados', () {
      final rows = indexOutline(book, depth: 2);

      expect(titles(rows), [
        'Primera parte',
        'Roma',
        'Grecia',
        'Segunda parte',
      ]);
      expect(
        [for (final r in rows) (r.hasChildren, r.unfolded)],
        [(true, true), (true, false), (false, true), (false, true)],
      );
    });

    test('«Niveles: 1» deja solo las partes, plegadas', () {
      final rows = indexOutline(book, depth: 1);

      expect(titles(rows), ['Primera parte', 'Segunda parte']);
      expect(rows.first.unfolded, isFalse);
    });

    test('«Todo» despliega todo', () {
      final rows = indexOutline(book, depth: null);

      expect(titles(rows), [for (final e in book) e.title]);
      expect(rows.every((r) => r.unfolded), isTrue);
    });

    test('«Niveles: 3» en un libro de tres niveles es lo mismo que «Todo»', () {
      expect(indexOutline(book, depth: 3), indexOutline(book, depth: null));
    });
  });

  group('lo abierto o cerrado a mano', () {
    test('abrir un capítulo plegado por los niveles muestra sus hijos, y '
        'solo los suyos', () {
      final rows = indexOutline(book, depth: 2, folds: {2: true});

      expect(titles(rows), [
        'Primera parte',
        'Roma',
        'La República',
        'El Imperio',
        'Grecia',
        'Segunda parte',
      ]);
    });

    test('cerrar una parte esconde todo lo de adentro, hasta la parte que '
        'sigue', () {
      final rows = indexOutline(book, depth: null, folds: {1: false});

      expect(titles(rows), ['Primera parte', 'Segunda parte']);
      expect(rows.first.unfolded, isFalse);
    });

    test('lo elegido para uno que no tiene hijos no cambia nada', () {
      expect(
        indexOutline(book, depth: 2, folds: {5: false}),
        indexOutline(book, depth: 2),
      );
    });

    test(
      'un hijo abierto a mano dentro de un padre cerrado sigue sin verse',
      () {
        final rows = indexOutline(
          book,
          depth: null,
          folds: {1: false, 2: true},
        );

        expect(titles(rows), ['Primera parte', 'Segunda parte']);
      },
    );
  });

  group('la numeración', () {
    test('«1», «1.1», «1.1.1»: cada nivel cuenta dentro de su padre', () {
      final rows = indexOutline(book, depth: null, numbered: true);

      expect(
        [for (final r in rows) r.number],
        ['1', '1.1', '1.1.1', '1.1.2', '1.2', '2'],
      );
    });

    test('lo plegado también cuenta: un número no cambia por plegar', () {
      final rows = indexOutline(book, depth: 1, numbered: true);

      expect([for (final r in rows) r.number], ['1', '2']);
    });

    test('apagada, ninguno', () {
      final rows = indexOutline(book, depth: null);

      expect(rows.every((r) => r.number == null), isTrue);
    });

    test('«Texto completo» y las imágenes no se numeran ni tienen hijos', () {
      final entries = [
        ...indexChapters('d', [(1, 'Uno'), (2, 'Dos')]),
        indexImage('d', 10, position: 0, title: 'Mapa'),
        indexImage('d', 11, position: 1),
      ];
      final rows = indexOutline(entries, depth: 1, numbered: true);

      // Las imágenes se ven aunque el capítulo de antes esté plegado: no
      // están adentro de él.
      expect(titles(rows), ['Uno', 'Mapa', '']);
      expect([for (final r in rows) r.number], ['1', null, null]);
      expect([for (final r in rows) r.hasChildren], [true, false, false]);

      final whole = indexOutline(
        [indexWholeText('t', 1)],
        depth: 1,
        numbered: true,
      );
      expect(whole.single.number, isNull);
      expect(whole.single.hasChildren, isFalse);
    });
  });

  test('una pasada, sin volver atrás: ocho veces más capítulos tardan '
      'mucho menos que 64 veces más (lo cuadrático)', () async {
    List<IndexEntry> chapters(int count) => indexChapters('grande', [
      for (var i = 0; i < count; i++) (1 + i % 4, 'Capítulo $i'),
    ]);
    final small = chapters(4000);
    final big = chapters(32000);

    final growth = await timeGrowth(
      () => micros(
        () => indexOutline(small, depth: 2, numbered: true, folds: {7: true}),
      ),
      () => micros(
        () => indexOutline(big, depth: 2, numbered: true, folds: {7: true}),
      ),
    );

    expect(growth, lessThan(20));
  });

  group('lo encontrado, con lo que lo contiene', () {
    IndexSearchHit hit(IndexEntry entry, List<IndexEntry> ancestors) =>
        IndexSearchHit(
          entry: entry,
          documentTitle: 'Doc ${entry.documentId}',
          sourceKind: SourceKind.document,
          spaceIds: const [],
          ancestors: ancestors,
        );

    test('cada documento es un grupo, y dos coincidencias de un mismo '
        'capítulo comparten a sus padres', () {
      final [parte, roma, republica, imperio, ..._] = book;
      final otro = indexChapters('otro', [(1, 'Roma antigua')]).single;

      final groups = groupIndexSearch([
        hit(republica, [parte, roma]),
        hit(imperio, [parte, roma]),
        hit(otro, const []),
      ]);

      expect([for (final g in groups) g.documentId], ['libro', 'otro']);
      expect(
        [for (final r in groups.first.rows) (r.entry.title, r.matched)],
        [
          ('Primera parte', false),
          ('Roma', false),
          ('La República', true),
          ('El Imperio', true),
        ],
      );
      expect(groups.last.rows.single.matched, isTrue);
    });

    test('un padre que también coincide se muestra una vez, como '
        'coincidencia', () {
      final [parte, roma, republica, ..._] = book;

      final groups = groupIndexSearch([
        hit(roma, [parte]),
        hit(republica, [parte, roma]),
      ]);

      expect(
        [for (final r in groups.single.rows) (r.entry.title, r.matched)],
        [('Primera parte', false), ('Roma', true), ('La República', true)],
      );
    });

    test('un padre que se mostró como padre y después coincide pasa a '
        'coincidencia, en su lugar', () {
      final [parte, roma, republica, ..._] = book;

      final groups = groupIndexSearch([
        hit(republica, [parte, roma]),
        hit(roma, [parte]),
      ]);

      expect(
        [for (final r in groups.single.rows) (r.entry.title, r.matched)],
        [('Primera parte', false), ('Roma', true), ('La República', true)],
      );
    });

    test('sin coincidencias, ningún grupo', () {
      expect(groupIndexSearch(const []), isEmpty);
    });
  });
}
