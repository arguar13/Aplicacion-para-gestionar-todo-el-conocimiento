import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

/// El contraste mínimo entre el color de un documento y el fondo del eje: el
/// 3:1 que WCAG 2.1 pide a lo gráfico que hay que distinguir (1.4.11).
const kDocumentColorMinContrast = 3.0;

/// Si [events] son de varios documentos y entonces conviene pintar cada uno
/// con su color (F40). Corta apenas ve el segundo: con diez mil hechos de dos
/// documentos no recorre la lista entera.
bool showsSeveralDocuments(Iterable<TimelineEvent> events) {
  String? first;
  for (final event in events) {
    if (first == null) {
      first = event.itemId;
    } else if (event.itemId != first) {
      return true;
    }
  }
  return false;
}

/// El color de cada documento en la línea de tiempo (F40): el mismo siempre.
///
/// Sale del identificador del elemento y de nada más —no del orden en que
/// aparecen, ni de cuántos hay a la vista—, así que filtrar por un tema o por
/// un documento no cambia los colores de los que quedan: es lo que permite
/// reconocer "el azul" de un vistazo.
///
/// Se elige de una paleta de doce tonos repartidos por el círculo, en dos
/// variantes de intensidad (veinticuatro colores), y se ajusta a **cada
/// tema**: el claro, el oscuro y los seis con nombre —Sepia entre ellos—
/// tienen otro fondo, y el mismo tono que se ve bien sobre blanco se pierde
/// sobre papel crema o sobre negro. Cada color se oscurece o se aclara, sin
/// cambiar de tono, hasta contrastar [kDocumentColorMinContrast] contra el
/// fondo de la pantalla y contra la superficie, los dos sobre los que se
/// dibuja el eje.
///
/// Con más de veinticuatro documentos dos se parecen: el color no es la única
/// pista —la leyenda dice cuál es cuál, y tocar un hecho dice de qué
/// documento sale—.
class DocumentColors {
  DocumentColors(ThemeData theme)
    : _grounds = [theme.scaffoldBackgroundColor, theme.colorScheme.surface],
      _dark = theme.brightness == Brightness.dark;

  final List<Color> _grounds;
  final bool _dark;

  final _cache = <String, Color>{};

  /// Doce tonos (en grados del círculo cromático) en un orden que separa a los
  /// vecinos: dos documentos seguidos en la paleta no se parecen.
  static const _hues = <double>[
    215, 15, 150, 285, 45, 185, 335, 100, 250, 30, 165, 310, //
  ];

  /// El color de [itemId].
  Color of(String itemId) => _cache.putIfAbsent(itemId, () => _compute(itemId));

  /// Cuántos colores distintos puede dar: doce tonos por dos intensidades.
  static const paletteSize = 24;

  /// A cuál de los [paletteSize] colores cae [itemId]. Es lo único que lo
  /// decide: sirve para probar que no depende de nada más.
  static int slotOf(String itemId) => _fnv1a(itemId) % paletteSize;

  Color _compute(String itemId) {
    final slot = slotOf(itemId);
    final hue = _hues[slot % _hues.length];
    final strong = slot < _hues.length;

    // Primero la intensidad que corresponde al brillo del tema; después el
    // ajuste fino, de a poco, hasta que contraste.
    var lightness = _dark ? (strong ? 0.66 : 0.76) : (strong ? 0.38 : 0.30);
    final saturation = strong ? 0.68 : 0.52;
    final step = _dark ? 0.02 : -0.02;
    var color = _hsl(hue, saturation, lightness);
    for (var i = 0; i < 40; i++) {
      if (_worstContrast(color) >= kDocumentColorMinContrast) break;
      lightness = (lightness + step).clamp(0.0, 1.0);
      color = _hsl(hue, saturation, lightness);
    }
    return color;
  }

  /// El menor contraste de [color] con los fondos sobre los que se dibuja.
  double _worstContrast(Color color) => _grounds
      .map((ground) => documentColorContrast(color, ground))
      .reduce(math.min);

  static Color _hsl(double hue, double saturation, double lightness) =>
      HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
}

/// El contraste de WCAG 2.1 entre dos colores opacos, de 1 a 21.
double documentColorContrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// FNV-1a de 32 bits sobre las unidades de código de [text]: simple, estable
/// entre corridas y plataformas (a diferencia de `hashCode`, que Dart no
/// promete igual de una ejecución a otra) y bien repartido.
int _fnv1a(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}
