import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_labels.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_export.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/widgets/infographic_style_option.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/widgets/infographic_viewer.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/widgets/infographic_viewer_actions.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La Infografía en Repasar (F43, paso 12): la de fábrica —idioma,
/// orientación, detalle, «Ilustraciones con IA», fuentes y descripción— con
/// «Estilo visual» en un carrusel con muestra, lo que estima según el estilo
/// y el detalle, su visor con zoom y cambio de estilo, sus botones y su
/// archivo (imagen o PDF).
final infographicKindSpecProvider = Provider<CreationKindSpec>(
  (ref) => defaultCreationKindSpec(StudyCreationKind.infographic).copyWith(
    optionsBuilder: (context, options) =>
        InfographicStyleOption(options: options),
    requestLines: infographicRequestLines,
    extraDefaults: {InfographicOptionKeys.style: InfographicStyleId.auto.id},
    expectedOutputTokens: infographicOutputTokens,
    illustrations: infographicIllustrationsFor,
    viewerBuilder: (context, creation) => InfographicViewer(creation: creation),
    viewerActions: infographicViewerActions,
    exporter: infographicExporter,
  ),
);

/// Lo pedido con el carrusel y el visor, para «Ver petición y fuentes»: el
/// estilo visual y, si se eligió una en el visor, la composición. La
/// orientación y el detalle ya los dice la hoja, que los conoce.
List<(String, String)> infographicRequestLines(
  AppLocalizations l10n,
  Map<String, Object?> options,
) {
  final design = infographicDesignOf(options);
  return [
    (l10n.f43InfoDesignStyle, l10n.infographicStyle(design.style)),
    if (design.composition != InfographicComposition.auto)
      (
        l10n.f43InfoDesignComposition,
        l10n.infographicComposition(design.composition),
      ),
  ];
}
