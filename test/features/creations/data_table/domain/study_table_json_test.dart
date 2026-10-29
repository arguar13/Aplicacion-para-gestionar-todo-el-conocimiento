import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table_json.dart';

/// F43, paso 9: la tabla de datos se lee con tolerancia y se guarda en una
/// forma canónica.
void main() {
  List<String> names(StudyTable t) => [for (final c in t.columns) c.name];
  List<TableColumnType> types(StudyTable t) => [
    for (final c in t.columns) c.type,
  ];

  group('la forma canónica', () {
    test('columnas con su tipo, filas como listas; encode y vuelta', () {
      final table = StudyTableJson.read({
        'title': 'Las plagas',
        'columns': [
          {'name': 'Plaga', 'type': 'text'},
          {'name': 'Orden', 'type': 'number'},
          {'name': 'Fecha', 'type': 'date'},
        ],
        'rows': [
          ['Sangre', '1', '1446 a. C.'],
          ['Ranas', '2', '1446 a. C.'],
        ],
      });
      expect(table.title, 'Las plagas');
      expect(names(table), ['Plaga', 'Orden', 'Fecha']);
      expect(types(table), [
        TableColumnType.text,
        TableColumnType.number,
        TableColumnType.date,
      ]);
      expect(table.rows, [
        ['Sangre', '1', '1446 a. C.'],
        ['Ranas', '2', '1446 a. C.'],
      ]);
      expect(StudyTableJson.decode(StudyTableJson.encode(table)), table);
      expect(StudyTableJson.decode(StudyTableJson.encodeString(table)), table);
    });
  });

  group('con tolerancia', () {
    test('las claves en castellano y las columnas como nombres sueltos', () {
      final table = StudyTableJson.read({
        'Título': 'Personajes',
        'columnas': ['Nombre', 'Papel'],
        'filas': [
          ['Moisés', 'Guía'],
          ['Aarón', 'Vocero'],
        ],
      });
      expect(table.title, 'Personajes');
      expect(names(table), ['Nombre', 'Papel']);
      expect(table.rows.last, ['Aarón', 'Vocero']);
    });

    test('filas como objetos: por nombre de columna, sin tildes ni '
        'mayúsculas; las claves nuevas suman columnas', () {
      final table = StudyTableJson.read({
        'columns': ['Nombre', 'Papel'],
        'rows': [
          {'nombre': 'Moisés', 'PAPEL': 'Guía'},
          {'Nombre': 'Aarón', 'Edad': 83},
        ],
      });
      expect(names(table), ['Nombre', 'Papel', 'Edad']);
      expect(table.rows, [
        ['Moisés', 'Guía', ''],
        ['Aarón', '', '83'],
      ]);
      expect(table.columns.last.type, TableColumnType.number);
    });

    test('objetos sin columnas: las columnas son sus claves, en orden', () {
      final table = StudyTableJson.read([
        {'Plaga': 'Sangre', 'Orden': 1},
        {'Plaga': 'Ranas', 'Orden': 2, 'Nota': 'muchas'},
      ]);
      expect(names(table), ['Plaga', 'Orden', 'Nota']);
      expect(table.rows.first, ['Sangre', '1', '']);
    });

    test(
      'una lista de listas: la primera, toda texto, son los encabezados',
      () {
        final table = StudyTableJson.read([
          ['Plaga', 'Orden'],
          ['Sangre', 1],
          ['Ranas', 2.0],
          ['Piojos', 3.5],
        ]);
        expect(names(table), ['Plaga', 'Orden']);
        expect(table.rows, [
          ['Sangre', '1'],
          ['Ranas', '2'],
          ['Piojos', '3.5'],
        ]);
      },
    );

    test('«headers»/«data», envuelta en «table» y en el texto de la IA', () {
      final table = StudyTableJson.read(
        'Acá está:\n```json\n{"table": {"headers": ["A", "B"], '
        '"data": [["1", "2"],]}}\n```',
      );
      expect(names(table), ['A', 'B']);
      expect(table.rows, [
        ['1', '2'],
      ]);
    });

    test('filas cortas se completan; largas suman columnas sin nombre; las '
        'vacías no entran', () {
      final table = StudyTableJson.read({
        'columns': ['A', 'B'],
        'rows': [
          ['1'],
          ['1', '2', '3'],
          ['', null],
          <Object?>[],
        ],
      });
      expect(names(table), ['A', 'B', '']);
      expect(table.rows, [
        ['1', '', ''],
        ['1', '2', '3'],
      ]);
    });

    test('los valores: null, booleanos, listas, objetos con «value», '
        'espacios de más', () {
      final table = StudyTableJson.read({
        'columns': ['A', 'B', 'C', 'D', 'E'],
        'rows': [
          [
            null,
            true,
            ['uno', 'dos'],
            {'value': 'envuelto'},
            '  con   espacios \r\n y renglón ',
          ],
        ],
      });
      expect(table.rows.single, [
        '',
        'true',
        'uno, dos',
        'envuelto',
        'con espacios\ny renglón',
      ]);
    });

    test('el tipo como lo diga la IA, en castellano o inglés', () {
      final table = StudyTableJson.read({
        'columns': [
          {'nombre': 'A', 'tipo': 'número'},
          {'name': 'B', 'type': 'Fecha'},
          {'name': 'C', 'type': 'porcentaje'},
          {'name': 'D', 'type': 'string'},
          {'name': 'E', 'type': 'raro'},
        ],
        'rows': [
          ['x', 'y', 'z', '4', '5'],
        ],
      });
      expect(types(table), [
        TableColumnType.number,
        TableColumnType.date,
        TableColumnType.number,
        TableColumnType.text,
        // «raro» no se entiende: se deduce de los valores.
        TableColumnType.number,
      ]);
    });

    test('sin tipo, se deduce: números, fechas escritas como tales, texto; '
        'los años solos son números', () {
      final table = StudyTableJson.read({
        'columns': ['Cifra', 'Cuándo', 'Año', 'Qué'],
        'rows': [
          ['1.250', '1446 a. C.', '1446', 'Sangre'],
          ['40 %', '29/10/2026', '1500', 'Ranas'],
          ['3 millones', 'marzo de 1990', '30', '12'],
          ['', '', '', ''],
          ['−12', 'siglo XIII', '2026', 'Moscas'],
        ],
      });
      expect(types(table), [
        TableColumnType.number,
        TableColumnType.date,
        TableColumnType.number,
        TableColumnType.text,
      ]);
    });

    test('dos columnas con el mismo nombre se distinguen', () {
      final table = StudyTableJson.read({
        'columns': ['Año', 'año', 'Otro'],
        'rows': [
          ['1', '2', '3'],
        ],
      });
      expect(names(table), ['Año', 'año (2)', 'Otro']);
    });

    test('los topes: columnas, filas y celdas', () {
      final table = StudyTableJson.read({
        'columns': [for (var i = 0; i < 20; i++) 'C$i'],
        'rows': [
          for (var r = 0; r < 400; r++)
            [
              if (r == 0) 'x ' * 1000 else '$r',
              for (var i = 1; i < 20; i++) '$r',
            ],
        ],
      });
      expect(table.columns, hasLength(StudyTableLimits.columns));
      expect(table.rows, hasLength(StudyTableLimits.rows));
      expect(table.rows.every((r) => r.length == 12), isTrue);
      expect(
        table.rows.first.first.length,
        lessThanOrEqualTo(StudyTableLimits.cell),
      );
      expect(table.rows.first.first, endsWith('…'));
    });
  });

  group('lo que no se puede leer', () {
    test('sin columnas ni filas, con el motivo para la IA', () {
      expect(
        () => StudyTableJson.read({
          'columns': ['A'],
          'rows': <Object?>[],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'motivo',
            contains('rows'),
          ),
        ),
      );
      expect(
        () => StudyTableJson.read({'title': 'x'}),
        throwsA(isA<FormatException>()),
      );
      expect(() => StudyTableJson.read(7), throwsA(isA<FormatException>()));
    });

    test('decode de algo roto da una tabla vacía', () {
      expect(StudyTableJson.decode('nada').isEmpty, isTrue);
      expect(StudyTableJson.tryDecode(null), isNull);
    });
  });
}
