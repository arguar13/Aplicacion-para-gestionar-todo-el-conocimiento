import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_labels.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_style_gallery.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Estilo visual» en la hoja de crear la infografía (F43, punto 4:
/// «Automático y las plantillas, en un carrusel con muestra»): los dieciocho
/// estilos de costado, cada uno con una lámina de muestra dibujada en vivo
/// con la orientación y el detalle elegidos arriba —todavía no hay una lámina
/// de verdad—.
///
/// Elegir uno guarda su `id` en las opciones (`InfographicOptionKeys.style`):
/// lo lee el generador —«Automático» le pide a la IA que sugiera uno— y es el
/// que abre el visor. Un estilo con ilustraciones con IA elegido sin el
/// interruptor prendido dice que se va a ver con su versión dibujada.
class InfographicStyleOption extends StatelessWidget {
  const InfographicStyleOption({required this.options, super.key});

  final CreationOptionsContext options;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final design = infographicDesignOf(options.options);
    final drawnInstead =
        design.style.isIllustrated &&
        !infographicWantsIllustrations(options.options);
    return Column(
      key: const Key('infographic-style-option'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CreationSectionLabel(l10n.f43InfoDesignStyle),
        InfographicStyleCarousel(
          key: const Key('infographic-style-carousel'),
          sheet: l10n.infographicSample(),
          design: design,
          tileWidth: 120,
          onChanged: (chosen) =>
              options.set(InfographicOptionKeys.style, chosen.style.id),
        ),
        if (drawnInstead)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.brush_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.f43IgStyleDrawnInstead(
                      l10n.infographicStyle(design.style),
                    ),
                    key: const Key('infographic-style-drawn-note'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
