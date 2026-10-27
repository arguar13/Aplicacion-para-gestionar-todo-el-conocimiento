import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/services/quote_date_locator.dart';

/// Dónde está escrita la fecha de un hecho dentro de su cita (F40): lo que la
/// ficha resalta.
void main() {
  HistoricalDate year(int y, {bool bce = false, bool circa = false}) =>
      HistoricalDate(
        year: y,
        precision: DatePrecision.year,
        isBce: bce,
        isCirca: circa,
      );

  String marked(String excerpt, HistoricalDate date, {HistoricalDate? end}) {
    final found = locateEventDate(excerpt, date: date, end: end);
    return found == null ? '' : excerpt.substring(found.start, found.end);
  }

  test('resalta la expresión que lee la fecha del hecho', () {
    expect(marked('En 1859 publicó su libro.', year(1859)), '1859');
  });

  test('con varias fechas, la del hecho y no otra', () {
    const quote = 'Nació en 1809 y publicó en 1859.';

    expect(marked(quote, year(1809)), '1809');
    expect(marked(quote, year(1859)), '1859');
  });

  test('una fecha con varias palabras se resalta entera', () {
    const quote = 'Cayó el 12 de febrero de 1809, dicen.';
    const date = HistoricalDate(
      year: 1809,
      precision: DatePrecision.day,
      month: 2,
      day: 12,
    );

    expect(marked(quote, date), '12 de febrero de 1809');
  });

  test('un hecho que es un tramo resalta el rango entero', () {
    const quote = 'La guerra duró de 1914 a 1918 y cambió Europa.';

    expect(marked(quote, year(1914), end: year(1918)), 'de 1914 a 1918');
  });

  test('un rango gana a la fecha suelta que lo empieza', () {
    const quote = 'En 1914 empezó; duró de 1914 a 1918.';

    // Un hecho con fin: el rango, no el «1914» de más adelante en la cita.
    expect(marked(quote, year(1914), end: year(1918)), 'de 1914 a 1918');
    // Sin fin: la fecha suelta.
    expect(marked(quote, year(1914)), '1914');
  });

  test('si el hecho tiene fin y la cita solo trae el comienzo, resalta el '
      'comienzo', () {
    expect(marked('Empezó en 1914.', year(1914), end: year(1918)), '1914');
  });

  test('un hecho sin fin no resalta un rango que solo lo empieza', () {
    expect(marked('Duró de 1914 a 1918.', year(1914)), 'de 1914 a 1918');
    expect(locateEventDate('Duró de 1914 a 1918.', date: year(1915)), isNull);
  });

  test('el «circa» no cuenta: «hacia 1500» y 1500 son la misma fecha', () {
    expect(marked('Fue hacia 1500, más o menos.', year(1500)), 'hacia 1500');
    expect(
      marked('Fue en 1500, más o menos.', year(1500, circa: true)),
      '1500',
    );
  });

  test('no mezcla la era: 44 a.C. no es 44 d.C.', () {
    const quote = 'En 44 a.C. murió César.';

    expect(marked(quote, year(44, bce: true)), '44 a.C.');
    expect(locateEventDate(quote, date: year(44)), isNull);
  });

  test('con dos rangos que empiezan igual, el que termina igual', () {
    const quote = 'Duró de 1914 a 1920 en un lado y de 1914 a 1918 en otro.';

    expect(marked(quote, year(1914), end: year(1918)), 'de 1914 a 1918');
    expect(marked(quote, year(1914), end: year(1920)), 'de 1914 a 1920');
  });

  test('si ninguna coincide en el fin, la primera que coincide en el '
      'comienzo', () {
    const quote = 'En 1914 empezó y otra vez en 1914 terminó.';
    final found = locateEventDate(quote, date: year(1914), end: year(1918));

    expect(found?.start, quote.indexOf('1914'));
  });

  test('otro día del mismo mes no es el mismo día', () {
    const quote = 'Cayó el 13 de febrero de 1809.';
    const date = HistoricalDate(
      year: 1809,
      precision: DatePrecision.day,
      month: 2,
      day: 12,
    );

    expect(locateEventDate(quote, date: date), isNull);
    expect(
      locateEventDate('Cayó el 12 de febrero de 1809.', date: date),
      isNotNull,
    );
  });

  test('si la cita no escribe la fecha, no resalta nada', () {
    expect(locateEventDate('Sin fechas.', date: year(1859)), isNull);
    expect(locateEventDate('Nació en 1809.', date: year(1859)), isNull);
  });

  test('la misma fecha con otra precisión no es la misma', () {
    const quote = 'Fue en el siglo XIX.';
    const century = HistoricalDate(
      year: 1801,
      precision: DatePrecision.century,
    );

    expect(marked(quote, century), 'siglo XIX');
    expect(locateEventDate(quote, date: year(1801)), isNull);
  });

  test('un mes no es otro mes del mismo año', () {
    const quote = 'Fue en febrero de 1809.';

    expect(
      locateEventDate(
        quote,
        date: const HistoricalDate(
          year: 1809,
          precision: DatePrecision.month,
          month: 3,
        ),
      ),
      isNull,
    );
    expect(
      marked(
        quote,
        const HistoricalDate(
          year: 1809,
          precision: DatePrecision.month,
          month: 2,
        ),
      ),
      'febrero de 1809',
    );
  });
}
