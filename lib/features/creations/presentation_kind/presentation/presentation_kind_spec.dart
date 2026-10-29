import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_labels.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/deck_illustration_style.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/presentation_exporter.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/widgets/presentation_options_section.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/widgets/presentation_viewer.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La Presentación en Repasar (F43, paso 11): la de fábrica —Formato,
/// Duración, Idioma, Fuentes, Descripción e «Ilustraciones con IA»— con la
/// plantilla elegida a la vista en vez de un desplegable, el estilo de las
/// ilustraciones, lo que de verdad escribe y dibuja para «Uso de IA» y
/// «Con tu IA actual», su visor y su PDF.
final presentationKindSpecProvider = Provider<CreationKindSpec>((ref) {
  final base = defaultCreationKindSpec(StudyCreationKind.presentation);
  return base.copyWith(
    // La plantilla la elige la tira con sus muestras
    // (`PresentationOptionsSection`), no el desplegable de fábrica.
    options: [
      for (final option in base.options)
        if (option.key != CreationOptionValues.template) option,
    ],
    optionsBuilder: PresentationOptionsSection.builder,
    requestLines: presentationRequestLines,
    extraDefaults: {
      CreationOptionValues.template: CreationOptionValues.auto,
      PresentationOptionKeys.illustrationStyle:
          DeckIllustrationStyle.template.id,
    },
    expectedOutputTokens: (options) =>
        PresentationOptions.of(options).expectedOutputTokens,
    illustrations: (options) =>
        PresentationOptions.of(options).maxIllustrations,
    viewerBuilder: (context, creation) =>
        PresentationViewer(creation: creation),
    viewerActions: presentationViewerActions,
    exporter: exportPresentationPdf,
  );
});

/// Lo pedido con la tira y el visor, para «Ver petición y fuentes»: la
/// plantilla —«Automática», la elegida o, si se cambió en el visor, la que
/// tiene ahora— y, con ilustraciones, su estilo. Formato, duración e
/// ilustraciones los dice la hoja, que los conoce.
List<(String, String)> presentationRequestLines(
  AppLocalizations l10n,
  Map<String, Object?> options,
) {
  final chosen = PresentationOptions.of(options);
  final saved = options[PresentationOptionKeys.design];
  final template = saved is Map
      ? DeckDesign.parse(saved).template
      : chosen.template;
  return [
    (
      l10n.f43StudioOptTemplate,
      template == null
          ? l10n.f43StudioOptTemplateAuto
          : l10n.deckTemplate(template),
    ),
    if (chosen.illustrations)
      (
        l10n.f43PresIllustrationStyle,
        illustrationStyleLabel(l10n, chosen.illustrationStyle),
      ),
  ];
}
