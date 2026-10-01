import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// Mantener apretado sobre el texto del PDF y, sin levantar el dedo,
/// arrastrarlo: la selección crece hasta donde está el dedo y los tiradores
/// lo acompañan —como en cualquier texto de Android—.
///
/// `pdfrx` solo selecciona la palabra al mantener apretado
/// (`onLongPressStart`) e ignora lo que el dedo hace después: la selección
/// quedaba fija en esa palabra hasta soltar y agarrar un tirador (F22, pedido
/// del usuario). Esto lo completa desde afuera, con su API pública: escucha
/// el dedo con un [Listener] —que ve los movimientos aunque el gesto ya lo
/// haya ganado el "mantener apretado" de `pdfrx`— y mueve la selección con
/// `setTextSelectionPointRange`.
///
/// Mientras el dedo arrastra, el menú "Copiar / Seleccionar todo" no se
/// muestra —taparía el texto que se está eligiendo—; vuelve al soltar.
class PdfLongPressDragSelection {
  PdfLongPressDragSelection(this.controller);

  final PdfViewerController controller;

  /// Cuántos dedos tocan el visor: con dos es un pellizco para hacer zoom,
  /// no una selección.
  final Set<int> _pointers = {};

  _Session? _session;

  /// Texto de las páginas a las que llegó el dedo, para no volver a leerlo
  /// en cada movimiento.
  final Map<int, PdfPageText> _texts = {};
  final Set<int> _loading = {};

  /// Si hay un arrastre de selección en curso: el menú espera a que termine.
  bool get isDragging => _session?.moved ?? false;

  /// Para [PdfViewerParams.onGeneralTap]: al mantener apretado, empieza a
  /// seguir al dedo. Nunca consume el toque —`pdfrx` sigue seleccionando la
  /// palabra como siempre—.
  bool onGeneralTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type != PdfViewerGeneralTapType.longPress ||
        _pointers.length != 1) {
      return false;
    }
    final current = controller.textSelectionDelegate.textSelectionPointRange;
    switch (details.tapOn) {
      case PdfViewerPart.nonSelectedText:
        // `pdfrx` selecciona la palabra en un instante —espera a tener el
        // texto de la página—: se toma como ancla cuando aparece.
        _session = _Session(_pointers.single, previous: current);
      case PdfViewerPart.selectedText when current != null:
        // Sobre lo que ya estaba seleccionado `pdfrx` no cambia nada: el
        // arrastre parte de esa selección.
        _session = _Session(_pointers.single, previous: current)
          ..anchor = current;
      case _:
        _session = null;
    }
    return false;
  }

  /// Para [PdfViewerParams.customizeContextMenuItems].
  void hideMenuWhileDragging(
    PdfViewerContextMenuBuilderParams params,
    List<Object?> items,
  ) {
    if (isDragging) items.clear();
  }

  void onPointerDown(PointerDownEvent event) => _pointers.add(event.pointer);

  void onPointerMove(PointerMoveEvent event) {
    final session = _session;
    if (session == null || event.pointer != session.pointer) return;
    session.lastGlobal = event.position;
    _follow(session);
  }

  void onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    final session = _session;
    if (session == null || event.pointer != session.pointer) return;
    _session = null;
    // Para que el menú vuelva a aparecer junto a la selección.
    if (session.moved && controller.isReady) controller.invalidate();
  }

  void _follow(_Session session) {
    if (!controller.isReady) return;
    final anchor = session.anchor ??= _newSelection(session);
    final global = session.lastGlobal;
    if (anchor == null || global == null) return;
    final document = controller.globalToDocument(global);
    if (document == null) return;
    final pageRects = controller.layout.pageLayouts;
    final pageIndex = pageRects.indexWhere((r) => r.contains(document));
    if (pageIndex < 0) return;
    final pageNumber = pageIndex + 1;
    final text = _textOf(pageNumber, anchor, session);
    if (text == null) return;
    final pageRect = pageRects[pageIndex];
    final point = (document - pageRect.topLeft).toPdfPoint(
      page: controller.pages[pageIndex],
      scaledPageSize: pageRect.size,
    );
    final index = nearestCharIndex(text, point);
    if (index == null) return;
    session.moved = true;
    controller.textSelectionDelegate.setTextSelectionPointRange(
      extendSelection(anchor, PdfTextSelectionPoint(text, index)),
    );
  }

  /// La palabra que `pdfrx` acaba de seleccionar, o nada si todavía no lo
  /// hizo.
  PdfTextSelectionRange? _newSelection(_Session session) {
    final current = controller.textSelectionDelegate.textSelectionPointRange;
    if (current == null || sameRange(current, session.previous)) return null;
    return current;
  }

  PdfPageText? _textOf(
    int pageNumber,
    PdfTextSelectionRange anchor,
    _Session session,
  ) {
    for (final point in [anchor.start, anchor.end]) {
      if (point.text.pageNumber == pageNumber) return point.text;
    }
    final cached = _texts[pageNumber];
    if (cached != null || !_loading.add(pageNumber)) return cached;
    controller.pages[pageNumber - 1].loadStructuredText().then(
      (text) {
        _loading.remove(pageNumber);
        _texts[pageNumber] = text;
        // El dedo pudo quedarse quieto sobre esta página mientras se leía.
        if (identical(_session, session)) _follow(session);
      },
      onError: (Object _) {
        _loading.remove(pageNumber);
      },
    );
    return null;
  }
}

class _Session {
  _Session(this.pointer, {required this.previous});

  final int pointer;

  /// La selección de antes de mantener apretado.
  final PdfTextSelectionRange? previous;

  /// Desde dónde crece la selección: la palabra de mantener apretado.
  PdfTextSelectionRange? anchor;

  Offset? lastGlobal;
  bool moved = false;
}

/// La selección desde [anchor] —la palabra donde se mantuvo apretado— hasta
/// el dedo, hacia adelante o hacia atrás: la palabra entera queda siempre
/// adentro, como en Android.
PdfTextSelectionRange extendSelection(
  PdfTextSelectionRange anchor,
  PdfTextSelectionPoint finger,
) {
  if (finger < anchor.start) {
    return PdfTextSelectionRange.fromPoints(finger, anchor.end);
  }
  if (finger > anchor.end) {
    return PdfTextSelectionRange.fromPoints(anchor.start, finger);
  }
  return anchor;
}

/// La letra bajo [point] —en coordenadas de la página PDF— o, si el dedo
/// está entre renglones o en el margen, la más cercana: arrastrar por el
/// margen derecho llega hasta el final de cada renglón.
int? nearestCharIndex(PdfPageText text, PdfPoint point) {
  int? closest;
  var best = double.infinity;
  for (var i = 0; i < text.charRects.length; i++) {
    final rect = text.charRects[i];
    if (rect.containsPoint(point)) return i;
    final d2 = rect.distanceSquaredTo(point);
    if (d2 < best) {
      best = d2;
      closest = i;
    }
  }
  return closest;
}

bool sameRange(PdfTextSelectionRange? a, PdfTextSelectionRange? b) =>
    a?.start == b?.start && a?.end == b?.end;
