import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_templates.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_labels.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja para personalizar el diseño de un mazo (F43, «Lo que se
/// personaliza en cada una»): la paleta —seis, más un color propio—, la
/// tipografía, la densidad, el fondo (F45: liso, con la textura de la
/// plantilla o en degradé), la transición, el formato, la numeración y el
/// pie. Cada cambio se ve enseguida en la diapositiva de arriba y se avisa
/// con [onChanged]; nada vuelve a pedirle algo a la IA (decisión G).
///
/// Tiene el aire de las hojas de NotebookLM: el ícono y el título arriba con
/// la ✕ redonda, botones segmentados con ✓ y esquinas muy redondeadas. Va
/// adentro de un `showModalBottomSheet` con `isScrollControlled`.
class DeckDesignSheet extends StatefulWidget {
  const DeckDesignSheet({
    required this.deck,
    required this.design,
    required this.onChanged,
    this.slideIndex = 0,
    this.illustrations,
    this.onChangeTemplate,
    super.key,
  });

  final SlideDeck deck;
  final DeckDesign design;
  final ValueChanged<DeckDesign> onChanged;

  /// La diapositiva que se muestra de muestra (la que se estaba viendo).
  final int slideIndex;
  final SlideIllustrationResolver? illustrations;

  /// Abrir la galería de plantillas; sin esto no se ofrece «Cambiar».
  final VoidCallback? onChangeTemplate;

  @override
  State<DeckDesignSheet> createState() => _DeckDesignSheetState();
}

class _DeckDesignSheetState extends State<DeckDesignSheet> {
  late DeckDesign _design = widget.design;

  /// El tono del color propio, mientras se elige.
  late double _hue = widget.design.customColor == null
      ? 210
      : HSLColor.fromColor(Color(widget.design.customColor!)).hue;

  @override
  void didUpdateWidget(DeckDesignSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.design != widget.design) _design = widget.design;
  }

  void _update(DeckDesign design) {
    setState(() => _design = design);
    widget.onChanged(design);
  }

  /// El color propio con el tono [hue], con la luz que le va a la plantilla:
  /// más claro sobre fondos oscuros, más hondo sobre los claros.
  int _customFor(double hue) {
    final base = DeckTemplates.of(
      _design.template,
    ).palette(_design.paletteIndex);
    final color = HSLColor.fromAHSL(
      1,
      hue % 360,
      0.68,
      base.isDark ? 0.66 : 0.46,
    ).toColor();
    return color.toARGB32();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final slides = widget.deck.slides;
    final index = slides.isEmpty
        ? 0
        : widget.slideIndex.clamp(0, slides.length - 1);
    return Material(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.palette_outlined,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.f43DeckDesignTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  CreationCloseButton(tooltip: l10n.f43DeckDesignClose),
                ],
              ),
            ),
            if (slides.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: AspectRatio(
                    aspectRatio: _design.aspect.ratio,
                    child: SlideView(
                      key: const Key('deck-design-preview'),
                      slide: slides[index],
                      design: _design,
                      deck: widget.deck,
                      index: index,
                      illustrations: widget.illustrations,
                      borderRadius: BorderRadius.circular(14),
                      shadow: true,
                    ),
                  ),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.onChangeTemplate != null) _template(l10n),
                    CreationSectionLabel(l10n.f43DeckDesignPalette),
                    _palettes(l10n),
                    if (_design.customColor != null) _hueSlider(l10n),
                    CreationSectionLabel(l10n.f43DeckDesignFonts),
                    _fonts(l10n),
                    CreationSectionLabel(l10n.f43DeckDesignDensity),
                    CreationSegmented<DeckDensity>(
                      keyPrefix: 'deck-density',
                      selected: _design.density,
                      onChanged: (d) => _update(_design.copyWith(density: d)),
                      segments: [
                        for (final d in DeckDensity.values)
                          CreationSegment(
                            value: d,
                            id: d.id,
                            label: l10n.deckDensity(d),
                          ),
                      ],
                    ),
                    CreationSectionLabel(l10n.f45S5DeckDesignBackground),
                    CreationSegmented<DeckBackground>(
                      keyPrefix: 'deck-background',
                      selected: _design.background ?? DeckBackground.texture,
                      onChanged: (b) =>
                          _update(_design.copyWith(background: b)),
                      segments: [
                        for (final b in DeckBackground.values)
                          CreationSegment(
                            value: b,
                            id: b.id,
                            label: l10n.deckBackground(b),
                          ),
                      ],
                    ),
                    CreationSectionLabel(l10n.f43DeckDesignTransition),
                    CreationSegmented<DeckTransition>(
                      keyPrefix: 'deck-transition',
                      selected: _design.transition,
                      onChanged: (t) =>
                          _update(_design.copyWith(transition: t)),
                      segments: [
                        for (final t in DeckTransition.values)
                          CreationSegment(
                            value: t,
                            id: t.id,
                            label: l10n.deckTransition(t),
                          ),
                      ],
                    ),
                    CreationSectionLabel(l10n.f43DeckDesignAspect),
                    CreationSegmented<DeckAspect>(
                      keyPrefix: 'deck-aspect',
                      selected: _design.aspect,
                      onChanged: (a) => _update(_design.copyWith(aspect: a)),
                      segments: [
                        for (final a in DeckAspect.values)
                          CreationSegment(value: a, id: a.id, label: a.id),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      key: const Key('deck-numbering'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.f43DeckDesignNumbering),
                      value: _design.numbering,
                      onChanged: (v) => _update(_design.copyWith(numbering: v)),
                    ),
                    SwitchListTile(
                      key: const Key('deck-footer'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.f43DeckDesignFooter),
                      value: _design.footer,
                      onChanged: (v) => _update(_design.copyWith(footer: v)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _template(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.f43DeckDesignTemplate,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.deckTemplate(_design.template),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            key: const Key('deck-change-template'),
            onPressed: widget.onChangeTemplate,
            child: Text(l10n.f43DeckDesignChangeTemplate),
          ),
        ],
      ),
    );
  }

  Widget _palettes(AppLocalizations l10n) {
    final template = DeckTemplates.of(_design.template);
    final custom = _design.customColor != null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < template.palettes.length; i++)
          CreationSwatch(
            key: ValueKey('deck-palette-$i'),
            label: l10n.f43DeckDesignPaletteNumber(i + 1),
            colors: template.palettes[i].swatch,
            selected: !custom && _design.paletteIndex == i,
            onTap: () =>
                _update(_design.copyWith(paletteIndex: i, customColor: null)),
          ),
        CreationSwatch(
          key: const ValueKey('deck-palette-custom'),
          label: l10n.f43DeckDesignCustomColor,
          colors: const [],
          selected: custom,
          onTap: () => _update(_design.copyWith(customColor: _customFor(_hue))),
        ),
      ],
    );
  }

  Widget _hueSlider(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CreationHueSlider(
        sliderKey: const Key('deck-hue'),
        hue: _hue,
        semanticLabel: l10n.f43DeckDesignHue,
        onChanged: (value) {
          _hue = value;
          _update(_design.copyWith(customColor: _customFor(value)));
        },
      ),
    );
  }

  Widget _fonts(AppLocalizations l10n) {
    final templateFonts = DeckTemplates.of(_design.template).fonts;
    final chosen = CreationFontPair.fromName(_design.fontPair);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        CreationFontChoice(
          key: const ValueKey('deck-fonts-template'),
          pair: templateFonts,
          label: l10n.f43DeckFontsOfTemplate,
          selected: chosen == null,
          onTap: () => _update(_design.copyWith(fontPair: null)),
        ),
        for (final pair in CreationFontPair.values)
          CreationFontChoice(
            key: ValueKey('deck-fonts-${pair.name}'),
            pair: pair,
            label: l10n.deckFonts(pair),
            selected: chosen == pair,
            onTap: () => _update(_design.copyWith(fontPair: pair.name)),
          ),
      ],
    );
  }
}
