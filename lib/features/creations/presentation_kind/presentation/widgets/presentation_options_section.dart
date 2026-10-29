import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_templates.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_labels.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/template_gallery.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/deck_illustration_style.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo propio de la hoja de la Presentación (F43, paso 11), debajo de
/// Formato, Duración e «Ilustraciones con IA»:
///
/// - **la plantilla**, a la vista: «Automática» y las dieciséis en una tira
///   con la portada de muestra dibujada en cada una, y «Ver todas» con la
///   galería entera (`TemplateGallery`), por familias;
/// - **el estilo de las ilustraciones**, si se piden: «Igual que la
///   plantilla», «Fotográfico», «Acuarela», «Plastilina», «Línea» e
///   «Isométrico», cada uno con su muestra.
///
/// La muestra es un mazo armado con las fuentes elegidas —su título en la
/// portada—: se elige viendo algo parecido a lo que va a salir.
class PresentationOptionsSection extends StatelessWidget {
  const PresentationOptionsSection({required this.options, super.key});

  final CreationOptionsContext options;

  /// Para `CreationKindSpec.optionsBuilder`.
  static Widget builder(BuildContext context, CreationOptionsContext options) =>
      PresentationOptionsSection(options: options);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chosen = PresentationOptions.of(options.options);
    final sample = presentationSampleDeck(l10n, [
      for (final source in options.sources) source.title,
    ]);
    final template = chosen.template;

    void choose(DeckTemplateId? id) => options.set(
      CreationOptionValues.template,
      id?.id ?? CreationOptionValues.auto,
    );

    return Column(
      key: const Key('presentation-options'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CreationSectionLabel(l10n.f43StudioOptTemplate),
        _TemplateStrip(deck: sample, selected: template, onChanged: choose),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('presentation-templates-all'),
            onPressed: () => unawaited(
              showTemplateGallerySheet(
                context,
                deck: sample,
                design: DeckDesign(
                  template: template ?? DeckTemplateId.editorial,
                ),
                selected: template != null,
                onChanged: (design) => choose(design.template),
              ),
            ),
            icon: const Icon(Icons.grid_view_rounded),
            label: Text(l10n.f43PresTemplateSeeAll),
          ),
        ),
        if (chosen.illustrations) ...[
          CreationSectionLabel(l10n.f43PresIllustrationStyle),
          _StyleStrip(
            selected: chosen.illustrationStyle,
            template: template ?? DeckTemplateId.editorial,
            onChanged: (style) =>
                options.set(PresentationOptionKeys.illustrationStyle, style.id),
          ),
        ],
      ],
    );
  }
}

/// Un mazo de muestra para ver las plantillas antes de generar: la portada
/// con el título de la primera fuente y unas ideas.
SlideDeck presentationSampleDeck(AppLocalizations l10n, List<String> titles) {
  final named = [
    for (final title in titles)
      if (title.trim().isNotEmpty) title.trim(),
  ];
  final title = named.isEmpty ? l10n.f43PresSampleTitle : named.first;
  return SlideDeck(
    title: title,
    slides: [
      Slide.cover(
        title: title,
        kicker: l10n.f43PresSampleKicker,
        subtitle: named.length > 1 ? named.skip(1).take(2).join(' · ') : '',
        illustrationPrompt: title,
      ),
      Slide.bullets(
        title: l10n.f43PresSampleIdeas,
        bullets: [
          l10n.f43PresSampleBullet1,
          l10n.f43PresSampleBullet2,
          l10n.f43PresSampleBullet3,
        ],
      ),
    ],
  );
}

/// La galería entera de plantillas en una hoja: elegir una la devuelve y
/// cierra. [selected] dice si la de [design] está elegida (en «Automática»,
/// ninguna).
Future<void> showTemplateGallerySheet(
  BuildContext context, {
  required SlideDeck deck,
  required DeckDesign design,
  required ValueChanged<DeckDesign> onChanged,
  SlideIllustrationResolver? illustrations,
  bool selected = true,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.9,
    minChildSize: 0.5,
    builder: (context, controller) {
      final l10n = AppLocalizations.of(context)!;
      final theme = Theme.of(context);
      return Material(
        key: const Key('presentation-gallery-sheet'),
        color: theme.colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.f43DeckGalleryTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  CreationCloseButton(tooltip: l10n.f43DeckDesignClose),
                ],
              ),
            ),
            Expanded(
              child: TemplateGallery(
                deck: deck,
                design: design,
                // En «Automática» no hay ninguna elegida: ninguna lleva el ✓.
                markSelected: selected,
                illustrations: illustrations,
                controller: controller,
                onChanged: (chosen) {
                  onChanged(chosen);
                  Navigator.of(sheetContext).pop();
                },
              ),
            ),
          ],
        ),
      );
    },
  ),
);

/// La tira de plantillas: «Automática» y las dieciséis, con la portada de
/// muestra dibujada en cada una.
class _TemplateStrip extends StatefulWidget {
  const _TemplateStrip({
    required this.deck,
    required this.selected,
    required this.onChanged,
  });

  final SlideDeck deck;
  final DeckTemplateId? selected;
  final ValueChanged<DeckTemplateId?> onChanged;

  static const double tileWidth = 148;
  static const double gap = 10;

  @override
  State<_TemplateStrip> createState() => _TemplateStripState();
}

class _TemplateStripState extends State<_TemplateStrip> {
  // La elegida, a la vista desde el principio.
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _offsetOf(widget.selected),
  );

  /// Dónde queda la baldosa de [selected], con media baldosa de aire antes.
  static double _offsetOf(DeckTemplateId? selected) {
    final index = selected == null
        ? 0
        : DeckTemplateId.values.indexOf(selected) + 1;
    return math.max(
      0,
      (index - 0.5) * (_TemplateStrip.tileWidth + _TemplateStrip.gap),
    );
  }

  @override
  void didUpdateWidget(_TemplateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // La que se eligió en la galería, a la vista.
    if (oldWidget.selected == widget.selected || !_scroll.hasClients) return;
    final target = _offsetOf(
      widget.selected,
    ).clamp(0.0, _scroll.position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      unawaited(
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: _StripTile.heightFor(
        context,
        _TemplateStrip.tileWidth,
        DeckAspect.widescreen.ratio,
      ),
      child: ListView.separated(
        key: const Key('presentation-template-strip'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        itemCount: DeckTemplateId.values.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: _TemplateStrip.gap),
        itemBuilder: (context, index) {
          final id = index == 0 ? null : DeckTemplateId.values[index - 1];
          final name = id == null
              ? l10n.f43StudioOptTemplateAuto
              : l10n.deckTemplate(id);
          return _StripTile(
            key: ValueKey('presentation-template-${id?.id ?? 'auto'}'),
            width: _TemplateStrip.tileWidth,
            label: name,
            selected: widget.selected == id,
            onTap: () => widget.onChanged(id),
            preview: id == null
                ? const _AutoPreview()
                : SlideView(
                    slide: widget.deck.slides.first,
                    design: DeckDesign(template: id),
                    deck: widget.deck,
                    index: 0,
                    borderRadius: BorderRadius.circular(12),
                  ),
            aspect: DeckAspect.widescreen.ratio,
          );
        },
      ),
    );
  }
}

/// La muestra de «Automática»: un degradé con la chispa de la IA.
class _AutoPreview extends StatelessWidget {
  const _AutoPreview();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: scheme.onPrimaryContainer,
                  size: 26,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.f43PresTemplateAutoHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
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

/// La tira de estilos de ilustración, cada uno con su muestra dibujada con la
/// paleta de la plantilla.
class _StyleStrip extends StatelessWidget {
  const _StyleStrip({
    required this.selected,
    required this.template,
    required this.onChanged,
  });

  final DeckIllustrationStyle selected;
  final DeckTemplateId template;
  final ValueChanged<DeckIllustrationStyle> onChanged;

  static const double tileWidth = 116;
  static const double _aspect = 3 / 2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final deckTemplate = DeckTemplates.of(template);
    return SizedBox(
      height: _StripTile.heightFor(context, tileWidth, _aspect),
      child: ListView.separated(
        key: const Key('presentation-style-strip'),
        scrollDirection: Axis.horizontal,
        itemCount: DeckIllustrationStyle.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final style = DeckIllustrationStyle.values[index];
          return _StripTile(
            key: ValueKey('presentation-style-${style.id}'),
            width: tileWidth,
            label: illustrationStyleLabel(l10n, style),
            selected: style == selected,
            onTap: () => onChanged(style),
            aspect: _aspect,
            preview: CreationArt(
              style: artStyleOf(style, deckTemplate.art),
              palette: deckTemplate.palette(0),
              seed: index * 13 + 5,
              radius: 12,
            ),
          );
        },
      ),
    );
  }
}

/// El trazo con que la app dibuja la muestra de [style] (y el lugar de una
/// ilustración que todavía no está).
CreationArtStyle artStyleOf(
  DeckIllustrationStyle style,
  CreationArtStyle templateArt,
) => switch (style) {
  DeckIllustrationStyle.template => templateArt,
  DeckIllustrationStyle.photo => CreationArtStyle.photo,
  DeckIllustrationStyle.watercolor => CreationArtStyle.organic,
  DeckIllustrationStyle.clay => CreationArtStyle.clay,
  DeckIllustrationStyle.linework => CreationArtStyle.linework,
  DeckIllustrationStyle.isometric => CreationArtStyle.isometric,
};

String illustrationStyleLabel(
  AppLocalizations l10n,
  DeckIllustrationStyle style,
) => switch (style) {
  DeckIllustrationStyle.template => l10n.f43PresStyleTemplate,
  DeckIllustrationStyle.photo => l10n.f43PresStylePhoto,
  DeckIllustrationStyle.watercolor => l10n.f43PresStyleWatercolor,
  DeckIllustrationStyle.clay => l10n.f43PresStyleClay,
  DeckIllustrationStyle.linework => l10n.f43PresStyleLinework,
  DeckIllustrationStyle.isometric => l10n.f43PresStyleIsometric,
};

/// Una baldosa de las tiras: la muestra, el nombre y el ✓ si está elegida.
class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.width,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
    required this.aspect,
    super.key,
  });

  final double width;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  /// El ancho sobre el alto de [preview].
  final double aspect;

  static const double _padding = 6;
  static const double _border = 2.5;
  static const double _labelGap = 6;

  /// El alto de una tira de baldosas de [width] con muestras de [aspect]: la
  /// muestra y dos renglones del nombre con la letra que pidió la persona.
  static double heightFor(BuildContext context, double width, double aspect) {
    final label = Theme.of(context).textTheme.labelLarge!;
    final line =
        MediaQuery.textScalerOf(context).scale(label.fontSize ?? 14) *
        (label.height ?? 1.43);
    const frame = (_padding + _border) * 2;
    return (width - frame) / aspect + frame + _labelGap + line * 2 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? l10n.f43DeckGallerySelected(label) : label,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(_padding),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: _border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: aspect,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        preview,
                        if (selected)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _labelGap),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
