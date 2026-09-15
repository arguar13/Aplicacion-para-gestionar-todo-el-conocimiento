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
}
