import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_export.dart';

/// F43, paso 9: «Copiar» (TSV) y «Exportar a CSV», byte por byte.
void main() {
  const table = StudyTable(
    title: 'Plagas',
    columns: [TableColumn('Plaga'), TableColumn('Nota')],
    rows: [
      ['Sangre', 'El "Nilo"; rojo'],
      ['Ranas', 'muchas\nen todo'],
      ['=SUMA(A1)', '-12'],
      ['@cmd', '-foo'],
      [' borde ', 'Éxodo, cap. 7'],
    ],
  );

  group('TSV', () {
    test('encabezados y filas separados por tabulación; las tabulaciones y '
        'saltos de adentro pasan a espacio', () {
      const t = StudyTable(
        title: '',
        columns: [TableColumn('A'), TableColumn('B')],
        rows: [
          ['uno\tdos', 'tres\r\ncuatro'],
          ['x', 'y'],
        ],
      );
      expect(tableToTsv(t), 'A\tB\nuno dos\ttres cuatro\nx\ty');
    });

    test('en el orden que se le da', () {
      const t = StudyTable(
        title: '',
        columns: [TableColumn('A')],
        rows: [
          ['1'],
          ['2'],
          ['3'],
        ],
      );
      expect(tableToTsv(t, order: [2, 0, 1]), 'A\n3\n1\n2');
    });
  });

  group('CSV', () {
    test('con «;»: BOM, CRLF, comillas donde hacen falta y las fórmulas '
        'desarmadas, byte por byte', () {
      final bytes = tableToCsv(table, separator: ';');
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(
        utf8.decode(bytes.sublist(3)),
        'Plaga;Nota\r\n'
        'Sangre;"El ""Nilo""; rojo"\r\n'
        'Ranas;"muchas\nen todo"\r\n'
        "'=SUMA(A1);-12\r\n"
        "'@cmd;'-foo\r\n"
        '" borde ";Éxodo, cap. 7\r\n',
      );
    });

    test('con «,»: la coma es la que obliga a las comillas', () {
      final text = utf8.decode(
        tableToCsv(table, separator: ',', order: const [4, 0]).sublist(3),
      );
      expect(
        text,
        'Plaga,Nota\r\n'
        '" borde ","Éxodo, cap. 7"\r\n'
        'Sangre,"El ""Nilo""; rojo"\r\n',
      );
    });

    test('los números con signo quedan como están', () {
      const t = StudyTable(
        title: '',
        columns: [TableColumn('N')],
        rows: [
          ['-12'],
          ['+5 %'],
          ['- 3'],
          ['-'],
          ['+A1'],
        ],
      );
      expect(
        utf8.decode(tableToCsv(t, separator: ';').sublist(3)),
        "N\r\n-12\r\n+5 %\r\n- 3\r\n-\r\n'+A1\r\n",
      );
    });

    test('el separador: «;» donde la coma es decimal, «,» donde es el '
        'punto', () {
      expect(csvSeparatorFor('es'), ';');
      expect(csvSeparatorFor('es_AR'), ';');
      expect(csvSeparatorFor('pt_BR'), ';');
      expect(csvSeparatorFor('de'), ';');
      expect(csvSeparatorFor('en'), ',');
      expect(csvSeparatorFor('en_US'), ',');
      expect(csvSeparatorFor('es_MX'), ',');
      expect(csvSeparatorFor('xx_INVALIDO'), ',');
    });
  });
}
