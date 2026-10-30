import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style_spec.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_cards.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_flows.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_grids.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_parts.dart';

/// Las seis composiciones de F45: la línea de tiempo vertical, la tabla
/// comparativa, el embudo, el ciclo, el mapa de temas y las estadísticas en
/// mosaico. Como las de F43, reciben el lugar del cuerpo de la lámina y lo
/// reparten sin que nada se salga.

/// Si [block] puede ir destacado, en una caja del color primario: los de
/// texto corto (una cifra, una idea, un concepto), y solo en los estilos de
/// cajas llenas —en los de filete o borde, un bloque lleno desentona—.
bool _canStandOut(InfoContext c, InfographicBlock block) {
  final fills = switch (c.spec.panel) {
    InfoPanelLook.tile ||
    InfoPanelLook.card ||
    InfoPanelLook.flat ||
    InfoPanelLook.clay ||
    InfoPanelLook.tinted ||
    InfoPanelLook.playful ||
    InfoPanelLook.sticker ||
    InfoPanelLook.block ||
    InfoPanelLook.note => true,
    _ => false,
  };
  return fills &&
      (block is StatBlock || block is FactBlock || block is ConceptBlock);
}

/// La línea de tiempo vertical: la línea a la izquierda, un punto por bloque
/// y cada bloque a su derecha, de arriba abajo, como una lista que se lee
/// sola. En horizontal, con muchos bloques, en dos columnas.
class VerticalTimelineComposition extends StatelessWidget {
  const VerticalTimelineComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final n = blocks.length;
    final style = c.style;
    final p = style.palette;
    final columns = style.isLandscape && n > 4 ? 2 : 1;
    final perColumn = (n / columns).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final gap = style.gap;
        const dot = 30.0;
        final stem = gap * 0.9;
        final columnGap = gap * 2;
        final columnWidth = (area.width - columnGap * (columns - 1)) / columns;
        final rowGap = gap * 0.7;
        final rowHeight = (area.height - rowGap * (perColumn - 1)) / perColumn;
        final placed = <PlacedBlock>[];
        final dots = <Offset>[];
        final lines = <List<Offset>>[];
        for (var column = 0; column < columns; column++) {
          final left = column * (columnWidth + columnGap);
          final x = left + dot / 2;
          final first = column * perColumn;
          final last = math.min(n, first + perColumn);
          if (first >= last) continue;
          for (var i = first; i < last; i++) {
            final top = (i - first) * (rowHeight + rowGap);
            dots.add(Offset(x, top + rowHeight / 2));
            placed.add((
              index: i,
              rect: Rect.fromLTWH(
                left + dot + stem,
                top,
                columnWidth - dot - stem - 0.5,
                rowHeight - 0.5,
              ),
            ));
          }
          lines.add([dots[first], dots[last - 1]]);
        }
        final options = InfoCardOptions(
          mediaOf: (b) =>
              b is FactBlock || b is ConceptBlock ? InfoMediaKind.badge : null,
        );
        final fitted = fitToContent(
          context,
          c,
          placed,
          options: options,
          focus: (block) => dots[block.index],
        );
        final glow = c.spec.panel == InfoPanelLook.neon;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: InfoLinesPainter(
                  paths: [
                    ...lines,
                    for (final (i, d) in dots.indexed)
                      [
                        Offset(d.dx + dot / 2, d.dy),
                        Offset(fitted[i].rect.left, d.dy),
                      ],
                  ],
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
                    color: style.tint(i),
                    border: Border.all(color: p.background, width: 6),
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

/// La tabla comparativa: la primera comparación como una tabla de dos
/// columnas —el nombre de cada lado en su franja de color y sus puntos
/// renglón por renglón, frente a frente—, con su conclusión abajo; lo demás,
/// en una fila debajo. Sin una comparación, los bloques en una grilla.
class ComparisonTableComposition extends StatelessWidget {
  const ComparisonTableComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final style = c.style;
    final main = blocks.indexWhere((b) => b is ComparisonBlock);
    if (main < 0) return BentoComposition(c: c);
    final comparison = blocks[main] as ComparisonBlock;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final gap = style.gap;
        final others = [
          for (var i = 0; i < blocks.length; i++)
            if (i != main) i,
        ];
        final perRow = style.isLandscape ? math.max(1, others.length) : 2;
        final rows = (others.length / perRow).ceil();
        final restHeight = others.isEmpty
            ? 0.0
            // En horizontal, una fila de un tercio: los bloques de abajo son
            // angostos y necesitan alto para su texto.
            : area.height * (style.isLandscape ? 0.33 : 0.16 * rows + 0.05);
        final tableHeight =
            area.height - restHeight - (others.isEmpty ? 0 : gap);
        final placed = <PlacedBlock>[];
        if (others.isNotEmpty) {
          final width = (area.width - gap * (perRow - 1)) / perRow - 0.5;
          final height = (restHeight - gap * (rows - 1)) / rows - 0.5;
          for (final (k, i) in others.indexed) {
            placed.add((
              index: i,
              rect: Rect.fromLTWH(
                (k % perRow) * (width + gap),
                tableHeight + gap + (k ~/ perRow) * (height + gap),
                width,
                height,
              ),
            ));
          }
        }
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: area.width,
              height: tableHeight,
              child: Semantics(
                label: blockSemantics(comparison),
                container: true,
                child: ExcludeSemantics(
                  child: _ComparisonTable(c: c, block: comparison),
                ),
              ),
            ),
            if (placed.isNotEmpty) PlacedCards(c: c, placed: placed),
          ],
        );
      },
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.c, required this.block});

  final InfoContext c;
  final ComparisonBlock block;

  @override
  Widget build(BuildContext context) {
    final style = c.style;
    final p = style.palette;
    final left = block.left.points;
    final right = block.right.points;
    final rows = math.max(1, math.max(left.length, right.length));
    final fills = [p.primary, p.secondary];
    final inks = [for (final f in fills) CreationContrast.readableOn(f)];
    final zebra = Color.alphaBlend(
      p.text.withValues(alpha: p.isDark ? 0.07 : 0.045),
      p.background,
    );
    final cellInk = CreationContrast.ensureOnAll(p.text, [
      p.background,
      zebra,
    ], minimum: 7);
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final gap = style.gap * 0.5;
        final hasTitle = block.title.isNotEmpty;
        final hasConclusion = block.conclusion.isNotEmpty;
        final titleHeight = hasTitle ? style.headingSize * 1.6 : 0.0;
        final conclusionHeight = hasConclusion ? style.bodySize * 3.2 : 0.0;
        final headHeight = style.headingSize * 2.1;
        final double bodyHeight = math.max(
          0,
          area.height -
              titleHeight -
              headHeight -
              conclusionHeight -
              (hasConclusion ? gap : 0),
        );
        final rowHeight = bodyHeight / rows;
        final cellWidth = area.width / 2;
        final pad = style.gap * 0.6;
        final cellSize = Size(
          math.max(0, cellWidth - pad * 2),
          math.max(0, rowHeight - pad * 0.8),
        );
        List<FitTextItem> cell(List<String> points, int row) => [
          if (row < points.length)
            FitTextItem(
              text: points[row],
              style: style.body(color: cellInk),
              textAlign: blockAlign(style),
            ),
        ];
        final groups = [
          for (var r = 0; r < rows; r++) ...[cell(left, r), cell(right, r)],
        ];
        final scale = FitTextGroup.sharedScale(context, [
          for (final g in groups)
            if (g.isNotEmpty) g,
        ], cellSize);
        Widget head(int side) {
          final heading = side == 0 ? block.left.heading : block.right.heading;
          return Container(
            height: headHeight,
            padding: EdgeInsets.symmetric(horizontal: pad),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fills[side],
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(math.min(style.spec.radius, 24)),
              ),
            ),
            child: FitText(
              heading,
              style: style.heading(color: inks[side]),
              maxLines: 2,
              minScale: 0.4,
              textAlign: TextAlign.center,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasTitle)
              SizedBox(
                height: titleHeight,
                child: Align(
                  alignment: style.spec.centered
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: FitText(
                    style.titleCase(block.title),
                    style: style.heading(),
                    maxLines: 1,
                    minScale: 0.4,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(child: head(0)),
                Expanded(child: head(1)),
              ],
            ),
            for (var r = 0; r < rows; r++)
              Container(
                height: rowHeight,
                color: r.isOdd ? zebra : null,
                child: Row(
                  children: [
                    for (var side = 0; side < 2; side++)
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: pad,
                            vertical: pad * 0.4,
                          ),
                          decoration: side == 0
                              ? BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: p.text.withValues(alpha: 0.18),
                                      width: 2,
                                    ),
                                  ),
                                )
                              : null,
                          alignment: style.spec.centered
                              ? Alignment.center
                              : Alignment.centerLeft,
                          child: FitTextGroup(
                            items: groups[r * 2 + side],
                            scale: scale,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (hasConclusion) ...[
              SizedBox(height: gap),
              Container(
                height: conclusionHeight,
                padding: EdgeInsets.only(left: style.gap * 0.7),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: p.accent, width: 10)),
                ),
                alignment: Alignment.centerLeft,
                child: FitText(
                  block.conclusion,
                  style: style.body(weight: 600),
                  maxLines: 2,
                  minScale: 0.4,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// El embudo: una franja por bloque, de la más ancha arriba a la más
/// angosta abajo, cada una de su color y con su texto adentro, como lo que
/// se va filtrando hasta lo esencial.
class FunnelComposition extends StatelessWidget {
  const FunnelComposition({required this.c, super.key});

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
        final gap = style.gap * 0.4;
        final bandHeight = (area.height - gap * (n - 1)) / n - 0.5;
        final widest = area.width;
        final narrowest = area.width * (style.isPortrait ? 0.5 : 0.36);
        double widthAt(double t) => widest - (widest - narrowest) * t;
        final colors = [
          for (var i = 0; i < n; i++)
            Color.lerp(p.primary, p.secondary, n == 1 ? 0 : i / (n - 1))!,
        ];
        final bands = [
          for (var i = 0; i < n; i++)
            (
              top: i * (bandHeight + gap),
              topWidth: widthAt(i / n),
              bottomWidth: widthAt((i + 1) / n),
            ),
        ];
        // El texto va en el rectángulo que entra en la franja: el ancho de
        // abajo, que es el menor, sin las puntas.
        final groups = <List<FitTextItem>>[];
        final sizes = <Size>[];
        for (var i = 0; i < n; i++) {
          final ink = CreationContrast.readableOn(colors[i]);
          groups.add([
            for (final item in InfoCards.textItems(
              c,
              blocks[i],
              ink: InfoCardInk(
                surface: colors[i],
                text: ink,
                muted: ink,
                accent: ink,
              ),
              look: InfoCardLook.inverse,
              includeValue: true,
            ))
              FitTextItem(
                text: item.text,
                style: item.style,
                gapBefore: item.gapBefore,
                maxLines: item.maxLines,
                textAlign: TextAlign.center,
              ),
          ]);
          sizes.add(
            Size(
              math.max(0, bands[i].bottomWidth * 0.82 - style.gap),
              math.max(0, bandHeight - style.gap * 0.6),
            ),
          );
        }
        var scale = 1.0;
        for (var i = 0; i < n; i++) {
          scale = math.min(
            scale,
            InfoCards.solve(context, groups[i], sizes[i]).scale,
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _FunnelPainter(
                  bands: [
                    for (final b in bands)
                      (b.top, bandHeight, b.topWidth, b.bottomWidth),
                  ],
                  colors: colors,
                  center: area.width / 2,
                  outline:
                      c.spec.panel == InfoPanelLook.sticker ||
                          c.spec.panel == InfoPanelLook.block
                      ? const Color(0xFF000000)
                      : null,
                ),
              ),
            ),
            for (var i = 0; i < n; i++)
              Positioned(
                left: area.width / 2 - sizes[i].width / 2,
                top: bands[i].top + (bandHeight - sizes[i].height) / 2,
                width: sizes[i].width,
                height: sizes[i].height,
                child: Semantics(
                  label: blockSemantics(blocks[i]),
                  container: true,
                  child: ExcludeSemantics(
                    child: Center(
                      child: FitTextGroup(
                        items: groups[i],
                        scale: scale,
                        crossAxisAlignment: CrossAxisAlignment.center,
                      ),
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

class _FunnelPainter extends CustomPainter {
  const _FunnelPainter({
    required this.bands,
    required this.colors,
    required this.center,
    this.outline,
  });

  /// Arriba, alto, ancho de arriba y ancho de abajo de cada franja.
  final List<(double, double, double, double)> bands;
  final List<Color> colors;
  final double center;
  final Color? outline;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, (top, height, topWidth, bottomWidth)) in bands.indexed) {
      final path = Path()
        ..addPolygon([
          Offset(center - topWidth / 2, top),
          Offset(center + topWidth / 2, top),
          Offset(center + bottomWidth / 2, top + height),
          Offset(center - bottomWidth / 2, top + height),
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
    }
  }

  @override
  bool shouldRepaint(_FunnelPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.outline != outline ||
      oldDelegate.bands.length != bands.length ||
      oldDelegate.colors.length != colors.length ||
      !Iterable<int>.generate(bands.length).every(
        (i) =>
            oldDelegate.bands[i] == bands[i] &&
            oldDelegate.colors[i] == colors[i],
      );
}

/// El ciclo: los bloques en una rueda, cada uno unido al siguiente por una
/// flecha curva —y el último al primero—, porque lo que cuenta vuelve a
/// empezar.
class CycleComposition extends StatelessWidget {
  const CycleComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final n = blocks.length;
    final style = c.style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final few = n <= 4;
        final card = style.isLandscape
            ? Size(
                area.width * (few ? 0.3 : 0.26),
                area.height * (few ? 0.4 : 0.32),
              )
            : style.isPortrait
            ? Size(area.width * 0.46, area.height * (few ? 0.27 : 0.21))
            : Size(area.width * 0.33, area.height * (few ? 0.32 : 0.26));
        // Sin centro que esquivar: la rueda gira alrededor de un punto.
        final rects = ellipseLayout(
          n: n,
          area: area,
          card: card,
          hub: Rect.fromCenter(
            center: area.center(Offset.zero),
            width: 1,
            height: 1,
          ),
          gap: style.gap * 0.6,
        );
        final options = InfoCardOptions(
          numberOf: (i) => i + 1,
          mediaOf: (b) => b is FactBlock || b is ConceptBlock || b is StepBlock
              ? InfoMediaKind.badge
              : null,
        );
        final placed = fitToContent(
          context,
          c,
          [for (var i = 0; i < n; i++) (index: i, rect: rects[i])],
          focus: (p) => area.center(Offset.zero),
          options: options,
        );
        final center = area.center(Offset.zero);
        // Las flechas: de un bloque al siguiente, por fuera de las cajas, con
        // la curva hacia afuera de la rueda.
        final arrows = <List<Offset>>[];
        for (var i = 0; i < n; i++) {
          final from = placed[i].rect;
          final to = placed[(i + 1) % n].rect;
          final a = edgePoint(from, to.center);
          final b = edgePoint(to, from.center);
          final middle = (a + b) / 2;
          final out = middle - center;
          final bulge = out.distance == 0
              ? Offset.zero
              : out / out.distance * style.gap * 1.4;
          arrows.add([a, middle + bulge, b]);
        }
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ArrowsPainter(
                  paths: arrows,
                  color: style.palette.primary.withValues(alpha: 0.65),
                  width: 5,
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

/// Flechas curvas: cada una pasa por tres puntos (el de salida, el del medio
/// y el de llegada) y lleva su punta en la llegada.
class _ArrowsPainter extends CustomPainter {
  const _ArrowsPainter({
    required this.paths,
    required this.color,
    required this.width,
  });

  final List<List<Offset>> paths;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = color;
    for (final points in paths) {
      final [from, through, to] = points;
      // La curva cuadrática que pasa por [through] en su mitad.
      final control = through * 2 - (from + to) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy),
        line,
      );
      final direction = to - control;
      if (direction.distance == 0) continue;
      final unit = direction / direction.distance;
      final normal = Offset(-unit.dy, unit.dx);
      final head = width * 3.6;
      canvas.drawPath(
        Path()
          ..moveTo(to.dx, to.dy)
          ..lineTo(
            to.dx - unit.dx * head + normal.dx * head * 0.6,
            to.dy - unit.dy * head + normal.dy * head * 0.6,
          )
          ..lineTo(
            to.dx - unit.dx * head - normal.dx * head * 0.6,
            to.dy - unit.dy * head - normal.dy * head * 0.6,
          )
          ..close(),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ArrowsPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.width != width ||
      oldDelegate.paths.length != paths.length ||
      !Iterable<int>.generate(paths.length).every(
        (i) =>
            oldDelegate.paths[i].length == paths[i].length &&
            Iterable<int>.generate(
              paths[i].length,
            ).every((k) => oldDelegate.paths[i][k] == paths[i][k]),
      );
}

/// El mapa de temas: el primer bloque arriba, destacado, como el tema; y los
/// demás debajo como sus subtemas, colgados de una llave que los une, en una
/// fila (o en dos, si son muchos para el ancho).
class TopicMapComposition extends StatelessWidget {
  const TopicMapComposition({required this.c, super.key});

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
        final children = n - 1;
        final perRow = children <= 0
            ? 1
            : style.isLandscape
            ? math.min(children, 4)
            : style.isPortrait
            ? math.min(children, 2)
            : math.min(children, 3);
        final rows = children <= 0 ? 0 : (children / perRow).ceil();
        final bracket = gap * 2.2;
        final rootHeight = children <= 0
            ? area.height
            : area.height * (style.isPortrait ? 0.22 : 0.3);
        final rootWidth = children <= 0
            ? area.width
            : area.width * (style.isPortrait ? 0.8 : 0.5);
        final rest = area.height - rootHeight - bracket;
        final rowGap = gap * 1.2;
        final rowHeight = rows == 0 ? 0.0 : (rest - rowGap * (rows - 1)) / rows;
        final width = (area.width - gap * (perRow - 1)) / perRow;
        final placed = <PlacedBlock>[
          (
            index: 0,
            rect: Rect.fromLTWH(
              (area.width - rootWidth) / 2,
              0,
              rootWidth,
              rootHeight - 0.5,
            ),
          ),
        ];
        for (var k = 0; k < children; k++) {
          final row = k ~/ perRow;
          final inRow = math.min(perRow, children - row * perRow);
          // Una fila corta va centrada.
          final offset = (perRow - inRow) * (width + gap) / 2;
          placed.add((
            index: k + 1,
            rect: Rect.fromLTWH(
              offset + (k % perRow) * (width + gap),
              rootHeight + bracket + row * (rowHeight + rowGap),
              width - 0.5,
              rowHeight - 0.5,
            ),
          ));
        }
        final standOut = _canStandOut(c, blocks.first);
        final options = InfoCardOptions(
          lookOf: (i) =>
              i == 0 && standOut ? InfoCardLook.inverse : InfoCardLook.panel,
          boostOf: (i) => i == 0 ? 1.15 : 1,
        );
        // Cada caja, lo que mide su texto: el tema pegado abajo (a la llave),
        // los subtemas arriba (colgando de ella).
        final fitted = fitToContent(
          context,
          c,
          placed,
          options: options,
          focus: (block) => block.index == 0
              ? Offset(block.rect.center.dx, block.rect.bottom)
              : Offset(block.rect.center.dx, block.rect.top),
        );
        // La llave: del tema baja una línea a un travesaño, y de él una
        // línea a cada subtema de la primera fila (los de las demás cuelgan
        // del de arriba).
        final root = fitted.first.rect;
        final y = rootHeight + bracket / 2;
        final paths = <List<Offset>>[];
        if (children > 0) {
          final firstRow = [
            for (final b in fitted.skip(1))
              if (b.index - 1 < perRow) b.rect,
          ];
          paths
            ..add([root.bottomCenter, Offset(root.center.dx, y)])
            ..add([
              Offset(firstRow.first.center.dx, y),
              Offset(firstRow.last.center.dx, y),
            ]);
          for (final b in fitted.skip(1)) {
            final k = b.index - 1;
            if (k < perRow) {
              paths.add([Offset(b.rect.center.dx, y), b.rect.topCenter]);
            } else {
              final above = fitted[b.index - perRow].rect;
              paths.add([above.bottomCenter, b.rect.topCenter]);
            }
          }
        }
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: InfoLinesPainter(
                  paths: paths,
                  color: style.palette.text.withValues(alpha: 0.3),
                  look: c.spec.connector,
                  width: 5,
                  seed: c.seed,
                ),
              ),
            ),
            PlacedCards(c: c, placed: fitted, options: options),
          ],
        );
      },
    );
  }
}

/// Las estadísticas en mosaico: baldosas de dos tamaños que llenan la
/// lámina sin huecos; la primera cifra, grande y del color del estilo, y
/// las demás cifras alternando el color y la caja, como un tablero.
class StatMosaicComposition extends StatelessWidget {
  const StatMosaicComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final columns = math.min(gridColumns(c), math.max(2, blocks.length));
    // La cifra que manda: la primera; y el turno de cada cifra entre las
    // cifras, para alternarlas.
    final lead = blocks.indexWhere((b) => b is StatBlock);
    var seen = 0;
    final statOrder = <int, int>{
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i] is StatBlock) i: seen++,
    };
    final leadStandsOut = lead >= 0 && _canStandOut(c, blocks[lead]);
    return LayoutBuilder(
      builder: (context, constraints) {
        final placed = packRows(
          blocks: blocks,
          columns: columns,
          area: constraints.biggest,
          gap: c.style.gap * 0.6,
          span: (b) =>
              identical(b, lead < 0 ? null : blocks[lead]) ||
                  (b is ChartBlock && b.data.length > 1) ||
                  b is ComparisonBlock
              ? 2
              : 1,
          weight: (b) =>
              identical(b, lead < 0 ? null : blocks[lead]) || b is ChartBlock
              ? 1.5
              : 1,
        );
        return PlacedCards(
          c: c,
          placed: placed,
          options: InfoCardOptions(
            lookOf: (i) {
              final order = statOrder[i];
              if (order == null) return InfoCardLook.panel;
              // La primera, destacada; las demás, un indicador sí y uno no.
              if (order == 0) {
                return leadStandsOut ? InfoCardLook.inverse : InfoCardLook.kpi;
              }
              return order.isOdd ? InfoCardLook.panel : InfoCardLook.kpi;
            },
            boostOf: (i) => i == lead ? 1.2 : 1,
          ),
        );
      },
    );
  }
}
