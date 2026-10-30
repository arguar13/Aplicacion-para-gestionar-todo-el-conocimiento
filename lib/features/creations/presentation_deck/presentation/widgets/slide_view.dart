import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_canvas.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_style.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_layouts_content.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_layouts_hero.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_layouts_more.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_layouts_structured.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_parts.dart';

export 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_parts.dart'
    show SlideIllustrationResolver;

/// Una diapositiva dibujada (F43): su contenido ([slide]) con el diseño del
/// mazo ([design]), a cualquier tamaño.
///
/// Se compone una sola vez en el lienzo lógico del formato (1920×1080 en
/// 16:9, 1440×1080 en 4:3) y se escala entero para caber en el lugar que le
/// den, así la miniatura, el visor y el PDF son la misma imagen. El texto se
/// ajusta solo contra el lienzo y nunca desborda.
///
/// Se basta sola —trae su dirección de texto y su estilo de letra—, así se
/// puede dibujar fuera de pantalla para el PDF (ver `DeckPdfExporter`).
class SlideView extends StatelessWidget {
  const SlideView({
    required this.slide,
    required this.design,
    required this.deck,
    this.index,
    this.illustrations,
    this.borderRadius = BorderRadius.zero,
    this.shadow = false,
    super.key,
  });

  final Slide slide;
  final DeckDesign design;
  final SlideDeck deck;

  /// La posición de [slide] en el mazo; sin ella, se busca.
  final int? index;

  /// Cómo encontrar las ilustraciones ya hechas; sin esto, todas las
  /// diapositivas que quieren una dibujan la de reserva.
  final SlideIllustrationResolver? illustrations;

  /// El redondeo de las esquinas, en píxeles de pantalla.
  final BorderRadius borderRadius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final style = DeckStyle(design: design, deckTitle: deck.title);
    final position = index ?? _indexOf(slide, deck);
    final c = SlideContext(
      style: style,
      slide: slide,
      index: position,
      total: deck.slides.isEmpty ? 1 : deck.slides.length,
      sectionNumber: _sectionNumber(deck, position),
      illustrations: illustrations,
    );
    return Semantics(
      label: slide.headline,
      container: true,
      child: CreationCanvas(
        logicalSize: style.canvas,
        borderRadius: borderRadius,
        shadow: shadow,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: style.body(),
            child: ExcludeSemantics(child: _layout(c)),
          ),
        ),
      ),
    );
  }

  static Widget _layout(SlideContext c) => switch (c.slide) {
    final CoverSlide s => CoverLayout(c: c, slide: s),
    final SectionSlide s => SectionLayout(c: c, slide: s),
    final BulletsSlide s => BulletsLayout(c: c, slide: s),
    final TwoColumnsSlide s => TwoColumnsLayout(c: c, slide: s),
    final QuoteSlide s => QuoteLayout(c: c, slide: s),
    final BigNumberSlide s => BigNumberLayout(c: c, slide: s),
    final StepsSlide s => StepsLayout(c: c, slide: s),
    final ComparisonSlide s => ComparisonLayout(c: c, slide: s),
    final TimelineSlide s => TimelineLayout(c: c, slide: s),
    final ImageTextSlide s => ImageTextLayout(c: c, slide: s),
    final ConceptGridSlide s => ConceptGridLayout(c: c, slide: s),
    final ClosingSlide s => ClosingLayout(c: c, slide: s),
    final FullQuoteSlide s => FullQuoteLayout(c: c, slide: s),
    final ImageGridSlide s => ImageGridLayout(c: c, slide: s),
    final ConceptMapSlide s => ConceptMapLayout(c: c, slide: s),
    final QuestionsSlide s => QuestionsLayout(c: c, slide: s),
    final StatGridSlide s => StatGridLayout(c: c, slide: s),
    final CycleSlide s => CycleLayout(c: c, slide: s),
    final MatrixSlide s => MatrixLayout(c: c, slide: s),
    final DefinitionSlide s => DefinitionLayout(c: c, slide: s),
  };

  static int _indexOf(Slide slide, SlideDeck deck) {
    final found = deck.slides.indexOf(slide);
    return found < 0 ? 0 : found;
  }

  /// Cuántas secciones hay hasta [index], incluida: el número de la parte.
  static int _sectionNumber(SlideDeck deck, int index) {
    var count = 0;
    for (var i = 0; i <= index && i < deck.slides.length; i++) {
      if (deck.slides[i] is SectionSlide) count++;
    }
    return count == 0 ? 1 : count;
  }
}
