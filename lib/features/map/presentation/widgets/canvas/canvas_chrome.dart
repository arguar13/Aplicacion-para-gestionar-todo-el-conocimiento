import 'package:flutter/material.dart';
import 'package:sinapsis/features/map/domain/entities/link_graph.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/link_strength.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_layers_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo menos que necesitan las migas al lado de los botones.
const _kMinCrumbsWidth = 140.0;

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

/// Lo de arriba del lienzo (F44, paso 2): las migas y los botones de lo que se
/// mira en una fila; si no entran con aire para las migas, los botones bajan a
/// la suya.
class MapCanvasHeader extends StatelessWidget {
  const MapCanvasHeader({
    required this.crumbs,
    required this.actions,
    super.key,
  });

  final List<MapCrumb> crumbs;

  /// Botones de 48 de ancho, como los `IconButton`.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final breadcrumb = MapBreadcrumb(crumbs: crumbs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxWidth - actions.length * 48;
          if (room >= _kMinCrumbsWidth) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: breadcrumb,
                  ),
                ),
                ...actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 12),
                child: breadcrumb,
              ),
              Wrap(alignment: WrapAlignment.end, children: actions),
            ],
          );
        },
      ),
    );
  }
}

/// Lo de abajo del lienzo (F44, paso 2): la disposición y las capas a un
/// lado, y el minimapa con el zoom al otro. En lo muy angosto se achican, no
/// se pisan.
class MapCanvasControls extends StatelessWidget {
  const MapCanvasControls({
    required this.arrangement,
    required this.onArrangement,
    required this.layersOn,
    required this.onLayers,
    required this.minimap,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
    this.showLabels = false,
    super.key,
  });

  final MapArrangement arrangement;
  final ValueChanged<MapArrangement> onArrangement;

  /// Cuántas capas hay prendidas, y abrir su hoja (F44, paso 5).
  final int layersOn;
  final VoidCallback onLayers;

  /// El minimapa, encima del zoom: se esconde solo.
  final Widget minimap;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;

  /// Si hay lugar para el nombre de cada disposición.
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.bottomStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MapArrangementSelector(
                  arrangement: arrangement,
                  showLabels: showLabels,
                  onChanged: onArrangement,
                ),
                const SizedBox(width: 8),
                MapLayersButton(
                  count: layersOn,
                  showLabel: showLabels,
                  onPressed: onLayers,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.bottomEnd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                minimap,
                MapZoomControls(
                  onZoomOut: onZoomOut,
                  onZoomIn: onZoomIn,
                  onFit: onFit,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Los vínculos entre documentos no se pudieron leer: lo dice y deja
/// reintentar.
class MapLinksLoadError extends StatelessWidget {
  const MapLinksLoadError({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.mapLinksLoadError),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: Text(l10n.mapRetry)),
        ],
      ),
    );
  }
}

/// Lo que no se dibujó, y por qué: los temas y las uniones que no entraron,
/// los documentos de más, el árbol cortado y, con los vínculos prendidos
/// ([links]), cuántos quedaron afuera, cuántos deja ver la fuerza elegida y
/// cuántos documentos no tienen ninguno.
///
/// [tree] es el árbol que se muestra —el del dibujo o el de la lista—, y
/// [linkGraph], lo vinculado, cuando ya llegó.
List<Widget> mapCanvasFootnotes(
  AppLocalizations l10n, {
  required bool links,
  required MapAltitude altitude,
  required GraphScene scene,
  required bool isTree,
  required bool asList,
  required CanvasTree? tree,
  required LinkGraph? linkGraph,
  required LinkStrengthFilter strength,
}) {
  final graph = linkGraph;
  return [
    if (!links && altitude == MapAltitude.topics && scene.hidden > 0)
      MapFootnote(
        key: const ValueKey('map-cut'),
        text: l10n.mapGraphTopicsCut(
          scene.nodes.length,
          scene.nodes.length + scene.hidden,
        ),
      ),
    if (!links &&
        !isTree &&
        !asList &&
        altitude == MapAltitude.topics &&
        scene.hiddenEdges > 0)
      MapFootnote(
        key: const ValueKey('map-edges-cut'),
        text: l10n.mapGraphEdgesCut(
          scene.edges.length,
          scene.edges.length + scene.hiddenEdges,
        ),
      ),
    if (!links && altitude == MapAltitude.documents && scene.hidden > 0)
      MapFootnote(
        key: const ValueKey('map-cut'),
        text: l10n.mapGraphItemsCut(scene.nodes.length),
      ),
    if ((isTree || asList) && tree != null && tree.truncated)
      MapFootnote(
        key: const ValueKey('map-tree-truncated'),
        text: l10n.mapSchemaTruncated(tree.entries.length),
      ),
    if (links && graph != null) ...[
      if (graph.hidden > 0)
        MapFootnote(
          key: const ValueKey('map-links-cut'),
          text: l10n.mapLinksCut(graph.items.length, graph.linkedCount),
        ),
      if (strength != LinkStrengthFilter.all)
        MapFootnote(
          key: const ValueKey('map-links-strength-cut'),
          text: l10n.mapLinksStrengthCut(
            graph.shownLinks,
            graph.totalLinks,
            strength.name,
          ),
        ),
      if (graph.unlinkedCount > 0)
        MapFootnote(
          key: const ValueKey('map-links-unlinked'),
          text: l10n.mapLinksUnlinked(graph.unlinkedCount),
        ),
    ],
  ];
}
