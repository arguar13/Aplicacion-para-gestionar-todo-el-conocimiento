import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';

void main() {
  const sep = pdfPageSeparator;

  group('dónde cae cada página en el texto, por los separadores', () {
    test('un separador menos que páginas: el tramo N es la página N', () {
      const content = 'uno${sep}dos${sep}tres';

      expect(pdfPageSlicesBySeparator(content, 3), [
        (start: 0, end: 3),
        (start: 10, end: 13),
        (start: 20, end: 24),
      ]);
    });

    test('una página en blanco ocupa su lugar, vacía', () {
      const content = 'A$sep${sep}B';

      expect(pdfPageSlicesBySeparator(content, 3), [
        (start: 0, end: 1),
        (start: 8, end: 8),
        (start: 15, end: 16),
      ]);
    });

    test('si no da la cuenta, no se adivina', () {
      const content = 'uno${sep}dos${sep}tres';

      expect(pdfPageSlicesBySeparator(content, 2), isNull);
      expect(pdfPageSlicesBySeparator(content, 4), isNull);
    });
  });

  group('recorriendo las páginas en orden', () {
    test('una página con un separador adentro queda entera', () {
      const first = 'uno${sep}dos';
      const content = '$first${sep}tres';
      final walker = PdfPageWalker(content);

      expect(pdfPageSlicesBySeparator(content, 2), isNull);
      expect(walker.next(first, last: false), (start: 0, end: first.length));
      expect(walker.next('tres', last: true), (
        start: first.length + sep.length,
        end: content.length,
      ));
    });

    test('una escaneada —el texto lo puso el OCR— va hasta el separador, y '
        'la siguiente sigue en su lugar', () {
      const content = 'uno${sep}texto reconocido${sep}tres';
      final walker = PdfPageWalker(content);

      expect(walker.next('uno', last: false), (start: 0, end: 3));
      expect(walker.next('', last: false), (start: 10, end: 26));
      expect(walker.next('tres', last: true), (start: 33, end: 37));
    });

    test('la última que no coincide llega hasta el final', () {
      const content = 'uno${sep}reconocida';
      final walker = PdfPageWalker(content)..next('uno', last: false);

      expect(walker.next('otra cosa', last: true), (
        start: 10,
        end: content.length,
      ));
    });

    test('la última, aunque su texto propio empiece igual —un sello y '
        'después lo reconocido—, llega hasta el final', () {
      const content = 'uno${sep}dos y lo reconocido';
      final walker = PdfPageWalker(content)..next('uno', last: false);

      expect(walker.next('dos', last: true), (start: 10, end: content.length));
    });

    test('una que coincide pero no la sigue un separador no es exacta', () {
      const content = 'unos${sep}dos';
      final walker = PdfPageWalker(content);

      expect(walker.next('uno', last: false), (start: 0, end: 4));
    });
  });

  // La página 2 de un PDF: «Hola mundo.» arriba y «Chau.» abajo, cada letra de
  // 10 puntos de ancho, en coordenadas PDF (y crece hacia arriba). PDFium
  // separa los renglones con \r\n, y el espacio no tiene lugar en la página.
  const raw = 'Hola mundo.\r\nChau.';
  final rects = <PdfRect>[
    for (var i = 0; i < 11; i++)
      if (i == 4) PdfRect.empty else PdfRect(i * 10.0, 100, i * 10.0 + 10, 90),
    PdfRect.empty,
    PdfRect.empty,
    for (var i = 0; i < 5; i++) PdfRect(i * 10.0, 80, i * 10.0 + 10, 70),
  ];
  const clean = 'Hola mundo.\nChau.';
  const content = 'Portada$sep$clean${sep}Fin';
  const start = 7 + sep.length;
  const slice = (start: start, end: start + clean.length);

  PdfStudyPage page() => PdfStudyPage(
    slice: slice,
    rawText: raw,
    charRects: rects,
    content: content,
  );

  group('lo pintado sobre las letras', () {
    test('un rectángulo por renglón y por color: la palabra clave encima de '
        'su oración', () {
      final boxes = page().boxes([
        (start: start, end: start + clean.length),
        (start: start + 5, end: start + 10),
      ]);

      expect(boxes, [
        (rect: const PdfRect(0, 100, 40, 90), paint: 0),
        (rect: const PdfRect(50, 100, 100, 90), paint: 1),
        (rect: const PdfRect(100, 100, 110, 90), paint: 0),
        (rect: const PdfRect(0, 80, 50, 70), paint: 0),
      ]);
    });

    test('lo que empieza en otra página se recorta a esta', () {
      final boxes = page().boxes([(start: 0, end: start + 4)]);

      expect(boxes, [(rect: const PdfRect(0, 100, 40, 90), paint: 0)]);
    });

    test('lo que no toca la página no pinta nada', () {
      expect(page().boxes([(start: 0, end: 7)]), isEmpty);
    });

    test('el salto de renglón no estira el rectángulo aunque PDFium le dé '
        'un lugar al final del renglón', () {
      const text = 'ab\r\ncd';
      final studied = PdfStudyPage(
        slice: (start: 0, end: 5),
        rawText: text,
        charRects: const [
          PdfRect(0, 100, 10, 90),
          PdfRect(10, 100, 20, 90),
          PdfRect(20, 100, 22, 90),
          PdfRect(22, 100, 24, 90),
          PdfRect(0, 80, 10, 70),
          PdfRect(10, 80, 20, 70),
        ],
        content: 'ab\ncd',
      );

      expect(studied.boxes([(start: 0, end: 5)]), [
        (rect: const PdfRect(0, 100, 20, 90), paint: 0),
        (rect: const PdfRect(0, 80, 20, 70), paint: 0),
      ]);
    });

    test('a la misma altura pero lejos —otra columna— va aparte', () {
      const text = 'ab';
      final studied = PdfStudyPage(
        slice: (start: 0, end: 2),
        rawText: text,
        charRects: const [PdfRect(0, 100, 10, 90), PdfRect(300, 100, 310, 90)],
        content: text,
      );

      expect(studied.boxes([(start: 0, end: 2)]), hasLength(2));
    });

    test('un renglón que sigue en el de abajo sin salto va aparte', () {
      const text = 'ab';
      final studied = PdfStudyPage(
        slice: (start: 0, end: 2),
        rawText: text,
        charRects: const [PdfRect(0, 100, 10, 90), PdfRect(10, 80, 20, 70)],
        content: text,
      );

      expect(studied.boxes([(start: 0, end: 2)]), hasLength(2));
    });

    test('lo que vuelve al principio a la misma altura va aparte', () {
      const text = 'abc';
      final studied = PdfStudyPage(
        slice: (start: 0, end: 3),
        rawText: text,
        charRects: const [
          PdfRect(100, 100, 110, 90),
          PdfRect(110, 100, 120, 90),
          PdfRect(0, 100, 10, 90),
        ],
        content: text,
      );

      expect(studied.boxes([(start: 0, end: 3)]), [
        (rect: const PdfRect(100, 100, 120, 90), paint: 0),
        (rect: const PdfRect(0, 100, 10, 90), paint: 0),
      ]);
    });
  });

  group('la letra tocada', () {
    test(r'su posición en el texto extraído, también después de un \r\n', () {
      expect(page().offsetAt(const PdfPoint(55, 95)), start + 5);
      expect(page().offsetAt(const PdfPoint(15, 75)), start + 13);
    });

    test('fuera de las letras, ninguna', () {
      expect(page().offsetAt(const PdfPoint(500, 500)), isNull);
    });
  });

  group('una página escaneada', () {
    final scanned = PdfStudyPage(
      slice: (start: 10, end: 26),
      rawText: '',
      charRects: const [],
      content: 'uno${sep}texto reconocido${sep}tres',
    );

    test('no tiene letras donde pintar ni tocar', () {
      expect(scanned.onLetters, isFalse);
      expect(scanned.boxes([(start: 10, end: 26)]), isEmpty);
      expect(scanned.offsetAt(const PdfPoint(1, 1)), isNull);
    });

    test('tampoco con un sello como texto propio: sus letras no son las del '
        'texto', () {
      final stamped = PdfStudyPage(
        slice: (start: 10, end: 26),
        rawText: 'sello',
        charRects: [
          for (var i = 0; i < 5; i++) PdfRect(i * 10.0, 100, i * 10.0 + 10, 90),
        ],
        content: 'uno${sep}texto reconocido${sep}tres',
      );

      expect(stamped.onLetters, isFalse);
      expect(stamped.boxes([(start: 10, end: 26)]), isEmpty);
      expect(stamped.offsetAt(const PdfPoint(15, 95)), isNull);
    });

    test('sabe si algo resaltado cae en ella, para avisarlo', () {
      expect(scanned.touches([(start: 12, end: 15)]), isTrue);
      expect(scanned.touches([(start: 0, end: 10)]), isFalse);
      expect(scanned.touches([(start: 26, end: 30)]), isFalse);
    });

    test('la de texto propio sí', () {
      expect(page().onLetters, isTrue);
    });
  });
}
