import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/services/source_quote_locator.dart';

/// La cita de un borrador de tarjeta la escribió un modelo de lenguaje: solo
/// se toma como el lugar de la fuente si está TEXTUAL. Un rango inventado
/// llevaría a un fragmento que no dice lo que la tarjeta.
void main() {
  const content =
      'Primer párrafo de la fuente.\n\n'
      'Rómulo fundó la ciudad en el 753 a. C., según la tradición.\n\n'
      'Último párrafo.';

  test('una frase que está textual devuelve su rango exacto', () {
    const quote = 'Rómulo fundó la ciudad en el 753 a. C.';

    final range = locateQuote(content, quote)!;

    expect(content.substring(range.start, range.end), quote);
    expect(range.start, content.indexOf(quote));
    expect(range.end - range.start, quote.length);
  });

  test('una frase que no está, aunque se parezca, no devuelve nada', () {
    // Una palabra distinta, la puntuación cambiada, un resumen: todo eso es lo
    // que un modelo chico hace, y ninguno es un lugar de la fuente.
    expect(
      locateQuote(content, 'Rómulo fundó la urbe en el 753 a. C.'),
      isNull,
    );
    expect(
      locateQuote(content, 'Rómulo fundó la ciudad en el 753 a C'),
      isNull,
    );
    expect(locateQuote(content, 'Roma fue fundada por Rómulo'), isNull);
  });

  test('no distingue nada que el modelo no haya escrito: mayúsculas y acentos '
      'cuentan', () {
    expect(locateQuote(content, 'rómulo fundó la ciudad'), isNull);
    expect(locateQuote(content, 'Romulo fundó la ciudad'), isNull);
  });

  test('tolera los espacios de los bordes', () {
    final range = locateQuote(content, '  Último párrafo.  ')!;

    expect(content.substring(range.start, range.end), 'Último párrafo.');
  });

  test('tolera un par de comillas que envuelve la frase entera', () {
    for (final quote in [
      '"Último párrafo."',
      '“Último párrafo.”',
      '«Último párrafo.»',
      "'Último párrafo.'",
    ]) {
      final range = locateQuote(content, quote)!;
      expect(content.substring(range.start, range.end), 'Último párrafo.');
    }
  });

  test('unas comillas que no abren y cierran de a pares no se sacan', () {
    expect(locateQuote(content, '«Último párrafo.'), isNull);
    expect(locateQuote(content, 'Último párrafo.»'), isNull);
  });

  test('una frase que aparece dos veces devuelve la primera', () {
    final range = locateQuote('uno dos uno dos', 'uno')!;

    expect(range, (start: 0, end: 3));
  });

  test('sin cita, o vacía, no devuelve nada', () {
    expect(locateQuote(content, null), isNull);
    expect(locateQuote(content, ''), isNull);
    expect(locateQuote(content, '   '), isNull);
    expect(locateQuote(content, '""'), isNull);
  });

  test('sin contenido no encuentra nada', () {
    expect(locateQuote('', 'algo'), isNull);
  });

  test('el rango es sobre el contenido tal cual llega, con sus saltos de '
      'línea', () {
    const text = 'línea uno\nlínea dos\nlínea tres';

    final range = locateQuote(text, 'línea dos')!;

    expect(range, (start: 10, end: 19));
    expect(text.substring(range.start, range.end), 'línea dos');
  });
}
