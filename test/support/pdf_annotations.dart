import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Para probar lo que se escribe en un PDF (F38): leerlo de vuelta con PDFium
/// y pintar la página como la pinta el visor.
///
/// Cada prueba pasa por PDFium de verdad, así que necesita su librería nativa
/// — ver `pdf_parser_test.dart`, que tiene el mismo requisito por el mismo
/// motivo.

/// Dónde está la librería nativa de PDFium.
final pdfiumPath = Platform.environment['PDFIUM_PATH'];

const missingPdfium =
    r'Falta PDFIUM_PATH. Correr: export PDFIUM_PATH="$(tool/fetch_pdfium.sh)"';

/// Una anotación tal como quedó escrita en el PDF, leída con PDFium.
typedef WrittenAnnotation = ({
  int subtype,
  int appearance,
  List<PdfRect> quads,
  String note,
  int flags,
});

/// Las anotaciones de cada página de [pdf], en orden.
Future<List<List<WrittenAnnotation>>> readAnnotations(Uint8List pdf) async {
  final document = await PdfDocument.openData(pdf);
  try {
    return await document.useNativeDocumentHandle(
      (handle) => using((arena) {
        final pdfium = pdfium_bindings.getPdfium(modulePath: pdfiumPath);
        final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle);
        final pages = <List<WrittenAnnotation>>[];
        for (var i = 0; i < pdfium.FPDF_GetPageCount(doc); i++) {
          final page = pdfium.FPDF_LoadPage(doc, i);
          final marks = <WrittenAnnotation>[];
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

/// Dónde están las letras [start]…[end] de la página [pageNumber] de [pdf]:
/// lo mismo que usa la app para ubicar lo que se resalta.
Future<PdfRect> lettersRect(
  Uint8List pdf, {
  required int start,
  required int end,
  int pageNumber = 1,
}) async {
  final document = await PdfDocument.openData(pdf);
  try {
    final text = await document.pages[pageNumber - 1].loadText();
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
Future<int> pixelsOf(
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
