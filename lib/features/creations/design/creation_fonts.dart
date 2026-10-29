import 'package:flutter/painting.dart';

/// Los pares de títulos y texto con que se dibuja todo lo creado (F43): las
/// diapositivas, las infografías y lo que venga después.
///
/// Las fuentes viajan con la app —ver tool/fetch_creation_fonts.sh y las
/// familias de pubspec.yaml—: un mazo se ve igual sin internet, con Gemma y
/// en el PDF. Cada par trae tres papeles:
///
/// - [display], la de los títulos;
/// - [body], la del texto corrido y las viñetas;
/// - [figures], la de las cifras, las fechas y los rótulos chicos (la
///   monoespaciada en el par técnico).
///
/// Los archivos son variables: el peso se pide con `fontWeight` —para que
/// Flutter elija la cara declarada y no sintetice una negrita encima— y con
/// `FontVariation('wght', …)`, que es lo que de verdad mueve el eje. Un peso
/// que la familia no declara en pubspec.yaml se lleva al declarado más cercano
/// (ver [declaredWeights]); la prueba de las fuentes comprueba que las dos
/// listas coincidan.
enum CreationFontPair {
  /// Serif de alto contraste para títulos, con Inter para leer: revista.
  editorial(
    display: 'Playfair Display',
    body: _inter,
    figures: 'Playfair Display',
    displayWeight: 700,
    displayHeight: 1.08,
    displayTracking: -0.01,
    displayItalic: true,
  ),

  /// Serif de libro y una sans humanista: lo que se lee largo.
  book(
    display: 'Lora',
    body: 'Source Sans 3',
    figures: 'Lora',
    displayWeight: 600,
    displayHeight: 1.12,
    displayTracking: -0.005,
    displayItalic: true,
  ),

  /// Inter en negrita apretada: la grotesca de siempre, la de la Suiza.
  swiss(
    display: _inter,
    body: _inter,
    figures: _inter,
    displayWeight: 800,
    displayHeight: 1.04,
    displayTracking: -0.03,
  ),

  /// Grotesca geométrica para títulos, con cifras monoespaciadas.
  technical(
    display: 'Space Grotesk',
    body: _inter,
    figures: 'JetBrains Mono',
    displayWeight: 700,
    displayHeight: 1.06,
    displayTracking: -0.02,
  ),

  /// Redondeada y amable de punta a punta.
  friendly(
    display: 'Nunito',
    body: 'Nunito',
    figures: 'Nunito',
    displayWeight: 800,
    displayHeight: 1.1,
    displayTracking: -0.01,
  ),

  /// Títulos manuscritos sobre un texto redondeado: pizarra y papel.
  handwritten(
    display: 'Caveat',
    body: 'Nunito',
    figures: 'Caveat',
    displayWeight: 700,
    displayHeight: 1,
    displayTracking: 0,
    // La manuscrita tiene el ojo chico: al mismo tamaño se ve más chica que
    // las demás, así que se agranda para que el título pese lo mismo.
    displaySizeFactor: 1.28,
  );

  const CreationFontPair({
    required this.display,
    required this.body,
    required this.figures,
    required this.displayWeight,
    required this.displayHeight,
    required this.displayTracking,
    this.displayItalic = false,
    this.displaySizeFactor = 1,
  });

  final String display;
  final String body;
  final String figures;

  /// El peso de los títulos.
  final int displayWeight;

  /// El interlineado de los títulos (los de cuerpo van a [bodyHeight]).
  final double displayHeight;

  /// El espaciado entre letras de los títulos, en «em»: los grandes se
  /// aprietan un poco, como en la imprenta.
  final double displayTracking;

  /// Si la fuente de títulos trae una itálica de verdad (las citas la usan;
  /// sin ella, una itálica sintetizada se ve torcida y no elegante).
  final bool displayItalic;

  /// Cuánto se agranda la fuente de títulos para pesar lo mismo que las
  /// demás a igual tamaño nominal.
  final double displaySizeFactor;

  static const _inter = 'Inter Creation';

  /// El interlineado del texto corrido.
  static const double bodyHeight = 1.32;

  /// Los pesos que cada familia declara en pubspec.yaml.
  static const Map<String, List<int>> declaredWeights = {
    _inter: [400, 500, 600, 700, 800],
    'Playfair Display': [400, 600, 700, 800],
    'Lora': [400, 500, 600, 700],
    'Source Sans 3': [400, 600, 700],
    'Space Grotesk': [400, 500, 700],
    'Nunito': [400, 600, 800],
    'Caveat': [400, 600, 700],
    'JetBrains Mono': [400, 500, 700],
  };

  /// Las familias que traen su propia itálica en pubspec.yaml.
  static const Set<String> italicFamilies = {'Playfair Display', 'Lora'};

  /// El par guardado con [name], o `null` si no se conoce (que quien lea use
  /// el de la plantilla).
  static CreationFontPair? fromName(String? name) {
    for (final pair in values) {
      if (pair.name == name) return pair;
    }
    return null;
  }

  /// Un título: la fuente de [display] con su peso, interlineado y tracking.
  TextStyle displayStyle({
    required double size,
    required Color color,
    int? weight,
    bool italic = false,
    double? height,
    double? tracking,
  }) => styleFor(
    family: display,
    size: size * displaySizeFactor,
    color: color,
    weight: weight ?? displayWeight,
    italic: italic && displayItalic,
    height: height ?? displayHeight,
    tracking: tracking ?? displayTracking,
  );

  /// Texto corrido o viñetas.
  TextStyle bodyStyle({
    required double size,
    required Color color,
    int weight = 400,
    bool italic = false,
    double? height,
    double tracking = 0,
  }) => styleFor(
    family: body,
    size: size,
    color: color,
    weight: weight,
    italic: italic,
    height: height ?? bodyHeight,
    tracking: tracking,
  );

  /// Cifras, fechas y rótulos.
  TextStyle figuresStyle({
    required double size,
    required Color color,
    int weight = 700,
    double height = 1,
    double tracking = -0.02,
  }) => styleFor(
    family: figures,
    size: figures == display ? size * displaySizeFactor : size,
    color: color,
    weight: weight,
    height: height,
    tracking: tracking,
  );

  /// El estilo de [family] en [weight], con el eje variable en ese peso y el
  /// peso llevado al declarado más cercano. [tracking] va en «em».
  static TextStyle styleFor({
    required String family,
    required double size,
    required Color color,
    required int weight,
    bool italic = false,
    double height = bodyHeight,
    double tracking = 0,
  }) {
    final declared = nearestDeclaredWeight(family, weight);
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      color: color,
      fontWeight: _fontWeight(declared),
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontVariations: [FontVariation.weight(declared.toDouble())],
      height: height,
      letterSpacing: tracking * size,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  /// El peso declarado de [family] más cercano a [weight] (en un empate, el
  /// más pesado: un título que pidió 650 prefiere quedar en 700).
  static int nearestDeclaredWeight(String family, int weight) {
    final options = declaredWeights[family];
    if (options == null || options.isEmpty) return weight;
    var best = options.first;
    for (final option in options) {
      final distance = (option - weight).abs();
      final bestDistance = (best - weight).abs();
      if (distance < bestDistance ||
          (distance == bestDistance && option > best)) {
        best = option;
      }
    }
    return best;
  }

  static FontWeight _fontWeight(int weight) => switch (weight) {
    <= 150 => FontWeight.w100,
    <= 250 => FontWeight.w200,
    <= 350 => FontWeight.w300,
    <= 450 => FontWeight.w400,
    <= 550 => FontWeight.w500,
    <= 650 => FontWeight.w600,
    <= 750 => FontWeight.w700,
    <= 850 => FontWeight.w800,
    _ => FontWeight.w900,
  };
}
