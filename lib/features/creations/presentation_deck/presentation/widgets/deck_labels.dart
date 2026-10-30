import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los nombres de lo del diseño de un mazo, en el idioma de la app (F43).
extension DeckLabels on AppLocalizations {
  String deckFamily(DeckTemplateFamily family) => switch (family) {
    DeckTemplateFamily.classic => f43DeckFamilyClassic,
    DeckTemplateFamily.modern => f43DeckFamilyModern,
    DeckTemplateFamily.graphic => f45S5DeckFamilyGraphic,
    DeckTemplateFamily.dark => f43DeckFamilyDark,
    DeckTemplateFamily.warm => f43DeckFamilyWarm,
    DeckTemplateFamily.business => f43DeckFamilyBusiness,
  };

  String deckTemplate(DeckTemplateId id) => switch (id) {
    DeckTemplateId.editorial => f43DeckTemplateEditorial,
    DeckTemplateId.parchment => f43DeckTemplateParchment,
    DeckTemplateId.academic => f43DeckTemplateAcademic,
    DeckTemplateId.newspaper => f45S5TemplateNewspaper,
    DeckTemplateId.ink => f45S5TemplateInk,
    DeckTemplateId.swiss => f43DeckTemplateSwiss,
    DeckTemplateId.bento => f43DeckTemplateBento,
    DeckTemplateId.aurora => f43DeckTemplateAurora,
    DeckTemplateId.glass => f43DeckTemplateGlass,
    DeckTemplateId.magazine => f45S5TemplateMagazine,
    DeckTemplateId.bauhaus => f45S5TemplateBauhaus,
    DeckTemplateId.brutalist => f45S5TemplateBrutalist,
    DeckTemplateId.midnight => f43DeckTemplateMidnight,
    DeckTemplateId.neon => f43DeckTemplateNeon,
    DeckTemplateId.chalkboard => f43DeckTemplateChalkboard,
    DeckTemplateId.darkMinimal => f45S5TemplateDarkMinimal,
    DeckTemplateId.terminal => f45S5TemplateTerminal,
    DeckTemplateId.artDeco => f45S5TemplateArtDeco,
    DeckTemplateId.watercolor => f43DeckTemplateWatercolor,
    DeckTemplateId.pastel => f43DeckTemplatePastel,
    DeckTemplateId.paperCut => f43DeckTemplatePaperCut,
    DeckTemplateId.retro => f45S5TemplateRetro,
    DeckTemplateId.manuscript => f45S5TemplateManuscript,
    DeckTemplateId.whiteboard => f45S5TemplateWhiteboard,
    DeckTemplateId.corporate => f43DeckTemplateCorporate,
    DeckTemplateId.data => f43DeckTemplateData,
    DeckTemplateId.executive => f43DeckTemplateExecutive,
    DeckTemplateId.blueprint => f45S5TemplateBlueprint,
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
    CreationFontPair.newsprint => f45S5FontsNewsprint,
    CreationFontPair.grotesk => f45S5FontsGrotesk,
    CreationFontPair.mono => f45S5FontsMono,
    CreationFontPair.script => f45S5FontsScript,
  };

  String deckDensity(DeckDensity density) => switch (density) {
    DeckDensity.airy => f43DeckDensityAiry,
    DeckDensity.standard => f43DeckDensityStandard,
    DeckDensity.compact => f43DeckDensityCompact,
  };

  String deckBackground(DeckBackground background) => switch (background) {
    DeckBackground.plain => f45S5DeckBackgroundPlain,
    DeckBackground.texture => f45S5DeckBackgroundTexture,
    DeckBackground.gradient => f45S5DeckBackgroundGradient,
  };

  String deckTransition(DeckTransition transition) => switch (transition) {
    DeckTransition.fade => f43DeckTransitionFade,
    DeckTransition.slide => f43DeckTransitionSlide,
    DeckTransition.zoom => f43DeckTransitionZoom,
    DeckTransition.none => f43DeckTransitionNone,
  };
}
