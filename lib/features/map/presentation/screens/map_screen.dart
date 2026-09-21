import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_graph_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_schema_view.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las vistas del mapa: tres maneras de mirar los mismos temas, con el mismo
/// motor, los mismos datos y los mismos filtros.
enum MapView {
  /// Los números que resumen la bóveda.
  board,

  /// Un árbol que parte de un tema y se despliega.
  schema,

  /// La red de comunidades, temas y elementos, según el zoom.
  graph,
}

/// El mapa de conocimiento (F14): la bóveda vista por temas, en una categoría
/// a la vez —«Tema» por defecto—.
///
/// La pantalla no calcula nada: pide el mapa al motor y lo muestra. Mientras el
/// motor recalcula, sigue mostrando el mapa anterior; si el recálculo falla,
/// lo dice y conserva el último que se pudo armar.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// La categoría elegida; `null` hasta que se elige una: se muestra «Tema».
  String? _definitionId;

  MapView _view = MapView.board;

  /// El filtro de la biblioteca sobre el que se calcula el mapa: sin
  /// restricciones, abarca todo.
  final LibraryQuery _filter = const LibraryQuery();

  /// Las categorías donde el mapa tiene sentido —las de texto: la jerarquía
  /// solo vive ahí— y la que se muestra: la elegida, o «Tema», o la primera.
  (List<PropertyDefinition>, PropertyDefinition?) _categories(
    List<PropertyDefinition> definitions,
  ) {
    final text = [
      for (final d in definitions)
        if (d.type == PropertyValueType.text) d,
    ];
    PropertyDefinition? selected;
    for (final d in text) {
      if (d.id == _definitionId) selected = d;
    }
    for (final d in text) {
      if (selected == null && d.isTema) selected = d;
    }
    return (text, selected ?? (text.isEmpty ? null : text.first));
  }

  void _openTopic(String valueId) =>
      context.go(RoutePaths.explorerFor(valueId));

  void _openItem(String itemId) => context.push(RoutePaths.itemDetail(itemId));

  void _openTension() => context.push(RoutePaths.graphTension);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final definitions =
        ref.watch(allPropertyDefinitionsProvider).valueOrNull ?? const [];
    final (categories, selected) = _categories(definitions);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mapTitle),
        actions: [
          if (categories.length > 1)
            PopupMenuButton<String>(
              key: const ValueKey('map-category'),
              tooltip: l10n.mapCategoryTooltip,
              icon: const Icon(Icons.category_outlined),
              initialValue: selected?.id,
              onSelected: (id) => setState(() => _definitionId = id),
              itemBuilder: (context) => [
                for (final d in categories)
                  PopupMenuItem(value: d.id, child: Text(d.name)),
              ],
            ),
        ],
      ),
      body: selected == null
          ? _Empty(l10n: l10n)
          : Column(
              children: [
                if (MapView.values.length > 1) _viewSelector(l10n),
                Expanded(
                  child: _MapBody(
                    request: MapRequest(selected.id, filter: _filter),
                    view: _view,
                    onOpenTopic: _openTopic,
                    onOpenItem: _openItem,
                    onOpenTension: _openTension,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _viewSelector(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        label: l10n.mapViewSelectorLabel,
        child: SegmentedButton<MapView>(
          key: const ValueKey('map-view-selector'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: MapView.board,
              icon: const Icon(Icons.dashboard_outlined),
              label: Text(l10n.mapViewBoard),
            ),
            ButtonSegment(
              value: MapView.schema,
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(l10n.mapViewSchema),
            ),
            ButtonSegment(
              value: MapView.graph,
              icon: const Icon(Icons.hub_outlined),
              label: Text(l10n.mapViewGraph),
            ),
          ],
          selected: {_view},
          onSelectionChanged: (views) => setState(() => _view = views.single),
        ),
      ),
    );
  }
}

/// El mapa de un pedido: pide el estado al motor y muestra la vista elegida.
class _MapBody extends ConsumerWidget {
  const _MapBody({
    required this.request,
    required this.view,
    required this.onOpenTopic,
    required this.onOpenItem,
    required this.onOpenTension,
  });

  final MapRequest request;
  final MapView view;
  final void Function(String valueId) onOpenTopic;
  final void Function(String itemId) onOpenItem;
  final VoidCallback onOpenTension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(knowledgeMapProvider(request)).valueOrNull;

    return switch (state) {
      null || MapLoading() => const Center(child: CircularProgressIndicator()),
      MapReady(:final snapshot) => _ready(context, ref, snapshot, l10n),
      MapFailed(:final lastGood) =>
        lastGood == null
            ? _Failed(
                l10n: l10n,
                onRetry: () => ref.invalidate(knowledgeMapProvider(request)),
              )
            : _ready(context, ref, lastGood, l10n, stale: true),
    };
  }

  Widget _ready(
    BuildContext context,
    WidgetRef ref,
    KnowledgeMapSnapshot snapshot,
    AppLocalizations l10n, {
    bool stale = false,
  }) {
    if (snapshot.graph.nodes.isEmpty) return _Empty(l10n: l10n);

    final dashboard = ref.watch(mapDashboardProvider(request)).valueOrNull;
    final body = switch (view) {
      MapView.board => MapBoardView(
        snapshot: snapshot,
        dashboard: dashboard,
        onOpenTopic: onOpenTopic,
        onOpenItem: onOpenItem,
        onOpenTension: onOpenTension,
      ),
      MapView.schema => MapSchemaView(
        key: const ValueKey('map-schema'),
        snapshot: snapshot,
        onOpenTopic: onOpenTopic,
        onOpenItem: onOpenItem,
      ),
      MapView.graph => MapGraphView(
        key: const ValueKey('map-graph'),
        snapshot: snapshot,
        onOpenTopic: onOpenTopic,
        onOpenItem: onOpenItem,
      ),
    };

    if (!stale) return body;
    return Column(
      children: [
        MaterialBanner(
          key: const ValueKey('map-stale'),
          content: Text(l10n.mapStaleNotice),
          actions: [
            TextButton(
              onPressed: () => ref.invalidate(knowledgeMapProvider(request)),
              child: Text(l10n.mapRetry),
            ),
          ],
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.hub_outlined,
      title: l10n.mapEmptyTitle,
      message: l10n.mapEmptyMessage,
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.l10n, required this.onRetry});

  final AppLocalizations l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.mapLoadError),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('map-retry'),
            onPressed: onRetry,
            child: Text(l10n.mapRetry),
          ),
        ],
      ),
    );
  }
}
