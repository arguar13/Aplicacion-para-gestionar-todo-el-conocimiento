import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_sort.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_values.dart';

/// F43, paso 9: ordenar una tabla por columna —números como números, fechas
/// como fechas y texto como un diccionario del idioma—.
void main() {
  final es = TableCollator('es');

  StudyTable table(TableColumnType type, List<String> cells) => StudyTable(
    title: '',
    columns: [
      const TableColumn('Id'),
      TableColumn('Valor', type: type),
    ],
    rows: [
      for (final (i, cell) in cells.indexed) ['$i', cell],
    ],
  );

  List<String> sorted(
    TableColumnType type,
    List<String> cells, {
    bool ascending = true,
    TableCollator? collator,
  }) {
    final t = table(type, cells);
    return [
      for (final i in tableRowOrder(
        t,
        TableSort(1, ascending: ascending),
        collator ?? es,
      ))
        t.rows[i][1],
    ];
  }

  group('los números', () {
    test('se leen como en castellano y en inglés, con signo, porcentaje y '
        'escala', () {
      expect(TableValues.number('1.250,5'), 1250.5);
      expect(TableValues.number('1,234.5'), 1234.5);
      expect(TableValues.number('40 %'), 40);
      expect(TableValues.number('−12'), -12);
      expect(TableValues.number(r'US$ 2,5 mil'), 2500);
      expect(TableValues.number('3 millones'), 3e6);
      expect(TableValues.number('2 mil millones'), 2e9);
      expect(TableValues.number('1,5 billones'), 1.5e12);
      expect(TableValues.number('7 billion'), 7e9);
      expect(TableValues.number('aprox. 40 años'), 40);
      expect(TableValues.number('ninguno'), isNull);
      expect(TableValues.number(''), isNull);
    });

    test('se ordenan por su valor, no como texto; al revés, al revés', () {
      final cells = ['10', '9', '1.250', '−3', '2,5'];
      expect(sorted(TableColumnType.number, cells), [
        '−3',
        '2,5',
        '9',
        '10',
        '1.250',
      ]);
      expect(sorted(TableColumnType.number, cells, ascending: false), [
        '1.250',
        '10',
        '9',
        '2,5',
        '−3',
      ]);
    });

    test('lo que no es número va después, y lo vacío al final en los dos '
        'sentidos', () {
      final cells = ['', '5', 'sin dato', '1', ''];
      expect(sorted(TableColumnType.number, cells), [
        '1',
        '5',
        'sin dato',
        '',
        '',
      ]);
      expect(sorted(TableColumnType.number, cells, ascending: false), [
        '5',
        '1',
        'sin dato',
        '',
        '',
      ]);
    });
  });

  group('las fechas', () {
    test('se leen en sus formas', () {
      expect(
        TableValues.date('2026-10-29'),
        closeTo(2026 + 9 / 12 + 28 / 372, 1e-9),
      );
      expect(TableValues.date('29/10/2026'), TableValues.date('2026-10-29'));
      expect(TableValues.date('10/29/2026'), TableValues.date('2026-10-29'));
      expect(
        TableValues.date('29 de octubre de 2026'),
        TableValues.date('2026-10-29'),
      );
      expect(
        TableValues.date('October 29, 2026'),
        TableValues.date('2026-10-29'),
      );
      expect(TableValues.date('octubre de 2026'), TableValues.date('2026-10'));
      expect(TableValues.date('1446 a. C.'), -1446);
      expect(TableValues.date('1446 BC'), -1446);
      expect(TableValues.date('30 d. C.'), 30);
      expect(TableValues.date('siglo XIII'), 1250);
      expect(TableValues.date('s. V a. C.'), -450);
      expect(TableValues.date('1446'), 1446);
      expect(TableValues.date('el Faraón'), isNull);
      expect(TableValues.date('31/13/2026'), isNull);
    });

    test('se ordenan de la más vieja a la más nueva, antes de Cristo '
        'primero', () {
      expect(
        sorted(TableColumnType.date, [
          '30 d. C.',
          '1446 a. C.',
          'siglo XIII',
          '1200 a. C.',
          '2026-10-29',
          '29/10/1990',
        ]),
        [
          '1446 a. C.',
          '1200 a. C.',
          '30 d. C.',
          'siglo XIII',
          '29/10/1990',
          '2026-10-29',
        ],
      );
    });
  });

  group('el texto, como un diccionario', () {
    test('sin mirar tildes ni mayúsculas primero', () {
      expect(
        sorted(TableColumnType.text, ['zorro', 'Ábaco', 'abeja', 'Éxodo']),
        ['Ábaco', 'abeja', 'Éxodo', 'zorro'],
      );
    });

    test('en castellano, la ñ después de la n; en inglés, con la n', () {
      final cells = ['ñandú', 'oso', 'nube', 'nzz'];
      expect(sorted(TableColumnType.text, cells), [
        'nube',
        'nzz',
        'ñandú',
        'oso',
      ]);
      expect(
        sorted(TableColumnType.text, cells, collator: TableCollator('en')),
        ['ñandú', 'nube', 'nzz', 'oso'],
      );
    });

    test('los números de adentro, como números', () {
      expect(
        sorted(TableColumnType.text, [
          'Capítulo 10',
          'Capítulo 2',
          'Capítulo 1',
        ]),
        ['Capítulo 1', 'Capítulo 2', 'Capítulo 10'],
      );
    });

    test('los signos no cuentan; en un empate, sin tilde y minúscula '
        'primero', () {
      expect(es.compare('«Éxodo»', 'exodo'), greaterThan(0));
      expect(es.compare('«exodo»', 'exodo'), 0);
      expect(es.compare('papa', 'papá'), lessThan(0));
      expect(es.compare('roma', 'Roma'), lessThan(0));
      expect(sorted(TableColumnType.text, ['¿Por qué?', 'Para', 'pez']), [
        'Para',
        'pez',
        '¿Por qué?',
      ]);
    });
  });

  test('estable: lo que empata queda en el orden de la IA', () {
    const t = StudyTable(
      title: '',
      columns: [TableColumn('Grupo'), TableColumn('Nombre')],
      rows: [
        ['B', 'uno'],
        ['A', 'dos'],
        ['B', 'tres'],
        ['A', 'cuatro'],
      ],
    );
    expect(tableRowOrder(t, const TableSort(0), es), [1, 3, 0, 2]);
    expect(tableRowOrder(t, const TableSort(0, ascending: false), es), [
      0,
      2,
      1,
      3,
    ]);
  });

  test('sin orden, o con una columna que no existe: el de la IA', () {
    final t = table(TableColumnType.text, ['c', 'a', 'b']);
    expect(tableRowOrder(t, null, es), [0, 1, 2]);
    expect(tableRowOrder(t, const TableSort(5), es), [0, 1, 2]);
  });

  test('tocar el encabezado: por él de menor a mayor, otra vez al revés; '
      'otro, de nuevo de menor a mayor', () {
    final first = TableSort.toggled(null, 2);
    expect(first, const TableSort(2));
    final again = TableSort.toggled(first, 2);
    expect(again, const TableSort(2, ascending: false));
    expect(TableSort.toggled(again, 2), const TableSort(2));
    expect(TableSort.toggled(again, 0), const TableSort(0));
  });
}
