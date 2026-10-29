import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';

/// En qué estilo se dibujan las ilustraciones de una presentación (F43,
/// «Plantillas → Presentación»: «Igual que la plantilla», «Fotográfico»,
/// «Acuarela», «Plastilina», «Línea», «Isométrico»).
///
/// [id] es lo que se guarda en las opciones. Las pistas van en inglés: es lo
/// que mejor entienden los modelos de imagen, y nunca se le muestran a la
/// persona.
enum DeckIllustrationStyle {
  template('template'),
  photo('photo'),
  watercolor('watercolor'),
  clay('clay'),
  linework('linework'),
  isometric('isometric');

  const DeckIllustrationStyle(this.id);

  final String id;

  static DeckIllustrationStyle? fromId(Object? id) {
    for (final style in values) {
      if (style.id == id) return style;
    }
    return null;
  }

  /// La pista de estilo para el modelo de imagen, con la plantilla
  /// [template] para «Igual que la plantilla».
  String hintFor(DeckTemplateId template) => switch (this) {
    DeckIllustrationStyle.template => _templateHints[template]!,
    DeckIllustrationStyle.photo =>
      'editorial photograph, natural light, shallow depth of field, '
          'realistic, calm composition with negative space',
    DeckIllustrationStyle.watercolor =>
      'loose watercolor painting on textured paper, soft bleeding washes, '
          'gentle pigment granulation, airy white space',
    DeckIllustrationStyle.clay =>
      'claymation style, plasticine 3D figures with visible fingerprints, '
          'soft studio lighting, simple pastel background',
    DeckIllustrationStyle.linework =>
      'elegant single-weight line drawing, fine ink lines on a plain '
          'background, minimal shading, lots of negative space',
    DeckIllustrationStyle.isometric =>
      'clean isometric 3D illustration, soft gradients, gentle shadows, '
          'simple geometric shapes on a plain background',
  };

  /// La pista de cada plantilla: su trazo y su clima de color, para que la
  /// ilustración parezca de la misma familia que la diapositiva.
  static const _templateHints = <DeckTemplateId, String>{
    DeckTemplateId.editorial:
        'refined editorial magazine illustration, muted ink and paper '
        'tones with one warm accent, fine linework, calm composition',
    DeckTemplateId.parchment:
        'antique engraving style illustration on aged parchment, sepia and '
        'umber ink, delicate hatching, classical feel',
    DeckTemplateId.academic:
        'scholarly textbook illustration, precise fine lines, subdued navy '
        'and cream palette, clear and informative',
    DeckTemplateId.swiss:
        'Swiss modernist poster art, bold flat geometric shapes, primary red '
        'with black and white, strong grid, minimal',
    DeckTemplateId.bento:
        'friendly flat vector illustration, rounded shapes, soft neutral '
        'background with bright playful accents',
    DeckTemplateId.aurora:
        'dreamy illustration with soft aurora gradients of violet, teal and '
        'pink, glowing light, smooth and modern',
    DeckTemplateId.glass:
        'glassmorphism 3D illustration, translucent frosted shapes, soft '
        'light refraction, cool blue and violet tones',
    DeckTemplateId.midnight:
        'moody night-time illustration, deep navy and indigo with soft gold '
        'highlights, elegant and quiet',
    DeckTemplateId.neon:
        'neon synthwave illustration on a near-black background, glowing '
        'magenta and cyan outlines, luminous lines',
    DeckTemplateId.chalkboard:
        'hand-drawn chalk illustration on a dark green chalkboard, white and '
        'pastel chalk strokes, sketchy texture',
    DeckTemplateId.watercolor:
        'loose watercolor painting on textured paper, soft bleeding washes '
        'of warm and cool colors, airy white space',
    DeckTemplateId.pastel:
        'soft pastel illustration, rounded friendly shapes, gentle pink, '
        'mint and lavender tones, light and cheerful',
    DeckTemplateId.paperCut:
        'layered paper-cut craft illustration, stacked colored paper with '
        'soft drop shadows, tactile depth',
    DeckTemplateId.corporate:
        'clean corporate flat illustration, professional blue and slate '
        'palette, simple shapes, plenty of white space',
    DeckTemplateId.data:
        'abstract data visualization art, charts and network lines as '
        'decoration, teal and graphite palette, crisp and technical',
    DeckTemplateId.executive:
        'sober executive illustration, charcoal and deep green with a touch '
        'of gold, minimal and premium, clean lines',
  };
}
