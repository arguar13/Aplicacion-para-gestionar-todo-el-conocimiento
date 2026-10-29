import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_scene.dart';

/// Los textos que dice el mapa para el lector de pantalla y en los «›»: los
/// pone quien lo muestra, así el dibujo no depende de la localización —la
/// imagen exportada no los usa—.
@immutable
class MindMapCanvasLabels {
  const MindMapCanvasLabels({
    required this.node,
    required this.open,
    required this.close,
    required this.hint,
  });

  /// Lo que se dice de un nodo: su nombre, su nivel y sus ramas.
  final String Function(MindMapNode node, int depth, {required bool open}) node;

  /// «Abrir rama» y «Cerrar rama».
  final String open;
  final String close;

  /// Qué hace tocarlo.
  final String hint;
}

/// El mapa mental dibujado (F43): las uniones como curvas suaves del color
/// del tipo y los nodos redondeados, cada nivel con su tinte, donde los
/// acomodó [MindMapScene]. Ocupa exactamente `scene.size`.
///
/// Es el mismo para la pantalla —con [onTapNode] y [onToggle], dentro del
/// visor que acerca y arrastra— y para la imagen que se exporta, sin ellos:
/// lo exportado es fiel por construcción.
class MindMapCanvas extends StatelessWidget {
  const MindMapCanvas({
    required this.scene,
    required this.palette,
    required this.metrics,
    this.expanded = const {},
    this.onTapNode,
    this.onToggle,
    this.labels,
    super.key,
  });

  final MindMapScene scene;
  final MindMapPalette palette;
  final MindMapMetrics metrics;

  /// Las ramas abiertas: su «›» apunta hacia atrás («‹»).
  final Set<String> expanded;

  final ValueChanged<MindMapNode>? onTapNode;
  final ValueChanged<MindMapNode>? onToggle;
  final MindMapCanvasLabels? labels;

  @override
  Widget build(BuildContext context) {
    final layout = scene.layout;
    return SizedBox.fromSize(
      size: scene.size,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: MindMapEdgesPainter(
                rects: layout.rects,
                edges: layout.edges,
                color: palette.edge,
              ),
            ),
          ),
          for (final entry in layout.rects.entries)
            Positioned.fromRect(
              key: ValueKey('mind-map-node-${entry.key}'),
              rect: entry.value,
              child: _NodeBox(
                node: scene.nodes[entry.key]!,
                depth: scene.depths[entry.key]!,
                palette: palette,
                metrics: metrics,
                open: expanded.contains(entry.key),
                onTap: onTapNode,
                onToggle: onToggle,
                labels: labels,
              ),
            ),
        ],
      ),
    );
  }
}

class _NodeBox extends StatelessWidget {
  const _NodeBox({
    required this.node,
    required this.depth,
    required this.palette,
    required this.metrics,
    required this.open,
    required this.onTap,
    required this.onToggle,
    required this.labels,
  });

  final MindMapNode node;
  final int depth;
  final MindMapPalette palette;
  final MindMapMetrics metrics;
  final bool open;
  final ValueChanged<MindMapNode>? onTap;
  final ValueChanged<MindMapNode>? onToggle;
  final MindMapCanvasLabels? labels;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(depth == 0 ? 22 : 16);
    final textColor = palette.textAt(depth);
    final text = Text(
      node.label,
      maxLines: MindMapMetrics.maxLines,
      overflow: TextOverflow.ellipsis,
      textWidthBasis: TextWidthBasis.longestLine,
      textScaler: metrics.textScaler,
      style: metrics.styleAt(depth).copyWith(color: textColor),
    );
    final toggles = metrics.interactive && node.hasChildren;
    final body = Padding(
      padding: EdgeInsetsDirectional.only(
        start: MindMapMetrics.horizontalPadding,
        end: toggles
            ? MindMapMetrics.toggleGap
            : MindMapMetrics.horizontalPadding,
      ),
      child: Row(
        children: [
          // El texto ya está medido: el nodo es de su ancho justo.
          Expanded(
            child: labels == null ? text : ExcludeSemantics(child: text),
          ),
          if (toggles) ...[
            const SizedBox(width: MindMapMetrics.toggleGap),
            _Toggle(
              id: node.id,
              open: open,
              palette: palette,
              depth: depth,
              label: labels == null
                  ? null
                  : open
                  ? labels!.close
                  : labels!.open,
              onPressed: onToggle == null ? null : () => onToggle!(node),
            ),
          ],
        ],
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: radius,
      side: depth == 0
          ? BorderSide.none
          : BorderSide(color: palette.borderAt(depth), width: 1.2),
    );
    final tap = onTap;
    final box = Material(
      color: palette.fillAt(depth),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: tap == null ? body : InkWell(onTap: () => tap(node), child: body),
    );
    final said = labels;
    if (said == null) return box;
    return Semantics(
      container: true,
      button: tap != null,
      label: said.node(node, depth, open: open),
      hint: said.hint,
      child: box,
    );
  }
}

/// El «›» de una idea con ramas: un círculo chico al final del nodo. Abierta,
/// apunta hacia atrás («‹»), como en NotebookLM.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.id,
    required this.open,
    required this.palette,
    required this.depth,
    required this.label,
    required this.onPressed,
  });

  final String id;
  final bool open;
  final MindMapPalette palette;
  final int depth;
  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final onRoot = depth == 0;
    final circle = Container(
      width: MindMapMetrics.toggleSize,
      height: MindMapMetrics.toggleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onRoot
            ? palette.rootText.withValues(alpha: 0.18)
            : palette.toggleFill,
        border: Border.all(
          color: onRoot
              ? palette.rootText.withValues(alpha: 0.5)
              : palette.borderAt(depth),
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        open ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
        size: 20,
        color: onRoot ? palette.rootText : palette.toggleIcon,
      ),
    );
    final press = onPressed;
    if (press == null) return circle;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        key: ValueKey('mind-map-toggle-$id'),
        onTap: press,
        radius: 22,
        child: circle,
      ),
    );
  }
}

/// Las uniones del mapa: de la punta derecha de cada idea al costado
/// izquierdo de cada rama, como una curva suave (una cúbica que sale y llega
/// horizontal).
class MindMapEdgesPainter extends CustomPainter {
  MindMapEdgesPainter({
    required this.rects,
    required this.edges,
    required this.color,
  });

  final Map<String, Rect> rects;
  final List<(String, String)> edges;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final path = Path();
    for (final (parent, child) in edges) {
      final from = rects[parent];
      final to = rects[child];
      if (from == null || to == null) continue;
      final start = Offset(from.right, from.center.dy);
      final end = Offset(to.left, to.center.dy);
      final middle = (start.dx + end.dx) / 2;
      path
        ..moveTo(start.dx, start.dy)
        ..cubicTo(middle, start.dy, middle, end.dy, end.dx, end.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MindMapEdgesPainter old) =>
      old.rects != rects || old.edges != edges || old.color != color;
}
