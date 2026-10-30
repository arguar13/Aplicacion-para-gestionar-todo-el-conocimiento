import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_icons.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_style.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_layouts_content.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_layouts_hero.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_layouts_structured.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_parts.dart';

/// Los ocho diseños de F45: la cita a toda página, la cuadrícula de
/// imágenes, el mapa de conceptos, el cierre con preguntas, el panel de
/// cifras, el ciclo, la matriz de dos por dos y la definición. Como los de
/// F43, toman la forma de la plantilla —sus paneles, sus viñetas, sus
/// títulos— y nunca desbordan: todo texto se ajusta contra su lugar.

/// La cita a toda página: la frase enorme sobre un campo del primario, o
/// sobre su ilustración velada para que el texto se lea siempre en claro.
class FullQuoteLayout extends StatelessWidget {
  const FullQuoteLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final FullQuoteSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final pictured = slide.wantsIllustration;
    // Sobre la ilustración, el velo es oscuro y la letra blanca; sobre el
    // primario, la que se lee sobre él.
    final ink = pictured ? CreationContrast.light : p.onPrimary;
    final soft = ink.withValues(alpha: 0.82);
    final attribution = [
      slide.author,
      slide.source,
    ].where((t) => t.isNotEmpty).join(' · ');
    final quoteStyle = s.fonts.displayStyle(
      size: 96 * s.typeScale,
      color: ink,
      weight: s.fonts.displayItalic ? 500 : s.fonts.displayWeight,
      italic: true,
      height: 1.16,
      tracking: -0.01,
    );
    return SlideFrame(
      context: c,
      padded: false,
      footerColor: soft,
      child: Stack(
        children: [
          Positioned.fill(
            child: pictured
                ? SlideArt(context: c, radius: 0)
                : ColoredBox(color: p.primary),
          ),
          if (pictured)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x8C000000), Color(0xD9000000)],
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                s.marginX * 1.15,
                s.marginY,
                s.marginX * 1.15,
                s.marginY + s.footerHeight,
              ),
              child: Align(
                alignment: const Alignment(-1, 0.2),
                child: FitTextGroup(
                  minScale: 0.4,
                  items: [
                    FitTextItem(
                      text: slide.quote,
                      style: quoteStyle,
                      maxLines: 6,
                      // Las comillas, enormes, del acento (o del claro, sobre
                      // un acento que no se distingue del campo).
                      ornamentHeight: 150,
                      // A su tamaño natural y achicadas a su lugar: cada letra
                      // dibuja las comillas con otro alto.
                      ornament: (scale) => Align(
                        alignment: Alignment.bottomLeft,
                        child: SizedBox(
                          height: 150 * scale,
                          child: FittedBox(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              '“',
                              style: s.fonts.displayStyle(
                                size: 260,
                                color: pictured
                                    ? p.accent
                                    : CreationContrast.ensure(
                                        p.accent,
                                        p.primary,
                                        minimum: 2,
                                      ),
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (attribution.isNotEmpty)
                      FitTextItem(
                        text: '— $attribution',
                        style: s.body(
                          size: s.bodySize * 0.95,
                          color: soft,
                          weight: 600,
                        ),
                        gapBefore: s.gap * 1.2,
                        maxLines: 2,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La cuadrícula de imágenes: cada una en su cuadro, con su epígrafe abajo.
/// La primera lleva la ilustración de la diapositiva; las demás, la de
/// reserva de la plantilla con su ícono, cada una distinta.
class ImageGridLayout extends StatelessWidget {
  const ImageGridLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final ImageGridSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final images = slide.images;
    final columns = images.length == 4 && s.isNarrow ? 2 : images.length;
    final rows = (images.length / columns).ceil();
    return ContentScaffold(
      c: c,
      title: slide.title,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final gap = s.gap * 0.8;
          final cellWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns - 0.5;
          final cellHeight =
              (constraints.maxHeight - gap * (rows - 1)) / rows - 0.5;
          // El epígrafe tiene un cuarto del cuadro; la imagen, lo demás, sin
          // pasar de 4:3 (una imagen muy alta y angosta se ve mal).
          final double captionHeight = math.max(0, cellHeight * 0.26);
          final double pictureHeight = math.max(
            0,
            math.min(cellHeight - captionHeight - gap * 0.5, cellWidth * 0.75),
          );
          final groups = [
            for (final image in images)
              [
                FitTextItem(
                  text: image.caption,
                  style: s.body(size: s.smallSize * 1.05, color: s.muted),
                  maxLines: 3,
                ),
              ],
          ];
          final scale = FitTextGroup.sharedScale(
            context,
            groups,
            Size(cellWidth, captionHeight),
          );
          Widget cell(int i) => SizedBox(
            width: cellWidth,
            height: pictureHeight + gap * 0.5 + captionHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: pictureHeight,
                  child: i == 0
                      ? SlideArt(
                          context: c,
                          icon: CreationIcons.resolve(images[i].icon),
                        )
                      : CreationArt(
                          style: s.template.art,
                          palette: s.palette,
                          seed: c.seed + i * 13,
                          icon: CreationIcons.resolve(images[i].icon),
                          radius: s.template.radius,
                        ),
                ),
                SizedBox(height: gap * 0.5),
                Expanded(
                  child: FitTextGroup(items: groups[i], scale: scale),
                ),
              ],
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
                      i < math.min(images.length, (row + 1) * columns);
                      i++
                    ) ...[if (i > row * columns) SizedBox(width: gap), cell(i)],
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// El mapa de conceptos: la idea del centro en una píldora del primario y
/// sus ramas en dos columnas, una a cada lado, unidas al centro por curvas.
/// Así, con tres o con seis, ninguna rama pisa a otra.
class ConceptMapLayout extends StatelessWidget {
  const ConceptMapLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final ConceptMapSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final nodes = slide.nodes;
    final center = slide.center.isEmpty ? slide.title : slide.center;
    // Con título y centro distintos, el título arriba; si son lo mismo, el
    // centro lo dice.
    final title = slide.center.isEmpty ? '' : slide.title;
    final left = (nodes.length / 2).ceil();
    return ContentScaffold(
      c: c,
      title: title,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final hubWidth = width * 0.26;
          final sideWidth = (width - hubWidth) / 2 - s.gap * 1.6;
          final rows = left;
          final gap = s.gap * 0.6;
          final nodeHeight = (height - gap * (rows - 1)) / rows - 0.5;
          final insets = DeckPanel.insets(s);
          final groups = [
            for (final n in nodes)
              titleDetailItems(s, n.title, n.detail, titleFactor: 0.78),
          ];
          final textSize = Size(
            math.max(0, sideWidth - insets.horizontal),
            math.max(0, nodeHeight - insets.vertical),
          );
          final scale = FitTextGroup.sharedScale(context, groups, textSize);
          var needed = 0.0;
          for (final group in groups) {
            needed = math.max(
              needed,
              FitTextGroup.heightAt(context, group, textSize, scale),
            );
          }
          final boxHeight = math.min(
            nodeHeight,
            needed + insets.vertical + s.gap * 0.6,
          );
          // Los rectángulos de cada rama: la mitad a la izquierda, la otra a
          // la derecha, centradas en el alto.
          Rect place(int i) {
            final onLeft = i < left;
            final inColumn = onLeft ? left : nodes.length - left;
            final index = onLeft ? i : i - left;
            final columnHeight = inColumn * boxHeight + (inColumn - 1) * gap;
            final top = (height - columnHeight) / 2 + index * (boxHeight + gap);
            return Rect.fromLTWH(
              onLeft ? 0 : width - sideWidth,
              top,
              sideWidth,
              boxHeight,
            );
          }

          final hub = Rect.fromCenter(
            center: Offset(width / 2, height / 2),
            width: hubWidth,
            height: math.min(height * 0.42, hubWidth * 0.62),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BranchesPainter(
                    hub: hub,
                    nodes: [for (var i = 0; i < nodes.length; i++) place(i)],
                    color: p.primary.withValues(alpha: 0.55),
                    width: 5,
                  ),
                ),
              ),
              for (var i = 0; i < nodes.length; i++)
                Positioned.fromRect(
                  rect: place(i),
                  child: DeckPanel(
                    style: s,
                    index: i,
                    child: FitTextGroup(items: groups[i], scale: scale),
                  ),
                ),
              Positioned.fromRect(
                rect: hub,
                child: Container(
                  padding: EdgeInsets.all(s.gap * 0.7),
                  decoration: BoxDecoration(
                    color: p.primary,
                    borderRadius: BorderRadius.circular(
                      math.min(hub.height / 2, s.template.radius * 2 + 24),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: FitText(
                    center,
                    style: s.heading(color: p.onPrimary),
                    maxLines: 3,
                    minScale: 0.4,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BranchesPainter extends CustomPainter {
  const _BranchesPainter({
    required this.hub,
    required this.nodes,
    required this.color,
    required this.width,
  });

  final Rect hub;
  final List<Rect> nodes;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = color;
    for (final node in nodes) {
      final onLeft = node.center.dx < hub.center.dx;
      final from = Offset(onLeft ? hub.left : hub.right, hub.center.dy);
      final to = Offset(onLeft ? node.right : node.left, node.center.dy);
      final middle = (from.dx + to.dx) / 2;
      canvas
        ..drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..cubicTo(middle, from.dy, middle, to.dy, to.dx, to.dy),
          paint,
        )
        ..drawCircle(to, width * 1.6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_BranchesPainter oldDelegate) =>
      oldDelegate.hub != hub ||
      oldDelegate.color != color ||
      oldDelegate.width != width ||
      oldDelegate.nodes.length != nodes.length ||
      !Iterable<int>.generate(
        nodes.length,
      ).every((i) => oldDelegate.nodes[i] == nodes[i]);
}

/// El cierre con preguntas: a la izquierda el título con un signo de
/// pregunta enorme del acento; a la derecha, cada pregunta en su panel,
/// numerada.
class QuestionsLayout extends StatelessWidget {
  const QuestionsLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final QuestionsSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final mark = CreationContrast.ensureOnAll(p.accent, [
      p.background,
    ], minimum: 3);
    return SlideFrame(
      context: c,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FitTextGroup(
                items: [
                  FitTextItem(
                    text: '?',
                    style: s.fonts.displayStyle(
                      size: 240,
                      color: mark,
                      height: 1,
                    ),
                    maxLines: 1,
                  ),
                  ...heroText(
                    c,
                    title: s.titleCase(slide.title),
                    subtitle: slide.subtitle,
                    titleSize: s.coverTitleSize * 0.7,
                  ),
                ].where((item) => item.text.isNotEmpty).toList(),
              ),
            ),
          ),
          SizedBox(width: s.gap * 1.8),
          Expanded(
            flex: 6,
            child: PanelGrid(
              style: s,
              count: slide.questions.length,
              columns: 1,
              textOf: (i) => [
                FitTextItem(
                  text: slide.questions[i],
                  style: s.body(size: s.bodySize * 1.04, weight: 500),
                  leadingWidth: s.bodySize * 1.9,
                  leading: (scale) => Text(
                    '${i + 1}'.padLeft(2, '0'),
                    maxLines: 1,
                    style: s.figure(size: s.bodySize * 0.9 * scale),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El panel de cifras: cada cifra en su tarjeta, enorme, con qué es y su
/// detalle debajo.
class StatGridLayout extends StatelessWidget {
  const StatGridLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final StatGridSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final stats = slide.stats;
    final columns = stats.length == 4 && s.isNarrow ? 2 : stats.length;
    return ContentScaffold(
      c: c,
      title: slide.title,
      body: PanelGrid(
        style: s,
        count: stats.length,
        columns: columns,
        headerHeight: 150,
        header: (i) => Text(
          stats[i].value,
          maxLines: 1,
          style: s.figure(size: 130 * s.typeScale, weight: 800),
        ),
        textOf: (i) => [
          if (stats[i].label.isNotEmpty)
            FitTextItem(
              text: stats[i].label,
              style: s.heading(size: s.headingSize * 0.78),
              maxLines: 3,
            ),
          if (stats[i].detail.isNotEmpty)
            FitTextItem(
              text: stats[i].detail,
              style: s.small(),
              gapBefore: stats[i].label.isEmpty ? 0 : s.gap * 0.4,
            ),
        ],
      ),
    );
  }
}

/// El ciclo: una rueda con un número por paso y flechas que van de uno al
/// siguiente —y del último al primero—, con lo que gira en el medio; al
/// lado, cada paso con su número, su nombre y su detalle.
class CycleLayout extends StatelessWidget {
  const CycleLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final CycleSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final steps = slide.steps;
    return ContentScaffold(
      c: c,
      title: slide.title,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wheel = math.min(
            constraints.maxHeight,
            constraints.maxWidth * (s.isNarrow ? 0.42 : 0.4),
          );
          const badge = 96.0;
          return Row(
            children: [
              SizedBox.square(
                dimension: wheel,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final size = box.biggest.shortestSide;
                    final radius = size / 2 - badge / 2;
                    final middle = Offset(size / 2, size / 2);
                    Offset at(int i) =>
                        middle +
                        Offset(
                              math.cos(
                                -math.pi / 2 + i * 2 * math.pi / steps.length,
                              ),
                              math.sin(
                                -math.pi / 2 + i * 2 * math.pi / steps.length,
                              ),
                            ) *
                            radius;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CyclePainter(
                              count: steps.length,
                              radius: radius,
                              gapAngle: (badge * 0.7) / radius,
                              color: p.primary.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        if (slide.center.isNotEmpty)
                          Positioned.fromRect(
                            rect: Rect.fromCircle(
                              center: middle,
                              radius: math.max(0, radius - badge * 0.9),
                            ),
                            child: Center(
                              child: FitText(
                                slide.center,
                                style: s.heading(
                                  size: s.headingSize * 0.9,
                                  color: p.accentText,
                                ),
                                maxLines: 3,
                                minScale: 0.3,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        for (var i = 0; i < steps.length; i++)
                          Positioned.fromRect(
                            rect: Rect.fromCenter(
                              center: at(i),
                              width: badge,
                              height: badge,
                            ),
                            child: NumberBadge(
                              style: s,
                              label: '${i + 1}',
                              size: badge,
                              color: s.tint(i),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(width: s.gap * 1.6),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FitTextGroup(
                    items: [
                      for (var i = 0; i < steps.length; i++) ...[
                        FitTextItem(
                          text: steps[i].title,
                          style: s.heading(size: s.headingSize * 0.8),
                          gapBefore: i == 0 ? 0 : s.gap * 0.55,
                          maxLines: 2,
                          leadingWidth: s.headingSize * 1.3,
                          leading: (scale) => Text(
                            '${i + 1}'.padLeft(2, '0'),
                            maxLines: 1,
                            style: s.figure(
                              size: s.headingSize * 0.7 * scale,
                              color: CreationContrast.ensureOnAll(s.tint(i), [
                                p.background,
                              ]),
                            ),
                          ),
                        ),
                        if (steps[i].detail.isNotEmpty)
                          FitTextItem(
                            text: steps[i].detail,
                            style: s.small(),
                            gapBefore: s.gap * 0.15,
                            leadingWidth: s.headingSize * 1.3,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CyclePainter extends CustomPainter {
  const _CyclePainter({
    required this.count,
    required this.radius,
    required this.gapAngle,
    required this.color,
  });

  final int count;
  final double radius;

  /// Cuánto ángulo se deja libre alrededor de cada número.
  final double gapAngle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final step = 2 * math.pi / count;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6
      ..color = color;
    final head = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final start = -math.pi / 2 + i * step + gapAngle / 2;
      final double sweep = math.max(0, step - gapAngle);
      canvas.drawArc(rect, start, sweep, false, line);
      // La punta de la flecha, al final del arco, mirando hacia donde gira.
      final end = start + sweep;
      final tip = center + Offset(math.cos(end), math.sin(end)) * radius;
      final tangent = Offset(-math.sin(end), math.cos(end));
      final normal = Offset(math.cos(end), math.sin(end));
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx + tangent.dx * 18, tip.dy + tangent.dy * 18)
          ..lineTo(
            tip.dx - tangent.dx * 6 + normal.dx * 14,
            tip.dy - tangent.dy * 6 + normal.dy * 14,
          )
          ..lineTo(
            tip.dx - tangent.dx * 6 - normal.dx * 14,
            tip.dy - tangent.dy * 6 - normal.dy * 14,
          )
          ..close(),
        head,
      );
    }
  }

  @override
  bool shouldRepaint(_CyclePainter oldDelegate) =>
      oldDelegate.count != count ||
      oldDelegate.radius != radius ||
      oldDelegate.gapAngle != gapAngle ||
      oldDelegate.color != color;
}

/// La matriz de dos por dos: los cuatro cuadrantes en sus paneles, con el
/// nombre del eje vertical a la izquierda y el del horizontal abajo, cada
/// uno con su flecha.
class MatrixLayout extends StatelessWidget {
  const MatrixLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final MatrixSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final axisSize = s.smallSize * 2;
    final axisStyle = s.kicker(color: s.muted);
    final grid = PanelGrid(
      style: s,
      count: slide.quadrants.length,
      columns: 2,
      textOf: (i) => columnItems(
        s,
        slide.quadrants[i],
        headingColor: CreationContrast.ensureOnAll(s.tint(i), [
          p.background,
          p.surfaceOnBackground,
        ]),
        markColor: s.tint(i),
      ),
    );
    // El grueso del lugar de cada flecha: la punta mide 20 de ancho.
    const axisThickness = 24.0;
    Widget axisLine({required bool vertical}) => CustomPaint(
      painter: _AxisPainter(
        vertical: vertical,
        color: p.text.withValues(alpha: 0.4),
      ),
    );
    return ContentScaffold(
      c: c,
      title: slide.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (slide.yAxis.isNotEmpty) ...[
                  // El nombre, girado, y la flecha pegada a la matriz.
                  SizedBox(
                    width: axisSize,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Center(
                        child: FitText(
                          slide.yAxis.toUpperCase(),
                          style: axisStyle,
                          maxLines: 1,
                          minScale: 0.4,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: axisThickness,
                    child: axisLine(vertical: true),
                  ),
                  SizedBox(width: s.gap * 0.5),
                ],
                Expanded(child: grid),
              ],
            ),
          ),
          if (slide.xAxis.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: s.gap * 0.5,
                left: slide.yAxis.isEmpty
                    ? 0
                    : axisSize + axisThickness + s.gap * 0.5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: axisThickness,
                    child: axisLine(vertical: false),
                  ),
                  SizedBox(
                    height: axisSize,
                    child: Center(
                      child: FitText(
                        slide.xAxis.toUpperCase(),
                        style: axisStyle,
                        maxLines: 1,
                        minScale: 0.4,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AxisPainter extends CustomPainter {
  const _AxisPainter({required this.vertical, required this.color});

  final bool vertical;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3;
    final from = vertical
        ? Offset(size.width / 2, size.height)
        : Offset(0, size.height / 2);
    final to = vertical
        ? Offset(size.width / 2, 0)
        : Offset(size.width, size.height / 2);
    canvas.drawLine(from, to, paint);
    // La punta: hacia arriba o hacia la derecha, adonde crece.
    final back = vertical ? const Offset(0, 1) : const Offset(-1, 0);
    final side = vertical ? const Offset(1, 0) : const Offset(0, 1);
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(
          to.dx + back.dx * 18 + side.dx * 10,
          to.dy + back.dy * 18 + side.dy * 10,
        )
        ..lineTo(
          to.dx + back.dx * 18 - side.dx * 10,
          to.dy + back.dy * 18 - side.dy * 10,
        )
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_AxisPainter oldDelegate) =>
      oldDelegate.vertical != vertical || oldDelegate.color != color;
}

/// La definición: el término enorme a la izquierda, con su rótulo arriba;
/// un filete del primario; y a la derecha qué es y, si lo hay, un ejemplo
/// con la barra del acento.
class DefinitionLayout extends StatelessWidget {
  const DefinitionLayout({required this.c, required this.slide, super.key});

  final SlideContext c;
  final DefinitionSlide slide;

  @override
  Widget build(BuildContext context) {
    final s = c.style;
    final p = s.palette;
    final exampleStyle = s.fonts.displayItalic
        ? s.fonts.displayStyle(
            size: s.bodySize * 0.96,
            color: s.muted,
            weight: 400,
            italic: true,
            height: 1.3,
            tracking: 0,
          )
        : s.body(size: s.bodySize * 0.94, color: s.muted);
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
                  title: s.titleCase(slide.term),
                  kicker: slide.kicker,
                  titleSize: s.coverTitleSize * 0.82,
                  titleLines: 3,
                ),
              ),
            ),
          ),
          Container(
            width: 6,
            height: s.canvas.height * 0.42,
            margin: EdgeInsets.symmetric(horizontal: s.gap * 1.4),
            color: p.primary,
          ),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FitTextGroup(
                items: [
                  FitTextItem(
                    text: slide.definition,
                    style: s.body(size: s.bodySize * 1.12),
                  ),
                  if (slide.example.isNotEmpty)
                    FitTextItem(
                      text: slide.example,
                      style: exampleStyle,
                      gapBefore: s.gap * 1.2,
                      leadingWidth: s.gap * 1.1,
                      leading: (scale) => Container(
                        width: 8 * scale,
                        height: s.bodySize * 1.3 * scale,
                        color: p.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El color de cada cosa de una serie (los pasos de un ciclo, los
/// cuadrantes): los tres de la paleta, por turno.
extension on DeckStyle {
  Color tint(int index) =>
      [palette.primary, palette.secondary, palette.accent][index % 3];
}
