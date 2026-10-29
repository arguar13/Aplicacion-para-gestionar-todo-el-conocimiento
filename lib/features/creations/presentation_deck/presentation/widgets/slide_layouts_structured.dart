import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_icons.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_style.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_template.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_layouts_content.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_parts.dart';

/// Los diseños con estructura (F43): la cifra destacada, la línea de pasos,
/// la cronología y la cuadrícula de conceptos.

/// El porcentaje de [value] si es uno («40 %», «12,5%»), entre 0 y 100; null
/// si no.
double? percentOf(String value) {
  final match = RegExp(r'^\s*(\d{1,3}(?:[.,]\d+)?)\s*%\s*$').firstMatch(value);
  if (match == null) return null;
  final number = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  if (number == null || number > 100) return null;
  return number / 100;
}

class BigNumberLayout extends StatelessWidget {
  const BigNumberLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final BigNumberSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final percent = percentOf(slide.value);
    final centered =
        c.template.centeredTitles ||
        c.template.cover == CoverLook.framed ||
        c.template.cover == CoverLook.floating;
    final valueStyle = s.figure(size: 300 * s.typeScale, weight: 800);
    final words = <FitTextItem>[
      if (slide.label.isNotEmpty)
        FitTextItem(
          text: slide.label,
          style: s.heading(size: s.headingSize * 1.18),
          textAlign: centered ? TextAlign.center : TextAlign.start,
          maxLines: 3,
        ),
      if (slide.detail.isNotEmpty)
        FitTextItem(
          text: slide.detail,
          style: s.body(color: s.muted),
          textAlign: centered ? TextAlign.center : TextAlign.start,
          gapBefore: s.gap * 0.7,
        ),
    ];
    final Widget figure;
    if (percent != null && c.template.art == CreationArtStyle.data) {
      figure = AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _RingPainter(
            value: percent,
            color: p.primary,
            track: p.text.withValues(alpha: 0.1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(90),
            child: Center(
              child: FitText(
                slide.value,
                style: valueStyle.copyWith(fontSize: 150),
                maxLines: 1,
                minScale: 0.15,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    } else {
      figure = FitText(
        slide.value,
        style: valueStyle,
        maxLines: 1,
        // Una cifra larga («3.000.000.000») se achica mucho antes de cortarse.
        minScale: 0.15,
        textAlign: centered ? TextAlign.center : TextAlign.start,
      );
    }
    final body = centered
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(flex: 5, child: Center(child: figure)),
              SizedBox(height: s.gap * 0.6),
              Container(width: 140, height: 6, color: p.primary),
              SizedBox(height: s.gap),
              Flexible(
                flex: 4,
                child: FractionallySizedBox(
                  widthFactor: 0.8,
                  child: FitTextGroup(
                    items: words,
                    crossAxisAlignment: CrossAxisAlignment.center,
                  ),
                ),
              ),
            ],
          )
        : Row(
            children: [
              Expanded(
                flex: 6,
                child: Align(alignment: Alignment.centerLeft, child: figure),
              ),
              SizedBox(width: s.gap * 1.6),
              Container(
                width: 6,
                height: 260,
                color: p.primary,
                margin: EdgeInsets.only(right: s.gap * 1.2),
              ),
              Expanded(
                flex: 5,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FitTextGroup(items: words),
                ),
              ),
            ],
          );
    return ContentScaffold(c: c, title: slide.title, body: body);
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.09;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas
      ..drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track,
      )
      ..drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}

/// El título y el detalle de un paso, de un hito o de un concepto.
List<FitTextItem> titleDetailItems(
  DeckStyle style,
  String title,
  String detail, {
  TextAlign align = TextAlign.start,
  double titleFactor = 0.86,
}) => [
  FitTextItem(
    text: title,
    style: style.heading(size: style.headingSize * titleFactor),
    textAlign: align,
    maxLines: 3,
  ),
  if (detail.isNotEmpty)
    FitTextItem(
      text: detail,
      style: style.small(size: style.smallSize, color: style.muted),
      textAlign: align,
      gapBefore: style.gap * 0.4,
    ),
];

class StepsLayout extends StatelessWidget {
  const StepsLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final StepsSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final steps = slide.steps;
    if (c.template.stepCards) {
      return ContentScaffold(
        c: c,
        title: slide.title,
        body: PanelGrid(
          style: s,
          count: steps.length,
          columns: steps.length <= 4 || !s.isNarrow
              ? steps.length
              : (steps.length / 2).ceil(),
          headerHeight: 84,
          header: (i) => Align(
            alignment: Alignment.centerLeft,
            child: NumberBadge(style: s, label: '${i + 1}', size: 84),
          ),
          textOf: (i) => titleDetailItems(s, steps[i].title, steps[i].detail),
        ),
      );
    }
    return ContentScaffold(
      c: c,
      title: slide.title,
      body: _Track(
        style: s,
        count: steps.length,
        marker: (i) => NumberBadge(style: s, label: '${i + 1}', size: 96),
        markerSize: 96,
        textOf: (i) => titleDetailItems(s, steps[i].title, steps[i].detail),
      ),
    );
  }
}

/// Una línea horizontal con una marca por punto y el texto de cada uno
/// debajo: los pasos y la cronología. Con [above], cada punto lleva además
/// un texto arriba de la línea (la fecha).
class _Track extends StatelessWidget {
  const _Track({
    required this.style,
    required this.count,
    required this.marker,
    required this.markerSize,
    required this.textOf,
    this.above,
    this.aboveHeight = 0,
  });

  final DeckStyle style;
  final int count;
  final Widget Function(int index) marker;
  final double markerSize;
  final List<FitTextItem> Function(int index) textOf;
  final List<FitTextItem> Function(int index)? above;
  final double aboveHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = style.gap * 0.7;
        final width = (constraints.maxWidth - gap * (count - 1)) / count - 0.5;
        // Lo fijo —la fecha, la marca y su aire— nunca ocupa más de la mitad
        // del alto: en un lugar bajo, se achica.
        final fixed = aboveHeight + markerSize + style.gap * 0.8;
        final double k = math.min(1, constraints.maxHeight * 0.5 / fixed);
        final aboveSize = aboveHeight * k;
        final markerBox = markerSize * k;
        final markerGap = style.gap * 0.8 * k;
        final double textHeight = math.max(
          0,
          constraints.maxHeight - aboveSize - markerBox - markerGap,
        );
        final groups = [for (var i = 0; i < count; i++) textOf(i)];
        final scale = FitTextGroup.sharedScale(
          context,
          groups,
          Size(width, textHeight),
        );
        final aboveGroups = above == null
            ? null
            : [for (var i = 0; i < count; i++) above!(i)];
        final aboveScale = aboveGroups == null
            ? 1.0
            : FitTextGroup.sharedScale(
                context,
                aboveGroups,
                Size(width, math.max(0, aboveSize - style.gap * 0.4 * k)),
              );
        final lineTop = aboveSize + markerBox / 2 - 2;
        // La línea mide lo que su texto más largo, y se ubica un poco arriba
        // del medio: con poco texto no queda pegada al título y vacía abajo.
        var needed = 0.0;
        for (final group in groups) {
          needed = math.max(
            needed,
            FitTextGroup.heightAt(
              context,
              group,
              Size(width, textHeight),
              scale,
            ),
          );
        }
        final trackHeight = math.min(
          constraints.maxHeight,
          aboveSize + markerBox + markerGap + needed + style.gap * 0.5,
        );
        return Align(
          alignment: const Alignment(0, -0.4),
          child: SizedBox(
            height: trackHeight,
            child: _stack(
              lineTop: lineTop,
              markerBox: markerBox,
              width: width,
              gap: gap,
              height: trackHeight,
              aboveGroups: aboveGroups,
              aboveSize: aboveSize,
              aboveScale: aboveScale,
              k: k,
              markerGap: markerGap,
              groups: groups,
              scale: scale,
            ),
          ),
        );
      },
    );
  }

  Widget _stack({
    required double lineTop,
    required double markerBox,
    required double width,
    required double gap,
    required double height,
    required List<List<FitTextItem>>? aboveGroups,
    required double aboveSize,
    required double aboveScale,
    required double k,
    required double markerGap,
    required List<List<FitTextItem>> groups,
    required double scale,
  }) {
    return Stack(
      children: [
        // La línea va del centro de la primera marca al de la última.
        Positioned(
          left: markerBox / 2,
          width: math.max(0, (count - 1) * (width + gap)),
          top: lineTop,
          height: 4,
          child: ColoredBox(color: style.palette.text.withValues(alpha: 0.18)),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(
                width: width,
                height: height,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (aboveGroups != null)
                      SizedBox(
                        height: aboveSize,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: style.gap * 0.4 * k,
                            ),
                            child: FitTextGroup(
                              items: aboveGroups[i],
                              scale: aboveScale,
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      height: markerBox,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SizedBox.square(
                          dimension: markerSize,
                          child: Center(child: marker(i)),
                        ),
                      ),
                    ),
                    SizedBox(height: markerGap),
                    Expanded(
                      child: FitTextGroup(items: groups[i], scale: scale),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class TimelineLayout extends StatelessWidget {
  const TimelineLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final TimelineSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final events = slide.events;
    final vertical = s.isNarrow && events.length > 4;
    Widget dot(int i) => Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.background,
        border: Border.all(color: p.primary, width: 8),
        boxShadow: c.template.panel == PanelLook.neon
            ? [BoxShadow(color: p.primary, blurRadius: 18)]
            : null,
      ),
    );
    List<FitTextItem> date(int i) => [
      FitTextItem(
        text: events[i].date,
        style: s.figure(size: 46 * s.typeScale),
        maxLines: 2,
      ),
    ];
    if (!vertical) {
      return ContentScaffold(
        c: c,
        title: slide.title,
        body: _Track(
          style: s,
          count: events.length,
          marker: dot,
          markerSize: 40,
          above: date,
          aboveHeight: 120,
          textOf: (i) => titleDetailItems(
            s,
            events[i].title,
            events[i].detail,
            titleFactor: 0.78,
          ),
        ),
      );
    }
    // En 4:3 con muchos hitos, la línea va de arriba abajo.
    return ContentScaffold(
      c: c,
      title: slide.title,
      body: LayoutBuilder(
        builder: (context, constraints) {
          const dateWidth = 260.0;
          final rowHeight = constraints.maxHeight / events.length;
          final textWidth = constraints.maxWidth - dateWidth - 100;
          final groups = [
            for (final e in events)
              titleDetailItems(s, e.title, e.detail, titleFactor: 0.72),
          ];
          final scale = FitTextGroup.sharedScale(
            context,
            groups,
            Size(textWidth, rowHeight - 8),
          );
          return Stack(
            children: [
              Positioned(
                left: dateWidth + 48,
                top: rowHeight / 2,
                bottom: rowHeight / 2,
                width: 4,
                child: ColoredBox(color: p.text.withValues(alpha: 0.18)),
              ),
              Column(
                children: [
                  for (var i = 0; i < events.length; i++)
                    SizedBox(
                      height: rowHeight,
                      child: Row(
                        children: [
                          SizedBox(
                            width: dateWidth,
                            child: FitText(
                              events[i].date,
                              style: s.figure(size: 40 * s.typeScale),
                              textAlign: TextAlign.end,
                              maxLines: 2,
                            ),
                          ),
                          SizedBox(width: 30, height: rowHeight),
                          dot(i),
                          const SizedBox(width: 30),
                          Expanded(
                            child: SizedBox(
                              height: rowHeight - 8,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FitTextGroup(
                                  items: groups[i],
                                  scale: scale,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class ConceptGridLayout extends StatelessWidget {
  const ConceptGridLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final ConceptGridSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final concepts = slide.concepts;
    final columns = switch (concepts.length) {
      <= 3 => concepts.length,
      4 => s.isNarrow ? 2 : 4,
      _ => 3,
    };
    final iconTints = [p.primary, p.secondary, p.accent];
    return ContentScaffold(
      c: c,
      title: slide.title,
      body: PanelGrid(
        style: s,
        count: concepts.length,
        columns: columns,
        headerHeight: 88,
        header: (i) {
          final tint = iconTints[i % iconTints.length];
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.16),
              ),
              child: Icon(
                CreationIcons.resolve(concepts[i].icon),
                size: 46,
                color: s.palette.accentText,
              ),
            ),
          );
        },
        textOf: (i) =>
            titleDetailItems(s, concepts[i].title, concepts[i].detail),
      ),
    );
  }
}
