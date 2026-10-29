import 'package:flutter/painting.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style_spec.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_templates.dart';

/// Los dieciocho estilos de infografía (F43, «Plantillas → Infografía»), en
/// el orden de [InfographicStyleId].
///
/// «Automático» no tiene receta propia: se resuelve en otro según el tema
/// (ver `InfographicAuto.styleFor`); [of] le da la de Bento, que es la que
/// elige cuando no hay nada que lo incline.
///
/// Cada estilo trae seis paletas: la primera es la suya, y las otras cinco
/// lo llevan a otros gustos sin perder el carácter; los claros traen también
/// una de noche. Las de Editorial, Minimal suizo, Bento, Pizarra, Neón
/// oscuro, Pergamino, Corporativo, Pastel, Datos y Acuarela son las de la
/// plantilla de presentación del mismo nombre. Todos los pares de texto
/// cumplen AA, lo comprueba `infographic_styles_test.dart`.
abstract final class InfographicStyles {
  static final List<InfographicStyleSpec> all = [
    InfographicStyleSpec(
      id: InfographicStyleId.editorial,
      fonts: CreationFontPair.editorial,
      palettes: _deck(DeckTemplateId.editorial),
      panel: InfoPanelLook.hairline,
      header: InfoHeaderLook.editorial,
      texture: InfoTexture.grain,
      art: CreationArtStyle.linework,
      iconLook: InfographicIconLook.bare,
      radius: 4,
      titleScale: 1.06,
    ),
    const InfographicStyleSpec(
      id: InfographicStyleId.geometric,
      fonts: CreationFontPair.technical,
      palettes: _Palettes.geometric,
      panel: InfoPanelLook.flat,
      header: InfoHeaderLook.poster,
      texture: InfoTexture.shapes,
      art: CreationArtStyle.geometric,
      iconLook: InfographicIconLook.solid,
      radius: 0,
    ),
    InfographicStyleSpec(
      id: InfographicStyleId.swiss,
      fonts: CreationFontPair.swiss,
      palettes: _deck(DeckTemplateId.swiss),
      panel: InfoPanelLook.hairline,
      header: InfoHeaderLook.poster,
      texture: InfoTexture.grid,
      art: CreationArtStyle.geometric,
      background: InfographicBackground.plain,
      iconLook: InfographicIconLook.bare,
      radius: 0,
      titleScale: 1.1,
    ),
    InfographicStyleSpec(
      id: InfographicStyleId.bento,
      fonts: CreationFontPair.swiss,
      palettes: _deck(DeckTemplateId.bento),
      panel: InfoPanelLook.tile,
      header: InfoHeaderLook.editorial,
      texture: InfoTexture.dots,
      art: CreationArtStyle.geometric,
      background: InfographicBackground.plain,
      radius: 36,
    ),
    InfographicStyleSpec(
      id: InfographicStyleId.chalkboard,
      fonts: CreationFontPair.handwritten,
      palettes: _deck(DeckTemplateId.chalkboard),
      panel: InfoPanelLook.chalk,
      header: InfoHeaderLook.centered,
      texture: InfoTexture.chalk,
      art: CreationArtStyle.chalk,
      iconLook: InfographicIconLook.outline,
      connector: InfoConnectorLook.hand,
      radius: 12,
      centered: true,
    ),
    InfographicStyleSpec(
      id: InfographicStyleId.neon,
      fonts: CreationFontPair.technical,
      palettes: _deck(DeckTemplateId.neon),
      panel: InfoPanelLook.neon,
      header: InfoHeaderLook.poster,
      texture: InfoTexture.neon,
      art: CreationArtStyle.neon,
      iconLook: InfographicIconLook.outline,
      connector: InfoConnectorLook.glow,
      radius: 18,
      uppercaseTitles: true,
    ),
    InfographicStyleSpec(
      id: InfographicStyleId.parchment,
      fonts: CreationFontPair.book,
      palettes: _deck(DeckTemplateId.parchment),
      panel: InfoPanelLook.framed,
      header: InfoHeaderLook.centered,
      texture: InfoTexture.parchment,
      art: CreationArtStyle.organic,
      iconLook: InfographicIconLook.outline,
      connector: InfoConnectorLook.dashed,
      radius: 4,
      centered: true,
    ),
    InfographicStyleSpec(
      id: InfographicStyleId.corporate,
      fonts: CreationFontPair.swiss,
      palettes: _deck(DeckTemplateId.corporate),
      panel: InfoPanelLook.card,
      header: InfoHeaderLook.banner,
      texture: InfoTexture.dots,
      art: CreationArtStyle.geometric,
      background: InfographicBackground.plain,
      iconLook: InfographicIconLook.solid,
      radius: 12,
      titleScale: 0.96,
    ),
    InfographicStyleSpec(
      id: InfographicStyleId.pastel,
      fonts: CreationFontPair.friendly,
      palettes: _deck(DeckTemplateId.pastel),
      panel: InfoPanelLook.card,
      header: InfoHeaderLook.centered,
      texture: InfoTexture.bubbles,
      art: CreationArtStyle.geometric,
      radius: 34,
      centered: true,
    ),
    const InfographicStyleSpec(
      id: InfographicStyleId.kids,
      fonts: CreationFontPair.friendly,
      palettes: _Palettes.kids,
      panel: InfoPanelLook.playful,
      header: InfoHeaderLook.centered,
      texture: InfoTexture.confetti,
      art: CreationArtStyle.paper,
      iconLook: InfographicIconLook.solid,
      connector: InfoConnectorLook.hand,
      radius: 30,
      titleScale: 1.06,
      centered: true,
    ),
    InfographicStyleSpec(
      id: InfographicStyleId.data,
      fonts: CreationFontPair.technical,
      palettes: _deck(DeckTemplateId.data),
      panel: InfoPanelLook.outline,
      header: InfoHeaderLook.editorial,
      texture: InfoTexture.grid,
      art: CreationArtStyle.data,
      iconLook: InfographicIconLook.outline,
      radius: 14,
    ),
    const InfographicStyleSpec(
      id: InfographicStyleId.clay,
      fonts: CreationFontPair.friendly,
      palettes: _Palettes.clay,
      panel: InfoPanelLook.clay,
      header: InfoHeaderLook.hero,
      texture: InfoTexture.bubbles,
      art: CreationArtStyle.clay,
      background: InfographicBackground.gradient,
      iconLook: InfographicIconLook.solid,
      radius: 40,
      illustrationHint:
          'claymation style, cute plasticine 3D figures with visible '
          'fingerprints, soft studio lighting, pastel background, no text',
    ),
    const InfographicStyleSpec(
      id: InfographicStyleId.kawaii,
      fonts: CreationFontPair.friendly,
      palettes: _Palettes.kawaii,
      panel: InfoPanelLook.tinted,
      header: InfoHeaderLook.hero,
      texture: InfoTexture.dots,
      art: CreationArtStyle.kawaii,
      background: InfographicBackground.gradient,
      connector: InfoConnectorLook.dashed,
      radius: 36,
      centered: true,
      illustrationHint:
          'kawaii illustration, adorable round characters with tiny faces, '
          'flat pastel colors, thick soft outlines, sparkles, no text',
    ),
    InfographicStyleSpec(
      id: InfographicStyleId.watercolor,
      fonts: CreationFontPair.book,
      palettes: _deck(DeckTemplateId.watercolor),
      panel: InfoPanelLook.card,
      header: InfoHeaderLook.hero,
      texture: InfoTexture.watercolor,
      art: CreationArtStyle.organic,
      iconLook: InfographicIconLook.outline,
      connector: InfoConnectorLook.dashed,
      radius: 26,
      illustrationHint:
          'delicate watercolor painting, loose wet brush strokes, soft '
          'bleeding pigments on textured white paper, no text',
    ),
    const InfographicStyleSpec(
      id: InfographicStyleId.isometric,
      fonts: CreationFontPair.technical,
      palettes: _Palettes.isometric,
      panel: InfoPanelLook.tile,
      header: InfoHeaderLook.hero,
      texture: InfoTexture.isometric,
      art: CreationArtStyle.isometric,
      iconLook: InfographicIconLook.solid,
      radius: 18,
      illustrationHint:
          'clean isometric 3D illustration, low-poly blocks and tiny '
          'objects on a floating platform, soft shadows, no text',
    ),
    const InfographicStyleSpec(
      id: InfographicStyleId.comic,
      fonts: CreationFontPair.friendly,
      palettes: _Palettes.comic,
      panel: InfoPanelLook.sticker,
      header: InfoHeaderLook.hero,
      texture: InfoTexture.halftone,
      art: CreationArtStyle.comic,
      iconLook: InfographicIconLook.solid,
      radius: 14,
      titleScale: 1.08,
      uppercaseTitles: true,
      illustrationHint:
          'comic book panel art, bold black ink outlines, halftone dots, '
          'vivid flat colors, dynamic action, no speech balloons, no text',
    ),
    const InfographicStyleSpec(
      id: InfographicStyleId.photo,
      fonts: CreationFontPair.editorial,
      palettes: _Palettes.photo,
      panel: InfoPanelLook.card,
      header: InfoHeaderLook.hero,
      texture: InfoTexture.bokeh,
      art: CreationArtStyle.photo,
      background: InfographicBackground.plain,
      iconLook: InfographicIconLook.bare,
      radius: 20,
      illustrationHint:
          'professional editorial photograph, natural light, shallow depth '
          'of field, realistic, high detail, no text, no watermark',
    ),
  ];

  /// La receta de [id]; la de Bento para «Automático» sin resolver.
  static InfographicStyleSpec of(InfographicStyleId id) {
    final concrete = id == InfographicStyleId.auto
        ? InfographicStyleId.bento
        : id;
    return all.firstWhere((spec) => spec.id == concrete);
  }

  static List<CreationPalette> _deck(DeckTemplateId id) =>
      DeckTemplates.of(id).palettes;
}

abstract final class _Palettes {
  static const geometric = [
    // Bauhaus: rojo, azul y amarillo sobre crema.
    CreationPalette(
      background: Color(0xFFF4EFE6),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFD7263D),
      secondary: Color(0xFF1B4F9C),
      accent: Color(0xFFF2B705),
      text: Color(0xFF151515),
      muted: Color(0xFF55524D),
    ),
    // Menta.
    CreationPalette(
      background: Color(0xFFEEF5F1),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF0F7B6C),
      secondary: Color(0xFF2D3A8C),
      accent: Color(0xFFF28C28),
      text: Color(0xFF10201C),
      muted: Color(0xFF4A5A55),
    ),
    // Coral.
    CreationPalette(
      background: Color(0xFFFFF4EE),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFE4572E),
      secondary: Color(0xFF2E294E),
      accent: Color(0xFF29A19C),
      text: Color(0xFF1E1A26),
      muted: Color(0xFF5B5560),
    ),
    // Índigo.
    CreationPalette(
      background: Color(0xFFF1F2FA),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF3D3BBF),
      secondary: Color(0xFFE8505B),
      accent: Color(0xFFF9C80E),
      text: Color(0xFF141530),
      muted: Color(0xFF50516B),
    ),
    // Terracota.
    CreationPalette(
      background: Color(0xFFF6EEE3),
      surface: Color(0xFFFFFBF5),
      primary: Color(0xFFB5523B),
      secondary: Color(0xFF3F6E5E),
      accent: Color(0xFFE0A458),
      text: Color(0xFF2A1D16),
      muted: Color(0xFF5F5047),
    ),
    // Noche.
    CreationPalette(
      background: Color(0xFF16181D),
      surface: Color(0xFF22252C),
      primary: Color(0xFFFF6B57),
      secondary: Color(0xFF5AA9E6),
      accent: Color(0xFFFFD166),
      text: Color(0xFFF4F1EA),
      muted: Color(0xFFADA9A0),
    ),
  ];

  static const kids = [
    // Recreo.
    CreationPalette(
      background: Color(0xFFFFF8E7),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFFF6B35),
      secondary: Color(0xFF2EC4B6),
      accent: Color(0xFFFFBF00),
      text: Color(0xFF22223B),
      muted: Color(0xFF56566E),
    ),
    // Cielo.
    CreationPalette(
      background: Color(0xFFEAF6FF),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF1E88E5),
      secondary: Color(0xFFFF4F79),
      accent: Color(0xFFFFC233),
      text: Color(0xFF0D2440),
      muted: Color(0xFF46607A),
    ),
    // Selva.
    CreationPalette(
      background: Color(0xFFEFFAEA),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF2E9E4F),
      secondary: Color(0xFFFF7A00),
      accent: Color(0xFF8E44AD),
      text: Color(0xFF13301C),
      muted: Color(0xFF4B6352),
    ),
    // Chicle.
    CreationPalette(
      background: Color(0xFFFFF0F6),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFE83F8C),
      secondary: Color(0xFF6C5CE7),
      accent: Color(0xFF00B894),
      text: Color(0xFF2D1430),
      muted: Color(0xFF634F66),
    ),
    // Arena.
    CreationPalette(
      background: Color(0xFFFBF3E4),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFD35400),
      secondary: Color(0xFF2980B9),
      accent: Color(0xFF27AE60),
      text: Color(0xFF2B2118),
      muted: Color(0xFF5E5246),
    ),
    // Noche estrellada.
    CreationPalette(
      background: Color(0xFF1B1E3C),
      surface: Color(0xFF272B52),
      primary: Color(0xFFFFB703),
      secondary: Color(0xFF8ECAE6),
      accent: Color(0xFFFB8500),
      text: Color(0xFFF7F7FF),
      muted: Color(0xFFB7B9D6),
    ),
  ];

  static const clay = [
    // Plastilina.
    CreationPalette(
      background: Color(0xFFF6EFE8),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFE76F51),
      secondary: Color(0xFF2A9D8F),
      accent: Color(0xFFE9C46A),
      text: Color(0xFF26201C),
      muted: Color(0xFF5C534C),
    ),
    // Menta y durazno.
    CreationPalette(
      background: Color(0xFFEEF6F2),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFF28F79),
      secondary: Color(0xFF3BA99C),
      accent: Color(0xFFF6C453),
      text: Color(0xFF1C2B27),
      muted: Color(0xFF4F605A),
    ),
    // Lavanda.
    CreationPalette(
      background: Color(0xFFF3F0FA),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF8E6CCF),
      secondary: Color(0xFFF08A9B),
      accent: Color(0xFF5CC8C2),
      text: Color(0xFF221C33),
      muted: Color(0xFF5A5468),
    ),
    // Cielo.
    CreationPalette(
      background: Color(0xFFEDF4FB),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF4A90D9),
      secondary: Color(0xFFF2A541),
      accent: Color(0xFF7CC47F),
      text: Color(0xFF152435),
      muted: Color(0xFF4B5D70),
    ),
    // Frutilla.
    CreationPalette(
      background: Color(0xFFFCEFEF),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFD9485B),
      secondary: Color(0xFF5B8DEF),
      accent: Color(0xFFFFC75F),
      text: Color(0xFF2E1A1E),
      muted: Color(0xFF664E53),
    ),
    // Arcilla de noche.
    CreationPalette(
      background: Color(0xFF2A2321),
      surface: Color(0xFF37302D),
      primary: Color(0xFFF4A261),
      secondary: Color(0xFF7FC8A9),
      accent: Color(0xFFF6D365),
      text: Color(0xFFF6EFE9),
      muted: Color(0xFFBDB1A8),
    ),
  ];

  static const kawaii = [
    // Algodón de azúcar.
    CreationPalette(
      background: Color(0xFFFFF1F5),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFF06292),
      secondary: Color(0xFF7EC8E3),
      accent: Color(0xFFFFD166),
      text: Color(0xFF3A1F2B),
      muted: Color(0xFF6E5260),
    ),
    // Menta.
    CreationPalette(
      background: Color(0xFFEDFAF6),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF2BB39A),
      secondary: Color(0xFFFF8FAB),
      accent: Color(0xFFB8A1FF),
      text: Color(0xFF173A33),
      muted: Color(0xFF4C6A63),
    ),
    // Lila.
    CreationPalette(
      background: Color(0xFFF5F0FF),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF9B7BEA),
      secondary: Color(0xFFFF9AA2),
      accent: Color(0xFF7FDBDA),
      text: Color(0xFF2B2240),
      muted: Color(0xFF5F5675),
    ),
    // Limón.
    CreationPalette(
      background: Color(0xFFFFFBE6),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFF4A100),
      secondary: Color(0xFFFF7EB6),
      accent: Color(0xFF6CC4F0),
      text: Color(0xFF33290A),
      muted: Color(0xFF655B3E),
    ),
    // Durazno.
    CreationPalette(
      background: Color(0xFFFFF3EC),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFFF8A65),
      secondary: Color(0xFF81C784),
      accent: Color(0xFFBA68C8),
      text: Color(0xFF3B2219),
      muted: Color(0xFF6D554B),
    ),
    // Noche dulce.
    CreationPalette(
      background: Color(0xFF2B2238),
      surface: Color(0xFF3A2F4B),
      primary: Color(0xFFFF9EC4),
      secondary: Color(0xFF9AD9F0),
      accent: Color(0xFFFFE08A),
      text: Color(0xFFFFF5FA),
      muted: Color(0xFFC9B9D3),
    ),
  ];

  static const isometric = [
    // Plano.
    CreationPalette(
      background: Color(0xFFEEF2F8),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF3B6FE0),
      secondary: Color(0xFF21B5A4),
      accent: Color(0xFFFF8A3D),
      text: Color(0xFF121A2B),
      muted: Color(0xFF4C5870),
    ),
    // Arena.
    CreationPalette(
      background: Color(0xFFF5F1EA),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFD9663C),
      secondary: Color(0xFF3E7CB1),
      accent: Color(0xFFF2C14E),
      text: Color(0xFF22201C),
      muted: Color(0xFF5A554D),
    ),
    // Bosque.
    CreationPalette(
      background: Color(0xFFEDF4EE),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF2F8F5B),
      secondary: Color(0xFF3D5A80),
      accent: Color(0xFFE9B44C),
      text: Color(0xFF15241B),
      muted: Color(0xFF4B5C51),
    ),
    // Violeta.
    CreationPalette(
      background: Color(0xFFF2EFFA),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF6C4FD8),
      secondary: Color(0xFF19A7CE),
      accent: Color(0xFFFF7AA2),
      text: Color(0xFF1D1833),
      muted: Color(0xFF555069),
    ),
    // Grafito.
    CreationPalette(
      background: Color(0xFFF1F1F1),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF37474F),
      secondary: Color(0xFF26A69A),
      accent: Color(0xFFFFB300),
      text: Color(0xFF151718),
      muted: Color(0xFF52585B),
    ),
    // Noche.
    CreationPalette(
      background: Color(0xFF141A2A),
      surface: Color(0xFF1E2639),
      primary: Color(0xFF5B8CFF),
      secondary: Color(0xFF2ED3B7),
      accent: Color(0xFFFFB547),
      text: Color(0xFFEEF2FA),
      muted: Color(0xFFA6AFC2),
    ),
  ];

  static const comic = [
    // Clásico: rojo, azul y amarillo de imprenta.
    CreationPalette(
      background: Color(0xFFFFF6D6),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFE63946),
      secondary: Color(0xFF1D70B8),
      accent: Color(0xFFFFD60A),
      text: Color(0xFF111111),
      muted: Color(0xFF4A4740),
    ),
    // Pop.
    CreationPalette(
      background: Color(0xFFFDF0F5),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFFF2E88),
      secondary: Color(0xFF00A6D6),
      accent: Color(0xFFFFE600),
      text: Color(0xFF121212),
      muted: Color(0xFF4A444A),
    ),
    // Selva.
    CreationPalette(
      background: Color(0xFFEEF8E8),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF2B9348),
      secondary: Color(0xFFF77F00),
      accent: Color(0xFFFCBF49),
      text: Color(0xFF101510),
      muted: Color(0xFF46504A),
    ),
    // Cielo.
    CreationPalette(
      background: Color(0xFFE8F4FD),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF0077B6),
      secondary: Color(0xFFEF476F),
      accent: Color(0xFFFFD166),
      text: Color(0xFF0B1520),
      muted: Color(0xFF435260),
    ),
    // Sepia.
    CreationPalette(
      background: Color(0xFFF4E9D8),
      surface: Color(0xFFFFFBF2),
      primary: Color(0xFFA23E2A),
      secondary: Color(0xFF3A5A40),
      accent: Color(0xFFE9A23B),
      text: Color(0xFF1E1610),
      muted: Color(0xFF56493B),
    ),
    // Noche.
    CreationPalette(
      background: Color(0xFF1A1A24),
      surface: Color(0xFF262634),
      primary: Color(0xFFFF4D6D),
      secondary: Color(0xFF4CC9F0),
      accent: Color(0xFFFFE066),
      text: Color(0xFFF8F8F2),
      muted: Color(0xFFB4B4C0),
    ),
  ];

  static const photo = [
    // Luz natural.
    CreationPalette(
      background: Color(0xFFF4F1EC),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF2F5D62),
      secondary: Color(0xFFA86B4C),
      accent: Color(0xFFDFA35E),
      text: Color(0xFF1A1A1A),
      muted: Color(0xFF55524E),
    ),
    // Atardecer.
    CreationPalette(
      background: Color(0xFFFBF1EA),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFC0533A),
      secondary: Color(0xFF3D5A80),
      accent: Color(0xFFE9A03B),
      text: Color(0xFF231A16),
      muted: Color(0xFF5E514A),
    ),
    // Océano.
    CreationPalette(
      background: Color(0xFFEEF3F6),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF1F6F8B),
      secondary: Color(0xFF99582A),
      accent: Color(0xFFE8B04B),
      text: Color(0xFF13202A),
      muted: Color(0xFF4B5966),
    ),
    // Bosque.
    CreationPalette(
      background: Color(0xFFEFF2EC),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF3A6B35),
      secondary: Color(0xFF8C5A3C),
      accent: Color(0xFFCBA135),
      text: Color(0xFF182116),
      muted: Color(0xFF50594C),
    ),
    // Blanco y negro, con un toque de oro.
    CreationPalette(
      background: Color(0xFFF2F2F2),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF222222),
      secondary: Color(0xFF6B6B6B),
      accent: Color(0xFFC9A227),
      text: Color(0xFF111111),
      muted: Color(0xFF555555),
    ),
    // Cine.
    CreationPalette(
      background: Color(0xFF111317),
      surface: Color(0xFF1C1F25),
      primary: Color(0xFFE8B04B),
      secondary: Color(0xFF6FA8DC),
      accent: Color(0xFFE06C5A),
      text: Color(0xFFF3F1EC),
      muted: Color(0xFFA9A69F),
    ),
  ];
}
