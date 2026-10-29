import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_style.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_template.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_parts.dart';

/// Los diseños de texto (F43): viñetas, dos columnas, cita, comparación e
/// imagen con texto.

/// El esqueleto de una diapositiva de contenido: el título arriba y el resto
/// del lugar para [body].
class ContentScaffold extends StatelessWidget {
  const ContentScaffold({
    required this.c,
    required this.title,
    required this.body,
    super.key,
  });

  final SlideContext c;
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      context: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty) ...[
            SlideTitle(context: c, text: title),
            SizedBox(height: c.style.gap * 1.1),
          ],
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Una grilla de tarjetas del mismo tamaño, con la misma letra en todas: se
/// calcula de antemano el lugar exacto del texto de cada una (ver
/// `DeckPanel.insets`) y se elige la escala que les sirve a todas.
class PanelGrid extends StatelessWidget {
  const PanelGrid({
    required this.style,
    required this.count,
    required this.columns,
    required this.textOf,
    this.header,
    this.headerHeight = 0,
    this.fills,
    super.key,
  });

  final DeckStyle style;
  final int count;
  final int columns;

  /// Los textos de cada tarjeta, por su posición.
  final List<FitTextItem> Function(int index) textOf;

  /// Lo que va arriba del texto en cada tarjeta (un ícono, un número), de
  /// alto fijo [headerHeight].
  final Widget Function(int index)? header;
  final double headerHeight;

  /// Un relleno propio por tarjeta.
  final Color? Function(int index)? fills;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (count / columns).ceil();
        final gap = style.gap * 0.8;
        // Medio punto menos por el redondeo: la suma no puede pasarse.
        final cellWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns - 0.5;
        final cellHeight =
            (constraints.maxHeight - gap * (rows - 1)) / rows - 0.5;
        final insets = DeckPanel.insets(style);
        final double inner = math.max(0, cellHeight - insets.vertical);
        // En una tarjeta baja, el ícono o el número se achican antes que el
        // texto: nunca ocupan más de un tercio.
        final headerSize = header == null
            ? 0.0
            : math.min(headerHeight, inner * 0.32);
        final headerGap = header == null
            ? 0.0
            : math.min(style.gap * 0.5, inner * 0.08);
        final textSize = Size(
          math.max(0, cellWidth - insets.horizontal),
          math.max(0, inner - headerSize - headerGap),
        );
        final groups = [for (var i = 0; i < count; i++) textOf(i)];
        final scale = FitTextGroup.sharedScale(context, groups, textSize);
        // Las tarjetas miden lo que pide la que más texto tiene, con aire;
        // no todo el alto, que con poco texto las deja vacías abajo.
        var needed = 0.0;
        for (final group in groups) {
          needed = math.max(
            needed,
            FitTextGroup.heightAt(context, group, textSize, scale),
          );
        }
        final fitted = math.min(
          cellHeight,
          needed + insets.vertical + headerSize + headerGap + style.gap * 0.9,
        );
        Widget cell(int i) => SizedBox(
          width: cellWidth,
          height: fitted,
          child: DeckPanel(
            style: style,
            index: i,
            fill: fills?.call(i),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (header != null) ...[
                  SizedBox(
                    height: headerSize,
                    // A su tamaño natural, achicado si no entra: un número
                    // en una letra de ojo chico (la manuscrita) pide más.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: header!(i),
                    ),
                  ),
                  SizedBox(height: headerGap),
                ],
                Expanded(
                  child: FitTextGroup(items: groups[i], scale: scale),
                ),
              ],
            ),
          ),
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) SizedBox(height: gap),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (
                    var i = row * columns;
                    i < math.min(count, (row + 1) * columns);
                    i++
                  ) ...[if (i > row * columns) SizedBox(width: gap), cell(i)],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class BulletsLayout extends StatelessWidget {
  const BulletsLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final BulletsSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final bullets = slide.bullets;
    final look = bullets.length < 2 ? ListLook.plain : c.template.list;
    Widget body;
    switch (look) {
      case ListLook.plain:
        body = Align(
          // Un poco arriba del medio: con pocas viñetas, la lista no queda
          // pegada al título y vacía abajo.
          alignment: const Alignment(-1, -0.35),
          child: FitTextGroup(items: bulletItems(s, bullets, gapFactor: 0.62)),
        );
      case ListLook.rows:
        body = Align(
          // Un poco arriba del medio: con pocas viñetas, la lista no queda
          // pegada al título y vacía abajo.
          alignment: const Alignment(-1, -0.35),
          child: FitTextGroup(
            items: [
              for (final (i, item) in bulletItems(
                s,
                bullets,
                mark: BulletMark.numeral,
                gapFactor: 0,
              ).indexed)
                FitTextItem(
                  text: item.text,
                  style: item.style,
                  leading: item.leading,
                  leadingWidth: item.leadingWidth,
                  // Un filete fino entre renglón y renglón.
                  ornamentHeight: i == 0 ? 0 : s.gap * 1.1,
                  ornament: i == 0
                      ? null
                      : (scale) => Center(
                          child: Container(
                            height: 1.5,
                            color: s.palette.text.withValues(alpha: 0.18),
                          ),
                        ),
                ),
            ],
          ),
        );
      case ListLook.cards:
        final columns = _columnsFor(bullets.length, narrow: s.isNarrow);
        body = PanelGrid(
          style: s,
          count: bullets.length,
          columns: columns,
          headerHeight: 46,
          header: (i) => Align(
            alignment: Alignment.centerLeft,
            child: Text('${i + 1}'.padLeft(2, '0'), style: s.figure(size: 40)),
          ),
          textOf: (i) => [
            FitTextItem(
              text: bullets[i],
              style: s.body(size: s.bodySize),
            ),
          ],
        );
    }
    if (slide.wantsIllustration && look != ListLook.cards) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: body),
          SizedBox(width: s.gap * 1.5),
          SizedBox(
            width: s.canvas.width * (s.isNarrow ? 0.3 : 0.34),
            child: SlideArt(context: c),
          ),
        ],
      );
    }
    return ContentScaffold(c: c, title: slide.title, body: body);
  }

  static int _columnsFor(int count, {required bool narrow}) {
    if (narrow) return count <= 2 ? count : (count <= 4 ? 2 : 3);
    return switch (count) {
      <= 3 => count,
      4 => 2,
      7 => 4,
      _ => 3,
    };
  }
}

/// Una columna: su encabezado y sus puntos, como textos de un grupo.
List<FitTextItem> columnItems(
  DeckStyle style,
  SlideColumn column, {
  Color? headingColor,
  Color? markColor,
  BulletMark? mark,
}) => [
  if (column.heading.isNotEmpty)
    FitTextItem(
      text: column.heading,
      style: style.heading(color: headingColor ?? style.palette.accentText),
      maxLines: 2,
    ),
  for (final (i, item) in bulletItems(
    style,
    column.points,
    markColor: markColor,
    mark: mark,
  ).indexed)
    FitTextItem(
      text: item.text,
      style: item.style,
      leading: item.leading,
      leadingWidth: item.leadingWidth,
      gapBefore: i == 0 && column.heading.isNotEmpty
          ? style.gap * 0.7
          : item.gapBefore,
    ),
];

class TwoColumnsLayout extends StatelessWidget {
  const TwoColumnsLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final TwoColumnsSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    return ContentScaffold(
      c: c,
      title: slide.title,
      body: PanelGrid(
        style: s,
        count: 2,
        columns: 2,
        textOf: (i) => columnItems(s, i == 0 ? slide.left : slide.right),
      ),
    );
  }
}

class ComparisonLayout extends StatelessWidget {
  const ComparisonLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final ComparisonSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final leftColor = CreationContrast.ensureOnAll(p.secondary, [
      p.background,
      p.surfaceOnBackground,
    ]);
    final versus = LayoutBuilder(
      builder: (context, constraints) {
        const badge = 120.0;
        final side = (constraints.maxWidth - badge - s.gap * 1.6) / 2;
        final insets = DeckPanel.insets(s);
        final groups = [
          columnItems(
            s,
            slide.left,
            headingColor: leftColor,
            markColor: p.secondary,
          ),
          columnItems(s, slide.right, markColor: p.primary),
        ];
        final scale = FitTextGroup.sharedScale(
          context,
          groups,
          Size(
            math.max(0, side - insets.horizontal),
            math.max(0, constraints.maxHeight - insets.vertical),
          ),
        );
        Widget panel(int i) => SizedBox(
          width: side,
          child: DeckPanel(
            style: s,
            index: i,
            child: FitTextGroup(items: groups[i], scale: scale),
          ),
        );
        // Los dos lados miden lo que pide el más largo, con aire, y quedan
        // en el medio del lugar: con poco texto no se ven cajas vacías.
        var needed = 0.0;
        for (final group in groups) {
          needed = math.max(
            needed,
            FitTextGroup.heightAt(
              context,
              group,
              Size(
                math.max(0, side - insets.horizontal),
                math.max(0, constraints.maxHeight - insets.vertical),
              ),
              scale,
            ),
          );
        }
        final height = math.min(
          constraints.maxHeight,
          math.max(badge, needed + insets.vertical + s.gap * 0.9),
        );
        return Center(
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                panel(0),
                SizedBox(width: s.gap * 0.8),
                SizedBox(
                  width: badge,
                  child: Center(
                    child: NumberBadge(
                      style: s,
                      label: 'vs',
                      size: badge,
                      color: p.accent,
                    ),
                  ),
                ),
                SizedBox(width: s.gap * 0.8),
                panel(1),
              ],
            ),
          ),
        );
      },
    );
    return ContentScaffold(
      c: c,
      title: slide.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: versus),
          if (slide.conclusion.isNotEmpty) ...[
            SizedBox(height: s.gap),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              padding: EdgeInsets.only(left: s.gap * 0.7),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: p.accent, width: 10)),
              ),
              child: FitText(
                slide.conclusion,
                style: s.body(size: s.bodySize * 1.02, weight: 600),
                maxLines: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class QuoteLayout extends StatelessWidget {
  const QuoteLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final QuoteSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final look = c.template.quote;
    final centered = look == QuoteLook.framed || look == QuoteLook.card;
    final align = centered ? TextAlign.center : TextAlign.start;
    final attribution = [
      slide.author,
      slide.source,
    ].where((t) => t.isNotEmpty).join(' · ');
    final quoteStyle = s.fonts.displayStyle(
      size: 68 * s.typeScale,
      color: p.text,
      weight: s.fonts.displayItalic ? 500 : s.fonts.displayWeight,
      italic: true,
      height: 1.22,
      tracking: 0,
    );
    final items = <FitTextItem>[
      FitTextItem(
        text: look == QuoteLook.marks ? slide.quote : '“${slide.quote}”',
        style: quoteStyle,
        textAlign: align,
        ornament: look == QuoteLook.framed
            ? (scale) => Center(
                child: OrnamentDivider(style: s, width: 300 * scale),
              )
            : (look == QuoteLook.card
                  ? (scale) => Center(
                      child: Icon(
                        Icons.format_quote_rounded,
                        size: 96 * scale,
                        color: p.primary,
                      ),
                    )
                  : null),
        ornamentHeight: switch (look) {
          QuoteLook.framed => 28 + s.gap,
          QuoteLook.card => 96 + s.gap * 0.4,
          _ => 0,
        },
      ),
      if (attribution.isNotEmpty)
        FitTextItem(
          text: '— $attribution',
          style: s.small(size: s.bodySize * 0.92, color: s.muted, weight: 600),
          textAlign: align,
          gapBefore: s.gap * 1.1,
          maxLines: 2,
        ),
    ];
    final group = FitTextGroup(
      items: items,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
    );
    final Widget body;
    switch (look) {
      case QuoteLook.marks:
        body = Stack(
          children: [
            Positioned(
              left: -12,
              top: -70,
              child: Text(
                '“',
                style: s.fonts.displayStyle(
                  size: 400,
                  color: p.primary,
                  height: 1,
                ),
              ),
            ),
            Positioned.fill(
              left: 230,
              top: 60,
              child: Align(alignment: Alignment.centerLeft, child: group),
            ),
          ],
        );
      case QuoteLook.framed:
        body = Center(
          child: FractionallySizedBox(widthFactor: 0.84, child: group),
        );
      case QuoteLook.bar:
        body = Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: EdgeInsets.only(left: s.gap * 1.2),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: p.primary, width: 14)),
            ),
            child: group,
          ),
        );
      case QuoteLook.card:
        body = Center(
          child: FractionallySizedBox(
            widthFactor: 0.86,
            child: DeckPanel(
              style: s,
              padding: EdgeInsets.symmetric(
                horizontal: s.gap * 2,
                vertical: s.gap * 1.4,
              ),
              child: group,
            ),
          ),
        );
    }
    return SlideFrame(
      context: c,
      child: slide.wantsIllustration
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: body),
                SizedBox(width: s.gap * 1.5),
                SizedBox(
                  width: s.canvas.width * 0.28,
                  child: SlideArt(context: c),
                ),
              ],
            )
          : body,
    );
  }
}

class ImageTextLayout extends StatelessWidget {
  const ImageTextLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final ImageTextSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final artFirst = c.index.isOdd;
    final art = SizedBox(
      width: s.canvas.width * (s.isNarrow ? 0.4 : 0.44),
      child: SlideArt(context: c),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slide.title.isNotEmpty) ...[
          SlideTitle(context: c, text: slide.title, maxHeight: 300),
          SizedBox(height: s.gap),
        ],
        Expanded(
          child: Align(
            alignment: const Alignment(-1, -0.4),
            child: FitTextGroup(
              items: [
                if (slide.body.isNotEmpty)
                  FitTextItem(
                    text: slide.body,
                    style: s.body(size: s.bodySize * 1.04),
                  ),
                for (final (i, item) in bulletItems(s, slide.bullets).indexed)
                  FitTextItem(
                    text: item.text,
                    style: item.style,
                    leading: item.leading,
                    leadingWidth: item.leadingWidth,
                    gapBefore: i == 0 && slide.body.isNotEmpty
                        ? s.gap
                        : item.gapBefore,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    return SlideFrame(
      context: c,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: artFirst
            ? [art, SizedBox(width: s.gap * 1.6), Expanded(child: text)]
            : [Expanded(child: text), SizedBox(width: s.gap * 1.6), art],
      ),
    );
  }
}
