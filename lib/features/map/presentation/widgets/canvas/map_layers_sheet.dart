import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layers_provider.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_layer_marks.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_relation_dialog.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El nombre de [layer], como se lee en la hoja y lo oye el lector de
/// pantalla. La burbuja se nombra por lo que se mira: «Sin tema», «Sin
/// etiquetas».
String mapLayerName(AppLocalizations l10n, MapLayer layer, String topicKind) =>
    switch (layer) {
      MapLayer.links => l10n.f44S5LayerLinks,
      MapLayer.unthemed => l10n.f44S5LayerUnthemed(topicKind),
      MapLayer.tensions => l10n.f44S5LayerTensions,
      MapLayer.similar => l10n.f44S5LayerSimilar,
      MapLayer.study => l10n.f44S5LayerStudy,
    };

/// El ícono de [layer]: el mismo en la hoja y en lo que dibuja.
IconData mapLayerIcon(MapLayer layer) => switch (layer) {
  MapLayer.links => Icons.link,
  MapLayer.unthemed => Icons.label_off_outlined,
  MapLayer.tensions => Icons.bolt,
  MapLayer.similar => Icons.join_inner,
  MapLayer.study => Icons.school_outlined,
};

/// «Capas», abajo junto a Red · Radial · Árbol (F44, paso 5): abre la hoja de
/// las capas y dice cuántas hay prendidas. Es lo que era el botón de cadena.
class MapLayersButton extends StatelessWidget {
  const MapLayersButton({
    required this.count,
    required this.onPressed,
    this.showLabel = false,
    super.key,
  });

  /// Cuántas capas hay prendidas.
  final int count;
  final VoidCallback onPressed;

  /// Si hay lugar para decir «Capas» al lado del ícono.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final icon = Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: const Icon(Icons.layers_outlined),
    );
    return Material(
      color: colors.surfaceContainerHigh,
      elevation: 2,
      shadowColor: colors.shadow.withValues(alpha: 0.3),
      shape: const StadiumBorder(),
      child: Tooltip(
        message: l10n.f44S5LayersTooltip(count),
        excludeFromSemantics: true,
        child: Semantics(
          label: l10n.f44S5LayersTooltip(count),
          button: true,
          excludeSemantics: true,
          onTap: onPressed,
          child: showLabel
              ? TextButton.icon(
                  key: const ValueKey('map-layers'),
                  onPressed: onPressed,
                  icon: icon,
                  label: Text(l10n.f44S5Layers),
                )
              : IconButton(
                  key: const ValueKey('map-layers'),
                  onPressed: onPressed,
                  icon: icon,
                ),
        ),
      ),
    );
  }
}

/// Lo que la hoja de las capas necesita saber del lienzo, y adónde lleva cada
/// atajo.
typedef MapLayersSheetInput = ({
  /// Qué es un tema acá: ver `topicSelectKind`.
  String topicKind,

  /// Cuántos documentos hay sin tema.
  int unthemedCount,

  /// Si se mira en Radial o Árbol, donde no se dibuja todo.
  bool inTree,

  /// Si ya se mira todo lo vinculado.
  bool inLinks,
  VoidCallback onSeeAllLinks,
  VoidCallback onOpenTension,
  VoidCallback onDownloadModel,
});

/// La hoja de las capas (F44, paso 5): cada una con su interruptor, lo que
/// agrega y sus atajos. Se pueden prender varias; la elección se recuerda.
///
/// Con el lector de pantalla, cada interruptor dice su capa y si está
/// prendida, y cada cambio se anuncia («Contradicciones: prendida»).
Future<void> showMapLayersSheet(
  BuildContext context, {
  required MapLayersSheetInput input,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _MapLayersSheet(input: input),
);

class _MapLayersSheet extends ConsumerStatefulWidget {
  const _MapLayersSheet({required this.input});

  final MapLayersSheetInput input;

  @override
  ConsumerState<_MapLayersSheet> createState() => _MapLayersSheetState();
}

class _MapLayersSheetState extends ConsumerState<_MapLayersSheet> {
  /// El último cambio, dicho para el lector de pantalla.
  String? _announced;

  void _set(MapLayer layer, {required bool on}) {
    final l10n = AppLocalizations.of(context)!;
    ref.read(mapLayersProvider.notifier).set(layer, on: on);
    final name = mapLayerName(l10n, layer, widget.input.topicKind);
    setState(
      () =>
          _announced = on ? l10n.f44S5LayerOn(name) : l10n.f44S5LayerOff(name),
    );
  }

  /// Cierra la hoja y hace [action]: los atajos llevan a otro lado.
  void _leaveWith(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final input = widget.input;
    final layers = ref.watch(mapLayersProvider);
    // Sin saberlo todavía, como si estuviera: no se avisa de más.
    final missing =
        !(ref.watch(mapSimilarModelReadyProvider).valueOrNull ?? true);
    final announced = _announced;

    Widget row(MapLayer layer, String hint, {bool enabled = true}) {
      final on = layers.contains(layer);
      return SwitchListTile(
        key: ValueKey('map-layer-${layer.name}'),
        secondary: Icon(mapLayerIcon(layer)),
        title: Text(mapLayerName(l10n, layer, input.topicKind)),
        subtitle: Text(hint),
        value: on,
        // Una capa que no se puede prender se puede, igual, apagar.
        onChanged: enabled || on ? (value) => _set(layer, on: value) : null,
      );
    }

    Widget shortcut(String key, String label, VoidCallback onPressed) =>
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 56, end: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: ValueKey(key),
              onPressed: () => _leaveWith(onPressed),
              child: Text(label),
            ),
          ),
        );

    return SingleChildScrollView(
      key: const ValueKey('map-layers-sheet'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Semantics(
              header: true,
              child: Text(l10n.f44S5Layers, style: theme.textTheme.titleLarge),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              input.inTree ? l10n.f44S5LayersInTree : l10n.f44S5LayersIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          row(MapLayer.links, l10n.f44S5LayerLinksHint),
          if (!input.inLinks)
            shortcut(
              'map-layer-links-all',
              l10n.f44S5LayerLinksAll,
              input.onSeeAllLinks,
            ),
          row(
            MapLayer.unthemed,
            l10n.f44S5LayerUnthemedHint(input.unthemedCount),
          ),
          row(MapLayer.tensions, l10n.f44S5LayerTensionsHint),
          shortcut(
            'map-layer-tensions-open',
            l10n.f44S5OpenTension,
            input.onOpenTension,
          ),
          row(MapLayer.similar, l10n.f44S5LayerSimilarHint, enabled: !missing),
          if (missing)
            Padding(
              key: const ValueKey('map-layer-similar-missing'),
              padding: const EdgeInsetsDirectional.fromSTEB(56, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.f44S5SimilarNeedsModel,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  FilledButton.tonalIcon(
                    key: const ValueKey('map-layer-similar-download'),
                    onPressed: () => _leaveWith(input.onDownloadModel),
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(l10n.f44S5DownloadModel),
                  ),
                ],
              ),
            ),
          row(MapLayer.study, l10n.f44S5LayerStudyHint),
          // Lo último que cambió, para el lector de pantalla: el interruptor
          // dice su estado, y esto, de qué capa era.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                announced ?? '',
                key: const ValueKey('map-layers-announced'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que dice «Parecidos» al tocar el «≈» entre dos documentos (decisión C):
/// que hablan de lo mismo y cuánto, con «Vincular» —un vínculo «relacionado»,
/// con un toque— u «Elegir el tipo». Nada se vincula sin que la persona lo
/// confirme. Devuelve si quedaron vinculados.
Future<bool> showMapSimilarProposal(
  BuildContext context,
  WidgetRef ref, {
  required SimilarPair pair,
  required String titleA,
  required String titleB,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final chosen =
      await showModalBottomSheet<({RelationKind kind, String? note})>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) {
          final theme = Theme.of(context);
          return SingleChildScrollView(
            key: const ValueKey('map-similar-sheet'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    l10n.f44S5SimilarTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.f44S5SimilarBody(titleA, titleB, similarPercent(pair)),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      key: const ValueKey('map-similar-dismiss'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.f44S5SimilarNotNow),
                    ),
                    OutlinedButton(
                      key: const ValueKey('map-similar-kind'),
                      onPressed: () async {
                        final picked =
                            await showDialog<
                              ({RelationKind kind, String? note})
                            >(
                              context: context,
                              builder: (context) => const PickRelationDialog(),
                            );
                        if (picked != null && context.mounted) {
                          Navigator.of(context).pop(picked);
                        }
                      },
                      child: Text(l10n.f44S5SimilarOtherKind),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('map-similar-link'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop((kind: RelationKind.relatedTo, note: null)),
                      icon: const Icon(Icons.add_link),
                      label: Text(l10n.f44S5SimilarLink),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
  if (chosen == null) return false;

  final result = await ref
      .read(organizeRepositoryProvider)
      .createRelation(
        fromItemId: pair.a,
        toItemId: pair.b,
        kind: chosen.kind,
        note: chosen.note,
      );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          result.fold(
            (failure) => failure.localizedMessage(l10n),
            (_) => l10n.relationLinked,
          ),
        ),
      ),
    );
  return result.isRight();
}
