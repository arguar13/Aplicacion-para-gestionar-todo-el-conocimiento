import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';

/// La marca de cada viñeta.
enum BulletMark {
  /// Una raya corta, de imprenta.
  dash,
  dot,
  square,
  diamond,

  /// El número de la viñeta, en la letra de las cifras.
  numeral,
  check,
  arrow,

  /// Una raya de tiza, con su temblor.
  chalk,

  /// Un punto que brilla.
  glow,

  /// Una píldora redondeada, de color.
  pill,

  /// El «>» de una terminal, en la letra de las cifras (F45).
  prompt,

  /// Un círculo, un cuadrado y un triángulo que se turnan, cada uno de su
  /// color, como un afiche de la Bauhaus (F45).
  shape,
}

/// Cómo se ve un panel: la caja de una columna, una tarjeta, un paso.
enum PanelLook {
  /// Sin caja: el texto sobre el fondo, con una línea fina arriba.
  hairline,

  /// Un borde fino, sin relleno.
  outline,

  /// La superficie de la paleta, con las esquinas de la plantilla.
  filled,

  /// Una baldosa blanca con sombra suave (Bento).
  tile,

  /// Una capa translúcida con un borde de luz (Vidrio).
  glass,

  /// Un recorte de papel con su sombra corrida (Papel recortado).
  paper,

  /// Un borde dibujado a tiza (Pizarra).
  chalk,

  /// Un borde que brilla (Neón).
  neon,

  /// La superficie con un doble filete (Pergamino).
  framed,

  /// Un borde grueso del color del texto y una sombra dura, corrida, sin
  /// desenfoque (Brutalista, F45).
  block,

  /// Una nota adhesiva teñida del acento, un poco torcida y con su cinta
  /// arriba (Manuscrito, F45).
  note,
}

/// Cómo se arma la portada (y, con la misma idea, el cierre).
enum CoverLook {
  /// El título enorme a la izquierda, bajo un filete, como una revista.
  editorial,

  /// Centrado dentro de un marco con ornamento.
  framed,

  /// El texto a la izquierda y un bloque de color con la ilustración.
  split,

  /// Una franja de color con la bajada.
  band,

  /// La letra enorme, como un afiche.
  poster,

  /// Centrado sobre las formas del fondo, dentro de un panel.
  floating,

  /// Una banda oscura a la izquierda con el título, y el resto en claro.
  sidebar,

  /// La cabecera de un diario: el rótulo entre filetes de lado a lado y el
  /// título enorme debajo, con la bajada como copete (Periódico, F45).
  masthead,
}

/// Cómo se arma el comienzo de una parte.
enum SectionLook {
  /// El número de la parte, enorme, junto al título.
  numeral,

  /// Una banda de color de alto entero con el número.
  band,

  /// Centrado, con el ornamento.
  centered,

  /// Una baldosa grande con el número en una insignia.
  tile,
}

/// Cómo se arma la cita.
enum QuoteLook {
  /// Unas comillas enormes de color.
  marks,

  /// Centrada entre dos ornamentos.
  framed,

  /// Con una barra de color a la izquierda.
  bar,

  /// Adentro de un panel.
  card,
}

/// Cómo se arma una lista de viñetas.
enum ListLook {
  /// La lista de siempre.
  plain,

  /// Cada viñeta un renglón entre filetes, con su número.
  rows,

  /// Cada viñeta una tarjeta.
  cards,
}

/// Cómo va el título de una diapositiva de contenido.
enum TitleLook {
  plain,

  /// Con una barra corta de color debajo.
  underline,

  /// Con un filete fino arriba y el rótulo de la diapositiva.
  rule,

  /// En una franja de color de lado a lado.
  band,

  /// Con una barra vertical de color a la izquierda.
  bar,

  /// Con un subrayado a mano.
  hand,

  /// Con un resplandor de su color.
  glow,

  /// Con un trazo de resaltador del acento detrás del comienzo del título
  /// (F45).
  highlight,
}

/// Una plantilla de presentación (F43, y las doce de F45): su letra, sus
/// seis paletas, su fondo y cómo compone cada diseño de diapositiva.
///
/// No dibuja nada sola: es la receta que leen `SlideView` y sus diseños. El
/// fondo lo pinta `DeckBackgroundPainter` según [id].
@immutable
class DeckTemplate {
  const DeckTemplate({
    required this.id,
    required this.fonts,
    required this.palettes,
    required this.bullet,
    required this.panel,
    required this.cover,
    required this.section,
    required this.quote,
    required this.list,
    required this.title,
    required this.art,
    this.radius = 24,
    this.titleScale = 1,
    this.centeredTitles = false,
    this.uppercaseTitles = false,
    this.stepCards = false,
  });

  final DeckTemplateId id;

  /// El par de letras de fábrica (la persona puede elegir otro).
  final CreationFontPair fonts;

  /// Las seis paletas; la primera es la de la plantilla.
  final List<CreationPalette> palettes;

  final BulletMark bullet;
  final PanelLook panel;
  final CoverLook cover;
  final SectionLook section;
  final QuoteLook quote;
  final ListLook list;
  final TitleLook title;

  /// El trazo de la ilustración de reserva.
  final CreationArtStyle art;

  /// El redondeo de los paneles, en puntos del lienzo.
  final double radius;

  /// Cuánto más grandes (o chicos) que lo común van los títulos.
  final double titleScale;

  final bool centeredTitles;

  /// Los títulos de contenido en mayúsculas (los afiches).
  final bool uppercaseTitles;

  /// Los pasos como tarjetas en vez de una línea con círculos.
  final bool stepCards;

  DeckTemplateFamily get family => id.family;

  /// La paleta [index] (llevada al rango), teñida con [customColor] si hay.
  CreationPalette palette(int index, {int? customColor}) {
    final base = palettes[index.clamp(0, palettes.length - 1)];
    return customColor == null
        ? base
        : base.withCustomColor(Color(customColor));
  }
}
