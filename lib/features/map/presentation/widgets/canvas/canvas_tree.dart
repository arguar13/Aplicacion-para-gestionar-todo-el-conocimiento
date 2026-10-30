import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/schema_layout.dart';
import 'package:sinapsis/features/map/domain/services/svg_writer.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/features/map/presentation/widgets/arrow_head.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_network.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El tamaño de la tarjeta de cada nodo de Radial y Árbol.
const kTreeNodeSize = Size(176, 44);

/// El aire alrededor del árbol dentro del lienzo.
const _kTreeMargin = 80.0;

/// Dónde va cada tarjeta del árbol, ya dentro del lienzo, y cuánto mide el
/// lienzo.
typedef TreePlacement = ({Map<String, Offset> positions, Size canvas});

/// Acomoda [tree] en radial —lo que se mira en el centro y sus ramas
/// alrededor— o en árbol —de izquierda a derecha, de lo general a lo
/// particular—.
TreePlacement placeCanvasTree(CanvasTree tree, MapArrangement arrangement) {
  final layout = arrangement == MapArrangement.radial
      ? layoutRadial(tree.root)
      : layoutTree(
          tree.root,
          // Cada nivel, una columna: más ancha que una tarjeta para que dos
          // niveles no se pisen.
          levelGap: kTreeNodeSize.width + 64,
          direction: SchemaDirection.right,
        );
  final bounds = layout.bounds;
  final shift = Offset(
    _kTreeMargin + kTreeNodeSize.width / 2 - bounds.left,
    _kTreeMargin + kTreeNodeSize.height / 2 - bounds.top,
  );
  return (
    positions: {
      for (final entry in layout.positions.entries)
        entry.key: entry.value + shift,
    },
    canvas: Size(
      bounds.width + 2 * _kTreeMargin + kTreeNodeSize.width,
      bounds.height + 2 * _kTreeMargin + kTreeNodeSize.height,
    ),
  );
}

/// El color de acento de un nodo del árbol: el de su comunidad para lo que
/// tiene una; el de su rol para un documento.
Color treeAccentOf(
  CanvasTreeEntry entry,
  ColorScheme colors,
  Brightness brightness,
) => switch (entry.ref.kind) {
  CanvasTreeKind.item =>
    (entry.isNote ? EntityRole.note : EntityRole.source).accent(colors),
  CanvasTreeKind.all || CanvasTreeKind.links => colors.primary,
  CanvasTreeKind.community || CanvasTreeKind.topic =>
    entry.group == null
        ? colors.primary
        : mapCommunityColor(entry.group, colors, brightness),
};

/// El ícono de un nodo del árbol.
IconData treeIconOf(CanvasTreeEntry entry) => switch (entry.ref.kind) {
  CanvasTreeKind.all => Icons.hub_outlined,
  CanvasTreeKind.links => Icons.link,
  CanvasTreeKind.community => Icons.bubble_chart_outlined,
  CanvasTreeKind.topic => Icons.label_outline,
  CanvasTreeKind.item =>
    entry.edge == CanvasTreeEdge.mapNote
        ? Icons.account_tree_outlined
        : entry.isNote
        ? Icons.sticky_note_2_outlined
        : Icons.article_outlined,
};

/// Qué es un nodo del árbol, dicho para el lector de pantalla y la lista.
String treeKindLabel(
  AppLocalizations l10n,
  CanvasTreeEntry entry,
  String topicKind,
) => switch (entry.ref.kind) {
  CanvasTreeKind.all || CanvasTreeKind.links => entry.title,
  CanvasTreeKind.community => l10n.mapGraphCommunitySemantics(
    entry.title,
    l10n.mapTopicCount(topicKind, entry.count),
  ),
  CanvasTreeKind.topic =>
    '${l10n.mapSchemaNodeTopic(topicKind)}: ${entry.title}',
  CanvasTreeKind.item => '${_itemKindName(l10n, entry)}: ${entry.title}',
};

String _itemKindName(AppLocalizations l10n, CanvasTreeEntry entry) {
  if (entry.edge == CanvasTreeEdge.mapNote) return l10n.mapSchemaNodeMapNote;
  return entry.isNote ? l10n.mapSchemaNodeNote : l10n.mapSchemaNodeSource;
}

/// La tarjeta de un nodo de Radial y Árbol: su ícono, su título y, si tiene
/// hijos, cómo desplegarlo («›» abre la rama, «‹» la cierra); el botón del
/// borde abre su ficha (F44, paso 4), con todo lo que se puede hacer con él.
/// Lo que no se despliega abre la ficha al tocarlo.
class MapTreeNodeCard extends StatelessWidget {
  const MapTreeNodeCard({
    required this.entry,
    required this.topicKind,
    required this.onToggle,
    this.onSheet,
    this.sheetTooltip,
    this.highlighted = false,
    super.key,
  });

  final CanvasTreeEntry entry;

  /// Qué es un tema acá: ver `topicSelectKind`.
  final String topicKind;
  final VoidCallback onToggle;

  /// Abrir su ficha; `null` si no tiene (todo, lo vinculado).
  final VoidCallback? onSheet;
  final String? sheetTooltip;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = treeAccentOf(entry, colors, theme.brightness);
    final isItem = entry.ref.kind == CanvasTreeKind.item;
    final role = entry.isNote ? EntityRole.note : EntityRole.source;
    final hint = !entry.canExpand
        ? null
        : entry.expanded
        ? l10n.mapSchemaCollapse(entry.title)
        : l10n.mapSchemaExpand(entry.title);
    final strong = entry.expanded || highlighted;

    return Semantics(
      label: treeKindLabel(l10n, entry, topicKind),
      hint: hint,
      button: true,
      expanded: entry.canExpand ? entry.expanded : null,
      excludeSemantics: true,
      onTap: entry.canExpand ? onToggle : onSheet,
      child: Material(
        key: ValueKey('map-tree-node-${entry.key}'),
        color: isItem ? role.surface(colors) : colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: strong ? accent : accent.withValues(alpha: 0.5),
            width: highlighted ? 2.5 : (entry.expanded ? 2 : 1),
          ),
          borderRadius: BorderRadius.circular(isItem ? role.radius : 8),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: entry.canExpand ? onToggle : onSheet,
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Row(
              children: [
                if (entry.ref.kind == CanvasTreeKind.community)
                  _CountDot(color: accent, count: entry.count)
                else
                  Icon(treeIconOf(entry), size: 18, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (entry.canExpand)
                  Icon(
                    entry.expanded ? Icons.chevron_left : Icons.chevron_right,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                if (onSheet != null)
                  IconButton(
                    key: ValueKey('map-tree-sheet-${entry.key}'),
                    tooltip: sheetTooltip ?? l10n.f44S4SheetShow(entry.title),
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: onSheet,
                    icon: const Icon(Icons.info_outline),
                  )
                else
                  const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El círculo de una comunidad, con cuántos temas junta.
class _CountDot extends StatelessWidget {
  const _CountDot({required this.color, required this.count});

  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: count > 99 ? 8 : 10,
          fontWeight: FontWeight.w700,
          color: onColor,
        ),
      ),
    );
  }
}

/// El rótulo de la unión de [entry] con su padre: el tipo de vínculo, o «nota
/// mapa»; `null` si no lleva.
String? treeEdgeLabel(AppLocalizations l10n, CanvasTreeEntry entry) =>
    switch (entry.edge) {
      CanvasTreeEdge.relation => entry.relation?.shortLabel(l10n),
      CanvasTreeEdge.mapNote => l10n.mapSchemaEdgeMapNote,
      _ => null,
    };

/// El color de la unión de [entry] con su padre: la de un vínculo, el de su
/// tipo; las demás, un gris tenue.
Color treeEdgeColor(CanvasTreeEntry entry, ColorScheme colors) {
  final relation = entry.relation;
  return relation == null
      ? colors.outline.withValues(alpha: 0.6)
      : relation.color(colors);
}

/// La punta de la flecha de un vínculo: cerca del extremo al que apunta, fuera
/// de la tarjeta.
ArrowHead? treeArrowHead(CanvasTreeEntry entry, Offset parent, Offset child) {
  if (entry.relation == null) return null;
  final from = entry.outgoing ? parent : child;
  final to = entry.outgoing ? child : parent;
  return arrowHead(
    from,
    to,
    back: math.min((to - from).distance * 0.3, 40),
    length: 9,
    half: 5,
  );
}

/// Las líneas entre cada nodo y su padre. Las de un vínculo llevan el tipo, el
/// color de su tipo y una punta de flecha hacia donde apunta.
class MapTreeEdgesPainter extends CustomPainter {
  const MapTreeEdgesPainter({
    required this.entries,
    required this.positions,
    required this.colors,
    required this.labelOf,
    required this.textColor,
  });

  final List<CanvasTreeEntry> entries;
  final Map<String, Offset> positions;
  final ColorScheme colors;
  final String? Function(CanvasTreeEntry entry) labelOf;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in entries) {
      final parent = entry.parentKey == null
          ? null
          : positions[entry.parentKey];
      final child = positions[entry.key];
      if (parent == null || child == null) continue;

      final color = treeEdgeColor(entry, colors);
      canvas.drawLine(
        parent,
        child,
        Paint()
          ..color = color
          ..strokeWidth = entry.relation == RelationKind.contradicts
              ? 2.5
              : 1.5,
      );
      final head = treeArrowHead(entry, parent, child);
      if (head != null) {
        canvas.drawPath(arrowPath(head), Paint()..color = color);
      }
      final label = labelOf(entry);
      if (label != null) _paintLabel(canvas, label, (parent + child) / 2);
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 11, color: textColor),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 110);
    final box = Rect.fromCenter(
      center: at,
      width: painter.width + 8,
      height: painter.height + 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = colors.surface.withValues(alpha: 0.9),
    );
    painter.paint(canvas, box.topLeft + const Offset(4, 1));
  }

  @override
  bool shouldRepaint(MapTreeEdgesPainter old) =>
      old.entries != entries ||
      old.positions != positions ||
      old.colors != colors;
}

/// El árbol como un documento SVG: las mismas uniones, con su tipo y su
/// punta, y las mismas tarjetas que en pantalla.
String treeSvg({
  required CanvasTree tree,
  required Map<String, Offset> positions,
  required Size canvas,
  required ColorScheme colors,
  required Brightness brightness,
  required AppLocalizations l10n,
}) {
  final svg = SvgWriter(
    width: math.max(canvas.width, 1),
    height: math.max(canvas.height, 1),
    background: colors.surface,
  );

  for (final entry in tree.entries.values) {
    final parent = entry.parentKey == null ? null : positions[entry.parentKey];
    final child = positions[entry.key];
    if (parent == null || child == null) continue;
    final color = treeEdgeColor(entry, colors);
    svg.line(
      parent,
      child,
      color: color,
      strokeWidth: entry.relation == RelationKind.contradicts ? 2.5 : 1.5,
    );
    final head = treeArrowHead(entry, parent, child);
    if (head != null) {
      svg.triangle(head.tip, head.left, head.right, fill: color);
    }
    final label = treeEdgeLabel(l10n, entry);
    if (label != null) {
      svg.text(
        label,
        (parent + child) / 2 + const Offset(0, 4),
        color: colors.onSurfaceVariant,
        size: 11,
      );
    }
  }

  for (final entry in tree.entries.values) {
    final at = positions[entry.key];
    if (at == null) continue;
    final isItem = entry.ref.kind == CanvasTreeKind.item;
    final role = entry.isNote ? EntityRole.note : EntityRole.source;
    final accent = treeAccentOf(entry, colors, brightness);
    svg
      ..rect(
        Rect.fromCenter(
          center: at,
          width: kTreeNodeSize.width,
          height: kTreeNodeSize.height,
        ),
        fill: isItem ? role.surface(colors) : colors.surfaceContainerHigh,
        stroke: entry.expanded ? accent : accent.withValues(alpha: 0.5),
        strokeWidth: entry.expanded ? 2 : 1,
        radius: isItem ? role.radius : 8,
      )
      ..text(
        SvgWriter.ellipsize(entry.title, 22),
        Offset(at.dx - kTreeNodeSize.width / 2 + 12, at.dy + 4),
        color: colors.onSurface,
        anchor: 'start',
      );
  }
  return svg.build();
}

/// De dónde parte Radial, Árbol y la lista: el nombre de la raíz, que al
/// tocarlo deja partir de una nota mapa o de cualquier tema, y —si se eligió
/// una— la ✕ que vuelve a lo que se mira.
class MapTreeRootRow extends StatelessWidget {
  const MapTreeRootRow({
    required this.root,
    required this.chosen,
    required this.onPick,
    required this.onReset,
    super.key,
  });

  /// La raíz del árbol, o `null` si todavía no se armó.
  final CanvasTreeEntry? root;

  /// Si la raíz la eligió la persona, en vez de ser lo que se mira.
  final bool chosen;
  final VoidCallback onPick;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final root = this.root;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: l10n.mapSchemaRootTooltip,
              child: OutlinedButton.icon(
                key: const ValueKey('map-tree-root'),
                onPressed: onPick,
                icon: Icon(
                  root == null ? Icons.account_tree_outlined : treeIconOf(root),
                ),
                label: Text(
                  root?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (chosen)
            IconButton(
              key: const ValueKey('map-tree-root-reset'),
              tooltip: l10n.f44S2RootReset,
              icon: const Icon(Icons.close),
              onPressed: onReset,
            ),
        ],
      ),
    );
  }
}
