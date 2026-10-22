import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_pagination.dart';

void main() {
  test('contenido vacío no tiene páginas', () {
    expect(splitIntoReaderPages(''), isEmpty);
    expect(splitIntoReaderPages('   \n  '), isEmpty);
  });

  test('un texto corto entra en una sola página', () {
    final pages = splitIntoReaderPages('Un texto cualquiera, bien corto.');

    expect(pages, hasLength(1));
    expect(pages.single, 'Un texto cualquiera, bien corto.');
  });

  test('un PDF con el separador de página de PdfParser corta ahí — página '
      'del libro, página del lector', () {
    const content = 'Página uno.\n\n---\n\nPágina dos.\n\n---\n\nPágina tres.';

    final pages = splitIntoReaderPages(content);

    expect(pages, ['Página uno.', 'Página dos.', 'Página tres.']);
  });

  test('párrafos se van juntando en una página hasta acercarse al límite', () {
    final paragraphs = List.generate(5, (i) => 'Párrafo número $i.');
    final content = paragraphs.join('\n\n');

    final pages = splitIntoReaderPages(content, targetPageLength: 40);

    // Ninguna página se pasa del límite salvo que un párrafo solo ya lo
    // supere (no es el caso acá), y ningún párrafo queda partido.
    for (final page in pages) {
      expect(page.length, lessThanOrEqualTo(40));
    }
    expect(pages.join('\n\n'), content);
  });

  test('un párrafo más largo que el límite se corta él solo, en un espacio, '
      'sin partir palabras', () {
    final longParagraph = List.generate(20, (i) => 'palabra$i').join(' ');

    final pages = splitIntoReaderPages(longParagraph, targetPageLength: 30);

    expect(pages.length, greaterThan(1));
    for (final page in pages) {
      expect(page.length, lessThanOrEqualTo(30));
      // Ninguna página termina a mitad de una palabra: el último
      // carácter de cada tramo cortado es el final de una "palabraN"
      // completa, nunca un dígito seguido de más dígitos del original.
      expect(page.trim(), page);
    }
    // Ninguna palabra se perdió ni se duplicó al unir todo de nuevo.
    expect(pages.join(' '), longParagraph);
  });

  test('una página del PDF que por sí sola es enorme también se subdivide', () {
    final hugePage = List.generate(
      50,
      (i) => 'Oración número $i.',
    ).join('\n\n');
    final content = 'Corta.\n\n---\n\n$hugePage';

    final pages = splitIntoReaderPages(content, targetPageLength: 100);

    expect(pages.first, 'Corta.');
    expect(pages.length, greaterThan(2));
  });

  group('readerPageRanges (F36)', () {
    test('un separador pegado al principio o al final —una página vacía de '
        'un PDF— no deja una página con los guiones', () {
      const content = '\n\n---\n\nPágina dos.\n\n---\n\n';

      expect(splitIntoReaderPages(content), ['Página dos.']);
      expect(readerPageRanges(content).single.start, 7);
    });

    test('cada página es el tramo tal cual del contenido, con su lugar', () {
      const content =
          '  \nPágina uno.\n\n\n\nSigue uno.\n\n---\n\nPágina dos.  \n';

      final ranges = readerPageRanges(content, targetPageLength: 12);

      expect(
        [for (final r in ranges) content.substring(r.start, r.end)],
        ['Página uno.', 'Sigue uno.', 'Página dos.'],
      );
      expect(ranges.first.start, content.indexOf('Página uno.'));
      expect(ranges.last.end, content.indexOf('  \n', ranges.last.start));
    });

    test('las mismas páginas que splitIntoReaderPages, aunque haya varios '
        'renglones en blanco entre párrafos', () {
      final content = [
        for (var i = 0; i < 30; i++) 'Párrafo $i con algo de texto.',
      ].join('\n\n\n');

      final ranges = readerPageRanges(content, targetPageLength: 100);
      final pages = splitIntoReaderPages(content, targetPageLength: 100);

      expect(pages, [
        for (final r in ranges) content.substring(r.start, r.end),
      ]);
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].start, greaterThan(ranges[i - 1].end));
      }
      expect(pages.length, greaterThan(1));
    });

    test('un párrafo cortado a la fuerza deja tramos contiguos sin perder '
        'nada', () {
      final content = List.generate(40, (i) => 'palabra$i').join(' ');

      final ranges = readerPageRanges(content, targetPageLength: 50);

      expect(ranges.first.start, 0);
      expect(ranges.last.end, content.length);
      for (var i = 1; i < ranges.length; i++) {
        expect(content.substring(ranges[i - 1].end, ranges[i].start), ' ');
      }
    });
  });
}
