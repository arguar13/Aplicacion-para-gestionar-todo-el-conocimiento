import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Un texto de un grupo que se ajusta junto (F43): un título y su bajada, las
/// viñetas de una lista, el nombre y el detalle de una tarjeta.
@immutable
class FitTextItem {
  const FitTextItem({
    required this.text,
    required this.style,
    this.gapBefore = 0,
    this.leadingWidth = 0,
    this.leading,
    this.ornamentHeight = 0,
    this.ornament,
    this.maxLines,
    this.textAlign = TextAlign.start,
  });

  final String text;

  /// El estilo al tamaño que se quiere; el ajuste lo achica si no entra.
  final TextStyle style;

  /// El espacio antes de este texto (y de su ornamento), al tamaño que se
  /// quiere: se achica con el texto.
  final double gapBefore;

  /// El ancho de lo que va a la izquierda del texto —la viñeta, el número—,
  /// al tamaño que se quiere.
  final double leadingWidth;

  /// Lo que va a la izquierda, dibujado a la escala que se le pasa.
  final Widget Function(double scale)? leading;

  /// El alto de un adorno que va arriba del texto —un filete, un ícono—, al
  /// tamaño que se quiere; se achica con el grupo.
  final double ornamentHeight;

  /// El adorno, dibujado a la escala que se le pasa en
  /// [ornamentHeight] × escala de alto.
  final Widget Function(double scale)? ornament;

  /// El tope de líneas que pide el diseño (un título de dos líneas), aparte
  /// del que imponga el lugar. Mientras se busca la escala, un texto que no
  /// entra en su tope cuenta como que no entra: se achica antes de cortarlo.
  final int? maxLines;

  final TextAlign textAlign;
}

/// Cómo quedó un grupo después de ajustarlo: la escala común y cuántas líneas
/// puede ocupar cada texto. Los que ya no entran ni en una línea, al final,
/// quedan fuera ([visibleCount]).
@immutable
class FitTextResult {
  const FitTextResult({
    required this.scale,
    required this.maxLines,
    required this.visibleCount,
    required this.height,
  });

  final double scale;

  /// Las líneas de cada texto visible (null: las que necesite, o las de su
  /// tope de diseño).
  final List<int?> maxLines;

  final int visibleCount;

  /// El alto que ocupa el grupo así.
  final double height;

  /// Si entró todo, entero, sin cortar nada.
  bool get complete =>
      visibleCount == maxLines.length && maxLines.every((m) => m == null);
}

/// El ajuste del texto al lugar que tiene, sin desbordar nunca (F43).
///
/// Primero se busca la escala más grande —de 1 hacia abajo, hasta
/// `minScale`— con la que el grupo entero entra en el alto disponible, cada
/// texto en su tope de líneas y sin partir ninguna palabra al medio. Si ni en
/// la mínima entra, se recortan líneas, primero al texto más largo y con «…»
/// al final; y si aun con una línea cada uno no alcanza, se dejan fuera los
/// últimos. Lo que se dibuja es exactamente lo que se midió —el mismo estilo,
/// el mismo escalador y el mismo ancho—, así que el alto calculado es el alto
/// real.
abstract final class FitTextLayout {
  /// Un margen de seguridad, en puntos del lienzo, contra el redondeo.
  static const double safety = 0.5;

  static FitTextResult solve({
    required List<FitTextItem> items,
    required double maxWidth,
    required double maxHeight,
    double minScale = 0.5,
    double? fixedScale,
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection textDirection = TextDirection.ltr,
    TextStyle? baseStyle,
  }) {
    if (items.isEmpty) {
      return const FitTextResult(
        scale: 1,
        maxLines: [],
        visibleCount: 0,
        height: 0,
      );
    }
    final measurer = _Measurer(
      items: items,
      maxWidth: maxWidth,
      textScaler: textScaler,
      textDirection: textDirection,
      baseStyle: baseStyle,
    );
    try {
      final limit = maxHeight - safety;
      final full = List<int?>.filled(items.length, null);
      bool fits(double scale) =>
          measurer.height(scale, full, strict: true) <= limit;

      double scale;
      if (fixedScale != null) {
        scale = fixedScale;
      } else if (fits(1)) {
        scale = 1;
      } else if (!fits(minScale)) {
        scale = minScale;
      } else {
        // La más grande que entra, entre la mínima (entra) y 1 (no entra).
        var low = minScale;
        var high = 1.0;
        for (var i = 0; i < 9; i++) {
          final mid = (low + high) / 2;
          if (fits(mid)) {
            low = mid;
          } else {
            high = mid;
          }
        }
        scale = low;
      }

      final height = measurer.height(scale, full);
      if (height <= limit) {
        return FitTextResult(
          scale: scale,
          maxLines: full,
          visibleCount: items.length,
          height: height,
        );
      }
      return _clamp(measurer, scale, limit);
    } finally {
      measurer.dispose();
    }
  }

  /// No entra ni a la escala mínima: se recortan líneas y, si hace falta,
  /// textos enteros desde el final.
  static FitTextResult _clamp(_Measurer measurer, double scale, double limit) {
    final count = measurer.items.length;
    final lines = [for (var i = 0; i < count; i++) measurer.lines(i, scale)];
    final caps = List<int>.of(lines);
    var visible = count;

    double heightOf() =>
        measurer.height(scale, _caps(caps, lines), visible: visible);

    while (heightOf() > limit) {
      // El texto visible con más líneas pierde una.
      var widest = -1;
      for (var i = 0; i < visible; i++) {
        if (caps[i] > 1 && (widest < 0 || caps[i] > caps[widest])) widest = i;
      }
      if (widest >= 0) {
        caps[widest]--;
      } else if (visible > 1) {
        visible--;
      } else {
        break;
      }
    }
    return FitTextResult(
      scale: scale,
      maxLines: _caps(caps, lines).sublist(0, visible),
      visibleCount: visible,
      height: heightOf(),
    );
  }

  static List<int?> _caps(List<int> caps, List<int> lines) => [
    for (var i = 0; i < caps.length; i++)
      if (caps[i] < lines[i]) caps[i] else null,
  ];

  /// [style] a la escala [scale].
  static TextStyle scaledStyle(TextStyle style, double scale) => style.copyWith(
    fontSize: (style.fontSize ?? 14) * scale,
    letterSpacing: style.letterSpacing == null
        ? null
        : style.letterSpacing! * scale,
  );

  static int? minLines(int? a, int? b) => a == null
      ? b
      : b == null
      ? a
      : math.min(a, b);
}

class _Measurer {
  _Measurer({
    required this.items,
    required this.maxWidth,
    required this.textScaler,
    required this.textDirection,
    required this.baseStyle,
  });

  final List<FitTextItem> items;
  final double maxWidth;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final TextStyle? baseStyle;
  final _painters = <TextPainter>[];

  TextStyle _style(int index, double scale) => (baseStyle ?? const TextStyle())
      .merge(FitTextLayout.scaledStyle(items[index].style, scale));

  double _width(int index, double scale) =>
      math.max(0, maxWidth - items[index].leadingWidth * scale);

  TextPainter _layout(int index, double scale, int? maxLines) {
    final item = items[index];
    final lines = FitTextLayout.minLines(item.maxLines, maxLines);
    final painter = TextPainter(
      text: TextSpan(text: item.text, style: _style(index, scale)),
      textAlign: item.textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: lines,
      ellipsis: lines == null ? null : '…',
    )..layout(maxWidth: _width(index, scale));
    _painters.add(painter);
    return painter;
  }

  /// Si alguna palabra de [index] es más ancha que su lugar: entonces se
  /// partiría al medio, y eso no se acepta mientras se pueda achicar.
  bool _breaksWord(int index, double scale) {
    final words = items[index].text.split(RegExp(r'\s+'))
      ..sort((a, b) => b.length.compareTo(a.length));
    final width = _width(index, scale);
    for (final word in words.take(3)) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: _style(index, scale)),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      _painters.add(painter);
      if (painter.width > width) return true;
    }
    return false;
  }

  /// Las líneas que ocupa el texto [index] entero (o con su tope de diseño).
  int lines(int index, double scale) =>
      math.max(1, _layout(index, scale, null).computeLineMetrics().length);

  /// El alto del grupo a [scale] con los topes [maxLines]. Con [strict], un
  /// texto que no entra en su tope de diseño o que parte una palabra cuenta
  /// como que no entra (alto infinito).
  double height(
    double scale,
    List<int?> maxLines, {
    int? visible,
    bool strict = false,
  }) {
    var total = 0.0;
    final count = visible ?? items.length;
    for (var i = 0; i < count; i++) {
      final item = items[i];
      total += (item.gapBefore + item.ornamentHeight) * scale;
      final painter = _layout(i, scale, maxLines[i]);
      if (strict && (painter.didExceedMaxLines || _breaksWord(i, scale))) {
        return double.infinity;
      }
      total += painter.height;
    }
    return total;
  }

  void dispose() {
    for (final painter in _painters) {
      painter.dispose();
    }
  }
}

/// Un grupo de textos que se ajusta al lugar que le toca (F43).
///
/// Ocupa a lo sumo el alto que le dan; con alto sin límite, se dibuja a la
/// escala 1 (o [scale]) sin cortar nada.
class FitTextGroup extends StatelessWidget {
  const FitTextGroup({
    required this.items,
    this.minScale = 0.5,
    this.scale,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    super.key,
  });

  final List<FitTextItem> items;
  final double minScale;

  /// Una escala ya decidida —la común de varias tarjetas hermanas, ver
  /// [FitTextGroup.sharedScale]—; sin ella, el grupo busca la suya.
  final double? scale;

  final CrossAxisAlignment crossAxisAlignment;

  /// La escala más chica de las que necesitan [groups] para entrar cada uno
  /// en [size]: con ella, tarjetas hermanas quedan con el mismo tamaño de
  /// letra aunque una traiga más texto.
  static double sharedScale(
    BuildContext context,
    List<List<FitTextItem>> groups,
    Size size, {
    double minScale = 0.5,
  }) {
    var shared = 1.0;
    for (final group in groups) {
      final result = FitTextLayout.solve(
        items: group,
        maxWidth: size.width,
        maxHeight: size.height,
        minScale: minScale,
        textScaler: _scalerOf(context),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        baseStyle: DefaultTextStyle.of(context).style,
      );
      shared = math.min(shared, result.scale);
    }
    return shared;
  }

  /// El alto que ocupa [items] dibujado a [scale] en [size] (con lo que
  /// haya que recortar si ni así entra): para que una tarjeta mida lo que
  /// su texto, y no todo el lugar que tiene.
  static double heightAt(
    BuildContext context,
    List<FitTextItem> items,
    Size size,
    double scale,
  ) => FitTextLayout.solve(
    items: items,
    maxWidth: size.width,
    maxHeight: size.height,
    fixedScale: scale,
    textScaler: _scalerOf(context),
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    baseStyle: DefaultTextStyle.of(context).style,
  ).height;

  static TextScaler _scalerOf(BuildContext context) =>
      MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = _scalerOf(context);
        final result = FitTextLayout.solve(
          items: items,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          minScale: minScale,
          fixedScale: scale,
          textScaler: scaler,
          textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          baseStyle: DefaultTextStyle.of(context).style,
        );
        final children = <Widget>[];
        for (var i = 0; i < result.visibleCount; i++) {
          final item = items[i];
          final lines = FitTextLayout.minLines(
            item.maxLines,
            result.maxLines[i],
          );
          if (item.gapBefore > 0) {
            children.add(SizedBox(height: item.gapBefore * result.scale));
          }
          if (item.ornamentHeight > 0) {
            children.add(
              SizedBox(
                height: item.ornamentHeight * result.scale,
                child: item.ornament?.call(result.scale),
              ),
            );
          }
          final text = Text(
            item.text,
            style: FitTextLayout.scaledStyle(item.style, result.scale),
            textAlign: item.textAlign,
            textScaler: scaler,
            maxLines: lines,
            overflow: lines == null ? null : TextOverflow.ellipsis,
          );
          if (item.leading == null && item.leadingWidth == 0) {
            children.add(
              constraints.maxWidth.isFinite
                  ? SizedBox(width: constraints.maxWidth, child: text)
                  : text,
            );
          } else {
            // La viñeta va encima, sin ocupar alto: el renglón mide lo que
            // su texto, exactamente lo que se midió (una marca que pidiera
            // medio punto más que la línea desbordaría el grupo).
            final lead = item.leadingWidth * result.scale;
            children.add(
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.only(start: lead),
                    child: text,
                  ),
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    width: lead,
                    child: item.leading?.call(result.scale) ?? const SizedBox(),
                  ),
                ],
              ),
            );
          }
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAxisAlignment,
          children: children,
        );
      },
    );
  }
}

/// Un solo texto que se ajusta al lugar que le toca: un título, una cifra.
class FitText extends StatelessWidget {
  const FitText(
    this.text, {
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.minScale = 0.5,
    super.key,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;
  final double minScale;

  @override
  Widget build(BuildContext context) => FitTextGroup(
    minScale: minScale,
    crossAxisAlignment: switch (textAlign) {
      TextAlign.center => CrossAxisAlignment.center,
      TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.start,
    },
    items: [
      FitTextItem(
        text: text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
      ),
    ],
  );
}
