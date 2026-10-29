import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los nombres de lo del diseño de un mazo, en el idioma de la app (F43).
extension DeckLabels on AppLocalizations {
  String deckFamily(DeckTemplateFamily family) => switch (family) {
    DeckTemplateFamily.classic => f43DeckFamilyClassic,
    DeckTemplateFamily.modern => f43DeckFamilyModern,
    DeckTemplateFamily.dark => f43DeckFamilyDark,
    DeckTemplateFamily.warm => f43DeckFamilyWarm,
    DeckTemplateFamily.business => f43DeckFamilyBusiness,
  };

  String deckTemplate(DeckTemplateId id) => switch (id) {
    DeckTemplateId.editorial => f43DeckTemplateEditorial,
    DeckTemplateId.parchment => f43DeckTemplateParchment,
    DeckTemplateId.academic => f43DeckTemplateAcademic,
    DeckTemplateId.swiss => f43DeckTemplateSwiss,
    DeckTemplateId.bento => f43DeckTemplateBento,
    DeckTemplateId.aurora => f43DeckTemplateAurora,
    DeckTemplateId.glass => f43DeckTemplateGlass,
    DeckTemplateId.midnight => f43DeckTemplateMidnight,
    DeckTemplateId.neon => f43DeckTemplateNeon,
    DeckTemplateId.chalkboard => f43DeckTemplateChalkboard,
    DeckTemplateId.watercolor => f43DeckTemplateWatercolor,
    DeckTemplateId.pastel => f43DeckTemplatePastel,
    DeckTemplateId.paperCut => f43DeckTemplatePaperCut,
    DeckTemplateId.corporate => f43DeckTemplateCorporate,
    DeckTemplateId.data => f43DeckTemplateData,
    DeckTemplateId.executive => f43DeckTemplateExecutive,
  };

  String deckLayout(SlideLayout layout) => switch (layout) {
    SlideLayout.cover => f43DeckLayoutCover,
    SlideLayout.section => f43DeckLayoutSection,
    SlideLayout.bullets => f43DeckLayoutBullets,
    SlideLayout.twoColumns => f43DeckLayoutTwoColumns,
    SlideLayout.quote => f43DeckLayoutQuote,
    SlideLayout.bigNumber => f43DeckLayoutBigNumber,
    SlideLayout.steps => f43DeckLayoutSteps,
    SlideLayout.comparison => f43DeckLayoutComparison,
    SlideLayout.timeline => f43DeckLayoutTimeline,
    SlideLayout.imageText => f43DeckLayoutImageText,
    SlideLayout.conceptGrid => f43DeckLayoutConceptGrid,
    SlideLayout.closing => f43DeckLayoutClosing,
  };

  String deckFonts(CreationFontPair pair) => switch (pair) {
    CreationFontPair.editorial => f43DeckFontsEditorial,
    CreationFontPair.book => f43DeckFontsBook,
    CreationFontPair.swiss => f43DeckFontsSwiss,
    CreationFontPair.technical => f43DeckFontsTechnical,
    CreationFontPair.friendly => f43DeckFontsFriendly,
    CreationFontPair.handwritten => f43DeckFontsHandwritten,
  };

  String deckDensity(DeckDensity density) => switch (density) {
    DeckDensity.airy => f43DeckDensityAiry,
    DeckDensity.standard => f43DeckDensityStandard,
    DeckDensity.compact => f43DeckDensityCompact,
  };

  String deckTransition(DeckTransition transition) => switch (transition) {
    DeckTransition.fade => f43DeckTransitionFade,
    DeckTransition.slide => f43DeckTransitionSlide,
    DeckTransition.zoom => f43DeckTransitionZoom,
    DeckTransition.none => f43DeckTransitionNone,
  };
}
