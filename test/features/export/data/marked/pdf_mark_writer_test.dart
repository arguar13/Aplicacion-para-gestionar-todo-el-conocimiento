import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/pdf_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/pdf_mark.dart';

import '../../../../support/sample_files.dart';

/// Dónde está la librería nativa de PDFium — ver `pdf_parser_test.dart`, que
/// tiene el mismo requisito por el mismo motivo.
final _pdfiumPath = Platform.environment['PDFIUM_PATH'];

const _missingPdfium =
    r'Falta PDFIUM_PATH. Correr: export PDFIUM_PATH="$(tool/fetch_pdfium.sh)"';

/// Turquesa y amarillo claro: colores que no se confunden con el blanco del
/// papel ni con el negro de las letras al buscarlos en la página pintada.
const _turquoise = 0xFF4DD0E1;
const _lightYellow = 0xFFFFF59D;

/// Un resaltado tal como quedó escrito en el PDF, leído con PDFium.
typedef _Written = ({
  int subtype,
  int appearance,
  List<PdfRect> quads,
  String note,
  int flags,
});

/// Las anotaciones de cada página de [pdf], en orden.
Future<List<List<_Written>>> _readMarks(Uint8List pdf) async {
  final document = await PdfDocument.openData(pdf);
  try {
    return await document.useNativeDocumentHandle(
      (handle) => using((arena) {
        final pdfium = pdfium_bindings.getPdfium(modulePath: _pdfiumPath);
        final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle);
        final pages = <List<_Written>>[];
        for (var i = 0; i < pdfium.FPDF_GetPageCount(doc); i++) {
          final page = pdfium.FPDF_LoadPage(doc, i);
          final marks = <_Written>[];
          for (var a = 0; a < pdfium.FPDFPage_GetAnnotCount(page); a++) {
            final annot = pdfium.FPDFPage_GetAnnot(page, a);

            final quads = <PdfRect>[];
            final quad = arena<pdfium_bindings.FS_QUADPOINTSF>();
            final quadCount = pdfium.FPDFAnnot_CountAttachmentPoints(annot);
            for (var q = 0; q < quadCount; q++) {
              pdfium.FPDFAnnot_GetAttachmentPoints(annot, q, quad);
              quads.add(
                PdfRect(quad.ref.x1, quad.ref.y1, quad.ref.x4, quad.ref.y4),
              );
            }

            final key = 'Contents'.toNativeUtf8(allocator: arena).cast<Char>();
            final bytes = pdfium.FPDFAnnot_GetStringValue(
              annot,
              key,
              nullptr,
              0,
            );
            final buffer = arena<Uint16>(bytes ~/ 2 + 1);
            pdfium.FPDFAnnot_GetStringValue(annot, key, buffer.cast(), bytes);
            final note = String.fromCharCodes(
              buffer.asTypedList(bytes ~/ 2).takeWhile((unit) => unit != 0),
            );

            marks.add((
              subtype: pdfium.FPDFAnnot_GetSubtype(annot),
              // El largo, en bytes, de lo que dibuja: 2 —el cero del final—
              // o menos es que no tiene apariencia.
              appearance: pdfium.FPDFAnnot_GetAP(
                annot,
                pdfium_bindings.FPDF_ANNOT_APPEARANCEMODE_NORMAL,
                nullptr,
                0,
              ),
              quads: quads,
              note: note,
              flags: pdfium.FPDFAnnot_GetFlags(annot),
            ));
            pdfium.FPDFPage_CloseAnnot(annot);
          }
          pdfium.FPDF_ClosePage(page);
          pages.add(marks);
        }
        return pages;
      }),
    );
  } finally {
    await document.dispose();
  }
}

/// Dónde están las letras [start]…[end] de la página 1 de [pdf]: lo mismo
/// que va a usar la app para ubicar lo que se resalta.
Future<PdfRect> _lettersRect(
  Uint8List pdf, {
  required int start,
  required int end,
}) async {
  final document = await PdfDocument.openData(pdf);
  try {
    final text = await document.pages.first.loadText();
    return text!.charRects.sublist(start, end).reduce((a, b) => a.merge(b));
  } finally {
    await document.dispose();
  }
}

/// Cuántos píxeles de [rect] son de [color] —con [tolerance] de margen en
/// cada canal, por el redondeo— al pintar la página [pageNumber] de [pdf]
/// como la pinta el visor, a un píxel por punto.
///
/// Sobre el papel blanco, el resaltado pinta su color tal cual: el modo de
/// mezcla que deja ver las letras multiplica, y el blanco no cambia nada.
Future<int> _pixelsOf(
  Uint8List pdf,
  PdfRect rect,
  int color, {
  int pageNumber = 1,
  int tolerance = 3,
}) async {
  final document = await PdfDocument.openData(pdf);
  try {
    final page = document.pages[pageNumber - 1];
    final image = await page.render(
      fullWidth: page.width,
      fullHeight: page.height,
      backgroundColor: 0xFFFFFFFF,
    );
    try {
      final pixels = image!.pixels;
      bool near(int value, int channel) => (value - channel).abs() <= tolerance;
      var count = 0;
      for (var y = page.height - rect.top; y < page.height - rect.bottom; y++) {
        for (var x = rect.left; x < rect.right; x++) {
          final at = (y.floor() * image.width + x.floor()) * 4;
          // BGRA.
          if (near(pixels[at], color & 0xff) &&
              near(pixels[at + 1], (color >> 8) & 0xff) &&
              near(pixels[at + 2], (color >> 16) & 0xff)) {
            count++;
          }
        }
      }
      return count;
    } finally {
      image?.dispose();
    }
  } finally {
    await document.dispose();
  }
}

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
    skip: _pdfiumPath == null ? _missingPdfium : null,
  );
}

void _tests() {
  const writer = PdfMarkWriter();

  setUpAll(() async {
    Pdfrx.pdfiumModulePath = _pdfiumPath;
    await pdfrxInitialize();
  });

  group('un resaltado sobre las letras', () {
    test('queda como una anotación de resaltado del estándar, con su '
        'renglón, su nota, su apariencia y la marca de imprimir', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      final mundo = await _lettersRect(pdf, start: 5, end: 10);

      final marked = await writer.write(pdf, [
        PdfMark(
          pageNumber: 1,
          lines: [mundo],
          color: _turquoise,
          note: 'Acá empieza todo — con acento',
        ),
      ]);

      final [marks] = await _readMarks(marked);
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
      final mundo = await _lettersRect(pdf, start: 5, end: 10);
      const blank = PdfRect(72, 400, 300, 380);

      final marked = await writer.write(pdf, [
        PdfMark(pageNumber: 1, lines: [mundo], color: _turquoise),
      ]);

      expect(await _pixelsOf(pdf, mundo, _turquoise), 0);
      expect(await _pixelsOf(marked, mundo, _turquoise), _mostOf(mundo));
      expect(await _pixelsOf(marked, blank, _turquoise), 0);
    });

    test('el subrayado es una anotación de subrayado, sin nota, y no pinta '
        'el fondo', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      final hola = await _lettersRect(pdf, start: 0, end: 4);

      final marked = await writer.write(pdf, [
        PdfMark(
          pageNumber: 1,
          lines: [hola],
          color: _turquoise,
          style: HighlightStyle.underline,
        ),
      ]);

      final [marks] = await _readMarks(marked);
      expect(marks.single.subtype, pdfium_bindings.FPDF_ANNOT_UNDERLINE);
      expect(marks.single.note, isEmpty);
      expect(marks.single.appearance, greaterThan(2));
      // La línea es fina y de bordes suavizados: casi nunca da el color
      // exacto, así que se le da más margen.
      final underlined = await _pixelsOf(
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

      final [marks] = await _readMarks(marked);
      expect(marks, hasLength(1));
      expect(marks.single.quads, hasLength(2));
      expect(marks.single.quads.last.top, closeTo(690, 0.01));
      expect(marks.single.quads.last.right, closeTo(200, 0.01));
      expect(await _pixelsOf(marked, second, _turquoise), _mostOf(second));
    });
  });

  group('sigue siendo el mismo PDF', () {
    test('lo que había queda byte por byte: el resaltado va agregado al '
        'final', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      final mundo = await _lettersRect(pdf, start: 5, end: 10);

      final marked = await writer.write(pdf, [
        PdfMark(pageNumber: 1, lines: [mundo], color: _turquoise),
      ]);

      expect(marked.length, greaterThan(pdf.length));
      expect(marked.sublist(0, pdf.length), pdf);
    });

    test('el texto sigue siendo texto: se extrae igual que antes', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      final mundo = await _lettersRect(pdf, start: 5, end: 10);

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

    final pages = await _readMarks(marked);
    expect([for (final page in pages) page.length], [1, 0, 2]);
    expect(await _pixelsOf(marked, line, _lightYellow), _mostOf(line));
    expect(await _pixelsOf(marked, line, _turquoise), 0);
    expect(
      await _pixelsOf(marked, line, _turquoise, pageNumber: 3),
      _mostOf(line),
    );
  });

  test('con un resaltado sin renglones, el PDF sale sin anotaciones', () async {
    final pdf = buildPdf(pageTexts: ['Hola mundo']);

    final marked = await writer.write(pdf, [
      const PdfMark(pageNumber: 1, lines: [], color: _turquoise),
    ]);

    final [marks] = await _readMarks(marked);
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
