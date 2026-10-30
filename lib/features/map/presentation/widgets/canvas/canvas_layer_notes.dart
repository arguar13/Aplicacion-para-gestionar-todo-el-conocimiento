import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/domain/services/canvas_layers.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_chrome.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_layer_state.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_layer_marks.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que dicen, debajo del lienzo, las capas prendidas (F44, paso 5): cuántas
/// contradicciones hay a la vista —con el atajo a Tensión—, cuántos parecidos
/// o por qué no hay, y cómo se lee el tinte del estudio. Es también lo que oye
/// el lector de pantalla de lo que una capa agregó al dibujo.
///
/// [tree] es el árbol que se ve en Radial, Árbol o la lista, o `null` si se ve
/// la Red; [showsDocuments], si la Red dibuja documentos.
List<Widget> mapLayerNotes(
  AppLocalizations l10n,
  CanvasLayerState state, {
  required CanvasTree? tree,
  required bool showsDocuments,
  required VoidCallback onOpenTension,
  required VoidCallback onDownloadModel,
}) {
  final layers = state.layers;
  final feeds = state.feeds;
  final network = tree == null;
  final treeItems = [
    for (final entry in tree?.entries.values ?? const <CanvasTreeEntry>[])
      if (entry.ref.kind == CanvasTreeKind.item) entry,
  ];
  final documents = network ? showsDocuments : treeItems.isNotEmpty;
  final similarDrawn = network && showsDocuments;
  // En Radial y Árbol, una contradicción es la unión que lo dice.
  final tensions = network
      ? tensionCount(state.scene)
      : treeItems
            .where((entry) => entry.relation == RelationKind.contradicts)
            .length;
  return [
    if (layers.contains(MapLayer.tensions))
      _NoteWithAction(
        key: const ValueKey('map-tensions'),
        icon: Icons.bolt,
        text: l10n.f44S5TensionsShown(tensions),
        actionKey: 'map-tensions-open',
        action: l10n.f44S5OpenTension,
        onAction: onOpenTension,
      ),
    if (layers.contains(MapLayer.similar))
      if (!(feeds.similarReady ?? true))
        _NoteWithAction(
          key: const ValueKey('map-similar-missing'),
          icon: Icons.download_for_offline_outlined,
          text: l10n.f44S5SimilarNeedsModel,
          actionKey: 'map-similar-missing-download',
          action: l10n.f44S5DownloadModel,
          onAction: onDownloadModel,
        )
      else if (!similarDrawn)
        MapFootnote(
          key: const ValueKey('map-similar-documents'),
          text: l10n.f44S5SimilarOnlyDocuments,
        )
      else if (feeds.similarFailed)
        MapFootnote(
          key: const ValueKey('map-similar-failed'),
          text: l10n.f44S5SimilarFailed,
        )
      else if ((feeds.similarReady ?? false) && !feeds.similarPending)
        MapFootnote(
          key: const ValueKey('map-similar-count'),
          text: l10n.f44S5SimilarShown(
            state.drawnSimilar(network: network).length,
          ),
        ),
    if (layers.contains(MapLayer.study) && documents)
      const _StudyLegend(key: ValueKey('map-study-legend')),
  ];
}

/// Una nota de una capa con su atajo al lado; en lo angosto, el atajo baja.
class _NoteWithAction extends StatelessWidget {
  const _NoteWithAction({
    required this.icon,
    required this.text,
    required this.actionKey,
    required this.action,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final String text;
  final String actionKey;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          Text(text, style: theme.textTheme.bodySmall),
          TextButton(
            key: ValueKey(actionKey),
            onPressed: onAction,
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

/// Cómo se lee el tinte de «Estudio»: cada insignia con lo que quiere decir.
class _StudyLegend extends StatelessWidget {
  const _StudyLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.bodySmall;
    // Con la letra grande, el texto baja de renglón al lado de su insignia.
    Widget entry(MapStudyMark mark, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: MapStudyBadge(mark: mark)),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: style)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          entry(const MapStudyMark(MapStudyState.none), l10n.f44S5StudyNone),
          entry(
            const MapStudyMark(MapStudyState.due, due: 1),
            l10n.f44S5StudyLegendDue,
          ),
          entry(
            const MapStudyMark(MapStudyState.upToDate),
            l10n.f44S5StudyUpToDate,
          ),
        ],
      ),
    );
  }
}
