import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_expressions.dart';

/// El detector de expresiones de tiempo, sin IA (F40).
void main() {
  HistoricalDate year(int n, {bool bce = false, bool circa = false}) =>
      HistoricalDate(
        year: n,
        precision: DatePrecision.year,
        isBce: bce,
        isCirca: circa,
      );

  HistoricalDate day(int y, int m, int d, {bool bce = false}) => HistoricalDate(
    year: y,
    precision: DatePrecision.day,
    month: m,
    day: d,
    isBce: bce,
  );

  HistoricalDate month(int y, int m, {bool bce = false}) => HistoricalDate(
    year: y,
    precision: DatePrecision.month,
    month: m,
    isBce: bce,
  );

  HistoricalDate century(int first, {bool bce = false, bool circa = false}) =>
      HistoricalDate(
        year: first,
        precision: DatePrecision.century,
        isBce: bce,
        isCirca: circa,
      );

  HistoricalDate decade(int first) =>
      HistoricalDate(year: first, precision: DatePrecision.decade);

  /// Lo que encuentra en [text]: el tramo tal cual está escrito.
  List<String> spans(String text) => [
    for (final e in findTemporalExpressions(text))
      text.substring(e.start, e.end),
  ];

  /// Lo único que encuentra en [text], o falla.
  TemporalExpression only(String text) {
    final found = findTemporalExpressions(text);
    expect(found, hasLength(1), reason: text);
    return found.single;
  }

  void reads(
    String text,
    String span,
    HistoricalDate date, [
    HistoricalDate? endDate,
  ]) {
    final e = only(text);
    expect(text.substring(e.start, e.end), span, reason: text);
    expect(e.date, date, reason: text);
    expect(e.endDate, endDate, reason: text);
  }

  group('años', () {
    test('un año de cuatro cifras entre 1000 y 2099', () {
      reads('Ocurrió en 1859 y fue clave.', '1859', year(1859));
      reads('Desde 1000 hasta hoy', '1000', year(1000));
      reads('Para 2099 se espera', '2099', year(2099));
    });

    test('un año suelto, al empezar el texto o la oración', () {
      reads('1859 fue un año clave.', '1859', year(1859));
      reads('Fue clave. 1859.', '1859', year(1859));
    });

    test('un número de cuatro cifras fuera de 1000–2099 no es un año', () {
      expect(spans('Había 999 casos y 2100 más, 3000 en total'), isEmpty);
      expect(spans('Pasó 0999 aquel día y 0476 el otro.'), isEmpty);
      expect(spans('El código 0999 y el 5000'), isEmpty);
    });

    test('«año 476», «en el año 476», «in the year 476»', () {
      reads('Roma cayó el año 476 de la era.', 'año 476', year(476));
      reads('En el año 476 cayó Roma.', 'año 476', year(476));
      reads('In the year 476 Rome fell.', 'year 476', year(476));
      reads('Año 1000, el milenio.', 'Año 1000', year(1000));
    });

    test('«año 3» sin era no es un año, con era sí', () {
      expect(spans('El año 3 de su reinado.'), isEmpty);
      expect(spans('Pasó el año 20 del plan.'), isEmpty);
      reads('El año 3 a.C. fue raro.', 'año 3 a.C.', year(3, bce: true));
    });

    test('«año 476 días» es una cantidad, no un año', () {
      expect(spans('Esperó el año 300 días'), isEmpty);
    });

    test('un número de tres cifras es un año solo con una preposición', () {
      reads('En 476 cayó Roma.', '476', year(476));
      reads('In 476 the Western Empire fell.', '476', year(476));
      // Sin era, un rango de tres cifras podría ser una cantidad: cada año
      // queda por su cuenta.
      expect(spans('Desde 800 hasta 1000'), ['800', '1000']);
      reads('Since 476 nothing changed.', '476', year(476));
      expect(spans('Había 476 soldados.'), isEmpty);
      expect(spans('El 476 es un número.'), isEmpty);
      expect(spans('Costó 800.'), isEmpty);
    });

    test(
      'un número de tres cifras después de «en» y una cantidad no es año',
      () {
        expect(spans('Llegó en 100 días.'), isEmpty);
        expect(spans('Corrió en 200 metros.'), isEmpty);
        expect(spans('Lo hizo in 300 years.'), isEmpty);
      },
    );

    test('con era, cualquier número es un año: a.C. y d.C.', () {
      reads(
        'César murió en el 44 a.C. en Roma.',
        '44 a.C.',
        year(44, bce: true),
      );
      reads('Fue en 44 a. C.', '44 a. C.', year(44, bce: true));
      reads('Fue en 44 A.C.', '44 A.C.', year(44, bce: true));
      reads('Fue en 44 a. de C.', '44 a. de C.', year(44, bce: true));
      reads('Fue en 44 BC.', '44 BC', year(44, bce: true));
      reads('Fue en 44 B.C.', '44 B.C.', year(44, bce: true));
      reads('Fue en 44 BCE.', '44 BCE', year(44, bce: true));
      reads('En 476 d.C. cayó.', '476 d.C.', year(476));
      reads('En 476 d. C. cayó.', '476 d. C.', year(476));
      reads('In 476 AD it fell.', '476 AD', year(476));
      reads('In 476 CE it fell.', '476 CE', year(476));
      reads('In AD 476 it fell.', 'AD 476', year(476));
      reads('In A.D. 476 it fell.', 'A.D. 476', year(476));
      reads('Año 5 d.C. fue otro.', 'Año 5 d.C.', year(5));
      reads('Hace 2000 años, 500 a.C.', '500 a.C.', year(500, bce: true));
    });

    test('«a C» sin punto es una preposición y una inicial, no una era', () {
      expect(spans('De 1914 a Churchill le tocó. A C. le dio igual.'), [
        '1914',
      ]);
    });

    test('el año 0 no existe', () {
      expect(spans('En el año 0 a.C. y en 0 d.C.'), isEmpty);
    });

    test('varios años en un texto, en orden', () {
      expect(spans('Nació en 1809, publicó en 1859 y murió en 1882.'), [
        '1809',
        '1859',
        '1882',
      ]);
    });

    test('un año con coma o paréntesis alrededor', () {
      reads('Darwin (1809) nació.', '1809', year(1809));
      reads('Darwin, 1809, nació.', '1809', year(1809));
      reads('Darwin "1809" nació.', '1809', year(1809));
    });
  });

  group('lo que no es un año', () {
    test('cantidades con separador de miles o decimales', () {
      expect(spans('Eran 3.000 soldados y 1.500 caballos.'), isEmpty);
      expect(spans('Costó 1,500 dólares y 12.5 más.'), isEmpty);
      expect(spans('Pesa 1500.5 gramos.'), isEmpty);
    });

    test('un número de cuatro cifras seguido de una unidad', () {
      expect(spans('Medía 1500 metros.'), isEmpty);
      expect(spans('Pagó 2000 euros.'), isEmpty);
      expect(spans('Pasaron 1500 años.'), isEmpty);
      expect(spans('A 1200 km de allí.'), isEmpty);
      expect(spans('Usa 1024 bytes.'), isEmpty);
      expect(spans('Eran 1500 soldados.'), isEmpty);
      expect(spans('Fueron 1900 personas.'), isEmpty);
      expect(spans('Pesa 1500 kg.'), isEmpty);
      expect(spans('Vendió 1500 millones.'), isEmpty);
      expect(spans('Sumaron 1500 mil.'), isEmpty);
      expect(spans('There were 1500 people there.'), isEmpty);
      expect(spans('It took 1500 days.'), isEmpty);
    });

    test('después de «en» o «in», el año gana a lo que se cuenta', () {
      reads('In 1914 people began to leave.', '1914', year(1914));
      reads('En 1914 soldados de toda Europa marcharon.', '1914', year(1914));
    });

    test('pero una unidad de tiempo o de medida sigue ganando', () {
      expect(spans('En 1500 años no cambió.'), isEmpty);
      expect(spans('In 2000 meters it ends.'), isEmpty);
    });

    test('páginas, capítulos, números y códigos', () {
      expect(spans('Ver pág. 1859.'), isEmpty);
      expect(spans('En p. 1859 y pp. 1900'), isEmpty);
      expect(spans('Capítulo 1859'), isEmpty);
      expect(spans('Fig. 1859 y Tabla 1900'), isEmpty);
      expect(spans('Ley 1859 del país'), isEmpty);
      expect(spans('N.º 1859 de la serie'), isEmpty);
      expect(spans('Nro 1859'), isEmpty);
      expect(spans('page 1859 of the book'), isEmpty);
      expect(spans('ISBN 1859'), isEmpty);
      expect(spans('Tel 1859'), isEmpty);
    });

    test('«más de» y «more than» con una cantidad', () {
      expect(spans('Más de 1500 vinieron.'), isEmpty);
      expect(spans('Menos de 1500 vinieron.'), isEmpty);
      expect(spans('More than 1500 came.'), isEmpty);
      expect(spans('Casi 1500 vinieron.'), isEmpty);
    });

    test('un ISBN, un teléfono y un código con guiones', () {
      expect(spans('ISBN 978-84-1234-5678-9'), isEmpty);
      expect(spans('Llamá al 4444-5555.'), isEmpty);
      expect(spans('Código 1234-1235'), isEmpty);
    });

    test('horas y fechas numéricas', () {
      expect(spans('A las 10:30 y a las 18:00.'), isEmpty);
      expect(spans('El 12/02/1809 nació.'), isEmpty);
      expect(spans('El 2020/21 fue distinto.'), isEmpty);
    });

    test('porcentajes y monedas', () {
      expect(spans(r'Subió 1500% y cuesta $1500 o €1900.'), isEmpty);
      expect(spans('Un 1500 % más.'), isEmpty);
      expect(spans('Costó #1859.'), isEmpty);
    });

    test('un número pegado a letras no es un año', () {
      expect(spans('El modelo X1859 y A1900B.'), isEmpty);
    });

    test('sin año, no se toma: días y meses sueltos', () {
      expect(
        spans('El 12 de febrero salió. El martes siguiente volvió.'),
        isEmpty,
      );
      expect(spans('En marzo y el 5 de mayo.'), isEmpty);
      expect(spans('On February 12 he left.'), isEmpty);
    });

    test('texto vacío y sin tiempo', () {
      expect(findTemporalExpressions(''), isEmpty);
      expect(
        findTemporalExpressions('Una oración sin nada de tiempo.'),
        isEmpty,
      );
    });
  });

  group('meses y días', () {
    test('día, mes y año en castellano', () {
      reads(
        'Nació el 12 de febrero de 1809 en Shrewsbury.',
        '12 de febrero de 1809',
        day(1809, 2, 12),
      );
      reads(
        'El 1 de mayo de 1886 hubo huelga.',
        '1 de mayo de 1886',
        day(1886, 5, 1),
      );
      reads('El 1º de mayo de 1886', '1º de mayo de 1886', day(1886, 5, 1));
      reads('El 1.º de mayo de 1886', '1.º de mayo de 1886', day(1886, 5, 1));
      reads(
        'El 15 de Marzo de 44 a.C. murió.',
        '15 de Marzo de 44 a.C.',
        day(44, 3, 15, bce: true),
      );
      reads(
        '12 de febrero del 1809',
        '12 de febrero del 1809',
        day(1809, 2, 12),
      );
      reads('12 de febrero, 1809', '12 de febrero, 1809', day(1809, 2, 12));
      reads(
        '9 de septiembre de 1900',
        '9 de septiembre de 1900',
        day(1900, 9, 9),
      );
      reads(
        '9 de setiembre de 1900',
        '9 de setiembre de 1900',
        day(1900, 9, 9),
      );
    });

    test('día, mes y año en inglés', () {
      reads(
        'He was born on February 12, 1809, in England.',
        'February 12, 1809',
        day(1809, 2, 12),
      );
      reads('On July 4th, 1776.', 'July 4th, 1776', day(1776, 7, 4));
      reads(
        'On March 15 44 BC he died.',
        'March 15 44 BC',
        day(44, 3, 15, bce: true),
      );
      reads('Born 12 February 1809.', '12 February 1809', day(1809, 2, 12));
      reads(
        'Born 12th of February, 1809.',
        '12th of February, 1809',
        day(1809, 2, 12),
      );
      reads('Born 2 May 1809.', '2 May 1809', day(1809, 5, 2));
    });

    test('un año de dos cifras sin era no es un año ni con día y mes', () {
      expect(spans('El 5 de mayo de 12 vino.'), isEmpty);
      expect(spans('On May 5, 12 he came.'), isEmpty);
      expect(spans('On 5 May 12 he came.'), isEmpty);
      reads(
        'El 5 de mayo de 12 a.C. vino.',
        '5 de mayo de 12 a.C.',
        day(12, 5, 5, bce: true),
      );
    });

    test('un día que no existe no se toma como día', () {
      // Lo que el texto dice de verdad queda: el mes y el año, sin el día.
      expect(spans('El 31 de febrero de 1809'), ['febrero de 1809']);
      expect(spans('El 30 de febrero de 1809'), ['febrero de 1809']);
      expect(spans('El 29 de febrero de 1809'), ['febrero de 1809']);
      expect(spans('El 32 de enero de 1809'), ['enero de 1809']);
      expect(spans('El 0 de enero de 1809'), ['enero de 1809']);
      expect(spans('February 30, 1809'), ['1809']);
      expect(spans('31 de abril de 1809').single, 'abril de 1809');
      reads(
        'El 29 de febrero de 1808',
        '29 de febrero de 1808',
        day(1808, 2, 29),
      );
      reads(
        'El 29 de febrero de 2000',
        '29 de febrero de 2000',
        day(2000, 2, 29),
      );
      expect(spans('El 29 de febrero de 1900'), ['febrero de 1900']);
    });

    test('mes y año', () {
      reads('En febrero de 1809 nació.', 'febrero de 1809', month(1809, 2));
      reads('Enero de 1900 fue frío.', 'Enero de 1900', month(1900, 1));
      reads(
        'En marzo del 44 a.C. pasó.',
        'marzo del 44 a.C.',
        month(44, 3, bce: true),
      );
      reads('En mayo 1809 llegó.', 'mayo 1809', month(1809, 5));
      reads('In March 1809 it began.', 'March 1809', month(1809, 3));
      reads('In March of 1809 it began.', 'March of 1809', month(1809, 3));
      reads('In March, 1809 it began.', 'March, 1809', month(1809, 3));
    });

    test('sin «de», un mes y tres cifras no son una fecha; con «de», sí', () {
      expect(spans('In May 100 he left.'), isEmpty);
      expect(spans('En mayo 476 se fue.'), isEmpty);
      reads('En mayo de 476 cayó.', 'mayo de 476', month(476, 5));
      reads('In May of 476 it fell.', 'May of 476', month(476, 5));
    });

    test('un mes y un número corto no son una fecha', () {
      expect(spans('May 100 people came.'), isEmpty);
      expect(spans('March 12 soldiers marched.'), isEmpty);
      expect(spans('En marzo de 12 llegó.'), isEmpty);
      expect(spans('March 1500 soldiers marched.'), isEmpty);
    });

    test('el mes es una palabra entera', () {
      expect(spans('Marzo, mayormente 1809'), ['1809']);
    });
  });

  group('siglos', () {
    test('«siglo XIX», «s. XV» y compañía', () {
      reads('Pasó en el siglo XIX.', 'siglo XIX', century(1801));
      reads('Fue en el Siglo V.', 'Siglo V', century(401));
      reads('Fue en el s. XV.', 's. XV', century(1401));
      reads('Fue en el s.XV.', 's.XV', century(1401));
      reads('Del S. XVI.', 'S. XVI', century(1501));
      reads('El siglo I fue así.', 'siglo I', century(1));
      reads('El siglo XXI.', 'siglo XXI', century(2001));
      reads('El siglo xix.', 'siglo xix', century(1801));
      reads('Los siglos XV vieron', 'siglos XV', century(1401));
    });

    test('con era: siglo V a.C.', () {
      reads(
        'Pasó en el siglo V a.C. en Atenas.',
        'siglo V a.C.',
        century(500, bce: true),
      );
      reads('Siglo I d.C.', 'Siglo I d.C.', century(1));
      reads('Siglo IV a. C.', 'Siglo IV a. C.', century(400, bce: true));
      reads('5th century BC', '5th century BC', century(500, bce: true));
    });

    test('romanos inválidos o fuera de rango no son un siglo', () {
      expect(spans('El siglo IIII y el siglo VX.'), isEmpty);
      expect(spans('El siglo IC y el siglo MIM.'), isEmpty);
      expect(spans('El siglo XLI.'), isEmpty);
      expect(spans('El siglo C y el siglo D.'), isEmpty);
      expect(spans('El siglo de Oro y el siglo de las luces.'), isEmpty);
    });

    test('«s.» en minúscula con un romano suelto no es un siglo', () {
      expect(spans('Ver s. v para más.'), isEmpty);
      expect(spans('Vea s. xv.'), isEmpty);
    });

    test('en inglés: «19th century», «nineteenth century», «XIX century»', () {
      reads('In the 19th century.', '19th century', century(1801));
      reads('In the 1st century.', '1st century', century(1));
      reads('In the 21st century.', '21st century', century(2001));
      reads('19th-century art', '19th-century', century(1801));
      reads('In the nineteenth century.', 'nineteenth century', century(1801));
      reads('Fifth century saw it.', 'Fifth century', century(401));
      reads(
        'In the twenty-first century.',
        'twenty-first century',
        century(2001),
      );
      reads('In the XIX century.', 'XIX century', century(1801));
      reads(
        'In the 5th century BCE.',
        '5th century BCE',
        century(500, bce: true),
      );
      reads(
        'The fifth century B.C.',
        'fifth century B.C.',
        century(500, bce: true),
      );
    });

    test('«0th century» y «41st century» no existen', () {
      expect(spans('In the 0th century and the 41st century.'), isEmpty);
    });

    test('«I century» suelto no es un siglo', () {
      expect(spans('I century is a typo'), isEmpty);
    });

    test('rangos de siglos', () {
      reads(
        'Entre los siglos XV–XVII',
        'siglos XV–XVII',
        century(1401),
        century(1601),
      );
      reads(
        'Los siglos XV-XVII',
        'siglos XV-XVII',
        century(1401),
        century(1601),
      );
      reads(
        'Del siglo XV al XVII',
        'siglo XV al XVII',
        century(1401),
        century(1601),
      );
      reads(
        'Los siglos V a III a.C.',
        'siglos V a III a.C.',
        century(500, bce: true),
        century(300, bce: true),
      );
      reads(
        'The 15th-17th centuries',
        '15th-17th centuries',
        century(1401),
        century(1601),
      );
      reads(
        'The 15th to 17th century',
        '15th to 17th century',
        century(1401),
        century(1601),
      );
    });

    test('un rango de siglos al revés no se toma como rango', () {
      expect(spans('Los siglos XVII-XV'), ['siglos XVII']);
      expect(spans('Los siglos XV-XV'), ['siglos XV']);
      expect(spans('The 17th-15th centuries'), isEmpty);
    });
  });

  group('décadas', () {
    test("«1920s» y «1920's»", () {
      reads('In the 1920s it grew.', '1920s', decade(1920));
      reads("In the 1920's it grew.", "1920's", decade(1920));
      reads('The 1990s.', '1990s', decade(1990));
    });

    test(
      'un siglo entero escrito «1900s» o «1500s» es ambiguo y no se toma',
      () {
        expect(spans('In the 1900s and the 1500s.'), isEmpty);
      },
    );

    test('«la década de 1920» y variantes', () {
      reads('Pasó en la década de 1920.', 'la década de 1920', decade(1920));
      reads('Pasó en la década del 1920.', 'la década del 1920', decade(1920));
      reads(
        'Pasó en la década de los 1920.',
        'la década de los 1920',
        decade(1920),
      );
      reads('Década de 1930 difícil.', 'Década de 1930', decade(1930));
      reads('Pasó en la década de 1920s.', 'la década de 1920s', decade(1920));
    });

    test('una década que no empieza en cero de unidades no es una década', () {
      expect(spans('La década de 1925.'), ['1925']);
      expect(spans('Los años 1925 fueron.'), ['1925']);
    });

    test('«los años 1920»', () {
      reads('En los años 1920 creció.', 'los años 1920', decade(1920));
    });

    test('«los años 20» toma el siglo del año más cercano', () {
      expect(
        findTemporalExpressions(
          'En 1914 empezó. En los años 20 siguió.',
        ).map((e) => e.date),
        [year(1914), decade(1920)],
      );
      expect(
        findTemporalExpressions(
          'Nació en 1809. Murió en 1882. En los años 90 se recordó.',
        ).map((e) => e.date),
        [year(1809), year(1882), decade(1890)],
      );
    });

    test('«los años 20» elige el año más cercano de cada lado', () {
      List<HistoricalDate> dates(String text) =>
          findTemporalExpressions(text).map((e) => e.date).toList();

      // El de después, si está más cerca que el de antes.
      expect(dates('En 1714 empezó todo aquello. En los años 20, en 1914.'), [
        year(1714),
        decade(1920),
        year(1914),
      ]);
      // A igual distancia, el de antes.
      expect(dates('En 1714 y los años 20 y 1914.'), [
        year(1714),
        decade(1720),
        year(1914),
      ]);
      // El último de antes, aunque haya varios.
      expect(dates('En 1614, 1714 y 1814, los años 20.'), [
        year(1614),
        year(1714),
        year(1814),
        decade(1820),
      ]);
      // Cada década con el suyo, en un mismo texto.
      expect(dates('En 1714 los años 20; ya en 1914, los años 30.'), [
        year(1714),
        decade(1720),
        year(1914),
        decade(1930),
      ]);
    });

    test('un año a más de 1500 caracteres no dice el siglo', () {
      List<HistoricalDate> dates(String text) =>
          findTemporalExpressions(text).map((e) => e.date).toList();
      String gap(int chars) => ' ' * chars;

      expect(dates('1914${gap(1500)}los años 20'), [year(1914), decade(1920)]);
      expect(dates('1914${gap(1501)}los años 20'), [year(1914)]);
      expect(dates('los años 20${gap(1500)}1914'), [decade(1920), year(1914)]);
      expect(dates('los años 20${gap(1501)}1914'), [year(1914)]);
    });

    test('«los años veinte», «the twenties», «the 20s»', () {
      expect(
        findTemporalExpressions(
          'En 1914 empezó. En los años veinte siguió.',
        ).map((e) => e.date),
        [year(1914), decade(1920)],
      );
      expect(
        findTemporalExpressions(
          'In 1914 it began. In the twenties it went on.',
        ).map((e) => e.date),
        [year(1914), decade(1920)],
      );
      expect(
        findTemporalExpressions(
          "In 1914 it began. In the '30s it went on.",
        ).map((e) => e.date),
        [year(1914), decade(1930)],
      );
      expect(
        findTemporalExpressions(
          'In 1914 it began. In the 50s it went on.',
        ).map((e) => e.date),
        [year(1914), decade(1950)],
      );
    });

    test(
      '«los años 20» con el año de contexto a unos cientos de caracteres',
      () {
        final text = 'En 1914 vio. ${'x ' * 100}En los años 20 pasó.';
        expect(findTemporalExpressions(text).map((e) => e.date), [
          year(1914),
          decade(1920),
        ]);
      },
    );

    test('«los años 20» sin un año cerca no se toma', () {
      expect(spans('En los años 20 pasó algo.'), isEmpty);
      expect(spans('En los años veinte pasó algo.'), isEmpty);
      expect(spans('In the twenties something happened.'), isEmpty);
    });

    test('«los años 20» con el año de contexto lejos tampoco', () {
      final far = '1914 ${'x ' * 1000}los años 20 pasó';
      expect(spans(far), ['1914']);
    });

    test('con un año del 2000 en adelante tampoco se toma el siglo', () {
      expect(spans('En 2005 vio. En los años 90 pasó.'), ['2005']);
    });

    test('con un año de antes de Cristo cerca tampoco', () {
      expect(spans('En 44 a.C. murió. En los años 20 pasó.'), ['44 a.C.']);
      // Aunque el número parezca de 1000–1999: es a.C.
      expect(spans('En 1500 a.C. vivió. En los años 20 pasó.'), ['1500 a.C.']);
    });

    test('«los años 20» elige el año más cercano, antes o después', () {
      // El de después está más cerca que el de antes.
      expect(
        findTemporalExpressions(
          'En 1809 nació. ${'x ' * 300}En los años 90 pasó. En 1789 cayó.',
        ).map((e) => e.date),
        [year(1809), decade(1790), year(1789)],
      );
      // El de antes está más cerca que el de después.
      expect(
        findTemporalExpressions(
          'En 1789 cayó. En los años 90 pasó. ${'x ' * 300}En 1809 nació.',
        ).map((e) => e.date),
        [year(1789), decade(1790), year(1809)],
      );
    });

    test('«los años 05» o «los años 25» no son décadas', () {
      expect(spans('En 1914 vio. En los años 25 y los años 05.'), ['1914']);
      expect(spans('En 1914 vio. En los años 00 y los años 100.'), ['1914']);
    });

    test('las palabras de las décadas valen lo que dicen', () {
      const words = {
        'veinte': 1920,
        'treinta': 1930,
        'cuarenta': 1940,
        'cincuenta': 1950,
        'sesenta': 1960,
        'setenta': 1970,
        'ochenta': 1980,
        'noventa': 1990,
      };
      words.forEach((word, first) {
        expect(
          findTemporalExpressions(
            'En 1914 vio. En los años $word pasó.',
          ).map((e) => e.date).last,
          decade(first),
          reason: word,
        );
      });
      const english = {
        'twenties': 1920,
        'thirties': 1930,
        'forties': 1940,
        'fifties': 1950,
        'sixties': 1960,
        'seventies': 1970,
        'eighties': 1980,
        'nineties': 1990,
      };
      english.forEach((word, first) {
        expect(
          findTemporalExpressions(
            'In 1914 it began. In the $word it ended.',
          ).map((e) => e.date).last,
          decade(first),
          reason: word,
        );
      });
    });
  });

  group('aproximadas', () {
    test('«hacia», «c.», «ca.», «circa»', () {
      reads(
        'Ocurrió hacia 1500 en Italia.',
        'hacia 1500',
        year(1500, circa: true),
      );
      reads('Ocurrió hacia el 1500.', 'hacia el 1500', year(1500, circa: true));
      reads('Ocurrió c. 1500.', 'c. 1500', year(1500, circa: true));
      reads('Ocurrió c.1500.', 'c.1500', year(1500, circa: true));
      reads('Ocurrió ca. 1500.', 'ca. 1500', year(1500, circa: true));
      reads('Ocurrió circa 1500.', 'circa 1500', year(1500, circa: true));
      reads('Ocurrió Circa 1500.', 'Circa 1500', year(1500, circa: true));
      reads('Hacia 1500 pasó.', 'Hacia 1500', year(1500, circa: true));
    });

    test('«alrededor de», «cerca de», «en torno a», «aproximadamente»', () {
      reads(
        'Pasó alrededor de 1500.',
        'alrededor de 1500',
        year(1500, circa: true),
      );
      reads(
        'Pasó alrededor del año 1000.',
        'alrededor del año 1000',
        year(1000, circa: true),
      );
      reads('Pasó cerca de 1500.', 'cerca de 1500', year(1500, circa: true));
      reads(
        'Pasó en torno a 1500.',
        'en torno a 1500',
        year(1500, circa: true),
      );
      reads(
        'Pasó en torno al 1500.',
        'en torno al 1500',
        year(1500, circa: true),
      );
      reads(
        'Pasó aproximadamente 1500.',
        'aproximadamente 1500',
        year(1500, circa: true),
      );
      reads('Pasó aprox. 1500.', 'aprox. 1500', year(1500, circa: true));
    });

    test('en inglés: «around», «about», «approximately», «roughly»', () {
      reads('It was around 1500.', 'around 1500', year(1500, circa: true));
      reads('It was about 1500.', 'about 1500', year(1500, circa: true));
      reads(
        'It was approximately 1500.',
        'approximately 1500',
        year(1500, circa: true),
      );
      reads('It was approx. 1500.', 'approx. 1500', year(1500, circa: true));
      reads('It was roughly 1500.', 'roughly 1500', year(1500, circa: true));
      reads(
        'It was circa the year 476.',
        'circa the year 476',
        year(476, circa: true),
      );
    });

    test('con a.C. y siglos', () {
      reads(
        'Hacia el 44 a.C. pasó.',
        'Hacia el 44 a.C.',
        year(44, bce: true, circa: true),
      );
      reads(
        'Hacia el siglo V pasó.',
        'Hacia el siglo V',
        century(401, circa: true),
      );
      reads(
        'Hacia el año 476 pasó.',
        'Hacia el año 476',
        year(476, circa: true),
      );
    });

    test('el rango aproximado lo es en los dos extremos', () {
      final e = only('Hacia 1500-1510 pasó.');
      expect(e.date, year(1500, circa: true));
      expect(e.endDate, year(1510, circa: true));
    });

    test('«hacia» sin una fecha pegada no hace aproximada a otra', () {
      reads('Hacia allá, en 1500 pasó.', '1500', year(1500));
      reads('Fue hacia fines del siglo XV.', 'siglo XV', century(1401));
    });

    test('el prefijo no se come la expresión de antes', () {
      final found = findTemporalExpressions('En 1400 hacia 1500.');
      expect(found.map((e) => (e.start, e.end)), [(3, 7), (8, 18)]);
      expect(found[1].date, year(1500, circa: true));
    });

    test('«c.» pegado a una palabra no es «circa»', () {
      reads('Doc. 1500 pasó.', '1500', year(1500));
      reads('Ábac. 1500.', '1500', year(1500));
    });

    test('«about» y una cantidad no son aproximadas', () {
      expect(spans('There were about 1500 people.'), isEmpty);
      expect(spans('Pasaron cerca de 1500 años.'), isEmpty);
    });
  });

  group('rangos', () {
    test('con guion corto, medio y largo', () {
      reads(
        'La vida (1809-1882) de Darwin',
        '1809-1882',
        year(1809),
        year(1882),
      );
      reads(
        'La vida (1809–1882) de Darwin',
        '1809–1882',
        year(1809),
        year(1882),
      );
      reads(
        'La vida (1809—1882) de Darwin',
        '1809—1882',
        year(1809),
        year(1882),
      );
      reads('La guerra 1914 - 1918 fue', '1914 - 1918', year(1914), year(1918));
      reads('La guerra 1914 – 1918 fue', '1914 – 1918', year(1914), year(1918));
    });

    test('con el fin abreviado a dos cifras', () {
      reads('La guerra 1939-45 fue', '1939-45', year(1939), year(1945));
      reads('La guerra 1914–18 fue', '1914–18', year(1914), year(1918));
      // Un fin abreviado que caería antes del inicio no es un rango.
      expect(spans('La guerra 1999-05 fue'), isEmpty);
    });

    test('«de 1914 a 1918», «desde … hasta …»', () {
      reads(
        'Duró de 1914 a 1918 en total.',
        'de 1914 a 1918',
        year(1914),
        year(1918),
      );
      reads('Duró De 1914 a 1918.', 'De 1914 a 1918', year(1914), year(1918));
      reads(
        'Duró desde 1914 hasta 1918.',
        'desde 1914 hasta 1918',
        year(1914),
        year(1918),
      );
      reads(
        'Duró del 1914 al 1918.',
        'del 1914 al 1918',
        year(1914),
        year(1918),
      );
      reads(
        'Duró del año 1914 al año 1918.',
        'del año 1914 al año 1918',
        year(1914),
        year(1918),
      );
      reads(
        'Duró desde el 1914 hasta el 1918.',
        'desde el 1914 hasta el 1918',
        year(1914),
        year(1918),
      );
      reads(
        'Duró desde el año 1914 hasta el año 1918.',
        'desde el año 1914 hasta el año 1918',
        year(1914),
        year(1918),
      );
    });

    test('«entre 1914 y 1918»', () {
      reads(
        'Duró entre 1914 y 1918.',
        'entre 1914 y 1918',
        year(1914),
        year(1918),
      );
      reads(
        'Duró Entre 1914 y 1918.',
        'Entre 1914 y 1918',
        year(1914),
        year(1918),
      );
      reads(
        'Duró entre los años 1914 y 1918.',
        'entre los años 1914 y 1918',
        year(1914),
        year(1918),
      );
    });

    test('en inglés: «from … to …», «between … and …»', () {
      reads(
        'It ran from 1914 to 1918.',
        'from 1914 to 1918',
        year(1914),
        year(1918),
      );
      reads(
        'It ran From 1914 until 1918.',
        'From 1914 until 1918',
        year(1914),
        year(1918),
      );
      reads(
        'It ran from 1914 through 1918.',
        'from 1914 through 1918',
        year(1914),
        year(1918),
      );
      reads(
        'It ran between 1914 and 1918.',
        'between 1914 and 1918',
        year(1914),
        year(1918),
      );
      reads(
        'It ran between the years 1914 and 1918.',
        'between the years 1914 and 1918',
        year(1914),
        year(1918),
      );
    });

    test('con era compartida o propia', () {
      reads(
        'De 490 a 479 a.C. duró',
        'De 490 a 479 a.C.',
        year(490, bce: true),
        year(479, bce: true),
      );
      reads(
        'Entre 100 y 44 a.C. pasó',
        'Entre 100 y 44 a.C.',
        year(100, bce: true),
        year(44, bce: true),
      );
      reads(
        'Fue 490-479 a.C. en total',
        '490-479 a.C.',
        year(490, bce: true),
        year(479, bce: true),
      );
      reads(
        'Fue 27 a.C.–14 d.C. en total',
        '27 a.C.–14 d.C.',
        year(27, bce: true),
        year(14),
      );
      reads('Fue 476–800 d.C. en total', '476–800 d.C.', year(476), year(800));
      reads(
        'Fue 490 a.C.-479 a.C. aquí',
        '490 a.C.-479 a.C.',
        year(490, bce: true),
        year(479, bce: true),
      );
      reads(
        'From 490 to 479 BC it ran',
        'From 490 to 479 BC',
        year(490, bce: true),
        year(479, bce: true),
      );
    });

    test('un rango de a.C. creciente o con la misma fecha no es un rango', () {
      expect(spans('De 100 a 200 a.C. pasó'), ['200 a.C.']);
      expect(spans('Fue 1914-1914 así'), isEmpty);
    });

    test('la era del primer extremo vale para el segundo', () {
      reads(
        'Fue 100 a.C.-44 así',
        '100 a.C.-44',
        year(100, bce: true),
        year(44, bce: true),
      );
    });

    test('un rango al revés no es un rango', () {
      expect(spans('De 1918 a 1914 pasó'), isNot(contains('De 1918 a 1914')));
    });

    test('rangos de cantidades no son años', () {
      expect(spans('Eran de 1000 a 1500 soldados.'), isEmpty);
      expect(spans('Pagó entre 1000 y 2000 euros.'), isEmpty);
      expect(spans('Pesa 1000-1500 kg.'), isEmpty);
      expect(spans('Son de 100 a 200 personas.'), isEmpty);
      expect(spans('Entre 100 y 200 vinieron.'), isEmpty);
      expect(spans('pp. 1900-1950'), isEmpty);
      expect(spans('Rango 100-200.'), isEmpty);
    });

    test('un rango que termina fuera de 1000–2099 no se toma como rango', () {
      expect(spans('Fue 1500-2500 así.'), isEmpty);
      expect(spans('Fue 1500-2150 así.'), isEmpty);
      expect(spans('Fue 0999-1500 así.'), isEmpty);
      expect(spans('Fue 1000-1500 así.'), ['1000-1500']);
      expect(spans('Fue 2000-2099 así.'), ['2000-2099']);
      expect(spans('Fue 999-1500 así.'), isEmpty);
    });

    test('«de 1914 a Churchill» no es un rango', () {
      expect(spans('Se fue de 1914 a Churchill.'), ['1914']);
    });
  });

  group('superposiciones y orden', () {
    test('un rango gana a las fechas que contiene', () {
      expect(spans('Fue de 1914 a 1918.'), ['de 1914 a 1918']);
    });

    test('una fecha completa gana al año que contiene', () {
      expect(spans('Fue el 12 de febrero de 1809.'), ['12 de febrero de 1809']);
    });

    test('las expresiones salen en orden y sin pisarse', () {
      const text =
          'En el siglo XIX, entre 1850 y 1860, el 5 de mayo de 1855 pasó; '
          'luego en 1900 y hacia 1950.';
      final found = findTemporalExpressions(text);
      expect(spans(text), [
        'siglo XIX',
        'entre 1850 y 1860',
        '5 de mayo de 1855',
        '1900',
        'hacia 1950',
      ]);
      for (var i = 1; i < found.length; i++) {
        expect(found[i].start, greaterThanOrEqualTo(found[i - 1].end));
      }
    });

    test('mezcla de español e inglés en el mismo texto', () {
      expect(
        spans('Born on February 12, 1809 (nació en 1809) in the 19th century.'),
        ['February 12, 1809', '1809', '19th century'],
      );
    });

    test('dos fechas pegadas por coma', () {
      expect(spans('1809, 1859, 1882'), ['1809', '1859', '1882']);
    });

    test('un libro entero se recorre en un tiempo que crece con el texto', () {
      // Se mide cuánto crece el tiempo, no cuánto tarda: con la máquina
      // cargada los dos tamaños se frenan juntos. Cuatro veces más texto
      // tarda unas cuatro veces más; si cada expresión se comparara con
      // todas las demás —o cada «los años 20» con todos los años del
      // texto—, tardaría doce.
      String book(int sentences) => List.filled(
        sentences,
        'Nació en 1809; en los años 20 viajó y murió en 1882. ',
      ).join();
      int micros(String text) {
        final watch = Stopwatch()..start();
        findTemporalExpressions(text);
        return watch.elapsedMicroseconds;
      }

      final small = book(8000);
      final big = book(32000);
      expect(findTemporalExpressions(big), hasLength(96000));
      micros(small);
      // Lo mejor de tres, intercalado: un tirón de la máquina no cae
      // siempre sobre el mismo tamaño.
      var bestSmall = micros(small);
      var bestBig = micros(big);
      for (var i = 0; i < 2; i++) {
        bestSmall = math.min(bestSmall, micros(small));
        bestBig = math.min(bestBig, micros(big));
      }
      expect(bestBig / bestSmall, lessThan(7));
    });

    test('los espacios duros y los saltos de línea dentro de la expresión', () {
      final nbsp = String.fromCharCode(0xa0);
      reads('Fue en 44${nbsp}a.C. así', '44${nbsp}a.C.', year(44, bce: true));
      reads('De 1914\na 1918 pasó', 'De 1914\na 1918', year(1914), year(1918));
      reads(
        'Fue el 12\nde febrero\nde 1809',
        '12\nde febrero\nde 1809',
        day(1809, 2, 12),
      );
    });

    test('una expresión con circa lee igual cada fecha', () {
      final e = only('Hacia el 12 de febrero de 1809');
      expect(e.date.isCirca, isTrue);
      expect(e.date.precision, DatePrecision.day);
    });
  });

  group('TemporalExpression', () {
    test('igualdad y representación', () {
      final a = TemporalExpression(start: 1, end: 5, date: year(1809));
      final b = TemporalExpression(start: 1, end: 5, date: year(1809));
      final c = TemporalExpression(
        start: 1,
        end: 5,
        date: year(1809),
        endDate: year(1810),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(TemporalExpression(start: 2, end: 5, date: year(1809))));
      expect(a, isNot(TemporalExpression(start: 1, end: 6, date: year(1809))));
      expect(a, isNot(TemporalExpression(start: 1, end: 5, date: year(1810))));
      expect(a.toString(), contains('1809'));
      expect(c.toString(), contains('1810'));
    });
  });
}
