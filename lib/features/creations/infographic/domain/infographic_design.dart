import 'package:freezed_annotation/freezed_annotation.dart';

part 'infographic_design.freezed.dart';

/// Las dos familias de estilos (F43, «Plantillas → Infografía»).
enum InfographicStyleFamily {
  /// Dibujados por la app: no necesitan IA de imágenes.
  drawn,

  /// Con ilustraciones con IA. Sin una IA que pueda, se ven terminados igual
  /// con su versión dibujada.
  illustrated,
}

/// Los dieciocho estilos, en el orden en que se muestran. [id] es lo que se
/// guarda (y lo que la IA escribe en `style_hint`).
enum InfographicStyleId {
  auto('auto', InfographicStyleFamily.drawn),
  editorial('editorial', InfographicStyleFamily.drawn),
  geometric('geometric', InfographicStyleFamily.drawn),
  swiss('swiss', InfographicStyleFamily.drawn),
  bento('bento', InfographicStyleFamily.drawn),
  chalkboard('chalkboard', InfographicStyleFamily.drawn),
  neon('neon', InfographicStyleFamily.drawn),
  parchment('parchment', InfographicStyleFamily.drawn),
  corporate('corporate', InfographicStyleFamily.drawn),
  pastel('pastel', InfographicStyleFamily.drawn),
  kids('kids', InfographicStyleFamily.drawn),
  data('data', InfographicStyleFamily.drawn),
  clay('clay', InfographicStyleFamily.illustrated),
  kawaii('kawaii', InfographicStyleFamily.illustrated),
  watercolor('watercolor', InfographicStyleFamily.illustrated),
  isometric('isometric', InfographicStyleFamily.illustrated),
  comic('comic', InfographicStyleFamily.illustrated),
  photo('photo', InfographicStyleFamily.illustrated);

  const InfographicStyleId(this.id, this.family);

  final String id;
  final InfographicStyleFamily family;

  bool get isIllustrated => family == InfographicStyleFamily.illustrated;

  static InfographicStyleId? fromId(Object? id) {
    for (final style in values) {
      if (style.id == id) return style;
    }
    return null;
  }
}

/// Las diez composiciones y «Automática», que elige según el contenido (ver
/// `InfographicAuto.composition`). [jsonName] es lo que se guarda y lo que
/// la IA escribe en `composition_hint`.
enum InfographicComposition {
  auto('auto'),
  bento('bento'),
  columns('columns'),
  zigzag('zigzag'),
  timeline('timeline'),
  process('process'),
  radial('radial'),
  comparison('comparison'),
  pyramid('pyramid'),
  statPanel('stat_panel'),
  conceptMap('concept_map');

  const InfographicComposition(this.jsonName);

  final String jsonName;

  /// Las diez de verdad, sin «Automática».
  static List<InfographicComposition> get concrete =>
      values.where((c) => c != auto).toList();

  static InfographicComposition? fromJsonName(Object? name) {
    for (final composition in values) {
      if (composition.jsonName == name) return composition;
    }
    return null;
  }
}

/// La forma de la lámina. Las tres tienen la misma superficie lógica
/// (1920×1080 = 1080×1920 ≈ 1440×1440), así la letra mide lo mismo en las
/// tres y solo cambia cómo se reparte.
enum InfographicOrientation {
  landscape('landscape', 1920, 1080),
  portrait('portrait', 1080, 1920),
  square('square', 1440, 1440);

  const InfographicOrientation(this.id, this.logicalWidth, this.logicalHeight);

  final String id;
  final double logicalWidth;
  final double logicalHeight;

  double get ratio => logicalWidth / logicalHeight;
}

/// Cuánto se cuenta (F43, punto 4): decide qué bloques se ven y si llevan su
/// detalle, sin volver a pedirle nada a la IA.
enum InfographicDetail {
  concise('concise'),
  standard('standard'),
  detailed('detailed');

  const InfographicDetail(this.id);

  final String id;
}

/// Cómo se dibujan los íconos del juego de lo creado (`CreationIcons`).
enum InfographicIconLook {
  /// El ícono sobre un disco tenue de su color: el de siempre.
  soft('soft'),

  /// Blanco (o negro) sobre un disco lleno de color.
  solid('solid'),

  /// Dentro de un aro fino.
  outline('outline'),

  /// El ícono solo, grande, sin disco.
  bare('bare'),

  /// Sin íconos: más lugar para el texto.
  none('none');

  const InfographicIconLook(this.id);

  final String id;
}

/// El fondo de la lámina.
enum InfographicBackground {
  /// El color del fondo, liso.
  plain('plain'),

  /// La textura del estilo: el grano, la tiza, la grilla, el papel.
  texture('texture'),

  /// Un degradé suave con los colores de la paleta.
  gradient('gradient');

  const InfographicBackground(this.id);

  final String id;
}

/// El diseño de una infografía (decisión G): todo lo que se cambia en el
/// visor sin volver a generar. Se guarda aparte del contenido —ver
/// [toJson]—, así cambiar el estilo no toca lo que escribió la IA.
///
/// [iconLook] y [background] en null toman lo del estilo.
@freezed
abstract class InfographicDesign with _$InfographicDesign {
  const factory InfographicDesign({
    @Default(InfographicStyleId.auto) InfographicStyleId style,
    @Default(InfographicComposition.auto) InfographicComposition composition,

    /// Cuál de las seis paletas del estilo.
    @Default(0) int paletteIndex,

    /// Un color propio (ARGB), que tiñe la paleta elegida; null si no hay.
    int? customColor,

    /// El nombre del par de letras (`CreationFontPair.name`), o null para el
    /// del estilo.
    String? fontPair,
    @Default(InfographicOrientation.portrait)
    InfographicOrientation orientation,
    @Default(InfographicDetail.standard) InfographicDetail detail,
    InfographicIconLook? iconLook,
    InfographicBackground? background,
  }) = _InfographicDesign;

  const InfographicDesign._();

  /// Lee un diseño guardado, con tolerancia: lo que falta o no se entiende
  /// toma el valor de fábrica, y nunca falla.
  factory InfographicDesign.parse(Object? json) {
    const fallback = InfographicDesign();
    if (json is! Map) return fallback;
    T? pick<T extends Enum>(String key, List<T> values, String Function(T) id) {
      final raw = json[key];
      for (final value in values) {
        if (id(value) == raw) return value;
      }
      return null;
    }

    final palette = json['palette'];
    final fonts = json['fonts'];
    return InfographicDesign(
      style: InfographicStyleId.fromId(json['style']) ?? fallback.style,
      composition:
          InfographicComposition.fromJsonName(json['composition']) ??
          fallback.composition,
      paletteIndex: palette is num
          ? palette.toInt().clamp(0, paletteCount - 1)
          : fallback.paletteIndex,
      customColor: parseColor(json['customColor']),
      fontPair: fonts is String && fonts.isNotEmpty ? fonts : null,
      orientation:
          pick('orientation', InfographicOrientation.values, (o) => o.id) ??
          fallback.orientation,
      detail:
          pick('detail', InfographicDetail.values, (d) => d.id) ??
          fallback.detail,
      iconLook: pick('icons', InfographicIconLook.values, (i) => i.id),
      background: pick('background', InfographicBackground.values, (b) => b.id),
    );
  }

  /// Cuántas paletas trae cada estilo.
  static const int paletteCount = 6;

  Map<String, Object?> toJson() => {
    'style': style.id,
    'composition': composition.jsonName,
    'palette': paletteIndex,
    if (customColor != null) 'customColor': formatColor(customColor!),
    if (fontPair != null) 'fonts': fontPair,
    'orientation': orientation.id,
    'detail': detail.id,
    if (iconLook != null) 'icons': iconLook!.id,
    if (background != null) 'background': background!.id,
  };

  /// «#RRGGBB» (o «#AARRGGBB»), o un entero ARGB; cualquier otra cosa, null.
  static int? parseColor(Object? raw) {
    if (raw is int) return raw;
    if (raw is! String) return null;
    final hex = raw.trim().replaceFirst('#', '');
    if (!RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) {
      return null;
    }
    final value = int.parse(hex, radix: 16);
    return hex.length == 6 ? 0xFF000000 | value : value;
  }

  static String formatColor(int argb) =>
      '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
