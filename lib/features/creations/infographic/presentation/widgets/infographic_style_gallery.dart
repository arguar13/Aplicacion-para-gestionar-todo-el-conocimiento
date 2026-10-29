import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_labels.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El diseño con que se muestra (y se elige) el estilo [id] a partir de
/// [design]: su paleta, su letra, sus íconos y su fondo de fábrica. La
/// composición, la orientación y el detalle se quedan como estaban.
InfographicDesign infographicStylePreview(
  InfographicDesign design,
  InfographicStyleId id,
) => design.copyWith(
  style: id,
  paletteIndex: 0,
  customColor: null,
  fontPair: null,
  iconLook: null,
  background: null,
);

/// La galería de estilos de infografía (F43, «Plantillas: variadas y para
/// todos los gustos»): los dieciocho, en sus dos familias, cada uno con una
/// muestra en vivo de la propia lámina —no una imagen de ejemplo—, así se
/// elige viendo el resultado. «Automático» dice qué eligió.
///
/// Elegir uno devuelve el diseño con ese estilo y lo suyo de fábrica (ver
/// [infographicStylePreview]); nada vuelve a la IA (decisión G).
class InfographicStyleGallery extends StatelessWidget {
  const InfographicStyleGallery({
    required this.sheet,
    required this.design,
    required this.onChanged,
    this.illustrations,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.controller,
    this.shrinkWrap = false,
    super.key,
  });

  final Infographic sheet;
  final InfographicDesign design;
  final ValueChanged<InfographicDesign> onChanged;
  final InfographicIllustrationResolver? illustrations;
  final EdgeInsets padding;
  final ScrollController? controller;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding.horizontal;
        final columns = math.max(
          2,
          (width /
                  (design.orientation == InfographicOrientation.portrait
                      ? 150
                      : 220))
              .floor(),
        );
        final rows = <Widget>[];
        for (final family in InfographicStyleFamily.values) {
          final styles = [
            for (final id in InfographicStyleId.values)
              if (id.family == family) id,
          ];
          rows.add(
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 4),
              child: Text(
                l10n.infographicFamily(family),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
          if (family == InfographicStyleFamily.illustrated) {
            rows.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  l10n.f43InfoFamilyIllustratedNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          rows.add(const SizedBox(height: 6));
          for (var start = 0; start < styles.length; start += columns) {
            rows.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = start; i < start + columns; i++) ...[
                      if (i > start) const SizedBox(width: 12),
                      Expanded(
                        child: i < styles.length
                            ? InfographicStyleTile(
                                id: styles[i],
                                sheet: sheet,
                                design: design,
                                selected: design.style == styles[i],
                                illustrations: illustrations,
                                onTap: () => onChanged(
                                  infographicStylePreview(design, styles[i]),
                                ),
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

/// Los estilos en una tira que se desliza de costado: para la hoja de crear
/// («Estilo visual: Automático y las plantillas, en un carrusel con
/// muestra»), con la lámina de muestra mientras no haya una de verdad (ver
/// `InfographicLabels.infographicSample`).
class InfographicStyleCarousel extends StatelessWidget {
  const InfographicStyleCarousel({
    required this.sheet,
    required this.design,
    required this.onChanged,
    this.tileWidth = 132,
    this.illustrations,
    super.key,
  });

  final Infographic sheet;
  final InfographicDesign design;
  final ValueChanged<InfographicDesign> onChanged;
  final double tileWidth;
  final InfographicIllustrationResolver? illustrations;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // El alto de la muestra y el de dos renglones del nombre, con la letra
    // de la persona.
    final height =
        tileWidth / design.orientation.ratio + 16 + scaler.scale(14) * 3.2 + 30;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: InfographicStyleId.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final id = InfographicStyleId.values[i];
          return SizedBox(
            width: tileWidth,
            child: InfographicStyleTile(
              id: id,
              sheet: sheet,
              design: design,
              selected: design.style == id,
              illustrations: illustrations,
              onTap: () => onChanged(infographicStylePreview(design, id)),
            ),
          );
        },
      ),
    );
  }
}

/// Un estilo para elegir: la lámina en miniatura con ese estilo y su
/// nombre; el elegido, con su borde y su ✓.
class InfographicStyleTile extends StatelessWidget {
  const InfographicStyleTile({
    required this.id,
    required this.sheet,
    required this.design,
    required this.selected,
    required this.onTap,
    this.illustrations,
    super.key,
  });

  final InfographicStyleId id;
  final Infographic sheet;

  /// El diseño de ahora: la muestra lo toma con este estilo.
  final InfographicDesign design;
  final bool selected;
  final VoidCallback onTap;
  final InfographicIllustrationResolver? illustrations;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = infographicStylePreview(design, id);
    final name = id == InfographicStyleId.auto
        ? l10n.f43InfoGalleryAutoResolved(
            l10n.infographicStyle(InfographicAuto.styleFor(sheet)),
          )
        : l10n.infographicStyle(id);
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? l10n.f43InfoGallerySelected(name) : name,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('infographic-style-${id.id}'),
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
                  aspectRatio: preview.orientation.ratio,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: InfographicView(
                          sheet: sheet,
                          design: preview,
                          illustrations: illustrations,
                          borderRadius: BorderRadius.circular(12),
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
