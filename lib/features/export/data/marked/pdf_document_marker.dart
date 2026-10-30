import 'dart:math';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/pdf_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';
import 'package:sinapsis/features/export/domain/entities/pdf_mark.dart';
import 'package:sinapsis/features/export/domain/services/scanned_page_lines.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';

/// Le pone a un PDF los tramos que se marcan en el documento que se
/// descarga (F38, paso 5): lo que el resumen, la síntesis o las palabras
/// clave marcaron, y los resaltados de la persona.
///
/// Los tramos vienen en posiciones del **texto extraído** —las páginas unidas
/// por un separador, ver `PdfParser`—. Cada uno se lleva a su página y a las
/// letras de ahí con la misma lógica con que el visor los pinta sobre el PDF
/// real (F36: `PdfStudyPage`, `PdfPageWalker`), y lo que sale son
/// anotaciones de verdad, de las que escribe [PdfMarkWriter]: un
/// rectángulo por renglón, el color, el estilo y la nota.
///
/// - Un tramo que cruza páginas da una anotación por página.
/// - Dos tramos que se pisan —una palabra clave dentro de su oración— salen
///   los dos enteros, cada uno con todos sus renglones: la anotación puede
///   estar encima de otra, y el lector las mezcla. Al pintarlos en la
///   pantalla uno tapa al otro; acá no hace falta.
/// - Una página **escaneada** no tiene letras donde ubicar nada (el OCR
///   guarda el texto, no dónde está), así que su marca es un recuadro de
///   color en el lugar aproximado del renglón (decisión D): ver
///   [scannedPageLines].
/// - Un tramo que no está en el texto, o que ya no cae en el PDF, se
///   saltea: el resto se marca igual.
/// - Una **nota en el texto** (F45, mejora 19) es una nota del PDF, de las
///   que se abren con un toque en cualquier lector: su ícono, del color de la
///   nota, va en el margen derecho de la página, a la altura del primer
///   renglón del pedazo —como en la app—, y el pedazo queda subrayado de ese
///   color. Se ubica como un tramo.
class PdfDocumentMarker {
  const PdfDocumentMarker({this.writer = const PdfMarkWriter()});

  final PdfMarkWriter writer;

  /// El PDF [pdf] con [marks] marcados y [notes] puestas. [content] es su
  /// texto extraído, el de las posiciones de los dos.
  ///
  /// Si no queda nada que marcar, devuelve [pdf] tal cual.
  Future<Uint8List> mark(
    Uint8List pdf, {
    required String content,
    required List<DocumentMark> marks,
    List<DocumentNote> notes = const [],
  }) async {
    final located = <_Located>[];
    for (final mark in marks) {
      final range = _locate(content, mark);
      if (range != null) located.add((range: range, mark: mark, note: null));
    }
    for (final note in notes) {
      // El pedazo de una nota, subrayado de su color; lo que dice va en su
      // ícono, no en el subrayado.
      final mark = DocumentMark(
        start: note.start,
        end: note.end,
        excerpt: note.excerpt,
        color: note.color,
        style: HighlightStyle.underline,
      );
      final range = _locate(content, mark);
      if (range != null) {
        located.add((range: range, mark: mark, note: note.note));
      }
    }
    if (located.isEmpty) return pdf;

    final pdfMarks = await _pdfMarks(pdf, content, located);
    if (pdfMarks.isEmpty) return pdf;
    return writer.write(pdf, pdfMarks);
  }

  Future<List<PdfMark>> _pdfMarks(
    Uint8List pdf,
    String content,
    List<_Located> located,
  ) async {
    final document = await PdfDocument.openData(pdf);
    try {
      final pages = document.pages;

      final placed = await _place(pages, content, located);
      final slices = placed.slices;
      final studied = placed.studied;

      final result = <PdfMark>[];
      for (final (:range, :mark, :note) in located) {
        // El ícono de una nota va una sola vez: en la página donde empieza.
        var iconPlaced = false;
        for (var i = 0; i < slices.length; i++) {
          final slice = slices[i];
          if (range.end <= slice.start || range.start >= slice.end) continue;
          final page = studied[i];
          if (page == null) continue;

          final lines = page.onLetters
              // Cada tramo con su llamada: juntos, uno tapa al otro donde se
              // pisan, y acá cada anotación tiene que estar entera.
              ? [
                  for (final box in page.boxes([range])) box.rect,
                ]
              : scannedPageLines(
                  pageText: content.substring(slice.start, slice.end),
                  from: max(range.start, slice.start) - slice.start,
                  to: min(range.end, slice.end) - slice.start,
                  width: pages[i].width,
                  height: pages[i].height,
                  rotation: pages[i].rotation,
                );
          if (lines.isEmpty) continue;
          final icon = note != null && !iconPlaced
              ? _noteIcon(pages[i], lines.first)
              : null;
          iconPlaced = iconPlaced || icon != null;
          result.add(
            PdfMark(
              pageNumber: i + 1,
              lines: lines,
              color: mark.color,
              style: mark.style,
              note: note ?? mark.note,
              noteIcon: icon,
            ),
          );
        }
      }
      return result;
    } finally {
      // Sin esto se filtra memoria nativa, que el recolector de Dart no ve.
      await document.dispose();
    }
  }

  /// Dónde cae cada página en el texto, y las que se van a marcar ubicadas
  /// en su tramo.
  ///
  /// Primero, el reparto barato por los separadores: con uno menos que
  /// páginas, el tramo N es la página N. Si no da la cuenta —el texto
  /// reconocido de una foto trae un `---` entre renglones en blanco, o un
  /// texto que se cambió— se recorren las páginas en orden, que es exacto
  /// (`PdfPageWalker`).
  Future<({List<TextSlice> slices, Map<int, PdfStudyPage> studied})> _place(
    List<PdfPage> pages,
    String content,
    List<_Located> located,
  ) async {
    final slices =
        pdfPageSlicesBySeparator(content, pages.length) ??
        await _walk(pages, content);
    return (
      slices: slices,
      studied: await _study(pages, content, slices, _touched(slices, located)),
    );
  }

  /// Las páginas de [slices] que alguno de [located] toca.
  Set<int> _touched(List<TextSlice> slices, List<_Located> located) => {
    for (var i = 0; i < slices.length; i++)
      if (located.any(
        (l) => l.range.end > slices[i].start && l.range.start < slices[i].end,
      ))
        i,
  };

  /// Las páginas [wanted] ubicadas en su tramo.
  Future<Map<int, PdfStudyPage>> _study(
    List<PdfPage> pages,
    String content,
    List<TextSlice> slices,
    Set<int> wanted,
  ) async {
    final studied = <int, PdfStudyPage>{};
    for (final i in wanted) {
      final raw = await _loadText(pages[i]);
      studied[i] = PdfStudyPage(
        slice: slices[i],
        rawText: raw?.fullText ?? '',
        charRects: raw?.charRects ?? const [],
        content: content,
      );
    }
    return studied;
  }

  /// Dónde cae cada página en [content], leyéndolas en orden. Solo se
  /// guarda el tramo de cada una: sus letras se vuelven a leer cuando se
  /// necesitan, para no tener un libro entero de rectángulos en memoria.
  Future<List<TextSlice>> _walk(List<PdfPage> pages, String content) async {
    final walker = PdfPageWalker(content);
    final slices = <TextSlice>[];
    for (var i = 0; i < pages.length; i++) {
      final raw = await _loadText(pages[i]);
      slices.add(
        walker.next(
          cleanPdfPageText(raw?.fullText ?? ''),
          last: i == pages.length - 1,
        ),
      );
    }
    return slices;
  }

  /// El texto de [page] con dónde está cada letra, o `null` si no se pudo
  /// leer: esa página se trata como si no tuviera letras.
  Future<PdfPageRawText?> _loadText(PdfPage page) async {
    try {
      return await page.loadText();
      // PDFium no tiene un tipo propio para sus fallas: una página que no se
      // lee no tira abajo el resto del documento.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }
}

/// Un tramo ubicado en el texto; con `note`, el pedazo de una nota en el
/// texto y lo que dice.
typedef _Located = ({TextSlice range, DocumentMark mark, String? note});

/// El lado del ícono de una nota del PDF, en puntos: el de la nota de Adobe.
const _noteIconSize = 20.0;

/// Dónde va el ícono de una nota cuyo pedazo empieza en el renglón [line] de
/// [page]: en el margen derecho, a la altura del renglón, sin salirse de la
/// página. En las coordenadas del PDF —sin girar, con la `y` hacia arriba—,
/// las mismas de los renglones.
PdfRect _noteIcon(PdfPage page, PdfRect line) {
  final quarter =
      page.rotation == PdfPageRotation.clockwise90 ||
      page.rotation == PdfPageRotation.clockwise270;
  final width = quarter ? page.height : page.width;
  final height = quarter ? page.width : page.height;
  final left = max(0, width - _noteIconSize - 8).toDouble();
  final top = line.top.clamp(_noteIconSize, height);
  return PdfRect(left, top, left + _noteIconSize, top - _noteIconSize);
}

/// Dónde está [mark] en [content], o `null` si no está.
///
/// Se confía en las posiciones cuando lo que hay ahí es el
/// [DocumentMark.excerpt] —salvo por los espacios y saltos de renglón, que
/// el que arma el tramo pudo haber juntado—. Si no, el texto cambió desde
/// que se marcó, y se busca el excerpt: la aparición más cercana a donde
/// estaba. Si tampoco está, el tramo se saltea: marcar en otro lugar es peor
/// que no marcar.
TextSlice? _locate(String content, DocumentMark mark) {
  final (:start, :end) = (start: mark.start, end: mark.end);
  final fits = start >= 0 && start < end && end <= content.length;
  final excerpt = mark.excerpt;

  if (fits &&
      (excerpt.trim().isEmpty ||
          _squash(content.substring(start, end)) == _squash(excerpt))) {
    return (start: start, end: end);
  }
  if (excerpt.trim().isEmpty) return null;

  final from = start.clamp(0, content.length);
  final before = content.lastIndexOf(excerpt, from);
  final after = content.indexOf(excerpt, from);
  final int at;
  if (before < 0 && after < 0) {
    return null;
  } else if (before < 0) {
    at = after;
  } else if (after < 0) {
    at = before;
  } else {
    at = (from - before) <= (after - from) ? before : after;
  }
  return (start: at, end: at + excerpt.length);
}

/// [text] sin distinguir un espacio de un salto de renglón ni cuántos hay
/// seguidos.
String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
