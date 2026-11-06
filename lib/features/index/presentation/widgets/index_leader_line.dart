import 'dart:math' as math;

import 'package:flutter/material.dart';

/// **Un renglón de índice de libro** (F46): el título, la línea de puntos y
/// la página a la derecha, como el índice automático de Word: «El Concilio de
/// Nicea ……… p. 47».
///
/// Los puntos salen del final del **último** renglón del título —uno largo se
/// parte y los puntos siguen al final, como en un libro— y llegan hasta la
/// página, que va a la altura de ese renglón. Cada punto cae en una grilla
/// medida desde el borde derecho, así los de un renglón quedan en columna con
/// los del de abajo, como los de una tabulación. Sin [page], ni puntos ni
/// número: el título solo.
///
/// Es un solo objeto que pinta las tres cosas, no una fila de tres: un `Row`
/// no sabe dónde termina el último renglón de un texto partido. Lo que lee el
/// lector de pantalla lo dice la fila que lo contiene.
class IndexLeaderLine extends LeafRenderObjectWidget {
  const IndexLeaderLine({
    required this.title,
    required this.titleStyle,
    this.page,
    this.pageStyle,
    this.dotColor,
    this.maxLines = 3,
    super.key,
  });

  /// El título, con lo buscado resaltado si hace falta.
  final InlineSpan title;
  final TextStyle titleStyle;

  /// «p. 47», «pág. 3»; `null` si no lleva.
  final String? page;

  /// El de la página; sin él, el del título con cifras tabulares.
  final TextStyle? pageStyle;

  /// El de los puntos; sin él, el de la página, más tenue.
  final Color? dotColor;

  /// Cuántos renglones puede ocupar el título antes de cortarse con «…».
  final int maxLines;

  /// El título como texto plano: lo que buscan las pruebas.
  String get plainTitle => title.toPlainText();

  @override
  RenderIndexLeaderLine createRenderObject(BuildContext context) =>
      RenderIndexLeaderLine(
        title: _title(context),
        page: _page(context),
        dotColor: _dotColor(context),
        maxLines: maxLines,
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderIndexLeaderLine renderObject,
  ) {
    renderObject
      ..title = _title(context)
      ..page = _page(context)
      ..dotColor = _dotColor(context)
      ..maxLines = maxLines
      ..textScaler = MediaQuery.textScalerOf(context)
      ..textDirection = Directionality.of(context)
      ..locale = Localizations.maybeLocaleOf(context);
  }

  TextStyle _resolvedTitleStyle(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(titleStyle);

  TextStyle _resolvedPageStyle(BuildContext context) =>
      _resolvedTitleStyle(context)
          .merge(pageStyle)
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  InlineSpan _title(BuildContext context) =>
      TextSpan(style: _resolvedTitleStyle(context), children: [title]);

  InlineSpan? _page(BuildContext context) => switch (page) {
    final page? => TextSpan(text: page, style: _resolvedPageStyle(context)),
    null => null,
  };

  Color _dotColor(BuildContext context) =>
      dotColor ??
      (_resolvedPageStyle(context).color ?? const Color(0xFF000000)).withValues(
        alpha: 0.45,
      );
}

/// Lo que dibuja [IndexLeaderLine].
class RenderIndexLeaderLine extends RenderBox {
  RenderIndexLeaderLine({
    required InlineSpan title,
    required InlineSpan? page,
    required Color dotColor,
    required int maxLines,
    required TextScaler textScaler,
    required TextDirection textDirection,
    Locale? locale,
  }) : _dotColor = dotColor,
       _titlePainter = TextPainter(
         text: title,
         maxLines: maxLines,
         ellipsis: '…',
         textScaler: textScaler,
         textDirection: textDirection,
         locale: locale,
       ),
       _pagePainter = page == null
           ? null
           : TextPainter(
               text: page,
               maxLines: 1,
               textScaler: textScaler,
               textDirection: textDirection,
               locale: locale,
             );

  final TextPainter _titlePainter;
  TextPainter? _pagePainter;
  Color _dotColor;

  /// Lo que queda entre el texto y los puntos, de cada lado.
  static const _gap = 6.0;

  /// Lo mínimo que se guarda para los puntos: un título largo nunca llega
  /// hasta la página.
  static const _minLeader = 18.0;

  /// La distancia entre dos puntos, sin escalar.
  static const _dotSpacing = 5.0;

  InlineSpan get title => _titlePainter.text!;

  set title(InlineSpan value) {
    final change = _titlePainter.text?.compareTo(value);
    if (change == RenderComparison.identical) return;
    _titlePainter.text = value;
    _changed(change);
  }

  InlineSpan? get page => _pagePainter?.text;

  set page(InlineSpan? value) {
    final painter = _pagePainter;
    if (value == null) {
      if (painter == null) return;
      painter.dispose();
      _pagePainter = null;
      markNeedsLayout();
      return;
    }
    if (painter == null) {
      _pagePainter = TextPainter(
        text: value,
        maxLines: 1,
        textScaler: _titlePainter.textScaler,
        textDirection: _titlePainter.textDirection,
        locale: _titlePainter.locale,
      );
      markNeedsLayout();
      return;
    }
    final change = painter.text?.compareTo(value);
    if (change == RenderComparison.identical) return;
    painter.text = value;
    _changed(change);
  }

  Color get dotColor => _dotColor;

  set dotColor(Color value) {
    if (value == _dotColor) return;
    _dotColor = value;
    markNeedsPaint();
  }

  int get maxLines => _titlePainter.maxLines!;

  set maxLines(int value) {
    if (value == _titlePainter.maxLines) return;
    _titlePainter.maxLines = value;
    markNeedsLayout();
  }

  TextScaler get textScaler => _titlePainter.textScaler;

  set textScaler(TextScaler value) {
    if (value == _titlePainter.textScaler) return;
    _titlePainter.textScaler = value;
    _pagePainter?.textScaler = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _titlePainter.textDirection!;

  set textDirection(TextDirection value) {
    if (value == _titlePainter.textDirection) return;
    _titlePainter.textDirection = value;
    _pagePainter?.textDirection = value;
    markNeedsLayout();
  }

  Locale? get locale => _titlePainter.locale;

  set locale(Locale? value) {
    if (value == _titlePainter.locale) return;
    _titlePainter.locale = value;
    _pagePainter?.locale = value;
    markNeedsLayout();
  }

  void _changed(RenderComparison? change) {
    if (change == RenderComparison.paint) {
      markNeedsPaint();
    } else {
      markNeedsLayout();
    }
  }

  /// Lo que la página y sus puntos le sacan al ancho del título.
  double get _reserved {
    final page = _pagePainter;
    if (page == null) return 0;
    page.layout();
    return page.width + 2 * _gap + _minLeader;
  }

  bool get _rtl => _titlePainter.textDirection == TextDirection.rtl;

  void _layoutTitle(double maxWidth) {
    _titlePainter.layout(maxWidth: math.max(0, maxWidth - _reserved));
  }

  @override
  double computeMinIntrinsicWidth(double height) => _reserved;

  @override
  double computeMaxIntrinsicWidth(double height) {
    _titlePainter.layout();
    return _titlePainter.maxIntrinsicWidth + _reserved;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _measure(width).height;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    _layoutTitle(constraints.maxWidth);
    return _titlePainter.computeDistanceToActualBaseline(baseline);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final measured = _measure(width);
    return constraints.constrain(
      Size(
        width.isFinite ? width : _titlePainter.width + _reserved,
        measured.height,
      ),
    );
  }

  /// Lo que ocupan el título partido en [maxWidth] y la página a la altura
  /// de su último renglón: dónde termina ese renglón, contado desde el
  /// comienzo, su línea de base y el alto de todo.
  ({double lastLineEnd, double lastBaseline, double pageTop, double height})
  _measure(double maxWidth) {
    _layoutTitle(maxWidth);
    final lines = _titlePainter.computeLineMetrics();
    final double lastLineEnd;
    final double lastBaseline;
    if (lines.isEmpty) {
      lastLineEnd = 0;
      lastBaseline = _titlePainter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
    } else {
      final last = lines.last;
      lastLineEnd = _rtl
          ? _titlePainter.width - last.left
          : last.left + last.width;
      lastBaseline = last.baseline;
    }
    final page = _pagePainter;
    if (page == null) {
      return (
        lastLineEnd: lastLineEnd,
        lastBaseline: lastBaseline,
        pageTop: 0,
        height: _titlePainter.height,
      );
    }
    page.layout();
    final pageTop = math.max<double>(
      0,
      lastBaseline -
          page.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    );
    return (
      lastLineEnd: lastLineEnd,
      lastBaseline: lastBaseline,
      pageTop: pageTop,
      height: math.max(_titlePainter.height, pageTop + page.height),
    );
  }

  // Lo que deja la última medida, para pintar.
  double _lastLineEnd = 0;
  double _lastBaseline = 0;
  double _pageTop = 0;

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    final measured = _measure(size.width);
    _lastLineEnd = measured.lastLineEnd;
    _lastBaseline = measured.lastBaseline;
    _pageTop = measured.pageTop;
  }

  /// Dónde va la página, en este objeto; `null` si no lleva. Para las
  /// pruebas.
  @visibleForTesting
  Rect? get debugPageRect {
    final page = _pagePainter;
    if (page == null) return null;
    final x = _rtl ? 0.0 : size.width - page.width;
    return Rect.fromLTWH(x, _pageTop, page.width, page.height);
  }

  /// El tramo de los puntos, medido desde el comienzo del renglón —la
  /// izquierda, o la derecha en un idioma que se escribe al revés— y su
  /// línea de base; `null` si no lleva puntos. Para las pruebas.
  @visibleForTesting
  ({double from, double to, double baseline})? get debugLeader {
    final page = _pagePainter;
    if (page == null) return null;
    final from = _lastLineEnd + _gap;
    final to = size.width - page.width - _gap;
    if (to <= from) return null;
    return (from: from, to: to, baseline: _lastBaseline);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final titleX = _rtl ? size.width - _titlePainter.width : 0.0;
    _titlePainter.paint(canvas, offset + Offset(titleX, 0));

    final page = _pagePainter;
    if (page == null) return;
    final pageX = _rtl ? 0.0 : size.width - page.width;
    page.paint(canvas, offset + Offset(pageX, _pageTop));

    // Los puntos: desde el final del último renglón hasta la página, en la
    // grilla que cuenta desde el borde de la página, sobre la línea de base
    // como un punto escrito.
    final leader = debugLeader;
    if (leader == null) return;
    final scale = _titlePainter.textScaler.scale(1);
    final spacing = _dotSpacing * scale;
    final radius = 0.75 * scale;
    final paint = Paint()..color = _dotColor;
    final y = offset.dy + leader.baseline - radius;
    for (var x = leader.to - radius; x >= leader.from + radius; x -= spacing) {
      final dx = _rtl ? size.width - x : x;
      canvas.drawCircle(Offset(offset.dx + dx, y), radius, paint);
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void dispose() {
    _titlePainter.dispose();
    _pagePainter?.dispose();
    super.dispose();
  }
}
