import 'package:flutter/material.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un paso del camino de migas: cómo se llama, qué altura es —para su clave—
/// y adónde lleva; `null` en el último, que es donde se está.
typedef MapCrumb = ({String label, String id, VoidCallback? onTap});

/// Las migas del lienzo (F44, paso 2): «Todo › Cristianismo › Tomás de
/// Aquino». Cada una lleva a esa altura; la última dice dónde se está.
class MapBreadcrumb extends StatelessWidget {
  const MapBreadcrumb({required this.crumbs, super.key});

  final List<MapCrumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      container: true,
      label: l10n.f44S2CrumbsLabel,
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 4,
          children: [
            for (var i = 0; i < crumbs.length; i++) ...[
              if (i > 0)
                const ExcludeSemantics(
                  child: Icon(Icons.chevron_right, size: 16),
                ),
              // Un nombre largo no rompe la fila: se corta, y entero queda en
              // la descripción accesible.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: ActionChip(
                  key: ValueKey('map-crumb-${crumbs[i].id}'),
                  label: Text(
                    crumbs[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: i == crumbs.length - 1 ? null : crumbs[i].onTap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Red · Radial · Árbol: cómo se acomoda lo que se mira. En un celular, solo
/// los íconos —con su nombre al pasar o para el lector—; con lugar, también
/// el nombre.
class MapArrangementSelector extends StatelessWidget {
  const MapArrangementSelector({
    required this.arrangement,
    required this.onChanged,
    this.showLabels = false,
    super.key,
  });

  final MapArrangement arrangement;
  final ValueChanged<MapArrangement> onChanged;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    ButtonSegment<MapArrangement> segment(
      MapArrangement value,
      IconData icon,
      String label,
    ) => ButtonSegment(
      value: value,
      icon: Icon(icon),
      tooltip: showLabels ? null : label,
      label: showLabels ? Text(label, maxLines: 1, softWrap: false) : null,
    );

    return Semantics(
      container: true,
      label: l10n.f44S2ArrangementLabel,
      child: Material(
        color: colors.surfaceContainerHigh,
        elevation: 2,
        shadowColor: colors.shadow.withValues(alpha: 0.3),
        shape: const StadiumBorder(),
        child: SegmentedButton<MapArrangement>(
          key: const ValueKey('map-arrangement'),
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            segment(
              MapArrangement.network,
              Icons.hub_outlined,
              l10n.f44S2ArrangementNetwork,
            ),
            segment(MapArrangement.radial, Icons.radar, l10n.mapSchemaRadial),
            segment(
              MapArrangement.tree,
              Icons.account_tree_outlined,
              l10n.mapSchemaTree,
            ),
          ],
          selected: {arrangement},
          onSelectionChanged: (choice) => onChanged(choice.single),
        ),
      ),
    );
  }
}

/// ⊖ ⊕ ⛶ en una píldora (F44, paso 2): alejar, acercar y encuadrar todo. En
/// la computadora y con el lector de pantalla, pellizcar no alcanza.
class MapZoomControls extends StatelessWidget {
  const MapZoomControls({
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
    super.key,
  });

  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    Widget button(String key, IconData icon, String tooltip, VoidCallback on) =>
        IconButton(
          key: ValueKey('map-$key'),
          icon: Icon(icon),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: on,
        );
    return Material(
      color: colors.surfaceContainerHigh,
      elevation: 2,
      shadowColor: colors.shadow.withValues(alpha: 0.3),
      shape: StadiumBorder(
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button('zoom-out', Icons.remove, l10n.f44S2ZoomOut, onZoomOut),
          button('zoom-in', Icons.add, l10n.f44S2ZoomIn, onZoomIn),
          button('fit', Icons.fit_screen_outlined, l10n.f44S2Fit, onFit),
        ],
      ),
    );
  }
}

/// Una línea chica debajo del lienzo: lo que no se dibujó y por qué.
class MapFootnote extends StatelessWidget {
  const MapFootnote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
