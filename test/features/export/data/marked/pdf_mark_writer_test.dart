import 'package:flutter_test/flutter_test.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/pdf_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/pdf_mark.dart';

import '../../../../support/pdf_annotations.dart';
import '../../../../support/sample_files.dart';

/// Turquesa y amarillo claro: colores que no se confunden con el blanco del
/// papel ni con el negro de las letras al buscarlos en la página pintada.
const _turquoise = 0xFF4DD0E1;
const _lightYellow = 0xFFFFF59D;

/// Que los píxeles contados sean buena parte de [rect]: las letras de encima
/// se llevan el resto.
Matcher _mostOf(PdfRect rect) =>
    greaterThan((rect.width * rect.height * 0.3).round());

void main() {
  // Cada prueba pasa por PDFium de verdad: sin la librería no hay nada que
  // probar, y se dice por qué en vez de quedar en verde.
  group(
    'PdfMarkWriter',
    _tests,
    skip: pdfiumPath == null ? missingPdfium : null,
  );
}

void _tests() {
  const writer = PdfMarkWriter();

  setUpAll(() async {
    Pdfrx.pdfiumModulePath = pdfiumPath;
    await pdfrxInitialize();
  });

  group('un resaltado sobre las letras', () {
    test('queda como una anotación de resaltado del estándar, con su '
        'renglón, su nota, su apariencia y la marca de imprimir', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      final mundo = await lettersRect(pdf, start: 5, end: 10);

      final marked = await writer.write(pdf, [
        PdfMark(
          pageNumber: 1,
          lines: [mundo],
          color: _turquoise,
          note: 'Acá empieza todo — con acento',
        ),
      ]);

      final [marks] = await readAnnotations(marked);
      expect(marks, hasLength(1));
      final mark = marks.single;
      expect(mark.subtype, pdfium_bindings.FPDF_ANNOT_HIGHLIGHT);
      expect(mark.note, 'Acá empieza todo — con acento');
      expect(mark.flags & pdfium_bindings.FPDF_ANNOT_FLAG_PRINT, isNot(0));
      // Lleva el dibujo ya armado: un lector que no sabe armarlo desde los
      // cuadriláteros igual lo muestra.
      expect(mark.appearance, greaterThan(2));
      final [quad] = mark.quads;
      expect(quad.left, closeTo(mundo.left, 0.01));
      expect(quad.top, closeTo(mundo.top, 0.01));
      expect(quad.right, closeTo(mundo.right, 0.01));
      expect(quad.bottom, closeTo(mundo.bottom, 0.01));
    });

    test('se ve con su color: al pintar la página, el lugar del resaltado '
        'lo toma y el resto sigue blanco', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      final mundo = await lettersRect(pdf, start: 5, end: 10);
      const blank = PdfRect(72, 400, 300, 380);

      final marked = await writer.write(pdf, [
        PdfMark(pageNumber: 1, lines: [mundo], color: _turquoise),
      ]);

      expect(await pixelsOf(pdf, mundo, _turquoise), 0);
      expect(await pixelsOf(marked, mundo, _turquoise), _mostOf(mundo));
      expect(await pixelsOf(marked, blank, _turquoise), 0);
    });

    test('el subrayado es una anotación de subrayado, sin nota, y no pinta '
        'el fondo', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      final hola = await lettersRect(pdf, start: 0, end: 4);

      final marked = await writer.write(pdf, [
        PdfMark(
          pageNumber: 1,
          lines: [hola],
          color: _turquoise,
          style: HighlightStyle.underline,
        ),
      ]);

      final [marks] = await readAnnotations(marked);
      expect(marks.single.subtype, pdfium_bindings.FPDF_ANNOT_UNDERLINE);
      expect(marks.single.note, isEmpty);
      expect(marks.single.appearance, greaterThan(2));
      // La línea es fina y de bordes suavizados: casi nunca da el color
      // exacto, así que se le da más margen.
      final underlined = await pixelsOf(
        marked,
        hola,
        _turquoise,
        tolerance: 0x30,
      );
      expect(underlined, greaterThan(0));
      expect(underlined, isNot(_mostOf(hola)));
    });

    test('un tramo en dos renglones son dos cuadriláteros de la misma '
        'anotación', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      const first = PdfRect(72, 720, 300, 700);
      const second = PdfRect(72, 690, 200, 670);

      final marked = await writer.write(pdf, [
        const PdfMark(pageNumber: 1, lines: [first, second], color: _turquoise),
      ]);

      final [marks] = await readAnnotations(marked);
      expect(marks, hasLength(1));
      expect(marks.single.quads, hasLength(2));
      expect(marks.single.quads.last.top, closeTo(690, 0.01));
      expect(marks.single.quads.last.right, closeTo(200, 0.01));
      expect(await pixelsOf(marked, second, _turquoise), _mostOf(second));
    });
  });

  group('sigue siendo el mismo PDF', () {
    test('lo que había queda byte por byte: el resaltado va agregado al '
        'final', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      final mundo = await lettersRect(pdf, start: 5, end: 10);

      final marked = await writer.write(pdf, [
        PdfMark(pageNumber: 1, lines: [mundo], color: _turquoise),
      ]);

      expect(marked.length, greaterThan(pdf.length));
      expect(marked.sublist(0, pdf.length), pdf);
    });

    test('el texto sigue siendo texto: se extrae igual que antes', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      final mundo = await lettersRect(pdf, start: 5, end: 10);

      final marked = await writer.write(pdf, [
        PdfMark(pageNumber: 1, lines: [mundo], color: _turquoise),
      ]);

      final document = await PdfDocument.openData(marked);
      try {
        final text = await document.pages.first.loadText();
        expect(text!.fullText.trim(), 'Hola mundo');
      } finally {
        await document.dispose();
      }
    });
  });

  test('varias páginas: cada una se lleva lo suyo, con su color', () async {
    final pdf = buildPdf(pageTexts: ['Uno', 'Dos', 'Tres']);
    const line = PdfRect(72, 720, 200, 700);

    final marked = await writer.write(pdf, [
      const PdfMark(pageNumber: 3, lines: [line], color: _turquoise),
      const PdfMark(pageNumber: 1, lines: [line], color: _lightYellow),
      const PdfMark(
        pageNumber: 3,
        lines: [line],
        color: _turquoise,
        style: HighlightStyle.underline,
      ),
    ]);

    final pages = await readAnnotations(marked);
    expect([for (final page in pages) page.length], [1, 0, 2]);
    expect(await pixelsOf(marked, line, _lightYellow), _mostOf(line));
    expect(await pixelsOf(marked, line, _turquoise), 0);
    expect(
      await pixelsOf(marked, line, _turquoise, pageNumber: 3),
      _mostOf(line),
    );
  });

  test('con un resaltado sin renglones, el PDF sale sin anotaciones', () async {
    final pdf = buildPdf(pageTexts: ['Hola mundo']);

    final marked = await writer.write(pdf, [
      const PdfMark(pageNumber: 1, lines: [], color: _turquoise),
    ]);

    final [marks] = await readAnnotations(marked);
    expect(marks, isEmpty);
  });

  test('una página que el PDF no tiene es un error, no se ignora', () async {
    final pdf = buildPdf(pageTexts: ['Hola mundo']);

    await expectLater(
      writer.write(pdf, [
        const PdfMark(
          pageNumber: 2,
          lines: [PdfRect(72, 720, 200, 700)],
          color: _turquoise,
        ),
      ]),
      throwsArgumentError,
    );
  });
}
