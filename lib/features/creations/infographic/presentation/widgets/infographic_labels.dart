import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los nombres de lo del diseño de una infografía, en el idioma de la app
/// (F43).
extension InfographicLabels on AppLocalizations {
  String infographicStyle(InfographicStyleId id) => switch (id) {
    InfographicStyleId.auto => f43InfoStyleAuto,
    InfographicStyleId.editorial => f43InfoStyleEditorial,
    InfographicStyleId.geometric => f43InfoStyleGeometric,
    InfographicStyleId.swiss => f43InfoStyleSwiss,
    InfographicStyleId.bento => f43InfoStyleBento,
    InfographicStyleId.chalkboard => f43InfoStyleChalkboard,
    InfographicStyleId.neon => f43InfoStyleNeon,
    InfographicStyleId.parchment => f43InfoStyleParchment,
    InfographicStyleId.corporate => f43InfoStyleCorporate,
    InfographicStyleId.pastel => f43InfoStylePastel,
    InfographicStyleId.kids => f43InfoStyleKids,
    InfographicStyleId.data => f43InfoStyleData,
    InfographicStyleId.clay => f43InfoStyleClay,
    InfographicStyleId.kawaii => f43InfoStyleKawaii,
    InfographicStyleId.watercolor => f43InfoStyleWatercolor,
    InfographicStyleId.isometric => f43InfoStyleIsometric,
    InfographicStyleId.comic => f43InfoStyleComic,
    InfographicStyleId.photo => f43InfoStylePhoto,
  };

  String infographicFamily(InfographicStyleFamily family) => switch (family) {
    InfographicStyleFamily.drawn => f43InfoFamilyDrawn,
    InfographicStyleFamily.illustrated => f43InfoFamilyIllustrated,
  };

  String infographicComposition(InfographicComposition c) => switch (c) {
    InfographicComposition.auto => f43InfoCompositionAuto,
    InfographicComposition.bento => f43InfoCompositionBento,
    InfographicComposition.columns => f43InfoCompositionColumns,
    InfographicComposition.zigzag => f43InfoCompositionZigzag,
    InfographicComposition.timeline => f43InfoCompositionTimeline,
    InfographicComposition.process => f43InfoCompositionProcess,
    InfographicComposition.radial => f43InfoCompositionRadial,
    InfographicComposition.comparison => f43InfoCompositionComparison,
    InfographicComposition.pyramid => f43InfoCompositionPyramid,
    InfographicComposition.statPanel => f43InfoCompositionStatPanel,
    InfographicComposition.conceptMap => f43InfoCompositionConceptMap,
  };

  String infographicOrientation(InfographicOrientation o) => switch (o) {
    InfographicOrientation.landscape => f43InfoOrientationLandscape,
    InfographicOrientation.portrait => f43InfoOrientationPortrait,
    InfographicOrientation.square => f43InfoOrientationSquare,
  };

  String infographicDetail(InfographicDetail d) => switch (d) {
    InfographicDetail.concise => f43InfoDetailConcise,
    InfographicDetail.standard => f43InfoDetailStandard,
    InfographicDetail.detailed => f43InfoDetailDetailed,
  };

  String infographicIcons(InfographicIconLook look) => switch (look) {
    InfographicIconLook.soft => f43InfoIconsSoft,
    InfographicIconLook.solid => f43InfoIconsSolid,
    InfographicIconLook.outline => f43InfoIconsOutline,
    InfographicIconLook.bare => f43InfoIconsBare,
    InfographicIconLook.none => f43InfoIconsNone,
  };

  String infographicBackground(InfographicBackground b) => switch (b) {
    InfographicBackground.plain => f43InfoBackgroundPlain,
    InfographicBackground.texture => f43InfoBackgroundTexture,
    InfographicBackground.gradient => f43InfoBackgroundGradient,
  };

  /// Una lámina de muestra, en el idioma de la app: para el carrusel de
  /// estilos de la hoja de crear, antes de que haya una infografía de
  /// verdad. Trae una cifra, tres ideas y su idea para llevarse.
  Infographic infographicSample() => Infographic(
    title: f43InfoSampleTitle,
    subtitle: f43InfoSampleSubtitle,
    takeaway: f43InfoSampleTakeaway,
    blocks: [
      InfographicBlock.stat(
        value: '75 %',
        label: f43InfoSampleStatLabel,
        icon: 'insights',
      ),
      InfographicBlock.fact(
        title: f43InfoSampleIdea1,
        detail: f43InfoSampleIdea1Detail,
        icon: 'lightbulb',
      ),
      InfographicBlock.fact(
        title: f43InfoSampleIdea2,
        detail: f43InfoSampleIdea2Detail,
        icon: 'hub',
      ),
      InfographicBlock.fact(
        title: f43InfoSampleIdea3,
        detail: f43InfoSampleIdea3Detail,
        icon: 'star',
      ),
    ],
  );
}
