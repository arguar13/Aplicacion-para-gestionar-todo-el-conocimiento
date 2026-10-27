import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_seed.dart';

/// De una selección de un texto a lo que ya se sabe del hecho (F40, paso 5):
/// la cita puesta y, si trae una fecha, la fecha.
void main() {
  const text =
      'Darwin nació en 1809. En 1859 publicó El origen de las especies. '
      'La guerra duró de 1914 a 1918 y cambió Europa.';

  DatedEventSeed seedOf(String quote, {String content = text}) {
    final start = content.indexOf(quote);
    return DatedEventSeed.fromQuote(
      itemId: 'libro',
      renditionId: 'texto',
      content: content,
      start: start,
      end: start + quote.length,
    );
  }

  test('la cita queda puesta tal cual está en el texto, con su posición', () {
    final seed = seedOf('En 1859 publicó El origen de las especies.');

    expect(seed.itemId, 'libro');
    expect(seed.renditionId, 'texto');
    expect(seed.excerpt, 'En 1859 publicó El origen de las especies.');
    expect(seed.startOffset, text.indexOf('En 1859'));
    expect(seed.endOffset, text.indexOf('En 1859') + seed.excerpt!.length);
    expect(seed.hasQuote, isTrue);
  });

  test('si la selección trae una fecha, viene cargada', () {
    final seed = seedOf('En 1859 publicó El origen de las especies.');

    expect(
      seed.date,
      const HistoricalDate(year: 1859, precision: DatePrecision.year),
    );
    expect(seed.end, isNull);
  });

  test('si trae un rango, viene cargado con su fin', () {
    final seed = seedOf('La guerra duró de 1914 a 1918 y cambió Europa.');

    expect(seed.date?.year, 1914);
    expect(seed.end?.year, 1918);
  });

  test('si trae varias fechas, la primera', () {
    final seed = seedOf('Darwin nació en 1809. En 1859 publicó');

    expect(seed.date?.year, 1809);
    expect(seed.end, isNull);
  });

  test('si no trae fecha, queda vacía y la cita sigue puesta', () {
    final seed = seedOf('El origen de las especies');

    expect(seed.date, isNull);
    expect(seed.end, isNull);
    expect(seed.hasQuote, isTrue);
    expect(seed.excerpt, 'El origen de las especies');
  });

  test('una cita corta sirve de título, con los renglones juntos', () {
    const content = 'Primero\n  pasó  esto en 1500.';
    final seed = seedOf(content, content: content);

    expect(seed.title, 'Primero pasó esto en 1500.');
  });

  test(
    'una cita larga deja el título vacío: un renglón cortado no es título',
    () {
      final long = 'a' * (DatedEventSeed.maxSuggestedTitle + 1);
      final seed = seedOf(long, content: 'En 1500 $long');

      expect(seed.title, isEmpty);
    },
  );

  test('una cita justo del largo máximo todavía sirve de título', () {
    final exact = 'b' * DatedEventSeed.maxSuggestedTitle;
    final seed = seedOf(exact, content: 'En 1500 $exact');

    expect(seed.title, exact);
  });

  test('una selección que no cae en el texto no se acepta', () {
    expect(
      () => DatedEventSeed.fromQuote(
        itemId: 'libro',
        renditionId: 'texto',
        content: 'corto',
        start: 2,
        end: 99,
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => DatedEventSeed.fromQuote(
        itemId: 'libro',
        renditionId: 'texto',
        content: 'corto',
        start: 3,
        end: 3,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('sin cita, el elemento sí se puede cambiar', () {
    const seed = DatedEventSeed(itemId: 'libro');

    expect(seed.hasQuote, isFalse);
    expect(seed.title, isEmpty);
    expect(seed.date, isNull);
  });

  test('una cita necesita su texto y su posición', () {
    expect(const DatedEventSeed(renditionId: 'texto').hasQuote, isFalse);
    expect(const DatedEventSeed(startOffset: 3).hasQuote, isFalse);
    expect(
      const DatedEventSeed(renditionId: 'texto', startOffset: 3).hasQuote,
      isTrue,
    );
  });

  test('dos semillas con lo mismo son iguales', () {
    final a = seedOf('En 1859 publicó El origen de las especies.');
    final b = seedOf('En 1859 publicó El origen de las especies.');

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(seedOf('Darwin nació en 1809.')));
  });
}
