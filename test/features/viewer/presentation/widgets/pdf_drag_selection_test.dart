import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_drag_selection.dart';

void main() {
  // Dos renglones de una página: "hola mundo" arriba y "chau" abajo, cada
  // letra de 10 puntos de ancho, en coordenadas PDF (y crece hacia arriba).
  PdfPageText page(int number) {
    final rects = <PdfRect>[
      for (var i = 0; i < 10; i++) PdfRect(i * 10.0, 100, i * 10.0 + 10, 90),
      for (var i = 0; i < 4; i++) PdfRect(i * 10.0, 80, i * 10.0 + 10, 70),
    ];
    return PdfPageText(
      pageNumber: number,
      fullText: 'hola mundochau',
      charRects: rects,
      fragments: const [],
    );
  }

  final text = page(1);
  PdfTextSelectionPoint at(int index, [PdfPageText? t]) =>
      PdfTextSelectionPoint(t ?? text, index);

  // "mundo", lo que selecciona mantener apretado.
  final word = PdfTextSelectionRange.fromPoints(at(5), at(9));

  group('arrastrar después de mantener apretado', () {
    test('hacia adelante, la selección va de la palabra hasta el dedo', () {
      final range = extendSelection(word, at(12));

      expect(range.start, at(5));
      expect(range.end, at(12));
    });

    test('hacia atrás, va del dedo hasta el final de la palabra: la '
        'palabra no se pierde', () {
      final range = extendSelection(word, at(1));

      expect(range.start, at(1));
      expect(range.end, at(9));
    });

    test('dentro de la palabra, queda la palabra entera', () {
      final range = extendSelection(word, at(7));

      expect(sameRange(range, word), isTrue);
    });

    test('hasta otra página', () {
      final next = page(2);

      final range = extendSelection(word, at(2, next));

      expect(range.start, at(5));
      expect(range.end.text.pageNumber, 2);
      expect(range.end.index, 2);
    });
  });

  group('la letra bajo el dedo', () {
    test('sobre una letra, esa letra', () {
      expect(nearestCharIndex(text, const PdfPoint(35, 95)), 3);
      expect(nearestCharIndex(text, const PdfPoint(15, 75)), 11);
    });

    test('en el margen derecho, la última del renglón', () {
      expect(nearestCharIndex(text, const PdfPoint(300, 95)), 9);
    });

    test('entre renglones, la más cercana', () {
      expect(nearestCharIndex(text, const PdfPoint(5, 81)), 10);
    });

    test('una página sin texto no da ninguna', () {
      const empty = PdfPageText(
        pageNumber: 1,
        fullText: '',
        charRects: [],
        fragments: [],
      );

      expect(nearestCharIndex(empty, const PdfPoint(5, 5)), isNull);
    });
  });
}
