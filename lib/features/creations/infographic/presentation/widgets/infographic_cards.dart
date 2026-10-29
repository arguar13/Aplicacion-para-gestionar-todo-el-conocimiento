import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_icons.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_chart_data.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_numbers.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_charts.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_parts.dart';

/// Cómo se presenta un bloque.
enum InfoCardLook {
  /// En la caja del estilo.
  panel,

  /// Sin caja, centrado, bajo una raya de color: las columnas.
  open,

  /// En una caja del color primario: el bloque destacado.
  inverse,

  /// Como un indicador: la cifra manda y un porcentaje se ve como anillo.
  kpi,
}

/// Lo que va arriba (o al costado) del texto de un bloque.
enum InfoMediaKind { none, icon, badge, figure, ring, art, quoteMark }

/// Las medidas de un bloque ya decididas: dónde va lo de arriba y cuánto
/// lugar le queda al texto. La misma cuenta la usa el bloque para dibujarse
/// y la composición para darles a todos los hermanos la misma letra.
@immutable
class InfoCardGeometry {
  const InfoCardGeometry({
    required this.insets,
    required this.media,
    required this.mediaSize,
    required this.horizontal,
    required this.mediaGap,
    required this.textSize,
  });

  final EdgeInsets insets;
  final InfoMediaKind media;
  final Size mediaSize;

  /// Lo de arriba va a la izquierda del texto (una caja ancha y baja).
  final bool horizontal;
  final double mediaGap;
  final Size textSize;
}

/// Los colores con que se escribe adentro de un bloque, con el contraste
/// comprobado contra su caja.
@immutable
class InfoCardInk {
  const InfoCardInk({
    required this.surface,
    required this.text,
    required this.muted,
    required this.accent,
  });

  factory InfoCardInk.of(InfographicStyle style, int index, InfoCardLook look) {
    final p = style.palette;
    if (look == InfoCardLook.inverse) {
      final on = p.onPrimary;
      return InfoCardInk(surface: p.primary, text: on, muted: on, accent: on);
    }
    final surface = look == InfoCardLook.open
        ? p.background
        : InfoPanel.surfaceOf(style, index);
    return InfoCardInk(
      surface: surface,
      text: CreationContrast.ensure(p.text, surface, minimum: 7),
      muted: CreationContrast.ensure(p.muted, surface),
      accent: CreationContrast.ensure(p.primary, surface),
    );
  }

  final Color surface;
  final Color text;
  final Color muted;
  final Color accent;
}

/// Un bloque común listo para dibujar (ver [InfoCards.layout]).
typedef InfoCardLayout = ({
  InfoCardGeometry geometry,
  List<FitTextItem> items,
  InfoCardInk ink,
});

/// Las cuentas de un bloque: qué lleva, dónde y con qué textos.
abstract final class InfoCards {
  /// Los bloques que se dibujan con su propio armado (y no entran en la letra
  /// común de sus hermanos).
  static bool isSpecial(InfographicBlock block) =>
      block is ComparisonBlock || block is ChartBlock;

  static EdgeInsets insetsFor(InfographicStyle style, InfoCardLook look) =>
      switch (look) {
        InfoCardLook.open => EdgeInsets.only(top: 10 + style.gap * 0.8),
        InfoCardLook.inverse => InfoPanel.innerPadding(style),
        InfoCardLook.panel || InfoCardLook.kpi => InfoPanel.insets(style),
      };

  /// Si [block] lleva una ilustración en un lugar de [inner]: la pidió, o
  /// el estilo es de los ilustrados, y hay lugar para que se vea.
  static bool _useArt(
    InfoContext c,
    InfographicBlock block,
    Size inner,
    InfoCardLook look,
  ) {
    if (look == InfoCardLook.kpi || look == InfoCardLook.inverse) return false;
    if (block is! FactBlock &&
        block is! ConceptBlock &&
        block is! StepBlock &&
        block is! EventBlock) {
      return false;
    }
    final wants = block.wantsIllustration || c.spec.isIllustrated;
    return wants && inner.width >= 200 && inner.height >= 300;
  }

  static InfoCardGeometry geometry(
    InfoContext c,
    InfographicBlock block,
    Size size, {
    InfoCardLook look = InfoCardLook.panel,
    InfoMediaKind? mediaOverride,
  }) {
    final style = c.style;
    final insets = insetsFor(style, look);
    final inner = Size(
      math.max(0, size.width - insets.horizontal),
      math.max(0, size.height - insets.vertical),
    );
    final art = _useArt(c, block, inner, look);
    final media =
        mediaOverride ??
        switch (block) {
          StatBlock(:final value) =>
            look == InfoCardLook.kpi &&
                    InfographicNumbers.percentOf(value) != null
                ? InfoMediaKind.ring
                : InfoMediaKind.figure,
          StepBlock() => art ? InfoMediaKind.art : InfoMediaKind.badge,
          FactBlock() || ConceptBlock() || EventBlock() =>
            art
                ? InfoMediaKind.art
                : style.iconLook == InfographicIconLook.none
                ? InfoMediaKind.none
                : InfoMediaKind.icon,
          QuoteBlock() => InfoMediaKind.quoteMark,
          ComparisonBlock() || ChartBlock() => InfoMediaKind.none,
        };
    // Lo de arriba pasa al costado en una caja ancha y baja; una cifra, que
    // se lee mejor arriba de su rótulo, solo en una muy ancha.
    final horizontal =
        media != InfoMediaKind.none &&
        media != InfoMediaKind.quoteMark &&
        size.width >= size.height * (media == InfoMediaKind.figure ? 2.6 : 1.8);
    // El aire entre lo de arriba y el texto, nunca más que una parte chica
    // del lugar (en una caja diminuta, no se come el texto).
    final gap = math.min(
      style.gap * 0.6,
      (horizontal ? inner.width : inner.height) * 0.08,
    );
    final Size mediaSize;
    if (horizontal) {
      mediaSize = switch (media) {
        InfoMediaKind.icon || InfoMediaKind.badge => Size.square(
          _min3(style.iconSize, inner.height * 0.8, inner.width * 0.25),
        ),
        InfoMediaKind.figure => Size(inner.width * 0.42, inner.height),
        InfoMediaKind.ring => Size.square(
          math.min(inner.height, inner.width * 0.36),
        ),
        InfoMediaKind.art => Size(
          math.min(inner.width * 0.4, inner.height * 1.3),
          inner.height,
        ),
        InfoMediaKind.none || InfoMediaKind.quoteMark => Size.zero,
      };
    } else {
      mediaSize = switch (media) {
        InfoMediaKind.icon || InfoMediaKind.badge => Size.square(
          _min3(style.iconSize, inner.height * 0.3, inner.width * 0.5),
        ),
        InfoMediaKind.figure => Size(
          inner.width,
          math.min(style.figureSize * 1.25, inner.height * 0.45),
        ),
        InfoMediaKind.ring => Size.square(
          math.min(inner.height * 0.5, inner.width * 0.62),
        ),
        InfoMediaKind.art => Size(
          inner.width,
          math.min(inner.height * 0.45, inner.width * 0.66),
        ),
        InfoMediaKind.quoteMark => Size(
          inner.width,
          math.min(style.headingSize * 1.5, inner.height * 0.22),
        ),
        InfoMediaKind.none => Size.zero,
      };
    }
    final mediaGap = media == InfoMediaKind.none ? 0.0 : gap;
    final textSize = horizontal
        ? Size(
            math.max(0, inner.width - mediaSize.width - mediaGap),
            inner.height,
          )
        : Size(
            inner.width,
            math.max(0, inner.height - mediaSize.height - mediaGap),
          );
    return InfoCardGeometry(
      insets: insets,
      media: media,
      mediaSize: mediaSize,
      horizontal: horizontal,
      mediaGap: mediaGap,
      textSize: textSize,
    );
  }

  static double _min3(double a, double b, double c) =>
      math.min(a, math.min(b, c));

  /// Los textos de [block], en el orden en que se leen. Sin el detalle en
  /// «Conciso». Con [includeValue], la cifra de un bloque de cifras va
  /// primera (cuando no va arriba, en grande).
  static List<FitTextItem> textItems(
    InfoContext c,
    InfographicBlock block, {
    required InfoCardInk ink,
    InfoCardLook look = InfoCardLook.panel,
    bool includeValue = false,
  }) {
    final style = c.style;
    final details = style.showDetails;
    final align = look == InfoCardLook.open
        ? TextAlign.center
        : blockAlign(style);
    FitTextItem title(String text, {double factor = 1, double gap = 0}) =>
        FitTextItem(
          text: text,
          style: style.heading(
            size: style.headingSize * factor,
            color: ink.text,
          ),
          textAlign: align,
          maxLines: 3,
          gapBefore: gap,
        );
    FitTextItem detail(String text) => FitTextItem(
      text: text,
      style: style.small(color: ink.muted),
      textAlign: align,
      gapBefore: style.gap * 0.4,
    );
    return switch (block) {
      StatBlock(:final value, :final label, detail: final d) => [
        if (includeValue)
          FitTextItem(
            text: value,
            style: style.figure(
              size: style.headingSize * 1.4,
              color: ink.accent,
            ),
            textAlign: align,
            maxLines: 1,
          ),
        if (label.isNotEmpty)
          title(label, factor: 0.8, gap: includeValue ? style.gap * 0.25 : 0),
        if (details && d.isNotEmpty) detail(d),
      ],
      FactBlock(title: final t, detail: final d) ||
      StepBlock(title: final t, detail: final d) ||
      ConceptBlock(
        title: final t,
        detail: final d,
      ) => [title(t), if (details && d.isNotEmpty) detail(d)],
      EventBlock(:final date, title: final t, detail: final d) => [
        if (date.isNotEmpty)
          FitTextItem(
            text: date,
            style: style.figure(
              size: style.headingSize * 0.92,
              color: ink.accent,
            ),
            textAlign: align,
            maxLines: 2,
          ),
        if (t != date)
          FitTextItem(
            text: t,
            style: style.heading(color: ink.text),
            textAlign: align,
            maxLines: 3,
            gapBefore: date.isEmpty ? 0 : style.gap * 0.3,
          ),
        if (details && d.isNotEmpty) detail(d),
      ],
      QuoteBlock(:final quote, :final author, :final source) => [
        FitTextItem(
          text: quote,
          style: style.fonts.displayStyle(
            size: style.headingSize * 1.05,
            color: ink.text,
            italic: true,
            height: 1.22,
          ),
          textAlign: align,
        ),
        if (author.isNotEmpty || source.isNotEmpty)
          FitTextItem(
            text:
                '— ${[author, source].where((s) => s.isNotEmpty).join(' · ')}',
            style: style.small(color: ink.muted, weight: 600),
            textAlign: align,
            gapBefore: style.gap * 0.5,
            maxLines: 2,
          ),
      ],
      ComparisonBlock() || ChartBlock() => const [],
    };
  }

  /// La escala de letra que les sirve a todos los bloques comunes de
  /// [cards] —cada uno con su tamaño—, para que tengan la misma. Un bloque
  /// que necesitaría achicarse demasiado no arrastra a los demás: no se baja
  /// de [floor], y ese bloque usa la suya.
  static double sharedScale(
    BuildContext context,
    InfoContext c,
    List<(InfographicBlock, Size, int)> cards, {
    InfoCardLook Function(int index)? lookOf,
    InfoMediaKind? Function(InfographicBlock block)? mediaOf,
    bool valuesOutside = false,
    double floor = 0.62,
  }) {
    var shared = 1.0;
    for (final (block, size, index) in cards) {
      if (isSpecial(block)) continue;
      final l = layout(
        c,
        block,
        size,
        index,
        look: lookOf?.call(index) ?? InfoCardLook.panel,
        media: mediaOf?.call(block),
        valuesOutside: valuesOutside,
      );
      shared = math.min(
        shared,
        solve(context, l.items, l.geometry.textSize).scale,
      );
    }
    return math.max(floor, shared);
  }

  /// Lo que hace falta para dibujar un bloque común en [size]: sus medidas,
  /// sus textos y sus colores. Con [valuesOutside], la cifra de un bloque de
  /// cifras no va en su texto: la composición la dibuja aparte.
  static InfoCardLayout layout(
    InfoContext c,
    InfographicBlock block,
    Size size,
    int index, {
    InfoCardLook look = InfoCardLook.panel,
    InfoMediaKind? media,
    bool valuesOutside = false,
  }) {
    final g = geometry(c, block, size, look: look, mediaOverride: media);
    final ink = InfoCardInk.of(c.style, index, look);
    final includeValue =
        !valuesOutside &&
        g.media != InfoMediaKind.figure &&
        g.media != InfoMediaKind.ring;
    return (
      geometry: g,
      items: textItems(
        c,
        block,
        ink: ink,
        look: look,
        includeValue: includeValue,
      ),
      ink: ink,
    );
  }

  /// El alto que necesita el bloque común [block] para mostrarse entero a
  /// [scale] en un lugar de [size] (a lo sumo el de [size]): para que una
  /// caja mida lo que su contenido, con un poco de aire.
  static double neededHeight(
    BuildContext context,
    InfoContext c,
    InfographicBlock block,
    Size size,
    int index,
    double scale, {
    InfoCardLook look = InfoCardLook.panel,
    InfoMediaKind? media,
    bool valuesOutside = false,
  }) {
    if (isSpecial(block)) return size.height;
    final l = layout(
      c,
      block,
      size,
      index,
      look: look,
      media: media,
      valuesOutside: valuesOutside,
    );
    final g = l.geometry;
    final own = solve(context, l.items, g.textSize).scale;
    final text =
        solve(
          context,
          l.items,
          g.textSize,
          fixedScale: math.min(own, scale),
        ).height +
        FitTextLayout.safety * 2;
    final content = g.horizontal
        ? math.max(g.mediaSize.height, text)
        : g.mediaSize.height + g.mediaGap + text;
    return math.min(
      size.height,
      content + g.insets.vertical + c.style.gap * 0.6,
    );
  }

  /// [FitTextLayout.solve] con lo mismo que usa `FitTextGroup` al dibujar:
  /// así lo medido es lo dibujado.
  static FitTextResult solve(
    BuildContext context,
    List<FitTextItem> items,
    Size size, {
    double? fixedScale,
    double minScale = 0.5,
  }) => FitTextLayout.solve(
    items: items,
    maxWidth: size.width,
    maxHeight: size.height,
    minScale: minScale,
    fixedScale: fixedScale,
    textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    baseStyle: DefaultTextStyle.of(context).style,
  );
}

/// Un grupo de textos medido de antemano en su lugar más grande: el alto que
/// va a ocupar y la escala con que se dibuja. Así una caja mide lo que su
/// texto —no todo el lugar que tenía— y lo dibujado es lo medido.
@immutable
class MeasuredText {
  const MeasuredText._(this.height, this.scale, {required this.visible});

  factory MeasuredText.of(
    BuildContext context,
    List<FitTextItem> items,
    Size max,
  ) {
    if (items.isEmpty) return const MeasuredText._(0, 1, visible: false);
    final result = InfoCards.solve(context, items, max);
    if (result.visibleCount == 0) {
      return const MeasuredText._(0, 1, visible: false);
    }
    // Con el margen del ajuste, lo medido entra justo en su caja.
    return MeasuredText._(
      math.min(max.height, result.height + FitTextLayout.safety * 2),
      result.scale,
      visible: true,
    );
  }

  final double height;
  final double scale;

  /// Si hay algo que dibujar (en un lugar de ni un renglón, no).
  final bool visible;

  Widget box(List<FitTextItem> items, double width, CrossAxisAlignment cross) =>
      SizedBox(
        width: width,
        height: height,
        child: visible
            ? FitTextGroup(
                items: items,
                scale: scale,
                crossAxisAlignment: cross,
              )
            : null,
      );
}

/// Un bloque dibujado en el lugar que le dan: su caja, lo de arriba (el
/// ícono, el número, la cifra, la ilustración) y sus textos, que se ajustan
/// sin desbordar nunca.
class InfoBlockCard extends StatelessWidget {
  const InfoBlockCard({
    required this.c,
    required this.block,
    required this.index,
    this.look = InfoCardLook.panel,
    this.scaleCap,
    this.number,
    this.media,
    this.valuesOutside = false,
    this.boost = 1,
    super.key,
  });

  final InfoContext c;
  final InfographicBlock block;

  /// La cifra de un bloque de cifras la dibuja la composición aparte (el
  /// zigzag): no va en el texto.
  final bool valuesOutside;

  /// Cuánto más grande va la letra de una comparación que ocupa casi toda
  /// la lámina.
  final double boost;

  /// Lo de arriba, si no es el de su tipo (un número en todos los pasos de
  /// un proceso, nada cuando la composición lo dibuja aparte).
  final InfoMediaKind? media;

  /// Su posición en la lámina: el color, la semilla de la ilustración.
  final int index;
  final InfoCardLook look;

  /// La escala común de sus hermanos (ver [InfoCards.sharedScale]); el
  /// bloque usa la menor entre esta y la suya.
  final double? scaleCap;

  /// El número del paso, si no es su posición más uno.
  final int? number;

  @override
  Widget build(BuildContext context) {
    final style = c.style;
    final card = switch (block) {
      final ComparisonBlock b => _ComparisonCard(
        c: c,
        block: b,
        index: index,
        boost: boost,
      ),
      final ChartBlock b => _ChartCard(
        c: c,
        block: b,
        index: index,
        look: look,
      ),
      _ => LayoutBuilder(
        builder: (context, constraints) =>
            _common(context, constraints.biggest),
      ),
    };
    final boxed = switch (look) {
      InfoCardLook.panel ||
      InfoCardLook.kpi => InfoPanel(style: style, index: index, child: card),
      InfoCardLook.inverse => Container(
        padding: InfoPanel.innerPadding(style),
        decoration: BoxDecoration(
          color: style.palette.primary,
          borderRadius: BorderRadius.circular(style.spec.radius),
        ),
        child: card,
      ),
      InfoCardLook.open => Container(
        padding: EdgeInsets.only(top: style.gap * 0.8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: style.tint(index), width: 10)),
        ),
        child: card,
      ),
    };
    // El lector de pantalla lee el bloque entero de una vez, con sus
    // números en palabras.
    return Semantics(
      container: true,
      label: blockSemantics(block),
      child: ExcludeSemantics(child: boxed),
    );
  }

  /// El de los bloques comunes. [outer] es el lugar de adentro de la caja;
  /// la cuenta se hace sobre el de afuera, como la hace la composición.
  Widget _common(BuildContext context, Size outer) {
    final style = c.style;
    final insets = InfoCards.insetsFor(style, look);
    final size = Size(
      outer.width + insets.horizontal,
      outer.height + insets.vertical,
    );
    final (geometry: g, :items, :ink) = InfoCards.layout(
      c,
      block,
      size,
      index,
      look: look,
      media: media,
      valuesOutside: valuesOutside,
    );
    final own = InfoCards.solve(context, items, g.textSize).scale;
    final scale = math.min(own, scaleCap ?? 1);
    final centered = look == InfoCardLook.open || style.spec.centered;
    final text = SizedBox.fromSize(
      size: g.textSize,
      child: Align(
        alignment: g.horizontal
            ? Alignment.centerLeft
            : (centered ? Alignment.topCenter : Alignment.topLeft),
        child: FitTextGroup(
          items: items,
          scale: scale,
          crossAxisAlignment: centered && !g.horizontal
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
        ),
      ),
    );
    if (g.media == InfoMediaKind.none) return text;
    final mediaBox = SizedBox.fromSize(
      size: g.mediaSize,
      child: _media(g, ink, centered),
    );
    return g.horizontal
        ? Row(
            children: [
              mediaBox,
              SizedBox(width: g.mediaGap),
              text,
            ],
          )
        : Column(
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              mediaBox,
              SizedBox(height: g.mediaGap),
              text,
            ],
          );
  }

  Widget _media(InfoCardGeometry g, InfoCardInk ink, bool centered) {
    final style = c.style;
    final side = g.mediaSize.shortestSide;
    final alignment = centered && !g.horizontal
        ? Alignment.center
        : Alignment.centerLeft;
    switch (g.media) {
      case InfoMediaKind.icon:
        return Align(
          alignment: alignment,
          child: InfoIcon(
            style: style,
            icon: blockIcon(block),
            size: side,
            tint: look == InfoCardLook.inverse ? ink.text : style.tint(index),
            surface: ink.surface,
          ),
        );
      case InfoMediaKind.badge:
        return Align(
          alignment: alignment,
          child: InfoNumberBadge(
            style: style,
            label: '${number ?? index + 1}',
            size: side,
            color: style.tint(index),
          ),
        );
      case InfoMediaKind.figure:
        final value = (block as StatBlock).value;
        return Align(
          alignment: g.horizontal
              ? Alignment.center
              : (centered ? Alignment.bottomCenter : Alignment.bottomLeft),
          child: FitText(
            value,
            style: style.figure(color: ink.accent),
            maxLines: 1,
            // Una cifra larga («3.000.000.000») se achica mucho antes de
            // cortarse.
            minScale: 0.15,
            textAlign: centered || g.horizontal
                ? TextAlign.center
                : TextAlign.start,
          ),
        );
      case InfoMediaKind.ring:
        final value = (block as StatBlock).value;
        return Align(
          alignment: alignment,
          child: SizedBox.square(
            dimension: side,
            child: CustomPaint(
              painter: InfoRingPainter(
                fractions: [InfographicNumbers.percentOf(value) ?? 0],
                colors: [InfoChart.colorOf(style, index, ink.surface)],
                track: ink.text.withValues(alpha: 0.12),
                single: true,
              ),
              child: Padding(
                padding: EdgeInsets.all(side * 0.2),
                child: Center(
                  child: FitText(
                    value,
                    style: style.figure(size: side * 0.26, color: ink.text),
                    maxLines: 1,
                    minScale: 0.2,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        );
      case InfoMediaKind.art:
        return Stack(
          children: [
            Positioned.fill(
              child: InfoArt(
                context: c,
                reference: block.illustrationRef,
                seed: c.seed + index * 13,
                icon: blockIcon(block),
                radius: math.max(8, style.spec.radius * 0.7),
              ),
            ),
            if (block is StepBlock)
              Positioned(
                left: side * 0.06,
                top: side * 0.06,
                child: InfoNumberBadge(
                  style: style,
                  label: '${number ?? index + 1}',
                  size: math.min(style.iconSize * 0.8, side * 0.3),
                  color: style.tint(index),
                ),
              ),
          ],
        );
      case InfoMediaKind.quoteMark:
        return Align(
          alignment: centered ? Alignment.center : Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '“',
              style: style.fonts.displayStyle(
                size: style.headingSize * 3,
                color: ink.accent,
                height: 1,
              ),
            ),
          ),
        );
      case InfoMediaKind.none:
        return const SizedBox.shrink();
    }
  }
}

/// Una comparación: los dos lados frente a frente, cada uno con su nombre y
/// sus puntos, un «VS» entre ellos y la conclusión abajo.
class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.c,
    required this.block,
    required this.index,
    this.boost = 1,
  });

  final InfoContext c;
  final ComparisonBlock block;
  final int index;
  final double boost;

  @override
  Widget build(BuildContext context) {
    final style = c.style;
    final ink = InfoCardInk.of(style, index, InfoCardLook.panel);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // Los respiros, a lo sumo una parte chica del lugar.
        final gap = math.min(style.gap * 0.6, math.min(w, h) * 0.05);
        final titleItems = [
          if (block.title.isNotEmpty)
            FitTextItem(
              text: block.title,
              style: style.heading(
                size: style.headingSize * boost,
                color: ink.text,
              ),
              textAlign: blockAlign(style),
              maxLines: 2,
            ),
        ];
        final conclusion = style.showDetails ? block.conclusion : '';
        final conclusionItems = [
          if (conclusion.isNotEmpty)
            FitTextItem(
              text: conclusion,
              style: style.small(color: ink.muted, weight: 600),
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
        ];
        final title = MeasuredText.of(context, titleItems, Size(w, h * 0.22));
        final end = MeasuredText.of(context, conclusionItems, Size(w, h * 0.2));
        final double sidesHeight = math.max(
          0,
          h -
              title.height -
              end.height -
              (titleItems.isEmpty ? 0 : gap) -
              (conclusionItems.isEmpty ? 0 : gap),
        );
        // En una caja más alta que ancha, un lado arriba del otro.
        final stacked = w < sidesHeight * 1.1;
        final vs = math.min(
          style.iconSize * 0.9,
          stacked ? sidesHeight * 0.14 : w * 0.12,
        );
        final sideWidth = stacked
            ? w
            : math.max<double>(0, (w - vs - gap * 2) / 2 - 0.5);
        final sideHeight = stacked
            ? math.max<double>(0, (sidesHeight - vs - gap * 2) / 2 - 0.5)
            : sidesHeight;
        final pad = math.min(
          style.gap * 0.6,
          math.min(sideWidth, sideHeight) * 0.12,
        );
        final textSize = Size(
          math.max(0, sideWidth - pad * 2),
          math.max(0, sideHeight - pad * 2),
        );
        final left = _sideItems(style, block.left, ink, 0);
        final right = _sideItems(style, block.right, ink, 1);
        final scale = math.min(
          InfoCards.solve(context, left, textSize).scale,
          InfoCards.solve(context, right, textSize).scale,
        );
        Widget side(List<FitTextItem> items, int which) {
          final tint = style.tint(which);
          return Container(
            width: sideWidth,
            height: sideHeight,
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                tint.withValues(alpha: 0.12),
                ink.surface,
              ),
              borderRadius: BorderRadius.circular(
                math.max(6, style.spec.radius * 0.6),
              ),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: FitTextGroup(items: items, scale: scale),
            ),
          );
        }

        final badge = SizedBox.square(
          dimension: vs,
          child: InfoNumberBadge(
            style: style,
            label: 'VS',
            size: vs,
            color: style.palette.accent,
          ),
        );
        return Column(
          children: [
            if (titleItems.isNotEmpty) ...[
              title.box(
                titleItems,
                w,
                style.spec.centered
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
              ),
              SizedBox(height: gap),
            ],
            SizedBox(
              height: sidesHeight,
              child: stacked
                  ? Column(
                      children: [
                        side(left, 0),
                        SizedBox(height: gap),
                        badge,
                        SizedBox(height: gap),
                        side(right, 1),
                      ],
                    )
                  : Row(
                      children: [
                        side(left, 0),
                        SizedBox(width: gap),
                        badge,
                        SizedBox(width: gap),
                        side(right, 1),
                      ],
                    ),
            ),
            if (conclusionItems.isNotEmpty) ...[
              SizedBox(height: gap),
              end.box(conclusionItems, w, CrossAxisAlignment.center),
            ],
          ],
        );
      },
    );
  }

  /// El nombre de un lado (con su ícono adelante) y sus puntos con viñeta.
  List<FitTextItem> _sideItems(
    InfographicStyle style,
    InfographicSide side,
    InfoCardInk ink,
    int which,
  ) {
    final tint = CreationContrast.ensure(
      style.tint(which),
      ink.surface,
      minimum: 3,
    );
    final size = style.bodySize * boost;
    final headingSize = style.headingSize * 0.9 * boost;
    final details = style.showDetails ? side.points : side.points.take(3);
    return [
      if (side.heading.isNotEmpty)
        FitTextItem(
          text: side.heading,
          style: style.heading(size: headingSize, color: ink.text),
          maxLines: 2,
          leadingWidth: side.icon == null ? 0 : headingSize * 1.4,
          leading: side.icon == null
              ? null
              : (scale) => Icon(
                  CreationIcons.resolve(side.icon),
                  size: headingSize * 1.1 * scale,
                  color: tint,
                ),
        ),
      for (final (i, point) in details.indexed)
        FitTextItem(
          text: point,
          style: style.body(size: size, color: ink.text),
          gapBefore: i == 0 && side.heading.isNotEmpty
              ? style.gap * 0.5
              : style.gap * 0.25,
          leadingWidth: size * 1.1,
          leading: (scale) => SizedBox(
            height: size * scale * 1.32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: size * scale * 0.32,
                height: size * scale * 0.32,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
    ];
  }
}

/// Un gráfico con su título arriba y, si hay, su detalle abajo.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.c,
    required this.block,
    required this.index,
    required this.look,
  });

  final InfoContext c;
  final ChartBlock block;
  final int index;
  final InfoCardLook look;

  @override
  Widget build(BuildContext context) {
    final style = c.style;
    final ink = InfoCardInk.of(style, index, look);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final gap = math.min(style.gap * 0.5, h * 0.05);
        final align = look == InfoCardLook.open
            ? TextAlign.center
            : blockAlign(style);
        final titleItems = [
          if (block.title.isNotEmpty)
            FitTextItem(
              text: block.title,
              style: style.heading(
                size: style.headingSize * 0.9,
                color: ink.text,
              ),
              textAlign: align,
              maxLines: 2,
            ),
        ];
        final detail = style.showDetails ? block.detail : '';
        final detailItems = [
          if (detail.isNotEmpty)
            FitTextItem(
              text: detail,
              style: style.small(color: ink.muted),
              textAlign: align,
              maxLines: 2,
            ),
        ];
        final title = MeasuredText.of(context, titleItems, Size(w, h * 0.24));
        final end = MeasuredText.of(context, detailItems, Size(w, h * 0.2));
        final double chartHeight = math.max(
          0,
          h -
              title.height -
              end.height -
              (titleItems.isEmpty ? 0 : gap) -
              (detailItems.isEmpty ? 0 : gap),
        );
        final cross = align == TextAlign.center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start;
        return Column(
          children: [
            if (titleItems.isNotEmpty) ...[
              title.box(titleItems, w, cross),
              SizedBox(height: gap),
            ],
            SizedBox(
              width: w,
              height: chartHeight,
              child: InfoChart(
                style: style,
                chart: block,
                surface: ink.surface,
                ink: look == InfoCardLook.inverse ? ink.text : null,
              ),
            ),
            if (detailItems.isNotEmpty) ...[
              SizedBox(height: gap),
              end.box(detailItems, w, cross),
            ],
          ],
        );
      },
    );
  }
}

/// Lo que dice un bloque, en palabras, para el lector de pantalla.
String blockSemantics(InfographicBlock block) => switch (block) {
  StatBlock(:final value, :final label, :final detail) => [
    value,
    label,
    detail,
  ].where((t) => t.isNotEmpty).join('. '),
  FactBlock(:final title, :final detail) ||
  StepBlock(:final title, :final detail) ||
  ConceptBlock(
    :final title,
    :final detail,
  ) => [title, detail].where((t) => t.isNotEmpty).join('. '),
  EventBlock(:final date, :final title, :final detail) => [
    date,
    title,
    detail,
  ].where((t) => t.isNotEmpty).join('. '),
  ComparisonBlock(:final title, :final left, :final right, :final conclusion) =>
    [
      title,
      '${left.heading}: ${left.points.join(', ')}',
      '${right.heading}: ${right.points.join(', ')}',
      conclusion,
    ].where((t) => t.trim().isNotEmpty && t.trim() != ':').join('. '),
  QuoteBlock(:final quote, :final author, :final source) => [
    quote,
    author,
    source,
  ].where((t) => t.isNotEmpty).join('. '),
  final ChartBlock chart => InfographicChartData.describe(chart),
};
