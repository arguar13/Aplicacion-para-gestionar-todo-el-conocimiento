import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/services/normalized_date_parser.dart';

/// El analizador estricto de la fecha normalizada que devuelve el modelo
/// (F40): lee el formato exacto o no lee nada.
void main() {
  HistoricalDate year(int n, {bool bce = false, bool circa = false}) =>
      HistoricalDate(
        year: n,
        precision: DatePrecision.year,
        isBce: bce,
        isCirca: circa,
      );

  HistoricalDate day(
    int y,
    int m,
    int d, {
    bool bce = false,
    bool circa = false,
  }) => HistoricalDate(
    year: y,
    precision: DatePrecision.day,
    month: m,
    day: d,
    isBce: bce,
    isCirca: circa,
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

  HistoricalDate decade(int first, {bool circa = false}) => HistoricalDate(
    year: first,
    precision: DatePrecision.decade,
    isCirca: circa,
  );

  void reads(String text, HistoricalDate start, [HistoricalDate? end]) {
    final span = parseNormalizedDate(text);
    expect(span, isNotNull, reason: text);
    expect(span!.start, start, reason: text);
    expect(span.end, end, reason: text);
  }

  void rejects(String text) {
    expect(parseNormalizedDate(text), isNull, reason: '«$text»');
  }

  group('años', () {
    test('un año de la era común', () {
      reads('1859', year(1859));
      reads('476', year(476));
      reads('5', year(5));
      reads('9999', year(9999));
      reads('0476', year(476));
    });

    test('los espacios de los bordes y repetidos no importan', () {
      reads('  1859  ', year(1859));
      reads('\n1859\t', year(1859));
      reads('44   a.C.', year(44, bce: true));
    });

    test('con la era: a.C. y sus variantes', () {
      for (final marker in [
        'a.C.',
        'a.C',
        'a. C.',
        'a. C',
        'A.C.',
        'aC',
        'a. de C.',
        'a. J.C.',
        'BC',
        'B.C.',
        'BCE',
        'B.C.E.',
        'antes de Cristo',
        'Before Christ',
      ]) {
        reads('44 $marker', year(44, bce: true));
      }
      reads('44a.C.', year(44, bce: true));
    });

    test('con la era: d.C. y sus variantes', () {
      for (final marker in [
        'd.C.',
        'd. C.',
        'D.C.',
        'dC',
        'AD',
        'A.D.',
        'CE',
        'C.E.',
        'después de Cristo',
      ]) {
        reads('476 $marker', year(476));
      }
      reads('AD 476', year(476));
      reads('A.D. 476', year(476));
    });

    test('no existe el año 0 ni uno de cinco cifras', () {
      rejects('0');
      rejects('00');
      rejects('0 a.C.');
      rejects('0 d.C.');
      rejects('AD 0');
      rejects('10000');
      rejects('12345');
    });

    test('un año con signo es ambiguo y no se lee', () {
      rejects('-43');
      rejects('-44');
      rejects('+43');
      rejects('−43');
      rejects('-1');
    });

    test('lo que no es un año', () {
      rejects('');
      rejects('   ');
      rejects('abc');
      rejects('mil novecientos');
      rejects('1859.5');
      rejects('1,859');
      rejects('1.859');
      rejects('18 59');
      rejects('1859?');
      rejects('~1859');
      rejects('1859 aprox');
    });

    test('una era desconocida, repetida o mal puesta', () {
      rejects('44 a.C.x');
      rejects('44 x.C.');
      rejects('44 a.C. a.C.');
      rejects('a.C. 44');
      rejects('AD 476 a.C.');
      rejects('44 d.C. d.C.');
      rejects('BC 44');
      rejects('44 a C');
    });
  });

  group('meses y días', () {
    test('mes y día', () {
      reads('1809-02', month(1809, 2));
      reads('1809-02-12', day(1809, 2, 12));
      reads('1809-2-5', day(1809, 2, 5));
      reads('1809-12-31', day(1809, 12, 31));
      reads('1809-01-01', day(1809, 1, 1));
      reads('476-09-04', day(476, 9, 4));
    });

    test('con era', () {
      reads('44-03-15 a.C.', day(44, 3, 15, bce: true));
      reads('44-03 a.C.', month(44, 3, bce: true));
      reads('44-03-15a.C.', day(44, 3, 15, bce: true));
      reads('476-09-04 d.C.', day(476, 9, 4));
    });

    test('un mes que no existe', () {
      rejects('1809-13');
      rejects('1809-13-01');
      rejects('1809-00');
      rejects('1809-00-10');
      rejects('1809-99-99');
    });

    test('un día que no existe', () {
      rejects('1809-02-30');
      rejects('1809-02-31');
      rejects('1809-04-31');
      rejects('1809-06-31');
      rejects('1809-09-31');
      rejects('1809-11-31');
      rejects('1809-01-32');
      rejects('1809-01-00');
    });

    test('el 29 de febrero solo en un año bisiesto', () {
      reads('1808-02-29', day(1808, 2, 29));
      reads('2000-02-29', day(2000, 2, 29));
      rejects('1809-02-29');
      rejects('1900-02-29');
      rejects('2100-02-29');
    });

    test('un formato partido de otra manera', () {
      rejects('1809-02-12-01');
      rejects('1809/02/12');
      rejects('12-02-1809');
      rejects('1809-02-');
      rejects('1809--02');
      rejects('1809-002');
      rejects('1809-02-123');
      rejects('12 de febrero de 1809');
      rejects('February 12, 1809');
    });
  });

  group('siglos', () {
    test('«s. XIX» y «siglo XIX»', () {
      reads('s. XIX', century(1801));
      reads('s.XIX', century(1801));
      reads('S. XIX', century(1801));
      reads('siglo XIX', century(1801));
      reads('Siglo XIX', century(1801));
      reads('siglo I', century(1));
      reads('s. XXI', century(2001));
      reads('siglo XL', century(3901));
      reads('s. V', century(401));
    });

    test('con la era: el siglo V a.C. empieza en el año 500 a.C.', () {
      reads('s. V a.C.', century(500, bce: true));
      reads('siglo V a. C.', century(500, bce: true));
      reads('s. I a.C.', century(100, bce: true));
      reads('s. II d.C.', century(101));
    });

    test('«siglo» admite el romano en minúscula, «s.» no', () {
      reads('siglo xix', century(1801));
      rejects('s. xix');
      rejects('s. v');
      rejects('S. xv');
    });

    test('romanos inválidos o fuera de rango', () {
      rejects('s. IIII');
      rejects('s. VX');
      rejects('s. IC');
      rejects('s. XXXX');
      rejects('s. XLI');
      rejects('s. C');
      rejects('siglo MIM');
      rejects('s. ');
      rejects('s.');
      rejects('siglo');
      rejects('siglo 19');
      rejects('s. 19');
      rejects('s. 0');
      rejects('siglo XIX XX');
    });
  });

  group('décadas', () {
    test('«década 1920» y variantes', () {
      reads('década 1920', decade(1920));
      reads('década de 1920', decade(1920));
      reads('década del 1920', decade(1920));
      reads('Década 1920', decade(1920));
      reads('1920s', decade(1920));
      reads('1990s', decade(1990));
      reads('década 10', decade(10));
      reads('década 340', decade(340));
    });

    test('un año que no empieza una década', () {
      rejects('década 1925');
      rejects('década 1921');
      rejects('1925s');
      rejects('década 1920s');
      rejects('década 5');
      rejects('década 0');
      rejects('década 00');
      rejects('0s');
    });

    test('una década a.C. es ambigua y no se lee', () {
      rejects('década 340 a.C.');
      rejects('340s BC');
      rejects('1920s a.C.');
      rejects('década 340 BC');
    });

    test('sin año o con otra cosa', () {
      rejects('década');
      rejects('década de');
      rejects('década 10000');
      rejects('década XX');
      rejects('s');
    });
  });

  group('aproximadas', () {
    test('«c.», «ca.», «circa»', () {
      reads('c. 1500', year(1500, circa: true));
      reads('c.1500', year(1500, circa: true));
      reads('ca. 1500', year(1500, circa: true));
      reads('circa 1500', year(1500, circa: true));
      reads('Circa 1500', year(1500, circa: true));
      reads('C. 1500', year(1500, circa: true));
    });

    test('con cualquier precisión', () {
      reads('c. 1809-02-12', day(1809, 2, 12, circa: true));
      reads('c. s. XV', century(1401, circa: true));
      reads('c. década 1920', decade(1920, circa: true));
      reads('c. 44 a.C.', year(44, bce: true, circa: true));
    });

    test('una palabra de aproximación que no es una de las tres', () {
      rejects('aprox 1500');
      rejects('hacia 1500');
      rejects('cc. 1500');
      rejects('about 1500');
      rejects('c. ');
      rejects('c.');
      rejects('circa');
      rejects('c. c. 1500');
    });
  });

  group('rangos', () {
    test('de años', () {
      reads('1914..1918', year(1914), year(1918));
      reads('1914 .. 1918', year(1914), year(1918));
      reads('476..800', year(476), year(800));
    });

    test('de fechas de cualquier precisión', () {
      reads('1809-02-12..1809-03-01', day(1809, 2, 12), day(1809, 3, 1));
      reads('s. XV..s. XVII', century(1401), century(1601));
      reads('década 1920..década 1930', decade(1920), decade(1930));
      reads('1914..1918-11-11', year(1914), day(1918, 11, 11));
    });

    test('con la era de cada extremo', () {
      reads('490 a.C...479 a.C.', year(490, bce: true), year(479, bce: true));
      reads('27 a.C...14 d.C.', year(27, bce: true), year(14));
      reads(
        's. V a.C...s. III a.C.',
        century(500, bce: true),
        century(300, bce: true),
      );
    });

    test('aproximadas en un extremo o en los dos', () {
      reads(
        'c. 1500..c. 1510',
        year(1500, circa: true),
        year(1510, circa: true),
      );
      reads('c. 1500..1510', year(1500, circa: true), year(1510));
    });

    test('el fin no es posterior al inicio', () {
      rejects('1918..1914');
      rejects('1914..1914');
      rejects('479 a.C...490 a.C.');
      rejects('s. XVII..s. XV');
      // La era es de cada extremo: 490 es d.C., y 479 a.C. es anterior.
      rejects('490..479 a.C.');
    });

    test('un extremo sin leer', () {
      rejects('1914..');
      rejects('..1918');
      rejects('..');
      rejects('1914..abc');
      rejects('abc..1918');
      rejects('1914..1809-13');
      rejects('1914....1918');
    });

    test('más de un rango', () {
      rejects('1914..1918..1920');
    });
  });

  test('una fecha sola no tiene fin', () {
    expect(parseNormalizedDate('1914')!.end, isNull);
    expect(parseNormalizedDate('s. XV')!.end, isNull);
  });
}
