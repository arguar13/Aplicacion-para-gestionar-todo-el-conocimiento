import 'package:flutter/painting.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_template.dart';

/// Las dieciséis plantillas de presentación (F43, «Plantillas →
/// Presentación»), en cinco familias y en el orden de [DeckTemplateId].
///
/// Cada una con sus seis paletas: la primera es la suya, y las otras cinco la
/// llevan a otros gustos sin perder el carácter. Las claras traen también una
/// versión de noche; las de la familia oscura son seis noches distintas.
/// Todos los pares de texto cumplen AA —el texto sobre el fondo y la
/// superficie, 7:1; el tenue, 4,5:1—, y los textos sobre los
/// rellenos de color salen de `CreationContrast`: lo comprueba
/// `deck_templates_test.dart`.
abstract final class DeckTemplates {
  static const List<DeckTemplate> all = [
    // Revista: serif enorme, filetes finos y un solo color de acento.
    DeckTemplate(
      id: DeckTemplateId.editorial,
      fonts: CreationFontPair.editorial,
      palettes: _Palettes.editorial,
      bullet: BulletMark.dash,
      panel: PanelLook.hairline,
      cover: CoverLook.editorial,
      section: SectionLook.numeral,
      quote: QuoteLook.marks,
      list: ListLook.rows,
      title: TitleLook.rule,
      art: CreationArtStyle.linework,
      radius: 4,
      titleScale: 1.08,
    ),
    // Papel antiguo con grano, viñeteado y doble filete; todo centrado.
    DeckTemplate(
      id: DeckTemplateId.parchment,
      fonts: CreationFontPair.book,
      palettes: _Palettes.parchment,
      bullet: BulletMark.diamond,
      panel: PanelLook.framed,
      cover: CoverLook.framed,
      section: SectionLook.centered,
      quote: QuoteLook.framed,
      list: ListLook.plain,
      title: TitleLook.plain,
      art: CreationArtStyle.organic,
      radius: 6,
      centeredTitles: true,
    ),
    // Blanco con azul marino y oro, como un trabajo de cátedra.
    DeckTemplate(
      id: DeckTemplateId.academic,
      fonts: CreationFontPair.book,
      palettes: _Palettes.academic,
      bullet: BulletMark.square,
      panel: PanelLook.outline,
      cover: CoverLook.band,
      section: SectionLook.band,
      quote: QuoteLook.bar,
      list: ListLook.plain,
      title: TitleLook.bar,
      art: CreationArtStyle.linework,
      radius: 8,
    ),
    // Grilla estricta, negrita apretada y un solo color fuerte.
    DeckTemplate(
      id: DeckTemplateId.swiss,
      fonts: CreationFontPair.swiss,
      palettes: _Palettes.swiss,
      bullet: BulletMark.dash,
      panel: PanelLook.hairline,
      cover: CoverLook.poster,
      section: SectionLook.numeral,
      quote: QuoteLook.bar,
      list: ListLook.rows,
      title: TitleLook.plain,
      art: CreationArtStyle.geometric,
      radius: 0,
      titleScale: 1.12,
    ),
    // Baldosas blancas redondeadas sobre un gris suave.
    DeckTemplate(
      id: DeckTemplateId.bento,
      fonts: CreationFontPair.swiss,
      palettes: _Palettes.bento,
      bullet: BulletMark.pill,
      panel: PanelLook.tile,
      cover: CoverLook.split,
      section: SectionLook.tile,
      quote: QuoteLook.card,
      list: ListLook.cards,
      title: TitleLook.plain,
      art: CreationArtStyle.geometric,
      radius: 40,
      stepCards: true,
    ),
    // Degradés suaves de colores que se funden.
    DeckTemplate(
      id: DeckTemplateId.aurora,
      fonts: CreationFontPair.technical,
      palettes: _Palettes.aurora,
      bullet: BulletMark.dot,
      panel: PanelLook.glass,
      cover: CoverLook.floating,
      section: SectionLook.tile,
      quote: QuoteLook.card,
      list: ListLook.plain,
      title: TitleLook.underline,
      art: CreationArtStyle.organic,
      radius: 36,
    ),
    // Capas translúcidas sobre un fondo de color profundo.
    DeckTemplate(
      id: DeckTemplateId.glass,
      fonts: CreationFontPair.swiss,
      palettes: _Palettes.glass,
      bullet: BulletMark.arrow,
      panel: PanelLook.glass,
      cover: CoverLook.floating,
      section: SectionLook.tile,
      quote: QuoteLook.card,
      list: ListLook.cards,
      title: TitleLook.plain,
      art: CreationArtStyle.organic,
      radius: 36,
      stepCards: true,
    ),
    // Azul noche, estrellas y filetes dorados.
    DeckTemplate(
      id: DeckTemplateId.midnight,
      fonts: CreationFontPair.editorial,
      palettes: _Palettes.midnight,
      bullet: BulletMark.diamond,
      panel: PanelLook.outline,
      cover: CoverLook.framed,
      section: SectionLook.centered,
      quote: QuoteLook.marks,
      list: ListLook.plain,
      title: TitleLook.underline,
      art: CreationArtStyle.linework,
      radius: 12,
      titleScale: 1.04,
    ),
    // Negro con trazos que brillan y un piso de grilla.
    DeckTemplate(
      id: DeckTemplateId.neon,
      fonts: CreationFontPair.technical,
      palettes: _Palettes.neon,
      bullet: BulletMark.glow,
      panel: PanelLook.neon,
      cover: CoverLook.poster,
      section: SectionLook.numeral,
      quote: QuoteLook.bar,
      list: ListLook.rows,
      title: TitleLook.glow,
      art: CreationArtStyle.neon,
      radius: 16,
      uppercaseTitles: true,
    ),
    // Pizarrón con polvo de tiza y letra a mano.
    DeckTemplate(
      id: DeckTemplateId.chalkboard,
      fonts: CreationFontPair.handwritten,
      palettes: _Palettes.chalkboard,
      bullet: BulletMark.chalk,
      panel: PanelLook.chalk,
      cover: CoverLook.floating,
      section: SectionLook.centered,
      quote: QuoteLook.marks,
      list: ListLook.plain,
      title: TitleLook.hand,
      art: CreationArtStyle.chalk,
      radius: 12,
    ),
    // Papel blanco con manchas de acuarela en los bordes.
    DeckTemplate(
      id: DeckTemplateId.watercolor,
      fonts: CreationFontPair.book,
      palettes: _Palettes.watercolor,
      bullet: BulletMark.dot,
      panel: PanelLook.filled,
      cover: CoverLook.floating,
      section: SectionLook.centered,
      quote: QuoteLook.marks,
      list: ListLook.plain,
      title: TitleLook.underline,
      art: CreationArtStyle.organic,
      radius: 28,
    ),
    // Colores tiernos, formas redondas y letra amable.
    DeckTemplate(
      id: DeckTemplateId.pastel,
      fonts: CreationFontPair.friendly,
      palettes: _Palettes.pastel,
      bullet: BulletMark.pill,
      panel: PanelLook.filled,
      cover: CoverLook.floating,
      section: SectionLook.tile,
      quote: QuoteLook.card,
      list: ListLook.cards,
      title: TitleLook.underline,
      art: CreationArtStyle.geometric,
      radius: 36,
      stepCards: true,
    ),
    // Capas de papel de colores recortado, con su sombra.
    DeckTemplate(
      id: DeckTemplateId.paperCut,
      fonts: CreationFontPair.handwritten,
      palettes: _Palettes.paperCut,
      bullet: BulletMark.pill,
      panel: PanelLook.paper,
      cover: CoverLook.floating,
      section: SectionLook.tile,
      quote: QuoteLook.card,
      list: ListLook.cards,
      title: TitleLook.hand,
      art: CreationArtStyle.paper,
      radius: 18,
      stepCards: true,
    ),
    // Sobria y clara: azul, gris y una franja de título.
    DeckTemplate(
      id: DeckTemplateId.corporate,
      fonts: CreationFontPair.swiss,
      palettes: _Palettes.corporate,
      bullet: BulletMark.check,
      panel: PanelLook.filled,
      cover: CoverLook.band,
      section: SectionLook.band,
      quote: QuoteLook.bar,
      list: ListLook.plain,
      title: TitleLook.band,
      art: CreationArtStyle.geometric,
      radius: 10,
      titleScale: 0.96,
    ),
    // Grilla de papel milimetrado y cifras monoespaciadas.
    DeckTemplate(
      id: DeckTemplateId.data,
      fonts: CreationFontPair.technical,
      palettes: _Palettes.data,
      bullet: BulletMark.numeral,
      panel: PanelLook.outline,
      cover: CoverLook.split,
      section: SectionLook.numeral,
      quote: QuoteLook.bar,
      list: ListLook.rows,
      title: TitleLook.bar,
      art: CreationArtStyle.data,
      radius: 12,
    ),
    // Grafito y oro, con una banda oscura de alto entero.
    DeckTemplate(
      id: DeckTemplateId.executive,
      fonts: CreationFontPair.editorial,
      palettes: _Palettes.executive,
      bullet: BulletMark.dash,
      panel: PanelLook.hairline,
      cover: CoverLook.sidebar,
      section: SectionLook.band,
      quote: QuoteLook.marks,
      list: ListLook.rows,
      title: TitleLook.rule,
      art: CreationArtStyle.linework,
      radius: 2,
      titleScale: 1.04,
    ),
  ];

  /// La plantilla [id].
  static DeckTemplate of(DeckTemplateId id) => all[id.index];
}

abstract final class _Palettes {
  static const editorial = [
    // Rojo tinta.
    CreationPalette(
      background: Color(0xFFF7F4EE),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFC8102E),
      secondary: Color(0xFF1F3A5F),
      accent: Color(0xFFE9B44C),
      text: Color(0xFF1A1A1A),
      muted: Color(0xFF5E5A55),
    ),
    // Azul.
    CreationPalette(
      background: Color(0xFFF5F6F8),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF1D4ED8),
      secondary: Color(0xFF0F172A),
      accent: Color(0xFFF59E0B),
      text: Color(0xFF111827),
      muted: Color(0xFF4B5563),
    ),
    // Verde botella.
    CreationPalette(
      background: Color(0xFFF4F1EA),
      surface: Color(0xFFFFFDF8),
      primary: Color(0xFF1E5B4F),
      secondary: Color(0xFF8C3B2E),
      accent: Color(0xFFC9A227),
      text: Color(0xFF1B1F1D),
      muted: Color(0xFF59605B),
    ),
    // Negro y amarillo.
    CreationPalette(
      background: Color(0xFFFAFAF7),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF111111),
      secondary: Color(0xFF6B6B6B),
      accent: Color(0xFFF2C200),
      text: Color(0xFF111111),
      muted: Color(0xFF555555),
    ),
    // Ciruela.
    CreationPalette(
      background: Color(0xFFF8F3F4),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF7A1F4B),
      secondary: Color(0xFF2E4057),
      accent: Color(0xFFD98E04),
      text: Color(0xFF22181C),
      muted: Color(0xFF62555A),
    ),
    // Noche.
    CreationPalette(
      background: Color(0xFF15171A),
      surface: Color(0xFF1F2226),
      primary: Color(0xFFFF5A5F),
      secondary: Color(0xFF8AB4F8),
      accent: Color(0xFFF4D35E),
      text: Color(0xFFF3F1EC),
      muted: Color(0xFFABA59C),
    ),
  ];

  static const parchment = [
    // Sepia.
    CreationPalette(
      background: Color(0xFFF1E4C8),
      surface: Color(0xFFF8EEDA),
      primary: Color(0xFF7A3E1D),
      secondary: Color(0xFF3E5C3A),
      accent: Color(0xFFB8862B),
      text: Color(0xFF2E2116),
      muted: Color(0xFF5E4A35),
    ),
    // Lacre.
    CreationPalette(
      background: Color(0xFFEFE2CC),
      surface: Color(0xFFF7EDDC),
      primary: Color(0xFF8B1E1E),
      secondary: Color(0xFF5A4632),
      accent: Color(0xFFA67C2E),
      text: Color(0xFF2B1D14),
      muted: Color(0xFF5C4834),
    ),
    // Tinta azul.
    CreationPalette(
      background: Color(0xFFF0E6D2),
      surface: Color(0xFFF8F1E3),
      primary: Color(0xFF23395D),
      secondary: Color(0xFF6B4E2E),
      accent: Color(0xFF9C6B30),
      text: Color(0xFF1F1A14),
      muted: Color(0xFF54493B),
    ),
    // Oliva.
    CreationPalette(
      background: Color(0xFFECE3C9),
      surface: Color(0xFFF5EEDB),
      primary: Color(0xFF4F5B25),
      secondary: Color(0xFF7A4A26),
      accent: Color(0xFFA88A3D),
      text: Color(0xFF26241A),
      muted: Color(0xFF545038),
    ),
    // Piedra.
    CreationPalette(
      background: Color(0xFFE9E4DA),
      surface: Color(0xFFF3EFE7),
      primary: Color(0xFF4A4440),
      secondary: Color(0xFF7A5C3E),
      accent: Color(0xFF9E7B4F),
      text: Color(0xFF23201D),
      muted: Color(0xFF57514B),
    ),
    // Cuero.
    CreationPalette(
      background: Color(0xFF2A1F17),
      surface: Color(0xFF362A20),
      primary: Color(0xFFE0B872),
      secondary: Color(0xFFC98B5E),
      accent: Color(0xFFF0D9A8),
      text: Color(0xFFF4E9D5),
      muted: Color(0xFFC2B092),
    ),
  ];

  static const academic = [
    // Marino y oro.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF3F5F9),
      primary: Color(0xFF13294B),
      secondary: Color(0xFF8A6D2F),
      accent: Color(0xFFC8A951),
      text: Color(0xFF141A26),
      muted: Color(0xFF4A5466),
    ),
    // Bordó.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF7F3F3),
      primary: Color(0xFF6D1A2A),
      secondary: Color(0xFF3C4A5C),
      accent: Color(0xFFB88A3B),
      text: Color(0xFF1C1416),
      muted: Color(0xFF5A4F52),
    ),
    // Verde.
    CreationPalette(
      background: Color(0xFFFDFDFB),
      surface: Color(0xFFF1F5F2),
      primary: Color(0xFF1F4D3A),
      secondary: Color(0xFF5B4A2F),
      accent: Color(0xFFA88B3D),
      text: Color(0xFF14201A),
      muted: Color(0xFF4D5A53),
    ),
    // Pizarra.
    CreationPalette(
      background: Color(0xFFF7F8FA),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF2F3E52),
      secondary: Color(0xFF6B7F99),
      accent: Color(0xFFD08C2E),
      text: Color(0xFF18202B),
      muted: Color(0xFF4E5A69),
    ),
    // Morado.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF5F3F8),
      primary: Color(0xFF3E2A6B),
      secondary: Color(0xFF2F5D62),
      accent: Color(0xFFB48A2F),
      text: Color(0xFF1B1626),
      muted: Color(0xFF524C5E),
    ),
    // Oscura.
    CreationPalette(
      background: Color(0xFF101826),
      surface: Color(0xFF18233A),
      primary: Color(0xFF9DB7E8),
      secondary: Color(0xFFD9B866),
      accent: Color(0xFFE6C67A),
      text: Color(0xFFEEF2F8),
      muted: Color(0xFFA9B4C6),
    ),
  ];

  static const swiss = [
    // Rojo.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF4F4F4),
      primary: Color(0xFFE30613),
      secondary: Color(0xFF111111),
      accent: Color(0xFF111111),
      text: Color(0xFF0D0D0D),
      muted: Color(0xFF555555),
    ),
    // Azul Klein.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF2F4F8),
      primary: Color(0xFF0033CC),
      secondary: Color(0xFF111111),
      accent: Color(0xFFFF4F00),
      text: Color(0xFF0D0D0D),
      muted: Color(0xFF545454),
    ),
    // Amarillo.
    CreationPalette(
      background: Color(0xFFF7F7F2),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF111111),
      secondary: Color(0xFFE30613),
      accent: Color(0xFFFFD400),
      text: Color(0xFF111111),
      muted: Color(0xFF525252),
    ),
    // Verde.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF1F5F3),
      primary: Color(0xFF00805A),
      secondary: Color(0xFF111111),
      accent: Color(0xFFFF5C39),
      text: Color(0xFF0F1412),
      muted: Color(0xFF52595A),
    ),
    // Negativo.
    CreationPalette(
      background: Color(0xFF111111),
      surface: Color(0xFF1C1C1C),
      primary: Color(0xFFFF3B30),
      secondary: Color(0xFFFFFFFF),
      accent: Color(0xFFFFD400),
      text: Color(0xFFFFFFFF),
      muted: Color(0xFFB3B3B3),
    ),
    // Naranja.
    CreationPalette(
      background: Color(0xFFFFF8F0),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFD9480F),
      secondary: Color(0xFF1A1A1A),
      accent: Color(0xFF1A1A1A),
      text: Color(0xFF141414),
      muted: Color(0xFF5C534B),
    ),
  ];

  static const bento = [
    // Índigo.
    CreationPalette(
      background: Color(0xFFEEF0F4),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF5B5BD6),
      secondary: Color(0xFF0EA5A4),
      accent: Color(0xFFF97362),
      text: Color(0xFF15171C),
      muted: Color(0xFF535966),
    ),
    // Menta.
    CreationPalette(
      background: Color(0xFFECF3EF),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF0F7B5F),
      secondary: Color(0xFF3E64D6),
      accent: Color(0xFFF2A93B),
      text: Color(0xFF121A16),
      muted: Color(0xFF4E5B54),
    ),
    // Arena.
    CreationPalette(
      background: Color(0xFFF3EFE8),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFB4532A),
      secondary: Color(0xFF2E5E8C),
      accent: Color(0xFFE2B33C),
      text: Color(0xFF1E1A16),
      muted: Color(0xFF5F574E),
    ),
    // Lila.
    CreationPalette(
      background: Color(0xFFF1EEF7),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF7A3FD1),
      secondary: Color(0xFFD9467A),
      accent: Color(0xFF2BA88F),
      text: Color(0xFF1A1625),
      muted: Color(0xFF585266),
    ),
    // Oscuro.
    CreationPalette(
      background: Color(0xFF0F1115),
      surface: Color(0xFF1A1D24),
      primary: Color(0xFF8B8BFF),
      secondary: Color(0xFF4FD1C5),
      accent: Color(0xFFFF8A7A),
      text: Color(0xFFF2F4F8),
      muted: Color(0xFFA3A9B6),
    ),
    // Cielo.
    CreationPalette(
      background: Color(0xFFEAF2FA),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF1C6DD0),
      secondary: Color(0xFFF0643C),
      accent: Color(0xFF2DB37A),
      text: Color(0xFF0F1A26),
      muted: Color(0xFF4C5A6A),
    ),
  ];

  static const aurora = [
    // Boreal.
    CreationPalette(
      background: Color(0xFFF5F4FF),
      surface: Color(0xB8FFFFFF),
      primary: Color(0xFF6D4AFF),
      secondary: Color(0xFF14B8A6),
      accent: Color(0xFFFF6FB5),
      text: Color(0xFF1A1640),
      muted: Color(0xFF4F4A75),
    ),
    // Amanecer.
    CreationPalette(
      background: Color(0xFFFFF5EF),
      surface: Color(0xB8FFFFFF),
      primary: Color(0xFFE2553D),
      secondary: Color(0xFFF2A541),
      accent: Color(0xFFB14AED),
      text: Color(0xFF2A1612),
      muted: Color(0xFF6A4D45),
    ),
    // Océano.
    CreationPalette(
      background: Color(0xFFEFF7FB),
      surface: Color(0xB8FFFFFF),
      primary: Color(0xFF0B7FAB),
      secondary: Color(0xFF22C3A6),
      accent: Color(0xFF6E7BFF),
      text: Color(0xFF0D2230),
      muted: Color(0xFF45606E),
    ),
    // Bosque.
    CreationPalette(
      background: Color(0xFFF1F7F0),
      surface: Color(0xB8FFFFFF),
      primary: Color(0xFF2F8F5B),
      secondary: Color(0xFFB7C93B),
      accent: Color(0xFF3BA6C9),
      text: Color(0xFF132416),
      muted: Color(0xFF4A5E4D),
    ),
    // Noche boreal.
    CreationPalette(
      background: Color(0xFF0E1030),
      surface: Color(0x24FFFFFF),
      primary: Color(0xFF8F7CFF),
      secondary: Color(0xFF2DE2C4),
      accent: Color(0xFFFF7AC6),
      text: Color(0xFFF4F3FF),
      muted: Color(0xFFB8B5DD),
    ),
    // Rosa.
    CreationPalette(
      background: Color(0xFFFFF3F8),
      surface: Color(0xB8FFFFFF),
      primary: Color(0xFFC2367A),
      secondary: Color(0xFF7B61FF),
      accent: Color(0xFFFF9F43),
      text: Color(0xFF2B1220),
      muted: Color(0xFF6B4A5B),
    ),
  ];

  static const glass = [
    // Índigo.
    CreationPalette(
      background: Color(0xFF1E1B4B),
      surface: Color(0x24FFFFFF),
      primary: Color(0xFF8B9CFF),
      secondary: Color(0xFFF472B6),
      accent: Color(0xFF5EEAD4),
      text: Color(0xFFFFFFFF),
      muted: Color(0xFFCBD0F5),
    ),
    // Océano.
    CreationPalette(
      background: Color(0xFF0B2A4A),
      surface: Color(0x24FFFFFF),
      primary: Color(0xFF5CC8FF),
      secondary: Color(0xFF7CF2C8),
      accent: Color(0xFFFFB86B),
      text: Color(0xFFFFFFFF),
      muted: Color(0xFFC4D8EA),
    ),
    // Atardecer.
    CreationPalette(
      background: Color(0xFF3B1340),
      surface: Color(0x24FFFFFF),
      primary: Color(0xFFFF9F7A),
      secondary: Color(0xFFFFD36E),
      accent: Color(0xFFC9A7FF),
      text: Color(0xFFFFFFFF),
      muted: Color(0xFFE3C9E6),
    ),
    // Esmeralda.
    CreationPalette(
      background: Color(0xFF0D3B33),
      surface: Color(0x24FFFFFF),
      primary: Color(0xFF6EE7B7),
      secondary: Color(0xFFA7F3D0),
      accent: Color(0xFFFCD34D),
      text: Color(0xFFFFFFFF),
      muted: Color(0xFFC3E3D9),
    ),
    // Grafito.
    CreationPalette(
      background: Color(0xFF1C1F26),
      surface: Color(0x1FFFFFFF),
      primary: Color(0xFFA0AEC0),
      secondary: Color(0xFF90CDF4),
      accent: Color(0xFFFBD38D),
      text: Color(0xFFFFFFFF),
      muted: Color(0xFFC7CDD6),
    ),
    // Claro.
    CreationPalette(
      background: Color(0xFFDCE6F5),
      surface: Color(0x99FFFFFF),
      primary: Color(0xFF3557C9),
      secondary: Color(0xFFC2418F),
      accent: Color(0xFF0E9F8E),
      text: Color(0xFF111A33),
      muted: Color(0xFF3F4A66),
    ),
  ];

  static const midnight = [
    // Oro.
    CreationPalette(
      background: Color(0xFF0B1026),
      surface: Color(0xFF141B38),
      primary: Color(0xFFE8C27A),
      secondary: Color(0xFF8FA8FF),
      accent: Color(0xFFF2D9A6),
      text: Color(0xFFEEF0F8),
      muted: Color(0xFFA8AFC9),
    ),
    // Plata.
    CreationPalette(
      background: Color(0xFF0E0F14),
      surface: Color(0xFF191B22),
      primary: Color(0xFFD7DCE5),
      secondary: Color(0xFF8AA4C8),
      accent: Color(0xFFE9C46A),
      text: Color(0xFFF2F3F6),
      muted: Color(0xFFA3A8B3),
    ),
    // Rubí.
    CreationPalette(
      background: Color(0xFF160A12),
      surface: Color(0xFF22111C),
      primary: Color(0xFFF08AA4),
      secondary: Color(0xFFE8C27A),
      accent: Color(0xFFFFB4C6),
      text: Color(0xFFF7ECEF),
      muted: Color(0xFFC2A7AF),
    ),
    // Esmeralda.
    CreationPalette(
      background: Color(0xFF07161A),
      surface: Color(0xFF0F2328),
      primary: Color(0xFF7FD8B8),
      secondary: Color(0xFFE8C27A),
      accent: Color(0xFFB4F0DC),
      text: Color(0xFFEAF5F2),
      muted: Color(0xFFA3C1BA),
    ),
    // Violeta.
    CreationPalette(
      background: Color(0xFF120D24),
      surface: Color(0xFF1D1636),
      primary: Color(0xFFC7A6FF),
      secondary: Color(0xFFF2C97D),
      accent: Color(0xFFE6D7FF),
      text: Color(0xFFF1EEF9),
      muted: Color(0xFFB2AACA),
    ),
    // Azul profundo.
    CreationPalette(
      background: Color(0xFF061428),
      surface: Color(0xFF0D2140),
      primary: Color(0xFF7CC4FF),
      secondary: Color(0xFFFFC86B),
      accent: Color(0xFFBDE2FF),
      text: Color(0xFFEAF3FF),
      muted: Color(0xFFA2B7D1),
    ),
  ];

  static const neon = [
    // Magenta.
    CreationPalette(
      background: Color(0xFF0A0A12),
      surface: Color(0xFF14141F),
      primary: Color(0xFFFF2BD6),
      secondary: Color(0xFF00E5FF),
      accent: Color(0xFFFFE14D),
      text: Color(0xFFF5F5FF),
      muted: Color(0xFFA8A8C0),
    ),
    // Cian.
    CreationPalette(
      background: Color(0xFF050B14),
      surface: Color(0xFF0D1726),
      primary: Color(0xFF00F0FF),
      secondary: Color(0xFF7C4DFF),
      accent: Color(0xFFFF4D9D),
      text: Color(0xFFF0FAFF),
      muted: Color(0xFF9FB3C8),
    ),
    // Lima.
    CreationPalette(
      background: Color(0xFF0A0F0A),
      surface: Color(0xFF131C13),
      primary: Color(0xFFB6FF3B),
      secondary: Color(0xFF3BFFC9),
      accent: Color(0xFFFF6B3B),
      text: Color(0xFFF4FFF0),
      muted: Color(0xFFA6B8A3),
    ),
    // Naranja.
    CreationPalette(
      background: Color(0xFF120A06),
      surface: Color(0xFF1E120B),
      primary: Color(0xFFFF7A1A),
      secondary: Color(0xFFFFD23F),
      accent: Color(0xFF3DE0FF),
      text: Color(0xFFFFF6EE),
      muted: Color(0xFFBFAE9F),
    ),
    // Violeta.
    CreationPalette(
      background: Color(0xFF0C0616),
      surface: Color(0xFF170D26),
      primary: Color(0xFFB44DFF),
      secondary: Color(0xFFFF4DC4),
      accent: Color(0xFF4DFFF3),
      text: Color(0xFFF7F0FF),
      muted: Color(0xFFB3A3C9),
    ),
    // Rojo.
    CreationPalette(
      background: Color(0xFF100608),
      surface: Color(0xFF1C0C10),
      primary: Color(0xFFFF3355),
      secondary: Color(0xFFFF9F1A),
      accent: Color(0xFF33D6FF),
      text: Color(0xFFFFF0F2),
      muted: Color(0xFFC2A3A9),
    ),
  ];

  static const chalkboard = [
    // Verde.
    CreationPalette(
      background: Color(0xFF22332B),
      surface: Color(0xFF2B3F35),
      primary: Color(0xFFF5E17A),
      secondary: Color(0xFFF2A7B8),
      accent: Color(0xFF9FD8F0),
      text: Color(0xFFF2F1EA),
      muted: Color(0xFFC3CBC2),
    ),
    // Negra.
    CreationPalette(
      background: Color(0xFF1F2224),
      surface: Color(0xFF2A2E31),
      primary: Color(0xFFFFE08A),
      secondary: Color(0xFF9FE2BF),
      accent: Color(0xFFF7A8A8),
      text: Color(0xFFF4F3EE),
      muted: Color(0xFFC6C8C4),
    ),
    // Azul.
    CreationPalette(
      background: Color(0xFF1D2B3A),
      surface: Color(0xFF263749),
      primary: Color(0xFFFFD27A),
      secondary: Color(0xFFA8E6FF),
      accent: Color(0xFFF6A6C8),
      text: Color(0xFFF1F4F7),
      muted: Color(0xFFBFCAD6),
    ),
    // Marrón.
    CreationPalette(
      background: Color(0xFF2E2620),
      surface: Color(0xFF3A3029),
      primary: Color(0xFFF7D774),
      secondary: Color(0xFFB7E4A6),
      accent: Color(0xFFF5A97F),
      text: Color(0xFFF5F0E8),
      muted: Color(0xFFCBC0B3),
    ),
    // Gris.
    CreationPalette(
      background: Color(0xFF34383C),
      surface: Color(0xFF3F4448),
      primary: Color(0xFFFFE59A),
      secondary: Color(0xFF9ED9F5),
      accent: Color(0xFFF4B6C2),
      text: Color(0xFFF6F6F3),
      muted: Color(0xFFD0D2D2),
    ),
    // Bordó.
    CreationPalette(
      background: Color(0xFF2E1A1F),
      surface: Color(0xFF3A242A),
      primary: Color(0xFFFFD98A),
      secondary: Color(0xFFA9E3D2),
      accent: Color(0xFFF3B0C3),
      text: Color(0xFFF7EFF0),
      muted: Color(0xFFD0BFC3),
    ),
  ];

  static const watercolor = [
    // Primavera.
    CreationPalette(
      background: Color(0xFFFBF9F4),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFD2557A),
      secondary: Color(0xFF4A90B8),
      accent: Color(0xFFF2B544),
      text: Color(0xFF2A2622),
      muted: Color(0xFF625B53),
    ),
    // Mar.
    CreationPalette(
      background: Color(0xFFF6FAFB),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF2B7A9B),
      secondary: Color(0xFF6FB8A8),
      accent: Color(0xFFE8946B),
      text: Color(0xFF1C2A30),
      muted: Color(0xFF52656D),
    ),
    // Otoño.
    CreationPalette(
      background: Color(0xFFFBF6EE),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFB5542C),
      secondary: Color(0xFFC9963A),
      accent: Color(0xFF7A8F3C),
      text: Color(0xFF2B211A),
      muted: Color(0xFF665649),
    ),
    // Lavanda.
    CreationPalette(
      background: Color(0xFFF8F6FB),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF7B5BB5),
      secondary: Color(0xFFD47FA6),
      accent: Color(0xFF6BA3C9),
      text: Color(0xFF241F2E),
      muted: Color(0xFF5E5868),
    ),
    // Bosque.
    CreationPalette(
      background: Color(0xFFF6F8F2),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF3F7D4E),
      secondary: Color(0xFF93B05A),
      accent: Color(0xFFD99A4E),
      text: Color(0xFF1E2A20),
      muted: Color(0xFF556258),
    ),
    // Noche.
    CreationPalette(
      background: Color(0xFF1E1E26),
      surface: Color(0xFF2A2A35),
      primary: Color(0xFFF28AA8),
      secondary: Color(0xFF7FC4E8),
      accent: Color(0xFFF7C873),
      text: Color(0xFFF3F0EA),
      muted: Color(0xFFB9B3C2),
    ),
  ];

  static const pastel = [
    // Caramelo.
    CreationPalette(
      background: Color(0xFFFFF8F0),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFE86A92),
      secondary: Color(0xFF7BC8A4),
      accent: Color(0xFFFFC857),
      text: Color(0xFF2D2433),
      muted: Color(0xFF66596B),
    ),
    // Menta.
    CreationPalette(
      background: Color(0xFFF0FAF6),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF2FA37C),
      secondary: Color(0xFF8FA8FF),
      accent: Color(0xFFFFB38A),
      text: Color(0xFF1D2B27),
      muted: Color(0xFF53635D),
    ),
    // Cielo.
    CreationPalette(
      background: Color(0xFFF0F6FF),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF4C7BE0),
      secondary: Color(0xFFFF9DB5),
      accent: Color(0xFFFFD66B),
      text: Color(0xFF1D2433),
      muted: Color(0xFF545E70),
    ),
    // Durazno.
    CreationPalette(
      background: Color(0xFFFFF4EC),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFE8743B),
      secondary: Color(0xFFB28DFF),
      accent: Color(0xFF6CCFB0),
      text: Color(0xFF2E211A),
      muted: Color(0xFF6B574B),
    ),
    // Lila.
    CreationPalette(
      background: Color(0xFFF7F2FF),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF9B6BE0),
      secondary: Color(0xFFFF9F80),
      accent: Color(0xFF7AD3C3),
      text: Color(0xFF271F33),
      muted: Color(0xFF5F566D),
    ),
    // Noche suave.
    CreationPalette(
      background: Color(0xFF25202E),
      surface: Color(0xFF312A3C),
      primary: Color(0xFFF59AB8),
      secondary: Color(0xFF9FE0C3),
      accent: Color(0xFFFFD98A),
      text: Color(0xFFF7F2FA),
      muted: Color(0xFFC2B8CC),
    ),
  ];

  static const paperCut = [
    // Primario.
    CreationPalette(
      background: Color(0xFFFFF6E5),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFF25C54),
      secondary: Color(0xFF2A9D8F),
      accent: Color(0xFFF4A259),
      text: Color(0xFF22252A),
      muted: Color(0xFF5B5F66),
    ),
    // Mar.
    CreationPalette(
      background: Color(0xFFEAF6F6),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF1B98B5),
      secondary: Color(0xFFF2C14E),
      accent: Color(0xFFF78154),
      text: Color(0xFF15262B),
      muted: Color(0xFF4C6067),
    ),
    // Selva.
    CreationPalette(
      background: Color(0xFFF1F6E8),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF4C9A2A),
      secondary: Color(0xFFF28F3B),
      accent: Color(0xFF2F6690),
      text: Color(0xFF1D2618),
      muted: Color(0xFF525E4B),
    ),
    // Caramelo.
    CreationPalette(
      background: Color(0xFFFFF0F3),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFE84A7F),
      secondary: Color(0xFF6C63FF),
      accent: Color(0xFFFFC145),
      text: Color(0xFF2A1A22),
      muted: Color(0xFF66525B),
    ),
    // Cartón.
    CreationPalette(
      background: Color(0xFFE9D8BE),
      surface: Color(0xFFF6EBD9),
      primary: Color(0xFFB5462F),
      secondary: Color(0xFF2F5D7C),
      accent: Color(0xFFE3A33B),
      text: Color(0xFF2A2017),
      muted: Color(0xFF5A4A38),
    ),
    // Noche.
    CreationPalette(
      background: Color(0xFF1E2A3A),
      surface: Color(0xFF2A3A50),
      primary: Color(0xFFFF7A59),
      secondary: Color(0xFF4FD1C5),
      accent: Color(0xFFFFD166),
      text: Color(0xFFF5F7FA),
      muted: Color(0xFFB6C2D2),
    ),
  ];

  static const corporate = [
    // Azul.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF3F6FA),
      primary: Color(0xFF0B5CAD),
      secondary: Color(0xFF1F2A37),
      accent: Color(0xFF00A3E0),
      text: Color(0xFF111827),
      muted: Color(0xFF4B5563),
    ),
    // Verde.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF2F7F4),
      primary: Color(0xFF0E7C4A),
      secondary: Color(0xFF1F2A2A),
      accent: Color(0xFF7CC242),
      text: Color(0xFF102018),
      muted: Color(0xFF4A5A52),
    ),
    // Rojo.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF8F3F3),
      primary: Color(0xFFB3122E),
      secondary: Color(0xFF2B2B2B),
      accent: Color(0xFFF2A900),
      text: Color(0xFF161616),
      muted: Color(0xFF555555),
    ),
    // Petróleo.
    CreationPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF1F6F7),
      primary: Color(0xFF0F5E6E),
      secondary: Color(0xFF243B53),
      accent: Color(0xFFF0A202),
      text: Color(0xFF102A33),
      muted: Color(0xFF4A5D66),
    ),
    // Gris.
    CreationPalette(
      background: Color(0xFFF7F8FA),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF374151),
      secondary: Color(0xFF2563EB),
      accent: Color(0xFF10B981),
      text: Color(0xFF111827),
      muted: Color(0xFF4B5563),
    ),
    // Oscura.
    CreationPalette(
      background: Color(0xFF0F172A),
      surface: Color(0xFF1E293B),
      primary: Color(0xFF60A5FA),
      secondary: Color(0xFF94A3B8),
      accent: Color(0xFF34D399),
      text: Color(0xFFF1F5F9),
      muted: Color(0xFFA7B3C4),
    ),
  ];

  static const data = [
    // Turquesa.
    CreationPalette(
      background: Color(0xFFF7F9FB),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF0F766E),
      secondary: Color(0xFF2563EB),
      accent: Color(0xFFF59E0B),
      text: Color(0xFF0F172A),
      muted: Color(0xFF475569),
    ),
    // Azul.
    CreationPalette(
      background: Color(0xFFF5F8FC),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF1D4ED8),
      secondary: Color(0xFF0891B2),
      accent: Color(0xFFE11D48),
      text: Color(0xFF0B1324),
      muted: Color(0xFF46536A),
    ),
    // Violeta.
    CreationPalette(
      background: Color(0xFFF8F7FC),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF6D28D9),
      secondary: Color(0xFF0EA5E9),
      accent: Color(0xFFF97316),
      text: Color(0xFF160F2E),
      muted: Color(0xFF524C66),
    ),
    // Naranja.
    CreationPalette(
      background: Color(0xFFFBF8F4),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFFC2410C),
      secondary: Color(0xFF0F766E),
      accent: Color(0xFF4F46E5),
      text: Color(0xFF1C1410),
      muted: Color(0xFF5C5048),
    ),
    // Terminal.
    CreationPalette(
      background: Color(0xFF0B1220),
      surface: Color(0xFF111A2E),
      primary: Color(0xFF22D3EE),
      secondary: Color(0xFFA78BFA),
      accent: Color(0xFFFACC15),
      text: Color(0xFFE6EDF7),
      muted: Color(0xFF9AA8BF),
    ),
    // Verde.
    CreationPalette(
      background: Color(0xFFF6FAF7),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF15803D),
      secondary: Color(0xFF0369A1),
      accent: Color(0xFFDB2777),
      text: Color(0xFF0D1A12),
      muted: Color(0xFF4A5A50),
    ),
  ];

  static const executive = [
    // Grafito y oro.
    CreationPalette(
      background: Color(0xFFFAF9F7),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF1F2328),
      secondary: Color(0xFFB8915A),
      accent: Color(0xFFB8915A),
      text: Color(0xFF1A1C1F),
      muted: Color(0xFF595C61),
    ),
    // Marino.
    CreationPalette(
      background: Color(0xFFF8F9FB),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF14213D),
      secondary: Color(0xFFC9A227),
      accent: Color(0xFFC9A227),
      text: Color(0xFF131A2A),
      muted: Color(0xFF545B6A),
    ),
    // Bordó.
    CreationPalette(
      background: Color(0xFFFAF8F7),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF4A1420),
      secondary: Color(0xFFC49A5A),
      accent: Color(0xFFC49A5A),
      text: Color(0xFF1F1416),
      muted: Color(0xFF5E5456),
    ),
    // Verde inglés.
    CreationPalette(
      background: Color(0xFFF8FAF8),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF173B2F),
      secondary: Color(0xFFB8935A),
      accent: Color(0xFFB8935A),
      text: Color(0xFF14201B),
      muted: Color(0xFF52605A),
    ),
    // Plata.
    CreationPalette(
      background: Color(0xFFF6F6F7),
      surface: Color(0xFFFFFFFF),
      primary: Color(0xFF2B2D33),
      secondary: Color(0xFF8A93A6),
      accent: Color(0xFF4A6FA5),
      text: Color(0xFF18191C),
      muted: Color(0xFF55585F),
    ),
    // Oscura.
    CreationPalette(
      background: Color(0xFF121417),
      surface: Color(0xFF1C1F23),
      primary: Color(0xFFD9B779),
      secondary: Color(0xFFE9D3A6),
      accent: Color(0xFFD9B779),
      text: Color(0xFFF3F1ED),
      muted: Color(0xFFABA8A2),
    ),
  ];
}
