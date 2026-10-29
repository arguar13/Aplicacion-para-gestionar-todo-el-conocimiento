import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style_spec.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_cards.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_parts.dart';

/// Las composiciones en grilla (F43): bloques bento, columnas, panel de
/// cifras y proceso. Todas reciben el lugar del cuerpo de la lámina y lo
/// reparten sin que nada se salga.

/// Un bloque ubicado: su posición en la lámina y su rectángulo.
typedef PlacedBlock = ({int index, Rect rect});

/// Reparte [blocks] en filas de [columns] columnas: cada bloque ocupa lo que
/// diga [span]; si una fila queda con lugar, el último de ella se estira
/// hasta completarla. Las filas se reparten el alto según [weight].
List<PlacedBlock> packRows({
  required List<InfographicBlock> blocks,
  required int columns,
  required Size area,
  required double gap,
  required int Function(InfographicBlock block) span,
  double Function(InfographicBlock block)? weight,
}) {
  final rows = <List<(int, int)>>[];
  var current = <(int, int)>[];
  var used = 0;
  for (var i = 0; i < blocks.length; i++) {
    final s = math.min(columns, math.max(1, span(blocks[i])));
    if (used + s > columns) {
      rows.add(current);
      current = [];
      used = 0;
    }
    current.add((i, s));
    used += s;
  }
  if (current.isNotEmpty) rows.add(current);
  // El último de cada fila completa lo que falte.
  for (final row in rows) {
    final total = row.fold<int>(0, (a, e) => a + e.$2);
    if (total < columns) {
      final last = row.removeLast();
      row.add((last.$1, last.$2 + columns - total));
    }
  }
  final weights = [
    for (final row in rows)
      row
          .map((e) => weight?.call(blocks[e.$1]) ?? 1.0)
          .fold<double>(0, math.max),
  ];
  final totalWeight = weights.fold<double>(0, (a, w) => a + w);
  final available = area.height - gap * (rows.length - 1);
  final cell = (area.width - gap * (columns - 1)) / columns;
  final placed = <PlacedBlock>[];
  var top = 0.0;
  for (var r = 0; r < rows.length; r++) {
    // Medio punto menos por el redondeo: la suma no puede pasarse.
    final height = available * weights[r] / totalWeight - 0.5;
    var column = 0;
    for (final (index, s) in rows[r]) {
      final left = column * (cell + gap);
      final width = cell * s + gap * (s - 1) - 0.5;
      placed.add((index: index, rect: Rect.fromLTWH(left, top, width, height)));
      column += s;
    }
    top += height + 0.5 + gap;
  }
  return placed;
}

/// Las columnas de una grilla según la orientación.
int gridColumns(
  InfoContext c, {
  int landscape = 4,
  int square = 3,
  int portrait = 2,
}) {
  final style = c.style;
  return style.isLandscape
      ? landscape
      : style.isPortrait
      ? portrait
      : square;
}

/// Cómo se presentan los bloques de una composición.
@immutable
class InfoCardOptions {
  const InfoCardOptions({
    this.lookOf,
    this.mediaOf,
    this.numberOf,
    this.boostOf,
    this.valuesOutside = false,
  });

  final InfoCardLook Function(int index)? lookOf;
  final InfoMediaKind? Function(InfographicBlock block)? mediaOf;
  final int? Function(int index)? numberOf;
  final double Function(int index)? boostOf;

  /// Las cifras las dibuja la composición aparte.
  final bool valuesOutside;

  InfoCardLook look(int index) => lookOf?.call(index) ?? InfoCardLook.panel;
}

/// La escala común de [placed] (ver `InfoCards.sharedScale`).
double placedScale(
  BuildContext context,
  InfoContext c,
  List<PlacedBlock> placed,
  InfoCardOptions options,
) => InfoCards.sharedScale(
  context,
  c,
  [for (final p in placed) (c.blocks[p.index], p.rect.size, p.index)],
  lookOf: options.lookOf,
  mediaOf: options.mediaOf,
  valuesOutside: options.valuesOutside,
);

/// [placed] con cada bloque común achicado a lo que mide su contenido (con
/// la letra común), dentro de su lugar y lo más cerca posible de [focus]:
/// el punto de la línea que lo une a algo. Así una caja no queda grande y
/// vacía abajo cuando su texto es corto.
List<PlacedBlock> fitToContent(
  BuildContext context,
  InfoContext c,
  List<PlacedBlock> placed, {
  required Offset Function(PlacedBlock block) focus,
  InfoCardOptions options = const InfoCardOptions(),
}) {
  final scale = placedScale(context, c, placed, options);
  return [
    for (final p in placed)
      () {
        final block = c.blocks[p.index];
        final needed = InfoCards.neededHeight(
          context,
          c,
          block,
          p.rect.size,
          p.index,
          scale,
          look: options.look(p.index),
          media: options.mediaOf?.call(block),
          valuesOutside: options.valuesOutside,
        );
        final rect = p.rect;
        // Entre lo más alto y lo más bajo que puede ir; sin `clamp`, que
        // con una caja que ya mide justo su lugar recibe los límites
        // cruzados por el redondeo.
        final low = rect.top + needed / 2;
        final high = math.max(low, rect.bottom - needed / 2);
        final center = math.min(high, math.max(low, focus(p).dy));
        return (
          index: p.index,
          rect: Rect.fromLTWH(
            rect.left,
            center - needed / 2,
            rect.width,
            needed,
          ),
        );
      }(),
  ];
}

/// Dibuja [placed] con la misma letra para todos los bloques comunes.
class PlacedCards extends StatelessWidget {
  const PlacedCards({
    required this.c,
    required this.placed,
    this.options = const InfoCardOptions(),
    super.key,
  });

  final InfoContext c;
  final List<PlacedBlock> placed;
  final InfoCardOptions options;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final scale = placedScale(context, c, placed, options);
    return Stack(
      children: [
        for (final p in placed)
          Positioned.fromRect(
            rect: p.rect,
            child: InfoBlockCard(
              c: c,
              block: blocks[p.index],
              index: p.index,
              look: options.look(p.index),
              media: options.mediaOf?.call(blocks[p.index]),
              number: options.numberOf?.call(p.index),
              boost: options.boostOf?.call(p.index) ?? 1,
              valuesOutside: options.valuesOutside,
              scaleCap: scale,
            ),
          ),
      ],
    );
  }
}

/// Bloques bento: baldosas de dos tamaños; lo que necesita lugar (una
/// comparación, un gráfico, una cita) ocupa dos columnas, y el primer
/// bloque común va destacado en el color del estilo.
class BentoComposition extends StatelessWidget {
  const BentoComposition({required this.c, super.key});

  final InfoContext c;

  static bool _wide(InfographicBlock b) =>
      b is ComparisonBlock ||
      (b is ChartBlock && b.data.length > 1) ||
      b is QuoteBlock;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final columns = math.min(gridColumns(c), math.max(2, blocks.length));
    final highlight = _highlightOf(c);
    return LayoutBuilder(
      builder: (context, constraints) {
        final placed = packRows(
          blocks: blocks,
          columns: columns,
          area: constraints.biggest,
          gap: c.style.gap,
          span: (b) => _wide(b) ? 2 : 1,
          weight: (b) => switch (b) {
            ComparisonBlock() || ChartBlock() => 1.4,
            QuoteBlock() => 1.15,
            _ => 1,
          },
        );
        return PlacedCards(
          c: c,
          placed: placed,
          options: InfoCardOptions(
            lookOf: (i) =>
                i == highlight ? InfoCardLook.inverse : InfoCardLook.panel,
          ),
        );
      },
    );
  }

  /// El bloque que va destacado: el primero común, en los estilos de cajas
  /// llenas (en los de filete o borde, un bloque lleno desentona).
  static int? _highlightOf(InfoContext c) {
    final fills = switch (c.spec.panel) {
      InfoPanelLook.tile ||
      InfoPanelLook.card ||
      InfoPanelLook.flat ||
      InfoPanelLook.clay ||
      InfoPanelLook.tinted ||
      InfoPanelLook.playful ||
      InfoPanelLook.sticker => true,
      _ => false,
    };
    if (!fills) return null;
    for (var i = 0; i < c.blocks.length; i++) {
      final b = c.blocks[i];
      if (b is StatBlock || b is FactBlock || b is ConceptBlock) return i;
    }
    return null;
  }
}

/// Columnas: cada bloque una columna sin caja, centrada, bajo una raya de
/// su color; con más bloques que columnas, en dos o tres filas. Una
/// comparación, un gráfico o una cita no caben en una columna angosta: van
/// abajo, a lo ancho, en su caja.
class ColumnsComposition extends StatelessWidget {
  const ColumnsComposition({required this.c, super.key});

  final InfoContext c;

  static bool _wide(InfographicBlock b) =>
      InfoCards.isSpecial(b) || b is QuoteBlock;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final common = [
      for (var i = 0; i < blocks.length; i++)
        if (!_wide(blocks[i])) i,
    ];
    final wide = [
      for (var i = 0; i < blocks.length; i++)
        if (_wide(blocks[i])) i,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final gap = c.style.gap * 1.4;
        final placed = <PlacedBlock>[];
        // Las de a lo ancho: en horizontal, una al lado de la otra en una
        // fila; si no, una debajo de otra, la cita más baja que una
        // comparación o un gráfico. Sin columnas, todo el alto.
        final side = c.style.isLandscape;
        double weight(int i) => blocks[i] is QuoteBlock ? 0.55 : 1;
        final totalWeight = wide.fold<double>(0, (a, i) => a + weight(i));
        final wideHeight = wide.isEmpty
            ? 0.0
            : common.isEmpty
            ? area.height
            : side
            ? area.height * 0.46
            : math.min(area.height * 0.62, area.height * 0.4 * totalWeight);
        final columnsHeight =
            area.height -
            wideHeight -
            (wide.isEmpty || common.isEmpty ? 0 : gap);
        if (common.isNotEmpty) {
          final columns = math.min(common.length, gridColumns(c));
          final rows = (common.length / columns).ceil();
          final width = (area.width - gap * (columns - 1)) / columns - 0.5;
          final height = (columnsHeight - gap * (rows - 1)) / rows - 0.5;
          for (final (k, i) in common.indexed) {
            final row = k ~/ columns;
            final inRow = math.min(columns, common.length - row * columns);
            // La última fila, si queda corta, va centrada.
            final offset = (columns - inRow) * (width + gap) / 2;
            placed.add((
              index: i,
              rect: Rect.fromLTWH(
                offset + (k % columns) * (width + gap),
                row * (height + gap),
                width,
                height,
              ),
            ));
          }
        }
        if (wide.isNotEmpty) {
          final top = common.isEmpty ? 0.0 : columnsHeight + gap;
          final between = c.style.gap;
          if (side) {
            final width =
                (area.width - between * (wide.length - 1)) / wide.length - 0.5;
            for (final (k, i) in wide.indexed) {
              placed.add((
                index: i,
                rect: Rect.fromLTWH(
                  k * (width + between),
                  top,
                  width,
                  wideHeight - 0.5,
                ),
              ));
            }
          } else {
            final available = wideHeight - between * (wide.length - 1);
            var y = top;
            for (final i in wide) {
              final height = available * weight(i) / totalWeight - 0.5;
              placed.add((
                index: i,
                rect: Rect.fromLTWH(0, y, area.width, height),
              ));
              y += height + 0.5 + between;
            }
          }
        }
        return PlacedCards(
          c: c,
          placed: placed,
          options: InfoCardOptions(
            lookOf: (i) =>
                _wide(blocks[i]) ? InfoCardLook.panel : InfoCardLook.open,
          ),
        );
      },
    );
  }
}

/// El panel de cifras: las cifras como indicadores grandes (un porcentaje,
/// con su anillo), los gráficos a lo ancho, y lo demás en baldosas chicas.
class StatPanelComposition extends StatelessWidget {
  const StatPanelComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final columns = math.min(gridColumns(c), math.max(2, blocks.length));
    return LayoutBuilder(
      builder: (context, constraints) {
        final placed = packRows(
          blocks: blocks,
          columns: columns,
          area: constraints.biggest,
          gap: c.style.gap,
          span: (b) => b is ChartBlock || b is ComparisonBlock ? 2 : 1,
          weight: (b) => b is ChartBlock || b is ComparisonBlock ? 1.35 : 1,
        );
        return PlacedCards(
          c: c,
          placed: placed,
          options: InfoCardOptions(
            lookOf: (i) =>
                blocks[i].isNumeric ? InfoCardLook.kpi : InfoCardLook.panel,
          ),
        );
      },
    );
  }
}

/// El proceso: los pasos numerados en orden, con una flecha entre uno y el
/// siguiente; en horizontal de izquierda a derecha (en dos filas si son
/// muchos), en vertical de arriba abajo.
class ProcessComposition extends StatelessWidget {
  const ProcessComposition({required this.c, super.key});

  final InfoContext c;

  @override
  Widget build(BuildContext context) {
    final blocks = c.blocks;
    final n = blocks.length;
    final style = c.style;
    final vertical = !style.isLandscape && n <= (style.isPortrait ? 5 : 4);
    final perRow = vertical
        ? 1
        : style.isLandscape
        ? (n <= 4 ? n : (n / 2).ceil())
        : 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final arrow = style.gap * 2.4;
        final rows = (n / perRow).ceil();
        final rowGap = vertical ? arrow : style.gap * 1.2;
        final width = (area.width - arrow * (perRow - 1)) / perRow - 0.5;
        final height = (area.height - rowGap * (rows - 1)) / rows - 0.5;
        final placed = <PlacedBlock>[];
        final arrows = <(Offset, bool)>[];
        for (var i = 0; i < n; i++) {
          final row = i ~/ perRow;
          final column = i % perRow;
          final rect = Rect.fromLTWH(
            column * (width + arrow),
            row * (height + rowGap),
            width,
            height,
          );
          placed.add((index: i, rect: rect));
          if (i == n - 1) continue;
          if (vertical) {
            arrows.add((Offset(rect.center.dx, rect.bottom + arrow / 2), true));
          } else if (column < perRow - 1) {
            arrows.add((Offset(rect.right + arrow / 2, rect.center.dy), false));
          }
        }
        final tint = style.palette.accentText;
        final options = InfoCardOptions(
          mediaOf: (b) => b is FactBlock || b is ConceptBlock || b is EventBlock
              ? InfoMediaKind.badge
              : null,
        );
        // De costado, las cajas de cada fila miden lo que la más alta de
        // ellas necesita, centradas en su fila (las flechas, en el medio).
        var boxes = placed;
        if (!vertical) {
          final fitted = fitToContent(
            context,
            c,
            placed,
            options: options,
            focus: (p) => p.rect.center,
          );
          final tallest = <int, double>{};
          for (final p in fitted) {
            final row = p.index ~/ perRow;
            tallest[row] = math.max(tallest[row] ?? 0, p.rect.height);
          }
          boxes = [
            for (final p in placed)
              (
                index: p.index,
                rect: Rect.fromCenter(
                  center: p.rect.center,
                  width: p.rect.width,
                  height: tallest[p.index ~/ perRow]!,
                ),
              ),
          ];
        }
        return Stack(
          children: [
            PlacedCards(c: c, placed: boxes, options: options),
            for (final (center, down) in arrows)
              Positioned(
                left: center.dx - arrow / 2,
                top: center.dy - arrow / 2,
                width: arrow,
                height: arrow,
                child: Icon(
                  down
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_forward_rounded,
                  size: arrow * 0.8,
                  color: tint,
                ),
              ),
          ],
        );
      },
    );
  }
}
