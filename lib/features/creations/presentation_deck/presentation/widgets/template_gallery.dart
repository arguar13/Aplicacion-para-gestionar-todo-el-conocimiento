import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_labels.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La galería de plantillas (F43, «Plantillas: variadas y para todos los
/// gustos»): las dieciséis, en sus cinco familias, cada una con una muestra
/// en vivo de las primeras diapositivas del propio mazo de la persona —no
/// una imagen de ejemplo—, así se elige viendo el resultado.
///
/// Elegir una devuelve el diseño con esa plantilla, su paleta de fábrica y
/// su letra: lo mismo que mostraba la muestra. La densidad, el formato, la
/// transición, la numeración y el pie se quedan como estaban.
class TemplateGallery extends StatelessWidget {
  const TemplateGallery({
    required this.deck,
    required this.design,
    required this.onChanged,
    this.illustrations,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.controller,
    this.shrinkWrap = false,
    this.markSelected = true,
    super.key,
  });

  final SlideDeck deck;
  final DeckDesign design;
  final ValueChanged<DeckDesign> onChanged;
  final SlideIllustrationResolver? illustrations;
  final EdgeInsets padding;
  final ScrollController? controller;
  final bool shrinkWrap;

  /// Si se marca con ✓ la plantilla de [design]. Apagado cuando no hay
  /// ninguna elegida todavía (la hoja de crear, en «Automática»): [design]
  /// pone solo cómo se ven las muestras.
  final bool markSelected;

  /// El diseño con que se muestra (y se elige) la plantilla [id].
  DeckDesign previewOf(DeckTemplateId id) => design.copyWith(
    template: id,
    paletteIndex: 0,
    customColor: null,
    fontPair: null,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding.horizontal;
        final columns = math.max(2, (width / 230).floor());
        final rows = <Widget>[];
        for (final family in DeckTemplateFamily.values) {
          final templates = [
            for (final id in DeckTemplateId.values)
              if (id.family == family) id,
          ];
          rows.add(
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 10),
              child: Text(
                l10n.deckFamily(family),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
          for (var start = 0; start < templates.length; start += columns) {
            rows.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = start; i < start + columns; i++) ...[
                      if (i > start) const SizedBox(width: 12),
                      Expanded(
                        child: i < templates.length
                            ? _TemplateTile(
                                id: templates[i],
                                deck: deck,
                                design: previewOf(templates[i]),
                                selected:
                                    markSelected &&
                                    design.template == templates[i],
                                illustrations: illustrations,
                                onTap: () => onChanged(previewOf(templates[i])),
                              )
                            : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
        }
        return ListView(
          controller: controller,
          shrinkWrap: shrinkWrap,
          padding: padding,
          children: rows,
        );
      },
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.id,
    required this.deck,
    required this.design,
    required this.selected,
    required this.onTap,
    this.illustrations,
  });

  final DeckTemplateId id;
  final SlideDeck deck;
  final DeckDesign design;
  final bool selected;
  final VoidCallback onTap;
  final SlideIllustrationResolver? illustrations;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = l10n.deckTemplate(id);
    final slides = deck.slides;
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? l10n.f43DeckGallerySelected(name) : name,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('template-${id.id}'),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: design.aspect.ratio,
                  child: Stack(
                    children: [
                      if (slides.isNotEmpty)
                        Positioned.fill(
                          child: SlideView(
                            slide: slides.first,
                            design: design,
                            deck: deck,
                            index: 0,
                            illustrations: illustrations,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      // La segunda diapositiva asoma en la esquina, como un
                      // mazo: se ve también cómo queda el contenido.
                      if (slides.length > 1)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          width: 74,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x40000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: AspectRatio(
                              aspectRatio: design.aspect.ratio,
                              child: SlideView(
                                slide: slides[1],
                                design: design,
                                deck: deck,
                                index: 1,
                                illustrations: illustrations,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      if (selected)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
