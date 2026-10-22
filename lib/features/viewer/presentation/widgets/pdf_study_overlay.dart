import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';

/// Lo estudiado de un PDF (F36) —el resumen o la síntesis, las palabras
/// clave—, pintado sobre las letras del PDF real, como un resaltador sobre
/// el papel.
///
/// Las capas vienen en posiciones del texto extraído, que son las páginas
/// unidas por un separador (ver `PdfParser`); acá se lleva cada una a su
/// página y a las letras de ahí, con lo que el PDF dice de dónde está cada
/// letra. El texto de una página se lee recién cuando hace falta pintarla.
///
/// Se pinta multiplicando el color con la página: el papel toma el color y
/// la letra queda negra, sin taparla, como el resaltador de un lector de PDF.
/// Una página escaneada no tiene letras donde pintar: lleva un aviso.
class PdfStudyOverlay {
  PdfStudyOverlay(this._controller);

  final PdfViewerController _controller;

  String? _content;
  List<PaintedRange> _paints = const [];
  List<TextSlice> _ranges = const [];
  String _scannedNotice = '';

  /// Dónde cae cada página en el texto, cuando ya se sabe.
  List<TextSlice>? _slices;

  /// Si el texto no se pudo repartir por los separadores y hay que recorrer
  /// las páginas en orden.
  bool _walking = false;

  final Map<int, PdfStudyPage> _pages = {};
  final Map<int, List<PdfPaintBox>> _boxes = {};
  final Set<int> _loading = {};

  /// Cambia con cada texto nuevo: lo que llega leído de antes se descarta.
  var _generation = 0;

  /// Lo que se pinta: [paints] sobre [content], el texto extraído del PDF.
  /// [scannedNotice] es el aviso de una página escaneada.
  void update({
    required String content,
    required List<PaintedRange> paints,
    required String scannedNotice,
  }) {
    var changed = false;
    if (content != _content) {
      _content = content;
      _slices = null;
      _walking = false;
      _pages.clear();
      _loading.clear();
      _generation++;
      changed = true;
    }
    if (!listEquals(paints, _paints)) {
      _paints = paints;
      _ranges = [for (final p in paints) (start: p.start, end: p.end)];
      changed = true;
    }
    _scannedNotice = scannedNotice;
    if (changed) {
      _boxes.clear();
      _repaintSoon();
    }
  }

  /// Para [PdfViewerParams.pagePaintCallbacks].
  void paintPage(Canvas canvas, Rect pageRect, PdfPage page) {
    if (_paints.isEmpty) return;
    final studied = _studied(page);
    if (studied == null) return;

    if (!studied.onLetters) {
      if (studied.touches(_ranges)) _paintNotice(canvas, pageRect);
      return;
    }
    final boxes = _boxes[page.pageNumber] ??= studied.boxes(_ranges);
    for (final box in boxes) {
      canvas.drawRect(
        box.rect.toRectInDocument(page: page, pageRect: pageRect),
        Paint()
          ..color = _paints[box.paint].background
          ..blendMode = BlendMode.multiply,
      );
    }
  }

  /// La posición del texto extraído de la letra en [documentPosition] —en
  /// coordenadas del documento, las de un toque de `pdfrx`—, o `null` si ahí
  /// no hay una letra de una página ya leída.
  int? offsetAt(Offset documentPosition) {
    if (!_controller.isReady) return null;
    final layouts = _controller.layout.pageLayouts;
    final index = layouts.indexWhere((r) => r.contains(documentPosition));
    if (index < 0) return null;
    final studied = _pages[index + 1];
    if (studied == null) return null;
    final pageRect = layouts[index];
    final point = (documentPosition - pageRect.topLeft).toPdfPoint(
      page: _controller.pages[index],
      scaledPageSize: pageRect.size,
    );
    return studied.offsetAt(point);
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

    final studied = PdfStudyPage(
      slice: slice,
      rawText: raw?.fullText ?? '',
      charRects: raw?.charRects ?? const [],
      content: content,
    );
    // Una página con letras propias que no coincide con su tramo: el texto
    // no se repartió bien por los separadores —uno quedó dentro de una
    // página—. Se recorren en orden, que es exacto.
    final ownText = cleanPdfPageText(raw?.fullText ?? '');
    if (!studied.onLetters && ownText.isNotEmpty && !_walking) {
      unawaited(_walk(page.document.pages, content));
      return;
    }
    _pages[number] = studied;
    _repaintSoon();
  }

  /// Ubica todas las páginas leyéndolas en orden. Solo se guarda dónde cae
  /// cada una: su texto se vuelve a leer cuando hace falta pintarla, para
  /// no tener un libro entero de letras en memoria.
  Future<void> _walk(List<PdfPage> pages, String content) async {
    if (_walking) return;
    _walking = true;
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
    if (_controller.isReady) _controller.invalidate();
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
