import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_hand_marks.dart';

/// Lo estudiado de un PDF (F36) —el resumen o la síntesis, las palabras
/// clave— y los resaltados a mano de la persona (F38), pintados sobre las
/// letras del PDF real, como un resaltador sobre el papel.
///
/// Las capas vienen en posiciones del texto extraído, que son las páginas
/// unidas por un separador (ver `PdfParser`); acá se lleva cada una a su
/// página y a las letras de ahí, con lo que el PDF dice de dónde está cada
/// letra. El texto de una página se lee recién cuando hace falta pintarla.
///
/// Se pinta multiplicando el color con la página: el papel toma el color y
/// la letra queda negra, sin taparla, como el resaltador de un lector de PDF.
/// Una página escaneada no tiene letras donde pintar: lleva un aviso.
///
/// **El orden de las capas (F38).** Los resaltados a mano van en el medio:
/// encima de las oraciones del resumen o la síntesis y debajo de las palabras
/// clave, que son las últimas en pintarse. Uno de fondo toma el lugar de lo
/// que tenga abajo, como una palabra clave sobre su oración; uno subrayado es
/// una línea debajo de las letras y no tapa nada. Lo que se lee en voz alta se
/// pinta aparte y por encima de todo: no pasa por acá.
///
/// Además de pintar, sabe el camino de vuelta: de una selección sobre el PDF
/// al tramo del texto extraído ([locateSelection]) y de un toque al
/// resaltado de ahí ([highlightAt]).
///
/// Sirve a un visor con controlador ([PdfStudyOverlay.new]) y a la primera
/// página fija de la vista previa ([PdfStudyOverlay.fixed]), que no tiene
/// controlador: ahí solo pinta, y avisa con `onRepaint` cuando una página
/// recién leída pide volver a dibujarse.
class PdfStudyOverlay {
  PdfStudyOverlay(PdfViewerController this._controller) : _onRepaint = null;

  PdfStudyOverlay.fixed({required VoidCallback onRepaint})
    : _controller = null,
      _onRepaint = onRepaint;

  final PdfViewerController? _controller;
  final VoidCallback? _onRepaint;

  String? _content;
  List<PaintedRange> _paints = const [];
  List<Highlight> _highlights = const [];
  String _scannedNotice = '';

  /// Las capas de abajo hacia arriba —lo estudiado, los resaltados de fondo
  /// y las palabras clave— y, aparte, las líneas de los subrayados.
  List<_Layer> _fill = const [];
  List<_Layer> _lines = const [];
  List<TextSlice> _fillRanges = const [];
  List<TextSlice> _lineRanges = const [];

  /// Dónde cae cada página en el texto, cuando ya se sabe.
  List<TextSlice>? _slices;

  /// Si el texto no se pudo repartir por los separadores y hay que recorrer
  /// las páginas en orden.
  bool _walking = false;

  /// El recorrido en marcha, para esperarlo.
  Future<void>? _walkDone;

  final Map<int, PdfStudyPage> _pages = {};
  final Map<int, _PageBoxes> _boxes = {};
  final Set<int> _loading = {};

  /// Cambia con cada texto nuevo: lo que llega leído de antes se descarta.
  var _generation = 0;

  /// Lo que se pinta: [paints] sobre [content], el texto extraído del PDF, y
  /// los [highlights] de la persona. [scannedNotice] es el aviso de una
  /// página escaneada.
  void update({
    required String content,
    required List<PaintedRange> paints,
    required String scannedNotice,
    List<Highlight> highlights = const [],
  }) {
    var changed = false;
    if (content != _content) {
      _content = content;
      _slices = null;
      _walking = false;
      _walkDone = null;
      _pages.clear();
      _loading.clear();
      _generation++;
      changed = true;
    }
    if (!listEquals(paints, _paints) || !listEquals(highlights, _highlights)) {
      _paints = paints;
      _highlights = stackedHighlights(highlights);
      _stack();
      changed = true;
    }
    _scannedNotice = scannedNotice;
    if (changed) {
      _boxes.clear();
      _repaintSoon();
    }
  }

  /// Apila las capas: las oraciones, los resaltados de la persona y las
  /// palabras clave, en ese orden.
  void _stack() {
    final fill = <_Layer>[
      for (final paint in _paints)
        if (!paint.aboveHighlights)
          _Layer(paint.start, paint.end, paint.background),
      for (final highlight in _highlights)
        if (highlight.style == HighlightStyle.fill)
          _Layer(
            highlight.startOffset,
            highlight.endOffset,
            HighlightPalette.onPaper(highlight.color),
          ),
      for (final paint in _paints)
        if (paint.aboveHighlights)
          _Layer(paint.start, paint.end, paint.background),
    ];
    final lines = <_Layer>[
      for (final highlight in _highlights)
        if (highlight.style == HighlightStyle.underline)
          _Layer(
            highlight.startOffset,
            highlight.endOffset,
            HighlightPalette.lineOnPaper(highlight.color),
          ),
    ];
    _fill = fill;
    _lines = lines;
    _fillRanges = [for (final l in fill) (start: l.start, end: l.end)];
    _lineRanges = [for (final l in lines) (start: l.start, end: l.end)];
  }

  /// Para [PdfViewerParams.pagePaintCallbacks].
  void paintPage(Canvas canvas, Rect pageRect, PdfPage page) {
    if (_fill.isEmpty && _lines.isEmpty) return;
    final studied = _studied(page);
    if (studied == null) return;

    if (!studied.onLetters) {
      if (studied.touches(_fillRanges) || studied.touches(_lineRanges)) {
        _paintNotice(canvas, pageRect);
      }
      return;
    }
    final boxes = _boxes[page.pageNumber] ??= (
      fill: studied.boxes(_fillRanges),
      lines: studied.boxes(_lineRanges),
    );
    for (final box in boxes.fill) {
      canvas.drawRect(
        box.rect.toRectInDocument(page: page, pageRect: pageRect),
        Paint()
          ..color = _fill[box.paint].color
          ..blendMode = BlendMode.multiply,
      );
    }
    for (final box in boxes.lines) {
      final rect = box.rect.toRectInDocument(page: page, pageRect: pageRect);
      final thickness = max(1, rect.height * 0.09);
      canvas.drawRect(
        Rect.fromLTRB(
          rect.left,
          rect.bottom - thickness,
          rect.right,
          rect.bottom,
        ),
        Paint()
          ..color = _lines[box.paint].color
          ..blendMode = BlendMode.multiply,
      );
    }
  }

  /// La posición del texto extraído de la letra en [documentPosition] —en
  /// coordenadas del documento, las de un toque de `pdfrx`—, o `null` si ahí
  /// no hay una letra de una página ya leída.
  int? offsetAt(Offset documentPosition) {
    final controller = _controller;
    if (controller == null || !controller.isReady) return null;
    final layouts = controller.layout.pageLayouts;
    final index = layouts.indexWhere((r) => r.contains(documentPosition));
    if (index < 0) return null;
    final studied = _pages[index + 1];
    if (studied == null) return null;
    final pageRect = layouts[index];
    final point = (documentPosition - pageRect.topLeft).toPdfPoint(
      page: controller.pages[index],
      scaledPageSize: pageRect.size,
    );
    return studied.offsetAt(point);
  }

  /// El resaltado de la persona que está en [documentPosition] —en
  /// coordenadas del documento—, o `null` si ahí no hay ninguno. Donde dos se
  /// pisan, el de encima: el más nuevo.
  Highlight? highlightAt(Offset documentPosition) {
    final offset = offsetAt(documentPosition);
    return offset == null ? null : highlightAtOffset(_highlights, offset);
  }

  /// Dónde cae una selección del PDF en el texto extraído (F38): [selection]
  /// son los tramos por página de `getSelectedTextRanges` y [pages] las
  /// páginas del documento.
  ///
  /// Lee las páginas que haga falta —y cómo se reparte el texto entre ellas,
  /// con el mismo recorrido con que se pintan—, así que sirve aunque todavía
  /// no se haya pintado nada. Da un tramo por página (ver
  /// [SelectionLocation]). Un PDF escaneado, o con un texto que no es el
  /// guardado, no se puede ubicar, y se sabe por qué.
  Future<SelectionLocation> locateSelection(
    List<PdfPageTextRange> selection,
    List<PdfPage> pages,
  ) async {
    if (_content == null) {
      return const SelectionLocation.failed(HighlightIssue.notLocated);
    }
    final slices = <TextSlice>[];
    for (final range in selection) {
      // Una página donde solo cayó un salto de línea no aporta nada.
      if (range.text.trim().isEmpty) continue;
      if (range.pageNumber < 1 || range.pageNumber > pages.length) {
        return const SelectionLocation.failed(HighlightIssue.notLocated);
      }
      final studied = await _studyPage(pages[range.pageNumber - 1]);
      if (studied == null) {
        return const SelectionLocation.failed(HighlightIssue.notLocated);
      }
      if (!studied.onLetters) {
        return SelectionLocation.failed(
          studied.hasOwnLetters
              ? HighlightIssue.notLocated
              : HighlightIssue.scanned,
        );
      }
      final slice = studied.sliceOfSelection(
        text: range.pageText.fullText,
        charRects: range.pageText.charRects,
        start: range.start,
        end: range.end,
      );
      if (slice == null) {
        return const SelectionLocation.failed(HighlightIssue.notLocated);
      }
      slices.add(slice);
    }
    return slices.isEmpty
        ? const SelectionLocation.failed(HighlightIssue.nothingSelected)
        : SelectionLocation.found(slices);
  }

  /// La página ubicada en el texto, o `null` mientras se lee.
  PdfStudyPage? _studied(PdfPage page) {
    final content = _content;
    if (content == null) return null;
    final cached = _pages[page.pageNumber];
    if (cached != null) return cached;

    final pages = page.document.pages;
    final slices = _slices ??= _walking
        ? null
        : pdfPageSlicesBySeparator(content, pages.length);
    if (slices == null) {
      unawaited(_walk(pages, content));
    } else if (page.pageNumber <= slices.length) {
      unawaited(_read(page, slices[page.pageNumber - 1], content));
    }
    return null;
  }

  Future<void> _read(PdfPage page, TextSlice slice, String content) async {
    final number = page.pageNumber;
    if (!_loading.add(number)) return;
    final generation = _generation;
    final raw = await _loadText(page);
    if (generation != _generation) return;
    _loading.remove(number);

    final studied = _pageOf(slice, raw, content);
    // Una página con letras propias que no coincide con su tramo: el texto
    // no se repartió bien por los separadores —uno quedó dentro de una
    // página—. Se recorren en orden, que es exacto.
    if (!studied.onLetters && studied.hasOwnLetters && !_walking) {
      unawaited(_walk(page.document.pages, content));
      return;
    }
    _pages[number] = studied;
    _repaintSoon();
  }

  /// Lo mismo que [_studied] pero esperando el resultado: lee la página y,
  /// si hace falta, recorre todas para saber dónde cae.
  Future<PdfStudyPage?> _studyPage(PdfPage page) async {
    // Un texto que cambia a mitad de camino, o un reparto por separadores que
    // resulta no ser exacto, piden volver a intentar: pocas veces.
    for (var attempt = 0; attempt < 3; attempt++) {
      final content = _content;
      if (content == null) return null;
      final cached = _pages[page.pageNumber];
      if (cached != null) return cached;

      final slices = await _slicesFor(page.document.pages, content);
      if (slices == null || page.pageNumber > slices.length) {
        if (!identical(content, _content)) continue;
        return null;
      }
      final generation = _generation;
      final raw = await _loadText(page);
      if (generation != _generation) continue;

      final studied = _pageOf(slices[page.pageNumber - 1], raw, content);
      if (!studied.onLetters && studied.hasOwnLetters && !_walking) {
        await _walk(page.document.pages, content);
        continue;
      }
      _pages[page.pageNumber] = studied;
      _repaintSoon();
      return studied;
    }
    return null;
  }

  PdfStudyPage _pageOf(TextSlice slice, PdfPageRawText? raw, String content) =>
      PdfStudyPage(
        slice: slice,
        rawText: raw?.fullText ?? '',
        charRects: raw?.charRects ?? const [],
        content: content,
      );

  /// Dónde cae cada página, esperando el recorrido si por los separadores no
  /// se pudo saber. `null` si el texto cambió mientras tanto.
  Future<List<TextSlice>?> _slicesFor(
    List<PdfPage> pages,
    String content,
  ) async {
    if (!_walking) {
      final slices = _slices ??= pdfPageSlicesBySeparator(
        content,
        pages.length,
      );
      if (slices != null) return slices;
    }
    await _walk(pages, content);
    return identical(content, _content) ? _slices : null;
  }

  /// Ubica todas las páginas leyéndolas en orden. Solo se guarda dónde cae
  /// cada una: su texto se vuelve a leer cuando hace falta pintarla, para
  /// no tener un libro entero de letras en memoria.
  Future<void> _walk(List<PdfPage> pages, String content) {
    if (_walking) return _walkDone ?? Future<void>.value();
    _walking = true;
    return _walkDone = _walkAll(pages, content);
  }

  Future<void> _walkAll(List<PdfPage> pages, String content) async {
    _slices = null;
    _pages.clear();
    _boxes.clear();
    // Lo que se estaba leyendo con el reparto por separadores ya no vale.
    final generation = ++_generation;
    final walker = PdfPageWalker(content);
    final slices = <TextSlice>[];
    for (var i = 0; i < pages.length; i++) {
      final raw = await _loadText(pages[i]);
      if (generation != _generation) return;
      slices.add(
        walker.next(
          cleanPdfPageText(raw?.fullText ?? ''),
          last: i == pages.length - 1,
        ),
      );
    }
    _slices = slices;
    _loading.clear();
    _repaintSoon();
  }

  /// El texto de [page] con dónde está cada letra, o `null` si no se pudo
  /// leer.
  Future<PdfPageRawText?> _loadText(PdfPage page) async {
    try {
      return await page.loadText();
      // PDFium no tiene un tipo propio para sus fallas: una página que no se
      // lee queda sin pintar, y el resto del documento sigue.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  void _repaintSoon() {
    final controller = _controller;
    if (controller != null && controller.isReady) controller.invalidate();
    _onRepaint?.call();
  }

  void _paintNotice(Canvas canvas, Rect pageRect) {
    final fontSize = (pageRect.width * 0.028).clamp(8.0, 14.0);
    final painter = TextPainter(
      text: TextSpan(
        text: _scannedNotice,
        style: TextStyle(color: Colors.white, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: max(0, pageRect.width * 0.8));
    final padding = fontSize * 0.6;
    final box = Rect.fromLTWH(
      pageRect.left + padding,
      pageRect.top + padding,
      painter.width + padding * 2,
      painter.height + padding,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(fontSize)),
      Paint()..color = const Color(0xCC37474F),
    );
    painter
      ..paint(canvas, box.topLeft + Offset(padding, padding / 2))
      ..dispose();
  }
}

/// El resaltado de [stacked] —de abajo hacia arriba— que cubre la posición
/// [offset] del texto extraído, el de encima si son varios, o `null`.
Highlight? highlightAtOffset(List<Highlight> stacked, int offset) {
  for (final highlight in stacked.reversed) {
    if (offset >= highlight.startOffset && offset < highlight.endOffset) {
      return highlight;
    }
  }
  return null;
}

/// Una capa de color sobre un tramo del texto extraído.
class _Layer {
  const _Layer(this.start, this.end, this.color);

  final int start;
  final int end;
  final Color color;
}

/// Los rectángulos de una página: los de fondo y los de las líneas de
/// subrayado, cada uno con el número de su capa.
typedef _PageBoxes = ({List<PdfPaintBox> fill, List<PdfPaintBox> lines});
