import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_template.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_parts.dart';

/// Los diseños «de presentación» (F43): la portada, la sección y el cierre.
/// Cada plantilla los compone a su manera (ver [CoverLook] y [SectionLook]).

/// El rótulo, el título y la bajada de una diapositiva de presentación, como
/// un solo grupo que se ajusta junto.
List<FitTextItem> heroText(
  SlideContext c, {
  required String title,
  String subtitle = '',
  String kicker = '',
  TextAlign align = TextAlign.start,
  Color? titleColor,
  Color? subtitleColor,
  Color? kickerColor,
  double? titleSize,
  int titleLines = 4,
  Widget Function(double scale)? ornament,
  double ornamentHeight = 0,
  Widget Function(double scale)? titleOrnament,
  double titleOrnamentHeight = 0,
}) {
  final s = c.style;
  final fonts = s.fonts;
  final subtitleStyle = fonts.displayItalic
      ? fonts.displayStyle(
          size: s.headingSize * 0.86,
          color: subtitleColor ?? s.muted,
          weight: 400,
          italic: true,
          height: 1.28,
          tracking: 0,
        )
      : s.body(size: s.headingSize * 0.78, color: subtitleColor ?? s.muted);
  final items = <FitTextItem>[
    if (kicker.isNotEmpty)
      FitTextItem(
        text: kicker.toUpperCase(),
        style: s.kicker(color: kickerColor),
        textAlign: align,
        maxLines: 2,
        ornament: ornament,
        ornamentHeight: ornamentHeight,
      ),
    FitTextItem(
      text: title,
      style: s.displayTitle(size: titleSize, color: titleColor),
      textAlign: align,
      maxLines: titleLines,
      gapBefore: kicker.isNotEmpty ? s.gap * 0.55 : 0,
      ornament: titleOrnament ?? (kicker.isEmpty ? ornament : null),
      ornamentHeight: titleOrnament != null
          ? titleOrnamentHeight
          : (kicker.isEmpty ? ornamentHeight : 0),
    ),
    if (subtitle.isNotEmpty)
      FitTextItem(
        text: subtitle,
        style: subtitleStyle,
        gapBefore: s.gap * 0.8,
        textAlign: align,
        maxLines: 4,
      ),
  ];
  return items;
}

/// Un medallón redondo con la ilustración, como adorno de arriba de un
/// título centrado: alto [size] más el aire de abajo.
Widget Function(double) medallion(SlideContext c, {double size = 210}) =>
    (scale) => Align(
      alignment: Alignment.topCenter,
      child: SizedBox.square(
        dimension: size * scale,
        child: ClipOval(child: SlideArt(context: c, radius: 0)),
      ),
    );

/// El filete corto de color de debajo de un rótulo.
Widget Function(double) accentRule(
  SlideContext c, {
  double width = 160,
  double thickness = 6,
  Alignment alignment = Alignment.centerLeft,
  Color? color,
}) =>
    (scale) => Align(
      alignment: alignment,
      child: Container(
        width: width * scale,
        height: thickness * scale,
        color: color ?? c.style.palette.primary,
      ),
    );

class CoverLayout extends StatelessWidget {
  const CoverLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final CoverSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final wants = slide.wantsIllustration;
    switch (c.template.cover) {
      case CoverLook.editorial:
        return SlideFrame(
          context: c,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FitTextGroup(
                    items: heroText(
                      c,
                      title: slide.title,
                      subtitle: slide.subtitle,
                      kicker: slide.kicker,
                      titleOrnament: accentRule(
                        c,
                        width: double.infinity,
                        thickness: 3,
                        color: p.text,
                      ),
                      titleOrnamentHeight: s.gap * 1.2,
                    ),
                  ),
                ),
              ),
              if (wants) ...[
                SizedBox(width: s.gap * 1.6),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 170),
                    child: SlideArt(context: c),
                  ),
                ),
              ],
            ],
          ),
        );
      case CoverLook.framed:
        return SlideFrame(
          context: c,
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.84,
              child: FitTextGroup(
                crossAxisAlignment: CrossAxisAlignment.center,
                items: heroText(
                  c,
                  title: slide.title,
                  subtitle: slide.subtitle,
                  kicker: slide.kicker,
                  align: TextAlign.center,
                  ornament: wants ? medallion(c) : null,
                  ornamentHeight: wants ? 210 + s.gap : 0,
                  titleOrnament: (scale) => Center(
                    child: OrnamentDivider(style: s, width: 360 * scale),
                  ),
                  titleOrnamentHeight: 28 + s.gap * 0.8,
                ),
              ),
            ),
          ),
        );
      case CoverLook.split:
        return SlideFrame(
          context: c,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 11,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FitTextGroup(
                    items: heroText(
                      c,
                      title: slide.title,
                      subtitle: slide.subtitle,
                      kicker: slide.kicker,
                      titleSize: s.coverTitleSize * 0.9,
                    ),
                  ),
                ),
              ),
              SizedBox(width: s.gap * 1.6),
              Expanded(flex: 9, child: SlideArt(context: c)),
            ],
          ),
        );
      case CoverLook.band:
        final width = s.canvas.width;
        // En Corporativa la franja deja ver los triángulos de la esquina.
        final narrowBand = c.template.id == DeckTemplateId.corporate;
        return SlideFrame(
          context: c,
          padded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 60,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    s.marginX,
                    s.marginY,
                    s.marginX,
                    s.gap,
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: FitTextGroup(
                      items: heroText(
                        c,
                        title: slide.title,
                        kicker: slide.kicker,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 40,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    width: narrowBand ? width * 0.74 : width,
                    color: p.primary,
                    padding: EdgeInsets.fromLTRB(
                      s.marginX,
                      s.gap,
                      s.gap * 2,
                      s.gap,
                    ),
                    alignment: Alignment.centerLeft,
                    child: slide.subtitle.isEmpty
                        ? Container(
                            width: 160,
                            height: 6,
                            color: CreationContrast.readableOn(p.primary),
                          )
                        : FitText(
                            slide.subtitle,
                            style: s.body(
                              size: s.headingSize * 0.8,
                              color: p.onPrimary,
                            ),
                            maxLines: 3,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      case CoverLook.poster:
        final glow = c.template.title == TitleLook.glow;
        final title = slide.title;
        final titleStyle = s.displayTitle(size: s.coverTitleSize * 1.18);
        return SlideFrame(
          context: c,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: glow ? 62 : 100,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FractionallySizedBox(
                    widthFactor: glow ? 0.86 : 0.66,
                    child: FitTextGroup(
                      items: [
                        if (slide.kicker.isNotEmpty)
                          FitTextItem(
                            text: slide.kicker.toUpperCase(),
                            style: s.kicker(),
                            maxLines: 2,
                          ),
                        FitTextItem(
                          text: c.style.titleCase(title),
                          style: glow
                              ? titleStyle.copyWith(
                                  shadows: [
                                    Shadow(color: p.primary, blurRadius: 30),
                                    Shadow(color: p.primary, blurRadius: 70),
                                  ],
                                )
                              : titleStyle,
                          gapBefore: slide.kicker.isEmpty ? 0 : s.gap * 0.6,
                          maxLines: 4,
                        ),
                        if (!glow && slide.subtitle.isNotEmpty)
                          FitTextItem(
                            text: slide.subtitle,
                            style: s.body(
                              size: s.headingSize * 0.8,
                              color: s.muted,
                            ),
                            gapBefore: s.gap,
                            maxLines: 3,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (glow) ...[
                SizedBox(height: s.gap * 1.4),
                Expanded(
                  flex: 38,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.7,
                      child: FitText(
                        slide.subtitle,
                        style: s.body(
                          size: s.headingSize * 0.8,
                          color: s.muted,
                        ),
                        maxLines: 3,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      case CoverLook.floating:
        return SlideFrame(
          context: c,
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.8,
              child: _floatingPanel(
                c,
                FitTextGroup(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  items: heroText(
                    c,
                    title: slide.title,
                    subtitle: slide.subtitle,
                    kicker: slide.kicker,
                    align: TextAlign.center,
                    ornament: wants ? medallion(c) : null,
                    ornamentHeight: wants ? 210 + s.gap : 0,
                  ),
                ),
              ),
            ),
          ),
        );
      case CoverLook.masthead:
        return _MastheadComposition(c: c, slide: slide);
      case CoverLook.sidebar:
        return _SidebarComposition(
          c: c,
          left: heroText(
            c,
            title: slide.title,
            kicker: slide.kicker,
            titleColor: p.onPrimary,
            kickerColor: CreationContrast.ensure(p.secondary, p.primary),
            titleSize: s.coverTitleSize * 0.82,
            titleOrnament: accentRule(c, width: 120, color: p.secondary),
            titleOrnamentHeight: slide.kicker.isEmpty ? 0 : s.gap * 0.9,
          ),
          right: slide.subtitle.isEmpty
              ? const []
              : [
                  FitTextItem(
                    text: slide.subtitle,
                    style: s.fonts.displayItalic
                        ? s.fonts.displayStyle(
                            size: s.headingSize * 0.9,
                            color: s.muted,
                            weight: 400,
                            italic: true,
                            height: 1.3,
                          )
                        : s.body(size: s.headingSize * 0.8, color: s.muted),
                    maxLines: 5,
                  ),
                ],
          art: wants,
        );
    }
  }
}

/// La portada de Periódico (F45): la cabecera de un diario de lado a lado
/// —el filete grueso, el rótulo como la línea de la fecha y el filete fino—
/// y debajo el título enorme con la bajada como copete; la ilustración, si
/// la hay, como la foto de la nota.
class _MastheadComposition extends StatelessWidget {
  const _MastheadComposition({required this.c, required this.slide});

  final SlideContext c;
  final CoverSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    return SlideFrame(
      context: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 7, color: p.text),
          SizedBox(height: s.gap * 0.4),
          SizedBox(
            height: s.kickerSize * 1.5,
            child: Row(
              children: [
                if (slide.kicker.isNotEmpty)
                  Expanded(
                    child: FitText(
                      slide.kicker.toUpperCase(),
                      style: s.kicker(color: p.text),
                      maxLines: 1,
                    ),
                  )
                else
                  const Spacer(),
                SizedBox(width: s.gap),
                Container(
                  width: s.kickerSize * 0.6,
                  height: s.kickerSize * 0.6,
                  color: p.secondary,
                ),
              ],
            ),
          ),
          SizedBox(height: s.gap * 0.4),
          Container(height: 2, color: p.text),
          SizedBox(height: s.gap * 1.3),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: FitTextGroup(
                      items: heroText(
                        c,
                        title: slide.title,
                        subtitle: slide.subtitle,
                        titleSize: s.coverTitleSize * 1.04,
                      ),
                    ),
                  ),
                ),
                if (slide.wantsIllustration) ...[
                  SizedBox(width: s.gap * 1.6),
                  Expanded(flex: 4, child: SlideArt(context: c, radius: 0)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El panel translúcido o de papel de las portadas flotantes; en las demás
/// plantillas flotantes, el texto va directo sobre el fondo.
Widget _floatingPanel(SlideContext c, Widget child) {
  final panel = c.template.panel;
  if (panel == PanelLook.glass || panel == PanelLook.paper) {
    return DeckPanel(
      style: c.style,
      padding: EdgeInsets.symmetric(
        horizontal: c.style.gap * 2,
        vertical: c.style.gap * 1.6,
      ),
      child: child,
    );
  }
  return child;
}

/// La composición de Ejecutiva: la banda oscura que pinta el fondo, con el
/// título adentro, y a la derecha la bajada (o las ideas) y la ilustración.
class _SidebarComposition extends StatelessWidget {
  const _SidebarComposition({
    required this.c,
    required this.left,
    required this.right,
    required this.art,
    this.rightAlignment = Alignment.bottomLeft,
  });

  final SlideContext c;
  final List<FitTextItem> left;
  final List<FitTextItem> right;
  final bool art;

  /// Dónde va lo de la derecha sin ilustración: abajo en la portada, a la
  /// altura del título; en el medio en el cierre.
  final Alignment rightAlignment;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final band = s.canvas.width * 0.42;
    return SlideFrame(
      context: c,
      padded: false,
      footerLeft: band + s.gap * 1.6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: band,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                s.marginX * 0.8,
                s.marginY,
                s.gap * 1.2,
                s.marginY,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: FitTextGroup(items: left),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                s.gap * 1.6,
                s.marginY,
                s.marginX,
                s.marginY + s.footerHeight,
              ),
              child: art
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: SlideArt(context: c)),
                        if (right.isNotEmpty) ...[
                          SizedBox(height: s.gap),
                          Expanded(
                            flex: 4,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: FitTextGroup(items: right),
                            ),
                          ),
                        ],
                      ],
                    )
                  : Align(
                      alignment: rightAlignment,
                      child: FitTextGroup(items: right),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionLayout extends StatelessWidget {
  const SectionLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final SectionSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final number = '${c.sectionNumber}'.padLeft(2, '0');
    final text = heroText(
      c,
      title: slide.title,
      subtitle: slide.subtitle,
      titleSize: s.coverTitleSize * 0.78,
    );
    switch (c.template.section) {
      case SectionLook.numeral:
        return SlideFrame(
          context: c,
          child: Row(
            children: [
              SizedBox(
                width: s.canvas.width * 0.26,
                child: FitText(
                  number,
                  style: s.figure(size: 330, weight: 800),
                  maxLines: 1,
                ),
              ),
              Container(
                width: 4,
                height: 300,
                margin: EdgeInsets.symmetric(horizontal: s.gap * 1.2),
                color: p.primary.withValues(alpha: 0.5),
              ),
              Expanded(
                child: Padding(
                  // Lejos del cuadrado de color de la esquina (Suiza).
                  padding: EdgeInsets.only(right: s.canvas.height * 0.2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FitTextGroup(items: text),
                  ),
                ),
              ),
            ],
          ),
        );
      case SectionLook.band:
        final band = s.canvas.width * 0.32;
        return SlideFrame(
          context: c,
          padded: false,
          footerLeft: band + s.gap * 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: band,
                color: p.primary,
                padding: EdgeInsets.all(s.gap * 1.5),
                alignment: Alignment.center,
                child: FitText(
                  number,
                  style: s.figure(size: 300, color: p.onPrimary),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    s.gap * 2,
                    s.marginY,
                    s.marginX,
                    s.marginY + s.footerHeight,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FitTextGroup(
                      items: heroText(
                        c,
                        title: slide.title,
                        subtitle: slide.subtitle,
                        titleSize: s.coverTitleSize * 0.74,
                        titleOrnament: accentRule(c, width: 120),
                        titleOrnamentHeight: s.gap,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      case SectionLook.centered:
        return SlideFrame(
          context: c,
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.82,
              child: FitTextGroup(
                crossAxisAlignment: CrossAxisAlignment.center,
                items: [
                  FitTextItem(
                    text: number,
                    style: s.figure(size: 72),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                  ...heroText(
                    c,
                    title: slide.title,
                    subtitle: slide.subtitle,
                    align: TextAlign.center,
                    titleSize: s.coverTitleSize * 0.76,
                    titleOrnament: (scale) => Center(
                      child: OrnamentDivider(style: s, width: 300 * scale),
                    ),
                    titleOrnamentHeight: 28 + s.gap,
                  ),
                ],
              ),
            ),
          ),
        );
      case SectionLook.tile:
        return SlideFrame(
          context: c,
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.86,
              child: DeckPanel(
                style: s,
                padding: EdgeInsets.all(s.gap * 1.6),
                child: Row(
                  children: [
                    NumberBadge(style: s, label: number, size: 170),
                    SizedBox(width: s.gap * 1.3),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: s.canvas.height * 0.52,
                        ),
                        child: FitTextGroup(items: text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    }
  }
}

class ClosingLayout extends StatelessWidget {
  const ClosingLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final ClosingSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final takeaways = slide.takeaways;
    switch (c.template.cover) {
      case CoverLook.framed:
      case CoverLook.floating:
        final items = [
          ...heroText(
            c,
            title: slide.title,
            subtitle: slide.subtitle,
            align: TextAlign.center,
            titleSize: s.coverTitleSize * 0.8,
            ornament: slide.wantsIllustration ? medallion(c, size: 180) : null,
            ornamentHeight: slide.wantsIllustration ? 180 + s.gap : 0,
          ),
          for (var i = 0; i < takeaways.length; i++)
            FitTextItem(
              text: takeaways[i],
              style: s.body(size: s.bodySize * 1.04),
              textAlign: TextAlign.center,
              gapBefore: i == 0 ? s.gap * 1.2 : s.gap * 0.3,
              maxLines: 3,
              // Un rombo chico centrado arriba de cada idea.
              ornament: (scale) => Center(
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 14 * scale,
                    height: 14 * scale,
                    color: p.primary,
                  ),
                ),
              ),
              ornamentHeight: 30,
            ),
        ];
        return SlideFrame(
          context: c,
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.82,
              child: _floatingPanel(
                c,
                FitTextGroup(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  items: items,
                ),
              ),
            ),
          ),
        );
      case CoverLook.sidebar:
        return _SidebarComposition(
          c: c,
          left: heroText(
            c,
            title: slide.title,
            subtitle: slide.subtitle,
            titleColor: p.onPrimary,
            subtitleColor: CreationContrast.ensure(
              p.onPrimary.withValues(alpha: 0.8),
              p.primary,
            ),
            titleSize: s.coverTitleSize * 0.76,
            titleOrnament: accentRule(c, width: 120, color: p.secondary),
            titleOrnamentHeight: s.gap * 0.9,
          ),
          right: bulletItems(
            s,
            takeaways,
            mark: BulletMark.numeral,
            gapFactor: 1.1,
            fontSize: s.bodySize * 1.08,
          ),
          art: slide.wantsIllustration,
          rightAlignment: Alignment.centerLeft,
        );
      case CoverLook.editorial:
      case CoverLook.split:
      case CoverLook.band:
      case CoverLook.poster:
      case CoverLook.masthead:
        return SlideFrame(
          context: c,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FitTextGroup(
                    items: heroText(
                      c,
                      title: c.style.titleCase(slide.title),
                      subtitle: slide.subtitle,
                      titleSize: s.coverTitleSize * 0.82,
                      titleOrnament: accentRule(c),
                      titleOrnamentHeight: s.gap * 1.1,
                    ),
                  ),
                ),
              ),
              if (takeaways.isNotEmpty) ...[
                SizedBox(width: s.gap * 2.4),
                Expanded(
                  flex: 6,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FitTextGroup(
                      items: bulletItems(
                        s,
                        takeaways,
                        mark: BulletMark.numeral,
                        gapFactor: 1.2,
                        fontSize: s.bodySize * 1.1,
                      ),
                    ),
                  ),
                ),
              ] else if (slide.wantsIllustration) ...[
                SizedBox(width: s.gap * 2),
                Expanded(flex: 4, child: SlideArt(context: c)),
              ],
            ],
          ),
        );
    }
  }
}
