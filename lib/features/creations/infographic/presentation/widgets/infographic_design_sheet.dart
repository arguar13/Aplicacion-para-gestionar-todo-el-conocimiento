import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_styles.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_labels.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_style_gallery.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_labels.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja para personalizar el diseño de una infografía (F43, «Lo que se
/// personaliza»): el estilo, la composición, la paleta —seis, más un color
/// propio—, la tipografía, la orientación, el detalle, los íconos y el
/// fondo. Cada cambio se ve enseguida en la lámina de arriba y se avisa con
/// [onChanged]; nada vuelve a pedirle algo a la IA (decisión G).
///
/// Tiene el aire de las hojas de NotebookLM: el ícono y el título arriba con
/// la ✕ redonda, botones segmentados con ✓ y esquinas muy redondeadas. Va
/// adentro de un `showModalBottomSheet` con `isScrollControlled`.
class InfographicDesignSheet extends StatefulWidget {
  const InfographicDesignSheet({
    required this.sheet,
    required this.design,
    required this.onChanged,
    this.illustrations,
    this.onChangeStyle,
    super.key,
  });

  final Infographic sheet;
  final InfographicDesign design;
  final ValueChanged<InfographicDesign> onChanged;
  final InfographicIllustrationResolver? illustrations;

  /// Abrir la galería de estilos entera; sin esto, los estilos se eligen en
  /// la tira de la hoja misma.
  final VoidCallback? onChangeStyle;

  @override
  State<InfographicDesignSheet> createState() => _InfographicDesignSheetState();
}

class _InfographicDesignSheetState extends State<InfographicDesignSheet> {
  late InfographicDesign _design = widget.design;

  /// El tono del color propio, mientras se elige.
  late double _hue = widget.design.customColor == null
      ? 210
      : HSLColor.fromColor(Color(widget.design.customColor!)).hue;

  @override
  void didUpdateWidget(InfographicDesignSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.design != widget.design) _design = widget.design;
  }

  void _update(InfographicDesign design) {
    setState(() => _design = design);
    widget.onChanged(design);
  }

  /// El estilo de verdad que se ve (el que eligió «Automático», si es él).
  InfographicStyleId get _concreteStyle =>
      InfographicAuto.arrange(widget.sheet, _design).style;

  /// El color propio con el tono [hue], con la luz que le va al estilo: más
  /// claro sobre fondos oscuros, más hondo sobre los claros.
  int _customFor(double hue) {
    final base = InfographicStyles.of(
      _concreteStyle,
    ).palette(_design.paletteIndex);
    return HSLColor.fromAHSL(
      1,
      hue % 360,
      0.68,
      base.isDark ? 0.66 : 0.46,
    ).toColor().toARGB32();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                      Icons.dashboard_customize_outlined,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.f43InfoDesignTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  CreationCloseButton(tooltip: l10n.f43InfoDesignClose),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: AspectRatio(
                  aspectRatio: _design.orientation.ratio,
                  child: InfographicView(
                    key: const Key('infographic-design-preview'),
                    sheet: widget.sheet,
                    design: _design,
                    illustrations: widget.illustrations,
                    borderRadius: BorderRadius.circular(14),
                    shadow: true,
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _padded(CreationSectionLabel(l10n.f43InfoDesignStyle)),
                    if (widget.onChangeStyle != null)
                      _padded(_styleRow(l10n))
                    else
                      InfographicStyleCarousel(
                        key: const Key('infographic-style-carousel'),
                        sheet: widget.sheet,
                        design: _design,
                        illustrations: widget.illustrations,
                        tileWidth: 112,
                        onChanged: _update,
                      ),
                    _padded(
                      CreationSectionLabel(l10n.f43InfoDesignComposition),
                    ),
                    _CompositionStrip(
                      sheet: widget.sheet,
                      design: _design,
                      onChanged: _update,
                    ),
                    _padded(CreationSectionLabel(l10n.f43InfoDesignPalette)),
                    _padded(_palettes(l10n)),
                    if (_design.customColor != null)
                      _padded(
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: CreationHueSlider(
                            sliderKey: const Key('infographic-hue'),
                            hue: _hue,
                            semanticLabel: l10n.f43InfoDesignHue,
                            onChanged: (value) {
                              _hue = value;
                              _update(
                                _design.copyWith(
                                  customColor: _customFor(value),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    _padded(CreationSectionLabel(l10n.f43InfoDesignFonts)),
                    _padded(_fonts(l10n)),
                    _padded(
                      CreationSectionLabel(l10n.f43InfoDesignOrientation),
                    ),
                    _padded(
                      CreationSegmented<InfographicOrientation>(
                        keyPrefix: 'infographic-orientation',
                        selected: _design.orientation,
                        onChanged: (o) =>
                            _update(_design.copyWith(orientation: o)),
                        segments: [
                          for (final o in InfographicOrientation.values)
                            CreationSegment(
                              value: o,
                              id: o.id,
                              label: l10n.infographicOrientation(o),
                            ),
                        ],
                      ),
                    ),
                    _padded(CreationSectionLabel(l10n.f43InfoDesignDetail)),
                    _padded(
                      CreationSegmented<InfographicDetail>(
                        keyPrefix: 'infographic-detail',
                        selected: _design.detail,
                        onChanged: (d) => _update(_design.copyWith(detail: d)),
                        segments: [
                          for (final d in InfographicDetail.values)
                            CreationSegment(
                              value: d,
                              id: d.id,
                              label: l10n.infographicDetail(d),
                            ),
                        ],
                      ),
                    ),
                    _padded(CreationSectionLabel(l10n.f43InfoDesignIcons)),
                    _padded(
                      CreationSegmented<InfographicIconLook>(
                        keyPrefix: 'infographic-icons',
                        selected:
                            _design.iconLook ??
                            InfographicStyles.of(_concreteStyle).iconLook,
                        onChanged: (i) =>
                            _update(_design.copyWith(iconLook: i)),
                        segments: [
                          for (final i in InfographicIconLook.values)
                            CreationSegment(
                              value: i,
                              id: i.id,
                              label: l10n.infographicIcons(i),
                            ),
                        ],
                      ),
                    ),
                    _padded(CreationSectionLabel(l10n.f43InfoDesignBackground)),
                    _padded(
                      CreationSegmented<InfographicBackground>(
                        keyPrefix: 'infographic-background',
                        selected:
                            _design.background ??
                            InfographicStyles.of(_concreteStyle).background,
                        onChanged: (b) =>
                            _update(_design.copyWith(background: b)),
                        segments: [
                          for (final b in InfographicBackground.values)
                            CreationSegment(
                              value: b,
                              id: b.id,
                              label: l10n.infographicBackground(b),
                            ),
                        ],
                      ),
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

  static Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: child,
  );

  Widget _styleRow(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final name = _design.style == InfographicStyleId.auto
        ? l10n.f43InfoGalleryAutoResolved(l10n.infographicStyle(_concreteStyle))
        : l10n.infographicStyle(_design.style);
    return Row(
      children: [
        Expanded(child: Text(name, style: theme.textTheme.titleMedium)),
        const SizedBox(width: 12),
        FilledButton.tonal(
          key: const Key('infographic-change-style'),
          onPressed: widget.onChangeStyle,
          child: Text(l10n.f43InfoDesignChangeStyle),
        ),
      ],
    );
  }

  Widget _palettes(AppLocalizations l10n) {
    final spec = InfographicStyles.of(_concreteStyle);
    final custom = _design.customColor != null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < spec.palettes.length; i++)
          CreationSwatch(
            key: ValueKey('infographic-palette-$i'),
            label: l10n.f43InfoDesignPaletteNumber(i + 1),
            colors: spec.palettes[i].swatch,
            selected: !custom && _design.paletteIndex == i,
            onTap: () =>
                _update(_design.copyWith(paletteIndex: i, customColor: null)),
          ),
        CreationSwatch(
          key: const ValueKey('infographic-palette-custom'),
          label: l10n.f43InfoDesignCustomColor,
          colors: const [],
          selected: custom,
          onTap: () => _update(_design.copyWith(customColor: _customFor(_hue))),
        ),
      ],
    );
  }

  Widget _fonts(AppLocalizations l10n) {
    final styleFonts = InfographicStyles.of(_concreteStyle).fonts;
    final chosen = CreationFontPair.fromName(_design.fontPair);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        CreationFontChoice(
          key: const ValueKey('infographic-fonts-style'),
          pair: styleFonts,
          label: l10n.f43InfoFontsOfStyle,
          selected: chosen == null,
          onTap: () => _update(_design.copyWith(fontPair: null)),
        ),
        for (final pair in CreationFontPair.values)
          CreationFontChoice(
            key: ValueKey('infographic-fonts-${pair.name}'),
            pair: pair,
            label: l10n.deckFonts(pair),
            selected: chosen == pair,
            onTap: () => _update(_design.copyWith(fontPair: pair.name)),
          ),
      ],
    );
  }
}

/// Las composiciones en una tira que se desliza de costado, cada una con la
/// lámina en miniatura armada así.
class _CompositionStrip extends StatelessWidget {
  const _CompositionStrip({
    required this.sheet,
    required this.design,
    required this.onChanged,
  });

  final Infographic sheet;
  final InfographicDesign design;
  final ValueChanged<InfographicDesign> onChanged;

  static const double _tileWidth = 112;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final previewHeight = _tileWidth / design.orientation.ratio;
    final height = previewHeight + 16 + scaler.scale(14) * 3.2 + 30;
    // «Automática» dice cuál eligió para esta lámina.
    final chosen = InfographicAuto.compositionFor(
      sheet,
      InfographicAuto.visibleBlocks(sheet, design.detail),
    );
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: InfographicComposition.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final composition = InfographicComposition.values[i];
          final selected = design.composition == composition;
          final name = composition == InfographicComposition.auto
              ? '${l10n.infographicComposition(composition)} · '
                    '${l10n.infographicComposition(chosen)}'
              : l10n.infographicComposition(composition);
          return SizedBox(
            width: _tileWidth,
            child: Semantics(
              button: true,
              selected: selected,
              label: selected ? l10n.f43InfoGallerySelected(name) : name,
              excludeSemantics: true,
              child: Material(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey(
                    'infographic-composition-${composition.jsonName}',
                  ),
                  onTap: () =>
                      onChanged(design.copyWith(composition: composition)),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected ? scheme.primary : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: previewHeight - 12,
                          child: InfographicView(
                            sheet: sheet,
                            design: design.copyWith(composition: composition),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
