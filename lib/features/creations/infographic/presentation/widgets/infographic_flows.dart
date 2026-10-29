import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_icons.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style_spec.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_cards.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_grids.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_parts.dart';

/// Las composiciones con recorrido (F43): zigzag, línea de tiempo, pirámide,
/// radial, mapa de conceptos y comparación. Como las de grilla, reciben el
/// lugar del cuerpo y lo reparten sin que nada se salga.

/// El punto del borde de [rect] por donde pasa la recta que va de su centro
/// a [toward]: para que una línea llegue hasta la caja y no se meta abajo.
Offset edgePoint(Rect rect, Offset toward) {
  final center = rect.center;
  final d = toward - center;
  if (d == Offset.zero) return center;
  final sx = d.dx == 0 ? double.infinity : (rect.width / 2) / d.dx.abs();
  final sy = d.dy == 0 ? double.infinity : (rect.height / 2) / d.dy.abs();
  return center + d * math.min(1, math.min(sx, sy));
}

/// [n] cajas de [card] alrededor del centro de [area], sobre una elipse, sin
/// pisar [hub] ni pisarse entre ellas: si no entran, se achican de a poco.
List<Rect> ellipseLayout({
  required int n,
  required Size area,
  required Size card,
  required Rect hub,
  required double gap,
}) {
  final center = area.center(Offset.zero);
  final start = switch (n) {
    2 => area.width >= area.height ? math.pi : -math.pi / 2,
    4 => -math.pi * 3 / 4,
    _ => -math.pi / 2,
  };
  var size = card;
  var rects = <Rect>[];
  for (var attempt = 0; attempt < 10; attempt++) {
    final double rx = math.max(0, area.width / 2 - size.width / 2);
    final double ry = math.max(0, area.height / 2 - size.height / 2);
    rects = [
      for (var i = 0; i < n; i++)
        Rect.fromCenter(
          center:
              center +
              Offset(
                math.cos(start + 2 * math.pi * i / n) * rx,
                math.sin(start + 2 * math.pi * i / n) * ry,
              ),
          width: size.width,
          height: size.height,
        ),
    ];
    var clear = rects.every((r) => !r.overlaps(hub.inflate(gap)));
    for (var i = 0; clear && i < n; i++) {
      for (var j = i + 1; clear && j < n; j++) {
        if (rects[i].overlaps(rects[j].inflate(gap / 2))) clear = false;
      }
    }
    if (clear) return rects;
    size = size * 0.9;
  }
  return rects;
}

/// Lo grande de cada paso del zigzag: la ilustración, el ícono, el número o
/// la cifra, en un círculo.
class _ZigMedia extends StatelessWidget {
  const _ZigMedia({
    required this.c,
    required this.block,
    required this.index,
    required this.side,
  });

  final InfoContext c;
  final InfographicBlock block;
  final int index;
  final double side;

  @override
  Widget build(BuildContext context) {
    final style = c.style;
    final tint = style.tint(index);
    switch (block) {
      case StatBlock(:final value):
        return Container(
          width: side,
          height: side,
          padding: EdgeInsets.all(side * 0.16),
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Center(
            child: FitText(
              value,
              style: style.figure(
                size: side * 0.3,
                color: CreationContrast.readableOn(tint),
              ),
              maxLines: 1,
              minScale: 0.2,
              textAlign: TextAlign.center,
            ),
          ),
        );
      case StepBlock():
        return InfoNumberBadge(
          style: style,
          label: '${index + 1}',
          size: side,
          color: tint,
        );
      default:
        final art =
            c.spec.isIllustrated ||
            block.wantsIllustration ||
            style.iconLook == InfographicIconLook.none;
        if (art) {
          return SizedBox.square(
            dimension: side,
            child: InfoArt(
              context: c,
              reference: block.illustrationRef,
              seed: c.seed + index * 13,
              icon: blockIcon(block),
              radius: side / 2,
            ),
          );
        }
        return InfoIcon(
          style: style,
          icon: blockIcon(block),
          size: side,
          tint: tint,
          surface: style.palette.background,
        );
    }
  }
}

InfoMediaKind? _none(InfographicBlock block) => InfoMediaKind.none;

/// Zigzag: cada bloque con algo grande (su ilustración, su ícono, su cifra)
/// que va de un lado y del otro, unidos por una línea que serpentea.
class ZigzagComposition extends StatelessWidget {
  const ZigzagComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final n = blocks.length;
    final style = c.style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final gap = style.gap;
        final placed = <PlacedBlock>[];
        final medias = <(int, Rect)>[];
        if (style.isLandscape) {
          final width = (area.width - gap * (n - 1)) / n - 0.5;
          final side = math.min(width * 0.78, area.height * 0.34);
          final cardHeight = area.height - side - gap * 1.4;
          for (var i = 0; i < n; i++) {
            final left = i * (width + gap);
            final mediaTop = i.isEven ? 0.0 : area.height - side;
            final cardTop = i.isEven ? side + gap * 1.4 : 0.0;
            placed.add((
              index: i,
              rect: Rect.fromLTWH(left, cardTop, width, cardHeight),
            ));
            if (!InfoCards.isSpecial(blocks[i])) {
              medias.add((
                i,
                Rect.fromLTWH(left + (width - side) / 2, mediaTop, side, side),
              ));
            }
          }
        } else {
          final height = (area.height - gap * (n - 1)) / n - 0.5;
          final side = math.min(height, area.width * 0.3);
          for (var i = 0; i < n; i++) {
            final top = i * (height + gap);
            if (InfoCards.isSpecial(blocks[i])) {
              placed.add((
                index: i,
                rect: Rect.fromLTWH(0, top, area.width, height),
              ));
              continue;
            }
            final mediaLeft = i.isEven ? 0.0 : area.width - side;
            final cardLeft = i.isEven ? side + gap * 1.4 : 0.0;
            placed.add((
              index: i,
              rect: Rect.fromLTWH(
                cardLeft,
                top,
                area.width - side - gap * 1.4,
                height,
              ),
            ));
            medias.add((
              i,
              Rect.fromLTWH(mediaLeft, top + (height - side) / 2, side, side),
            ));
          }
        }
        final path = [for (final (_, r) in medias) r.center];
        const options = InfoCardOptions(mediaOf: _none, valuesOutside: true);
        // Cada caja mide lo que su texto, a la altura de su círculo.
        final mediaOf = {for (final (i, r) in medias) i: r};
        final fitted = fitToContent(
          context,
          c,
          placed,
          options: options,
          focus: (p) => mediaOf[p.index]?.center ?? p.rect.center,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: InfoLinesPainter(
                  paths: [path],
                  color: style.palette.muted.withValues(alpha: 0.55),
                  look: c.spec.connector == InfoConnectorLook.solid
                      ? InfoConnectorLook.dashed
                      : c.spec.connector,
                  width: 5,
                  seed: c.seed,
                ),
              ),
            ),
            PlacedCards(c: c, placed: fitted, options: options),
            for (final (i, rect) in medias)
              Positioned.fromRect(
                rect: rect,
                child: _ZigMedia(
                  c: c,
                  block: blocks[i],
                  index: i,
                  side: rect.width,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// La línea de tiempo: una línea con un punto por hito y cada bloque de un
/// lado y del otro; acostada en horizontal, parada en vertical.
class TimelineComposition extends StatelessWidget {
  const TimelineComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final n = blocks.length;
    final style = c.style;
    final p = style.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final gap = style.gap;
        const dot = 34.0;
        final stem = gap * 1.2;
        final placed = <PlacedBlock>[];
        final dots = <Offset>[];
        final stems = <List<Offset>>[];
        final List<Offset> line;
        if (style.isLandscape) {
          final y = area.height / 2;
          line = [Offset(0, y), Offset(area.width, y)];
          final slot = area.width / n;
          // Las del mismo lado no se tocan, tampoco las de las puntas, que se
          // corren hacia adentro para no salirse.
          final width = math.min(
            math.min(slot * 2 - gap, (slot * 2.5 - gap) / 1.5),
            area.width * 0.34,
          );
          final height = y - dot / 2 - stem;
          for (var i = 0; i < n; i++) {
            final x = slot * (i + 0.5);
            dots.add(Offset(x, y));
            final left = math.max<double>(
              0,
              math.min(x - width / 2, area.width - width),
            );
            final top = i.isEven ? 0.0 : y + dot / 2 + stem;
            final rect = Rect.fromLTWH(left, top, width, height - 0.5);
            placed.add((index: i, rect: rect));
            stems.add([
              Offset(x, i.isEven ? rect.bottom : rect.top),
              Offset(x, i.isEven ? y - dot / 2 : y + dot / 2),
            ]);
          }
        } else {
          final x = area.width / 2;
          line = [Offset(x, 0), Offset(x, area.height)];
          final slot = area.height / n;
          final height = math.min(
            math.min(slot * 2 - gap, (slot * 2.5 - gap) / 1.5),
            area.height * 0.36,
          );
          final width = x - dot / 2 - stem;
          for (var i = 0; i < n; i++) {
            final y = slot * (i + 0.5);
            dots.add(Offset(x, y));
            final top = math.max<double>(
              0,
              math.min(y - height / 2, area.height - height),
            );
            final left = i.isEven ? 0.0 : x + dot / 2 + stem;
            final rect = Rect.fromLTWH(left, top, width - 0.5, height);
            placed.add((index: i, rect: rect));
            stems.add([
              Offset(i.isEven ? rect.right : rect.left, y),
              Offset(i.isEven ? x - dot / 2 : x + dot / 2, y),
            ]);
          }
        }
        final glow = c.spec.panel == InfoPanelLook.neon;
        // Los hitos ya traen su fecha arriba; lo demás, su número.
        final options = InfoCardOptions(
          mediaOf: (b) =>
              b is FactBlock || b is ConceptBlock ? InfoMediaKind.badge : null,
        );
        // Cada caja mide lo que su texto, pegada a su punto de la línea: el
        // lado que da a la línea no se mueve, así el palito sigue llegando.
        final fitted = fitToContent(
          context,
          c,
          placed,
          options: options,
          focus: (p) => dots[p.index],
        );
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: InfoLinesPainter(
                  paths: [line, ...stems],
                  color: p.text.withValues(alpha: 0.28),
                  look: c.spec.connector,
                  width: 5,
                  seed: c.seed,
                ),
              ),
            ),
            PlacedCards(c: c, placed: fitted, options: options),
            for (final (i, center) in dots.indexed)
              Positioned(
                left: center.dx - dot / 2,
                top: center.dy - dot / 2,
                width: dot,
                height: dot,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.background,
                    border: Border.all(color: style.tint(i), width: 8),
                    boxShadow: glow
                        ? [BoxShadow(color: style.tint(i), blurRadius: 18)]
                        : null,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// La pirámide: un nivel por bloque, del más angosto arriba al más ancho
/// abajo, cada uno con su número, y el texto de cada nivel a su derecha,
/// unido por una línea.
class PyramidComposition extends StatelessWidget {
  const PyramidComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final n = blocks.length;
    final style = c.style;
    final p = style.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final gap = style.gap * 0.45;
        final pyramidWidth = area.width * (style.isPortrait ? 0.42 : 0.4);
        final bandHeight = (area.height - gap * (n - 1)) / n - 0.5;
        final textLeft = pyramidWidth + style.gap * 2.2;
        final textSize = Size(
          math.max(0, area.width - textLeft),
          math.max(0, bandHeight),
        );
        final ink = InfoCardInk.of(style, 0, InfoCardLook.open);
        final groups = [
          for (final b in blocks)
            if (InfoCards.isSpecial(b))
              [
                FitTextItem(
                  text: b.headline,
                  style: style.heading(color: ink.text),
                  maxLines: 3,
                ),
              ]
            else
              // Los textos de siempre, pero alineados a la izquierda: van
              // pegados a la línea que sale de su nivel.
              [
                for (final item in InfoCards.textItems(
                  c,
                  b,
                  ink: ink,
                  look: InfoCardLook.open,
                  includeValue: true,
                ))
                  FitTextItem(
                    text: item.text,
                    style: item.style,
                    gapBefore: item.gapBefore,
                    maxLines: item.maxLines,
                  ),
              ],
        ];
        var scale = 1.0;
        for (final group in groups) {
          scale = math.min(
            scale,
            InfoCards.solve(context, group, textSize).scale,
          );
        }
        final colors = [
          for (var i = 0; i < n; i++)
            Color.lerp(p.primary, p.secondary, n == 1 ? 0 : i / (n - 1))!,
        ];
        final bands = [
          for (var i = 0; i < n; i++)
            _Band(
              top: i * (bandHeight + gap),
              height: bandHeight,
              topWidth: pyramidWidth * i / n,
              bottomWidth: pyramidWidth * (i + 1) / n,
            ),
        ];
        final badge = math.min(style.iconSize * 0.8, bandHeight * 0.5);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PyramidPainter(
                  bands: bands,
                  colors: colors,
                  center: pyramidWidth / 2,
                  outline: c.spec.panel == InfoPanelLook.sticker
                      ? const Color(0xFF000000)
                      : null,
                  connector: p.text.withValues(alpha: 0.3),
                  textLeft: textLeft - style.gap * 0.6,
                ),
              ),
            ),
            for (var i = 0; i < n; i++)
              Positioned(
                left: pyramidWidth / 2 - badge / 2,
                // En la punta, el número va abajo, donde hay ancho.
                top:
                    bands[i].top +
                    (i == 0 ? bandHeight * 0.62 : bandHeight / 2) -
                    badge / 2,
                width: badge,
                height: badge,
                child: Center(
                  child: FittedBox(
                    child: Text(
                      '${i + 1}',
                      style: style.figure(
                        size: badge * 0.8,
                        color: CreationContrast.readableOn(colors[i]),
                      ),
                    ),
                  ),
                ),
              ),
            for (var i = 0; i < n; i++)
              Positioned(
                left: textLeft,
                top: bands[i].top,
                width: textSize.width,
                height: textSize.height,
                child: Semantics(
                  label: blockSemantics(blocks[i]),
                  container: true,
                  child: ExcludeSemantics(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FitTextGroup(items: groups[i], scale: scale),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

@immutable
class _Band {
  const _Band({
    required this.top,
    required this.height,
    required this.topWidth,
    required this.bottomWidth,
  });

  final double top;
  final double height;
  final double topWidth;
  final double bottomWidth;
}

class _PyramidPainter extends CustomPainter {
  const _PyramidPainter({
    required this.bands,
    required this.colors,
    required this.center,
    required this.connector,
    required this.textLeft,
    this.outline,
  });

  final List<_Band> bands;
  final List<Color> colors;
  final double center;
  final Color connector;
  final double textLeft;
  final Color? outline;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, band) in bands.indexed) {
      final path = Path()
        ..addPolygon([
          Offset(center - band.topWidth / 2, band.top),
          Offset(center + band.topWidth / 2, band.top),
          Offset(center + band.bottomWidth / 2, band.top + band.height),
          Offset(center - band.bottomWidth / 2, band.top + band.height),
        ], true);
      canvas.drawPath(path, Paint()..color = colors[i]);
      if (outline != null) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeJoin = StrokeJoin.round
            ..color = outline!,
        );
      }
      // La línea del nivel a su texto, desde el costado del medio.
      final y = band.top + band.height / 2;
      final from = center + (band.topWidth + band.bottomWidth) / 4 + 12;
      canvas
        ..drawLine(
          Offset(from, y),
          Offset(textLeft, y),
          Paint()
            ..strokeWidth = 3
            ..color = connector,
        )
        ..drawCircle(Offset(textLeft, y), 7, Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(_PyramidPainter oldDelegate) =>
      oldDelegate.bands != bands ||
      oldDelegate.colors != colors ||
      oldDelegate.center != center;
}

/// El centro de un radial: un círculo del color del estilo con un ícono.
class _Hub extends StatelessWidget {
  const _Hub({required this.c, required this.size});

  final InfoContext c;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = c.style;
    final p = style.palette;
    if (c.spec.isIllustrated) {
      return ClipOval(
        child: InfoArt(
          context: c,
          reference: c.sheet.illustrationRef,
          seed: c.seed + 101,
          icon: CreationIcons.resolve('hub'),
          radius: size / 2,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.primary,
        border: Border.all(
          color: Color.alphaBlend(
            p.background.withValues(alpha: 0.7),
            p.primary,
          ),
          width: size * 0.06,
        ),
        boxShadow: c.spec.panel == InfoPanelLook.neon
            ? [BoxShadow(color: p.primary, blurRadius: 40)]
            : null,
      ),
      child: Icon(
        CreationIcons.resolve('hub'),
        size: size * 0.42,
        color: p.onPrimary,
      ),
    );
  }
}

/// Radial: un centro y los bloques alrededor, cada uno unido al centro por
/// un rayo.
class RadialComposition extends StatelessWidget {
  const RadialComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final n = blocks.length;
    final style = c.style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        // En vertical el centro es más chico: los bloques de los costados
        // necesitan el ancho.
        final hubSide = area.shortestSide * (style.isPortrait ? 0.2 : 0.26);
        final hub = Rect.fromCenter(
          center: area.center(Offset.zero),
          width: hubSide,
          height: hubSide,
        );
        final few = n <= 4;
        final card = style.isLandscape
            ? Size(
                area.width * (few ? 0.3 : 0.27),
                area.height * (few ? 0.4 : 0.31),
              )
            : style.isPortrait
            ? Size(area.width * 0.46, area.height * (few ? 0.27 : 0.21))
            : Size(area.width * 0.33, area.height * (few ? 0.32 : 0.26));
        final rects = ellipseLayout(
          n: n,
          area: area,
          card: card,
          hub: hub,
          gap: style.gap * 0.6,
        );
        // Cada caja mide lo que su texto, del lado que mira al centro.
        final placed = fitToContent(context, c, [
          for (var i = 0; i < n; i++) (index: i, rect: rects[i]),
        ], focus: (p) => hub.center);
        final spokes = [
          for (final p in placed)
            [edgePoint(hub, p.rect.center), edgePoint(p.rect, hub.center)],
        ];
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: InfoLinesPainter(
                  paths: spokes,
                  color: style.palette.text.withValues(alpha: 0.3),
                  look: c.spec.connector,
                  width: 5,
                  seed: c.seed,
                ),
              ),
            ),
            Positioned.fromRect(
              rect: hub,
              child: _Hub(c: c, size: hubSide),
            ),
            PlacedCards(c: c, placed: placed),
          ],
        );
      },
    );
  }
}

/// El mapa de conceptos: el primer bloque en el centro, destacado, y los
/// demás alrededor como nodos unidos a él por líneas curvas.
class ConceptMapComposition extends StatelessWidget {
  const ConceptMapComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final n = blocks.length;
    final style = c.style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final node = style.isLandscape
            ? Size(area.width * 0.25, area.height * 0.27)
            : style.isPortrait
            ? Size(area.width * 0.44, area.height * 0.18)
            : Size(area.width * 0.31, area.height * 0.22);
        final center = Rect.fromCenter(
          center: area.center(Offset.zero),
          width: node.width * 1.15,
          height: node.height * 1.15,
        );
        final rects = n <= 1
            ? <Rect>[]
            : ellipseLayout(
                n: n - 1,
                area: area,
                card: node,
                hub: center,
                gap: style.gap * 0.6,
              );
        final options = InfoCardOptions(
          lookOf: (i) => i == 0 && !InfoCards.isSpecial(blocks[0])
              ? InfoCardLook.inverse
              : InfoCardLook.panel,
        );
        // Cada nodo mide lo que su texto, del lado que mira al centro.
        final placed = fitToContent(
          context,
          c,
          [
            (index: 0, rect: center),
            for (var i = 1; i < n; i++) (index: i, rect: rects[i - 1]),
          ],
          options: options,
          focus: (p) => center.center,
        );
        final hub = placed.first.rect;
        final links = <List<Offset>>[];
        for (final (i, p) in placed.skip(1).indexed) {
          final r = p.rect;
          final from = edgePoint(hub, r.center);
          final to = edgePoint(r, hub.center);
          // Una curva suave: el punto de control, corrido hacia un costado.
          final mid = Offset.lerp(from, to, 0.5)!;
          final d = to - from;
          final normal = d.distance == 0
              ? Offset.zero
              : Offset(-d.dy, d.dx) / d.distance;
          final bend = normal * d.distance * (i.isEven ? 0.18 : -0.18);
          links.add([from, mid + bend, to]);
        }
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: InfoLinesPainter(
                  paths: links,
                  color: style.palette.primary.withValues(alpha: 0.5),
                  look: c.spec.connector,
                  width: 5,
                  seed: c.seed,
                ),
              ),
            ),
            PlacedCards(c: c, placed: placed, options: options),
          ],
        );
      },
    );
  }
}

/// La comparación: la comparación principal en grande, con sus dos lados
/// frente a frente, y lo demás en una fila abajo. Sin una comparación, los
/// bloques se reparten en dos columnas enfrentadas.
class ComparisonComposition extends StatelessWidget {
  const ComparisonComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final style = c.style;
    final main = blocks.indexWhere((b) => b is ComparisonBlock);
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final gap = style.gap;
        if (main < 0) return _facing(area, gap);
        final others = [
          for (var i = 0; i < blocks.length; i++)
            if (i != main) i,
        ];
        final perRow = style.isLandscape ? math.max(1, others.length) : 2;
        final rows = (others.length / perRow).ceil();
        final restHeight = others.isEmpty
            ? 0.0
            : area.height * (style.isLandscape ? 0.3 : 0.18 * rows + 0.06);
        final mainHeight =
            area.height - restHeight - (others.isEmpty ? 0 : gap);
        final placed = <PlacedBlock>[
          (
            index: main,
            rect: Rect.fromLTWH(0, 0, area.width, mainHeight - 0.5),
          ),
        ];
        if (others.isNotEmpty) {
          final width = (area.width - gap * (perRow - 1)) / perRow - 0.5;
          final height = (restHeight - gap * (rows - 1)) / rows - 0.5;
          for (final (k, i) in others.indexed) {
            placed.add((
              index: i,
              rect: Rect.fromLTWH(
                (k % perRow) * (width + gap),
                mainHeight + gap + (k ~/ perRow) * (height + gap),
                width,
                height,
              ),
            ));
          }
        }
        // La comparación principal, con la letra más grande: tiene casi
        // toda la lámina.
        return PlacedCards(
          c: c,
          placed: placed,
          options: InfoCardOptions(boostOf: (i) => i == main ? 1.3 : 1),
        );
      },
    );
  }

  /// Sin comparación: la primera mitad de los bloques a la izquierda, la
  /// otra a la derecha, y un «VS» en el medio.
  Widget _facing(Size area, double gap) {
    final style = c.style;
    final n = c.blocks.length;
    final leftCount = (n / 2).ceil();
    final vs = math.min(style.iconSize * 1.1, area.width * 0.12);
    final width = (area.width - vs - gap * 2) / 2 - 0.5;
    final placed = <PlacedBlock>[];
    for (var side = 0; side < 2; side++) {
      final indices = side == 0
          ? [for (var i = 0; i < leftCount; i++) i]
          : [for (var i = leftCount; i < n; i++) i];
      if (indices.isEmpty) continue;
      final height =
          (area.height - gap * (indices.length - 1)) / indices.length - 0.5;
      for (final (k, i) in indices.indexed) {
        placed.add((
          index: i,
          rect: Rect.fromLTWH(
            side == 0 ? 0 : width + gap * 2 + vs,
            k * (height + gap),
            width,
            height,
          ),
        ));
      }
    }
    return Stack(
      children: [
        PlacedCards(c: c, placed: placed),
        Positioned(
          left: width + gap,
          top: area.height / 2 - vs / 2,
          width: vs,
          height: vs,
          child: InfoNumberBadge(
            style: style,
            label: 'VS',
            size: vs,
            color: style.palette.accent,
          ),
        ),
      ],
    );
  }
}
