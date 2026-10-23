import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/domain/entities/pdf_mark.dart';

/// Escribe resaltados de verdad en un PDF (F38): las anotaciones del estándar
/// —`Highlight` y `Underline`—, que cualquier lector de PDF muestra y deja
/// borrar, sin tocar el texto ni dibujar una copia de las páginas
/// (decisión B del plan).
///
/// Se guarda **agregando** al final del archivo (guardado incremental): lo
/// que había queda byte por byte y lo nuevo va después, así que es el mismo
/// PDF —con su firma, si tenía— más los resaltados.
///
/// `pdfrx_engine` no envuelve las anotaciones, así que se llama a PDFium
/// directo, con el documento que abrió `pdfrx`. Se hace **en el hilo de
/// PDFium de `pdfrx`** ([PdfrxEntryFunctions.compute]), como hace `pdfrx` por
/// dentro: ahí registró sus funciones para buscar las fuentes, y PDFium las
/// llama al armar cómo se ve un resaltado; desde otro hilo, el proceso se
/// cae.
class PdfMarkWriter {
  const PdfMarkWriter();

  /// El PDF [pdf] con [marks] agregados.
  Future<Uint8List> write(Uint8List pdf, List<PdfMark> marks) async {
    final document = await PdfDocument.openData(pdf);
    try {
      // Antes de mandarlo al otro hilo, que devuelve los errores envueltos.
      for (final mark in marks) {
        if (mark.pageNumber < 1 || mark.pageNumber > document.pages.length) {
          throw ArgumentError.value(
            mark.pageNumber,
            'pageNumber',
            'no está en el PDF',
          );
        }
      }
      final handle = await document.useNativeDocumentHandle((handle) => handle);
      await PdfrxEntryFunctions.instance.compute(_annotate, (
        document: handle,
        marks: marks,
      ));
      return await document.encodePdf(incremental: true);
    } finally {
      await document.dispose();
    }
  }
}

/// La misma biblioteca que carga `pdfrx_engine`, desde el mismo lugar.
final _pdfium = pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);

/// Corre en el hilo de PDFium de `pdfrx`, con lo que se le manda copiado.
void _annotate(({int document, List<PdfMark> marks}) message) {
  final marks = message.marks;
  final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(message.document);
  final byPage = <int, List<PdfMark>>{};
  for (final mark in marks) {
    if (mark.lines.isEmpty) continue;
    (byPage[mark.pageNumber] ??= []).add(mark);
  }

  for (final MapEntry(key: pageNumber, value: pageMarks) in byPage.entries) {
    final page = _pdfium.FPDF_LoadPage(document, pageNumber - 1);
    if (page == nullptr) {
      throw StateError('PDFium no pudo abrir la página $pageNumber');
    }
    try {
      for (final mark in pageMarks) {
        _addMark(page, mark);
      }
      _generateAppearances(page);
    } finally {
      _pdfium.FPDF_ClosePage(page);
    }
  }
}

/// Que el archivo lleve también cómo se ve cada resaltado de [page] —su
/// «apariencia», el dibujo ya armado—, y no solo dónde va y de qué color.
///
/// Desde PDF 2.0 la apariencia es obligatoria, y un lector que no sabe
/// dibujarla a partir de los cuadriláteros no muestra el resaltado sin ella.
/// PDFium la genera —con el modo de mezcla que deja ver las letras debajo—
/// la primera vez que pinta una anotación que no la tiene, y la deja en el
/// documento. No tiene otra función pública para pedirlo, así que se pinta la
/// página en un bitmap de un píxel, con las anotaciones.
void _generateAppearances(pdfium_bindings.FPDF_PAGE page) {
  final bitmap = _pdfium.FPDFBitmap_Create(1, 1, 0);
  if (bitmap == nullptr) {
    throw StateError('PDFium no pudo armar la apariencia de los resaltados');
  }
  try {
    _pdfium.FPDF_RenderPageBitmap(
      bitmap,
      page,
      0,
      0,
      1,
      1,
      0,
      pdfium_bindings.FPDF_ANNOT,
    );
  } finally {
    _pdfium.FPDFBitmap_Destroy(bitmap);
  }
}

void _addMark(pdfium_bindings.FPDF_PAGE page, PdfMark mark) {
  final annot = _pdfium.FPDFPage_CreateAnnot(page, switch (mark.style) {
    HighlightStyle.fill => pdfium_bindings.FPDF_ANNOT_HIGHLIGHT,
    HighlightStyle.underline => pdfium_bindings.FPDF_ANNOT_UNDERLINE,
  });
  if (annot == nullptr) {
    throw StateError('PDFium no pudo crear el resaltado');
  }
  try {
    using((arena) {
      final color = mark.color;
      _pdfium.FPDFAnnot_SetColor(
        annot,
        pdfium_bindings.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
        (color >> 16) & 0xff,
        (color >> 8) & 0xff,
        color & 0xff,
        (color >> 24) & 0xff,
      );

      // Un cuadrilátero por renglón, en el orden del estándar: arriba a la
      // izquierda, arriba a la derecha, abajo a la izquierda, abajo a la
      // derecha. Es lo que el lector pinta, y el subrayado va por su borde de
      // abajo.
      final quad = arena<pdfium_bindings.FS_QUADPOINTSF>();
      for (final line in mark.lines) {
        quad.ref
          ..x1 = line.left
          ..y1 = line.top
          ..x2 = line.right
          ..y2 = line.top
          ..x3 = line.left
          ..y3 = line.bottom
          ..x4 = line.right
          ..y4 = line.bottom;
        _pdfium.FPDFAnnot_AppendAttachmentPoints(annot, quad);
      }

      final bounds = mark.lines.reduce((a, b) => a.merge(b));
      final rect = arena<pdfium_bindings.FS_RECTF>();
      rect.ref
        ..left = bounds.left
        ..top = bounds.top
        ..right = bounds.right
        ..bottom = bounds.bottom;
      _pdfium
        ..FPDFAnnot_SetRect(annot, rect)
        // Que salga también al imprimir: sin esta marca, un lector lo
        // muestra en pantalla pero no en el papel.
        ..FPDFAnnot_SetFlags(annot, pdfium_bindings.FPDF_ANNOT_FLAG_PRINT);

      final note = mark.note;
      if (note != null && note.isNotEmpty) {
        _pdfium.FPDFAnnot_SetStringValue(
          annot,
          'Contents'.toNativeUtf8(allocator: arena).cast(),
          _wide(note, arena),
        );
      }
    });
  } finally {
    _pdfium.FPDFPage_CloseAnnot(annot);
  }
}

/// [text] en UTF-16LE terminado en cero, como pide PDFium.
Pointer<UnsignedShort> _wide(String text, Allocator allocator) {
  final units = text.codeUnits;
  final pointer = allocator<Uint16>(units.length + 1);
  pointer.asTypedList(units.length + 1)
    ..setAll(0, units)
    ..[units.length] = 0;
  return pointer.cast();
}
