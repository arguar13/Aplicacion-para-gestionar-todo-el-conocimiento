import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_canvas.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_flows.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_grids.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_more.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_parts.dart';

export 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_parts.dart'
    show InfographicIllustrationResolver;

/// Una infografía dibujada (F43): su contenido ([sheet]) con su diseño
/// ([design]), a cualquier tamaño.
///
/// Se compone una sola vez en el lienzo lógico de la orientación (1920×1080,
/// 1080×1920 o 1440×1440) y se escala entera para caber en el lugar que le
/// den, así la miniatura de la galería, el visor y la imagen exportada son
/// la misma lámina. El texto se ajusta solo contra el lienzo y nunca
/// desborda.
///
/// «Automático» y «Automática» se resuelven acá, con lo que dice el
/// contenido (ver `InfographicAuto`): nada vuelve a la IA. Se basta sola
/// —trae su dirección de texto y su estilo de letra—, así se puede dibujar
/// fuera de pantalla para el PNG y el PDF (ver `InfographicExporter`).
class InfographicView extends StatelessWidget {
  const InfographicView({
    required this.sheet,
    required this.design,
    this.illustrations,
    this.borderRadius = BorderRadius.zero,
    this.shadow = false,
    super.key,
  });

  final Infographic sheet;
  final InfographicDesign design;

  /// Cómo encontrar las ilustraciones ya hechas; sin esto, todos los
  /// bloques que quieren una dibujan la de reserva.
  final InfographicIllustrationResolver? illustrations;

  /// El redondeo de las esquinas, en píxeles de pantalla.
  final BorderRadius borderRadius;
  final bool shadow;

  /// El estilo resuelto con que se dibuja [sheet] con [design].
  static InfographicStyle styleOf(
    Infographic sheet,
    InfographicDesign design,
  ) => InfographicStyle(
    design: design,
    arrangement: InfographicAuto.arrange(sheet, design),
  );

  @override
  Widget build(BuildContext context) {
    final style = styleOf(sheet, design);
    final c = InfoContext(
      style: style,
      sheet: sheet,
      illustrations: illustrations,
    );
    return Semantics(
      label: sheet.title,
      // Se basta sola también para el lector de pantalla: fuera de una app
      // (la imagen exportada, una prueba) no hay una dirección heredada.
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      container: true,
      explicitChildNodes: true,
      child: CreationCanvas(
        logicalSize: style.canvas,
        borderRadius: borderRadius,
        shadow: shadow,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: style.body(),
            child: InfoFrame(context: c, body: _body(c)),
          ),
        ),
      ),
    );
  }

  static Widget _body(InfoContext c) {
    if (c.blocks.isEmpty) return const SizedBox.expand();
    return switch (c.style.arrangement.composition) {
      InfographicComposition.auto ||
      InfographicComposition.bento => BentoComposition(c: c),
      InfographicComposition.columns => ColumnsComposition(c: c),
      InfographicComposition.zigzag => ZigzagComposition(c: c),
      InfographicComposition.timeline => TimelineComposition(c: c),
      InfographicComposition.process => ProcessComposition(c: c),
      InfographicComposition.radial => RadialComposition(c: c),
      InfographicComposition.comparison => ComparisonComposition(c: c),
      InfographicComposition.pyramid => PyramidComposition(c: c),
      InfographicComposition.statPanel => StatPanelComposition(c: c),
      InfographicComposition.conceptMap => ConceptMapComposition(c: c),
      InfographicComposition.verticalTimeline => VerticalTimelineComposition(
        c: c,
      ),
      InfographicComposition.comparisonTable => ComparisonTableComposition(
        c: c,
      ),
      InfographicComposition.funnel => FunnelComposition(c: c),
      InfographicComposition.cycle => CycleComposition(c: c),
      InfographicComposition.topicMap => TopicMapComposition(c: c),
      InfographicComposition.statMosaic => StatMosaicComposition(c: c),
    };
  }
}
