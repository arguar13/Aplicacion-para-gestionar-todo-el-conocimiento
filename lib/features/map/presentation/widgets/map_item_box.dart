import 'package:flutter/material.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/services/svg_writer.dart';

/// El tamaño de la caja de un elemento en el Mapa: la misma en el nivel de
/// elementos del grafo y en la vista «Vínculos» (F28).
const kMapItemBoxSize = Size(150, 34);

/// Un elemento del Mapa —una nota o una fuente— como se dibuja en el grafo y
/// en la vista «Vínculos»: una caja con el ícono y el color de lo que es y su
/// título en una línea. Con [highlighted], el borde del color de lo que es, y
/// más grueso: el elemento en el que se puso el foco.
class MapItemBox extends StatelessWidget {
  const MapItemBox({
    required this.isNote,
    required this.label,
    this.highlighted = false,
    super.key,
  });

  final bool isNote;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final role = isNote ? EntityRole.note : EntityRole.source;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: role.surface(colors),
        border: Border.all(
          color: highlighted ? role.accent(colors) : role.outline(colors),
          width: highlighted ? 2.5 : 1,
        ),
        borderRadius: BorderRadius.circular(role.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(
              isNote ? Icons.sticky_note_2_outlined : Icons.article_outlined,
              size: 14,
              color: role.accent(colors),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Escribe en [svg] la caja de un elemento centrada en [at], como la dibuja
/// [MapItemBox]: lo que exportan el grafo y la vista «Vínculos».
void writeMapItemBoxSvg(
  SvgWriter svg, {
  required bool isNote,
  required String label,
  required Offset at,
  required ColorScheme colors,
  bool highlighted = false,
}) {
  final role = isNote ? EntityRole.note : EntityRole.source;
  svg
    ..rect(
      Rect.fromCenter(
        center: at,
        width: kMapItemBoxSize.width,
        height: kMapItemBoxSize.height,
      ),
      fill: role.surface(colors),
      stroke: highlighted ? role.accent(colors) : role.outline(colors),
      radius: role.radius,
    )
    ..text(
      SvgWriter.ellipsize(label, 22),
      Offset(at.dx - kMapItemBoxSize.width / 2 + 10, at.dy + 4),
      color: colors.onSurface,
      size: 11,
      anchor: 'start',
    );
}
