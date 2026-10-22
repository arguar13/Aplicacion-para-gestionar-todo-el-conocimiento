import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';

void main() {
  group('de cada letra del texto limpio, la del texto de la página', () {
    test(r'sin \r, cada una es la misma', () {
      expect(pdfCleanToRawIndices('ab\ncd'), [0, 1, 2, 3, 4]);
    });

    test(r'un \r\n es un solo salto: el del \n', () {
      const raw = 'ab\r\ncd\r\ne';
      final indices = pdfCleanToRawIndices(raw);
      final clean = cleanPdfPageText(raw);

      expect(indices, [0, 1, 3, 4, 5, 7, 8]);
      expect(indices, hasLength(clean.length));
      for (var i = 0; i < clean.length; i++) {
        final unit = raw[indices[i]];
        expect(unit == '\r' ? '\n' : unit, clean[i], reason: 'letra $i');
      }
    });

    test(r'un \r solo queda, ya convertido en salto', () {
      expect(pdfCleanToRawIndices('a\rb'), [0, 1, 2]);
    });

    test('una página de solo espacios no tiene letras', () {
      expect(pdfCleanToRawIndices('  \r\n '), isEmpty);
    });
  });
}
