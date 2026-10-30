import 'package:freezed_annotation/freezed_annotation.dart';

part 'deck_design.freezed.dart';

/// Las familias de plantillas: las cinco de F43 («Plantillas →
/// Presentación») y las gráficas de F45, de afiche y de revista.
enum DeckTemplateFamily { classic, modern, graphic, dark, warm, business }

/// Las veintiocho plantillas —las dieciséis de F43 y las doce de F45—, en el
/// orden en que se muestran: cada familia junta. [id] es lo que se guarda;
/// el orden, no, así que una nueva entra donde va su familia.
enum DeckTemplateId {
  editorial('editorial', DeckTemplateFamily.classic),
  parchment('parchment', DeckTemplateFamily.classic),
  academic('academic', DeckTemplateFamily.classic),
  newspaper('newspaper', DeckTemplateFamily.classic),
  ink('ink', DeckTemplateFamily.classic),
  swiss('swiss', DeckTemplateFamily.modern),
  bento('bento', DeckTemplateFamily.modern),
  aurora('aurora', DeckTemplateFamily.modern),
  glass('glass', DeckTemplateFamily.modern),
  magazine('magazine', DeckTemplateFamily.graphic),
  bauhaus('bauhaus', DeckTemplateFamily.graphic),
  brutalist('brutalist', DeckTemplateFamily.graphic),
  midnight('midnight', DeckTemplateFamily.dark),
  neon('neon', DeckTemplateFamily.dark),
  chalkboard('chalkboard', DeckTemplateFamily.dark),
  darkMinimal('dark_minimal', DeckTemplateFamily.dark),
  terminal('terminal', DeckTemplateFamily.dark),
  artDeco('art_deco', DeckTemplateFamily.dark),
  watercolor('watercolor', DeckTemplateFamily.warm),
  pastel('pastel', DeckTemplateFamily.warm),
  paperCut('paper_cut', DeckTemplateFamily.warm),
  retro('retro', DeckTemplateFamily.warm),
  manuscript('manuscript', DeckTemplateFamily.warm),
  whiteboard('whiteboard', DeckTemplateFamily.warm),
  corporate('corporate', DeckTemplateFamily.business),
  data('data', DeckTemplateFamily.business),
  executive('executive', DeckTemplateFamily.business),
  blueprint('blueprint', DeckTemplateFamily.business);

  const DeckTemplateId(this.id, this.family);

  final String id;
  final DeckTemplateFamily family;

  static DeckTemplateId? fromId(Object? id) {
    for (final template in values) {
      if (template.id == id) return template;
    }
    return null;
  }
}

/// Cuánto aire hay alrededor y entre las cosas.
enum DeckDensity {
  airy('airy'),
  standard('standard'),
  compact('compact');

  const DeckDensity(this.id);

  final String id;
}

/// Cómo se pasa de una diapositiva a la otra.
enum DeckTransition {
  fade('fade'),
  slide('slide'),
  zoom('zoom'),
  none('none');

  const DeckTransition(this.id);

  final String id;
}

/// El fondo de las diapositivas (F45, «personalizar»).
enum DeckBackground {
  /// El color del fondo, liso: la diapositiva más callada, la que mejor se
  /// imprime.
  plain('plain'),

  /// El fondo de la plantilla, con su textura y sus ornamentos: el de
  /// siempre.
  texture('texture'),

  /// Un degradé suave con los colores de la paleta.
  gradient('gradient');

  const DeckBackground(this.id);

  final String id;
}

/// La forma de la diapositiva. Las dos tienen el mismo alto lógico, así el
/// tamaño de la letra es el mismo en las dos y solo cambia el ancho.
enum DeckAspect {
  widescreen('16:9', 1920, 1080),
  standard('4:3', 1440, 1080);

  const DeckAspect(this.id, this.logicalWidth, this.logicalHeight);

  final String id;
  final double logicalWidth;
  final double logicalHeight;

  double get ratio => logicalWidth / logicalHeight;
}

/// El diseño de un mazo (decisión G): todo lo que se cambia en el visor sin
/// volver a generar. Se guarda aparte del contenido —ver [toJson]—, así
/// cambiar la plantilla no toca lo que escribió la IA.
@freezed
abstract class DeckDesign with _$DeckDesign {
  const factory DeckDesign({
    @Default(DeckTemplateId.editorial) DeckTemplateId template,

    /// Cuál de las seis paletas de la plantilla.
    @Default(0) int paletteIndex,

    /// Un color propio (ARGB), que tiñe la paleta elegida; null si no hay.
    int? customColor,

    /// El nombre del par de letras (`CreationFontPair.name`), o null para el
    /// de la plantilla.
    String? fontPair,
    @Default(DeckDensity.standard) DeckDensity density,
    @Default(DeckTransition.fade) DeckTransition transition,
    @Default(DeckAspect.widescreen) DeckAspect aspect,

    /// El número de cada diapositiva, abajo.
    @Default(true) bool numbering,

    /// Un pie con el título del mazo.
    @Default(false) bool footer,

    /// El fondo, o null para el de la plantilla (su textura): así un mazo
    /// guardado antes de que se pudiera elegir se sigue viendo igual.
    DeckBackground? background,
  }) = _DeckDesign;

  const DeckDesign._();

  /// Lee un diseño guardado, con tolerancia: lo que falta o no se entiende
  /// toma el valor de fábrica, y nunca falla.
  factory DeckDesign.parse(Object? json) {
    const fallback = DeckDesign();
    if (json is! Map) return fallback;
    T pick<T extends Enum>(
      String key,
      List<T> values,
      String Function(T) id,
      T or,
    ) {
      final raw = json[key];
      for (final value in values) {
        if (id(value) == raw) return value;
      }
      return or;
    }

    final palette = json['palette'];
    final color = json['customColor'];
    final fonts = json['fonts'];
    return DeckDesign(
      template: DeckTemplateId.fromId(json['template']) ?? fallback.template,
      paletteIndex: palette is num
          ? palette.toInt().clamp(0, paletteCount - 1)
          : fallback.paletteIndex,
      customColor: _parseColor(color),
      fontPair: fonts is String && fonts.isNotEmpty ? fonts : null,
      density: pick(
        'density',
        DeckDensity.values,
        (d) => d.id,
        fallback.density,
      ),
      transition: pick(
        'transition',
        DeckTransition.values,
        (t) => t.id,
        fallback.transition,
      ),
      aspect: pick('aspect', DeckAspect.values, (a) => a.id, fallback.aspect),
      numbering: json['numbering'] is bool
          ? json['numbering'] as bool
          : fallback.numbering,
      footer: json['footer'] is bool ? json['footer'] as bool : fallback.footer,
      background: DeckBackground.values
          .where((b) => b.id == json['background'])
          .firstOrNull,
    );
  }

  /// Cuántas paletas trae cada plantilla.
  static const int paletteCount = 6;

  Map<String, Object?> toJson() => {
    'template': template.id,
    'palette': paletteIndex,
    if (customColor != null) 'customColor': _formatColor(customColor!),
    if (fontPair != null) 'fonts': fontPair,
    'density': density.id,
    'transition': transition.id,
    'aspect': aspect.id,
    'numbering': numbering,
    'footer': footer,
    if (background != null) 'background': background!.id,
  };

  /// «#RRGGBB» (o «#AARRGGBB»), o un entero ARGB; cualquier otra cosa, null.
  static int? _parseColor(Object? raw) {
    if (raw is int) return raw;
    if (raw is! String) return null;
    final hex = raw.trim().replaceFirst('#', '');
    if (!RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) {
      return null;
    }
    final value = int.parse(hex, radix: 16);
    return hex.length == 6 ? 0xFF000000 | value : value;
  }

  static String _formatColor(int argb) =>
      '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
