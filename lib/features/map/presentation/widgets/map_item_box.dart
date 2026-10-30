import 'package:flutter/material.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/domain/services/svg_writer.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_layer_marks.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';

/// El tamaño de la caja de un elemento en el Mapa: la misma en el nivel de
/// elementos del grafo y en la vista «Vínculos» (F28).
const kMapItemBoxSize = Size(150, 34);

/// Un elemento del Mapa —una nota o una fuente— como se dibuja en el grafo y
/// en la vista «Vínculos»: una caja con el ícono y el color de lo que es y su
/// título en una línea. Con [highlighted], el borde del color de lo que es, y
/// más grueso: el elemento en el que se puso el foco. Con [study] —la capa
/// «Estudio» (F44, paso 5)—, el fondo teñido según sus tarjetas y su insignia
/// al final.
class MapItemBox extends StatelessWidget {
  const MapItemBox({
    required this.isNote,
    required this.label,
    this.highlighted = false,
    this.study,
    super.key,
  });

  final bool isNote;
  final String label;
  final bool highlighted;
  final MapStudyMark? study;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final role = isNote ? EntityRole.note : EntityRole.source;
    final study = this.study;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: study == null
            ? role.surface(colors)
            : mapStudyColors(study.state, colors).fill,
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
            if (study != null) ...[
              const SizedBox(width: 4),
              MapStudyBadge(mark: study),
            ],
          ],
        ),
      ),
    );
  }
}

/// Escribe en [svg] la caja de un elemento centrada en [at], como la dibuja
/// [MapItemBox]: lo que exportan el grafo y la vista «Vínculos». Con
/// [dimmed], apagada, como queda fuera del foco (F44, paso 4); con [study],
/// teñida y con su insignia, como la deja la capa «Estudio» (F44, paso 5).
void writeMapItemBoxSvg(
  SvgWriter svg, {
  required bool isNote,
  required String label,
  required Offset at,
  required ColorScheme colors,
  bool highlighted = false,
  bool dimmed = false,
  MapStudyMark? study,
}) {
  final role = isNote ? EntityRole.note : EntityRole.source;
  Color shown(Color color) => dimmed ? mapDimmed(color) : color;
  svg
    ..rect(
      Rect.fromCenter(
        center: at,
        width: kMapItemBoxSize.width,
        height: kMapItemBoxSize.height,
      ),
      fill: shown(
        study == null
            ? role.surface(colors)
            : mapStudyColors(study.state, colors).fill,
      ),
      stroke: shown(highlighted ? role.accent(colors) : role.outline(colors)),
      radius: role.radius,
    )
    ..text(
      // Con la insignia, el título deja lugar al final.
      SvgWriter.ellipsize(label, study == null ? 22 : 19),
      Offset(at.dx - kMapItemBoxSize.width / 2 + 10, at.dy + 4),
      color: shown(colors.onSurface),
      size: 11,
      anchor: 'start',
    );
  if (study != null) {
    writeStudyBadgeSvg(
      svg,
      Offset(
        at.dx + kMapItemBoxSize.width / 2 - 8 - kMapStudyBadgeSize / 2,
        at.dy,
      ),
      study,
      colors: colors,
      dimmed: dimmed,
    );
  }
}
