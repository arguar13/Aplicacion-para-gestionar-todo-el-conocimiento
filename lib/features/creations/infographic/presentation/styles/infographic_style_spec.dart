import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';

/// Cómo se ve la caja de un bloque.
enum InfoPanelLook {
  /// Sin caja: el texto sobre el fondo, bajo un filete fino (Editorial,
  /// Minimal suizo).
  hairline,

  /// La superficie lisa, sin sombra (Geométrico).
  flat,

  /// Un borde fino, sin relleno (Datos).
  outline,

  /// Una baldosa con sombra suave y esquinas muy redondas (Bento,
  /// Isométrico).
  tile,

  /// La superficie con una sombra corta (Corporativo, Pastel, Acuarela,
  /// Fotográfico).
  card,

  /// Un borde dibujado a tiza (Pizarra).
  chalk,

  /// Un borde que brilla (Neón oscuro).
  neon,

  /// Un doble filete, como un grabado (Pergamino).
  framed,

  /// Un borde grueso de color, distinto en cada bloque (Infantil).
  playful,

  /// Una figurita de historieta: borde negro grueso y sombra corrida
  /// (Cómic).
  sticker,

  /// Plastilina: muy redondeada, con un brillo arriba y una sombra blanda
  /// (Plastilina).
  clay,

  /// Un relleno tenue del color de cada bloque, muy redondeado (Kawaii).
  tinted,

  /// Un borde grueso del color del texto y una sombra dura, sin desenfoque
  /// (Brutalista, F45).
  block,

  /// Una nota adhesiva teñida del acento, con su cinta arriba (Manuscrito,
  /// F45).
  note,
}

/// Cómo se arma la cabecera: el antetítulo, el título y la bajada.
enum InfoHeaderLook {
  /// El título a la izquierda, con el antetítulo arriba y un filete debajo,
  /// como una revista.
  editorial,

  /// La letra enorme, como un afiche.
  poster,

  /// Centrado, con un ornamento debajo.
  centered,

  /// Una franja de color de lado a lado, con el título encima.
  banner,

  /// El título junto a una ilustración grande (los estilos con ilustraciones
  /// con IA): arriba en vertical, al costado en horizontal.
  hero,

  /// La cabecera de un diario: un filete grueso arriba, el rótulo, el título
  /// y un filete doble debajo (Periódico, F45).
  masthead,
}

/// La textura del fondo «con textura».
enum InfoTexture {
  /// El grano del papel.
  grain,

  /// Una grilla de puntos, como un cuaderno punteado.
  dots,

  /// Papel milimetrado.
  grid,

  /// Polvo de tiza.
  chalk,

  /// Un piso de neón y estrellas.
  neon,

  /// Papel antiguo con su viñeteado.
  parchment,

  /// Formas geométricas grandes en los bordes.
  shapes,

  /// Papel picado: confeti de colores.
  confetti,

  /// Trama de puntos de historieta.
  halftone,

  /// Manchas de acuarela en las esquinas.
  watercolor,

  /// La grilla isométrica.
  isometric,

  /// Luces desenfocadas, como el fondo de una foto.
  bokeh,

  /// Burbujas suaves de plastilina.
  bubbles,

  // Las de F45, cada una la del estilo del mismo nombre.

  /// Papel de diario: el grano y la trama de una foto en una esquina.
  newsprint,

  /// Aguadas de tinta china y el sello rojo.
  inkWash,

  /// Un bloque de color a sangre en un borde, como una revista.
  colorBlock,

  /// El círculo, el medio círculo y el triángulo de la Bauhaus.
  bauhaus,

  /// El marco grueso y una etiqueta de color ácido.
  brutal,

  /// Una luz muy tenue arriba, sobre casi negro.
  spotlight,

  /// Las líneas de barrido y el resplandor de una pantalla vieja.
  scanlines,

  /// Los escalonados de oro en las esquinas y un abanico de rayos.
  deco,

  /// Un sol de franjas que asoma de una esquina.
  sunset,

  /// Los renglones y el margen rojo de un cuaderno.
  ruled,

  /// Lo que quedó de lo borrado y el marco de aluminio de una pizarra.
  marker,

  /// La grilla blanca y las marcas de registro de un plano.
  blueprint,
}

/// Cómo se dibujan las líneas que unen (la cronología, el proceso, los
/// rayos del radial, el mapa).
enum InfoConnectorLook { solid, dashed, hand, glow }

/// Un estilo de infografía (F43): su letra, sus seis paletas, su fondo, su
/// cabecera, la caja de los bloques y la ilustración de reserva.
///
/// No dibuja nada solo: es la receta que leen `InfographicView` y sus
/// composiciones. Las paletas de los estilos que se llaman igual que una
/// plantilla de presentación (Editorial, Pizarra, Pergamino, y los doce de
/// F45) son las de esa plantilla, así una lámina y un mazo del mismo nombre
/// combinan.
@immutable
class InfographicStyleSpec {
  const InfographicStyleSpec({
    required this.id,
    required this.fonts,
    required this.palettes,
    required this.panel,
    required this.header,
    required this.texture,
    required this.art,
    this.background = InfographicBackground.texture,
    this.iconLook = InfographicIconLook.soft,
    this.connector = InfoConnectorLook.solid,
    this.radius = 24,
    this.titleScale = 1,
    this.uppercaseTitles = false,
    this.centered = false,
    this.illustrationHint,
  });

  final InfographicStyleId id;

  /// El par de letras de fábrica (la persona puede elegir otro).
  final CreationFontPair fonts;

  /// Las seis paletas; la primera es la del estilo.
  final List<CreationPalette> palettes;

  final InfoPanelLook panel;
  final InfoHeaderLook header;
  final InfoTexture texture;

  /// El trazo de la ilustración de reserva.
  final CreationArtStyle art;

  /// El fondo de fábrica.
  final InfographicBackground background;

  /// Los íconos de fábrica.
  final InfographicIconLook iconLook;

  final InfoConnectorLook connector;

  /// El redondeo de las cajas, en puntos del lienzo.
  final double radius;

  /// Cuánto más grande (o chico) que lo común va el título.
  final double titleScale;

  final bool uppercaseTitles;

  /// La cabecera y los textos de los bloques, centrados.
  final bool centered;

  /// Cómo se le describe el estilo a la IA de imágenes (en inglés, que es
  /// lo que mejor entienden), para los estilos con ilustraciones con IA; null
  /// en los dibujados.
  final String? illustrationHint;

  InfographicStyleFamily get family => id.family;

  bool get isIllustrated => illustrationHint != null;

  /// La paleta [index] (llevada al rango), teñida con [customColor] si hay.
  CreationPalette palette(int index, {int? customColor}) {
    final base = palettes[index.clamp(0, palettes.length - 1)];
    return customColor == null
        ? base
        : base.withCustomColor(Color(customColor));
  }
}
