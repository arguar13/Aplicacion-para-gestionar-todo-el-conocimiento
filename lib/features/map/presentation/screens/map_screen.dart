import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/usecases/export_map_usecase.dart';
import 'package:sinapsis/features/map/presentation/providers/map_filter_provider.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_export_handle.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_filter_sheet.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_graph_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_links_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_schema_view.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las vistas del mapa: cuatro maneras de mirar la bóveda con los mismos
/// filtros. Tres miran los temas con el mismo motor; «Vínculos», los
/// elementos y sus vínculos, tengan o no temas (F28).
enum MapView {
  /// Los números que resumen la bóveda.
  board,

  /// Los elementos y los vínculos entre ellos, sin temas de por medio.
  links,

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

  /// Lo que la vista de ahora ofrece para exportarse.
  final _exportHandle = MapExportHandle();

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

  /// Guarda el dibujo de la vista de ahora como [format] —`png` o `svg`—,
  /// donde el usuario elija.
  Future<void> _export(String format, PropertyDefinition category) async {
    // Antes de esperar nada: al terminar, esta pantalla puede haber cambiado.
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final export = ref.read(exportMapUseCaseProvider);

    final Uint8List? bytes;
    if (format == 'svg') {
      final svg = _exportHandle.svg?.call();
      bytes = svg == null ? null : Uint8List.fromList(utf8.encode(svg));
    } else {
      bytes = await _exportHandle.png?.call();
    }
    if (bytes == null) return;

    final result = await export(
      ExportMapParams(
        fileName:
            'mapa-${_viewSlug(_view)}-${_fileSlug(category.name)}.$format',
        bytes: bytes,
      ),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.fold(
              (failure) => failure.localizedMessage(l10n),
              (_) => l10n.mapExportSaved,
            ),
          ),
        ),
      );
  }

  static String _viewSlug(MapView view) => switch (view) {
    MapView.board => 'tablero',
    MapView.links => 'vinculos',
    MapView.schema => 'esquema',
    MapView.graph => 'grafo',
  };

  /// El nombre de la categoría como parte de un nombre de archivo: en
  /// minúsculas, sin acentos y con guiones.
  static String _fileSlug(String name) {
    final dashed = normalizeVocabularyLabel(
      name,
    ).replaceAll(RegExp('[^a-z0-9]+'), '-');
    final slug = dashed.replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'mapa' : slug;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final definitions =
        ref.watch(allPropertyDefinitionsProvider).valueOrNull ?? const [];
    final (categories, selected) = _categories(definitions);
    // El filtro de la biblioteca sobre el que se calcula el mapa: sin
    // restricciones, abarca todo.
    final filter = ref.watch(mapFilterProvider);
    final activeFilters = activeMapFilters(filter);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mapTitle),
        actions: [
          IconButton(
            key: const ValueKey('map-filters'),
            tooltip: l10n.mapFiltersTooltip,
            icon: Badge(
              isLabelVisible: activeFilters > 0,
              label: Text('$activeFilters'),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => showMapFilters(context),
          ),
          // Solo el esquema y el grafo son un dibujo que se pueda guardar.
          PopupMenuButton<String>(
            key: const ValueKey('map-export'),
            enabled: selected != null && _view != MapView.board,
            tooltip: _view == MapView.board
                ? l10n.mapExportUnavailable
                : l10n.mapExportAction,
            icon: const Icon(Icons.ios_share),
            onSelected: (format) => unawaited(_export(format, selected!)),
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const ValueKey('map-export-png'),
                value: 'png',
                child: Text(l10n.mapExportPng),
              ),
              PopupMenuItem(
                key: const ValueKey('map-export-svg'),
                value: 'svg',
                child: Text(l10n.mapExportSvg),
              ),
            ],
          ),
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
                if (activeFilters > 0)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: InputChip(
                        key: const ValueKey('map-filter-active'),
                        avatar: const Icon(Icons.filter_list, size: 18),
                        label: Text(l10n.mapFilterActive(activeFilters)),
                        deleteButtonTooltipMessage: l10n.mapFilterClear,
                        onDeleted: ref.read(mapFilterProvider.notifier).clear,
                        onPressed: () => showMapFilters(context),
                      ),
                    ),
                  ),
                Expanded(
                  child: _MapBody(
                    request: MapRequest(selected.id, filter: filter),
                    view: _view,
                    exportHandle: _exportHandle,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Cuatro vistas no entran con ícono y nombre en un celular angosto:
          // ahí, solo el nombre, que es lo que dice cuál es cuál.
          final icons = constraints.maxWidth >= 520;
          ButtonSegment<MapView> segment(
            MapView view,
            IconData icon,
            String label,
          ) => ButtonSegment(
            value: view,
            icon: icons ? Icon(icon) : null,
            label: Text(label, maxLines: 1, softWrap: false),
          );
          return Semantics(
            label: l10n.mapViewSelectorLabel,
            child: SegmentedButton<MapView>(
              key: const ValueKey('map-view-selector'),
              showSelectedIcon: false,
              segments: [
                segment(
                  MapView.board,
                  Icons.dashboard_outlined,
                  l10n.mapViewBoard,
                ),
                segment(MapView.links, Icons.link, l10n.mapViewLinks),
                segment(
                  MapView.schema,
                  Icons.account_tree_outlined,
                  l10n.mapViewSchema,
                ),
                segment(MapView.graph, Icons.hub_outlined, l10n.mapViewGraph),
              ],
              selected: {_view},
              onSelectionChanged: (views) =>
                  setState(() => _view = views.single),
            ),
          );
        },
      ),
    );
  }
}

/// El mapa de un pedido: pide el estado al motor y muestra la vista elegida.
class _MapBody extends ConsumerWidget {
  const _MapBody({
    required this.request,
    required this.view,
    required this.exportHandle,
    required this.onOpenTopic,
    required this.onOpenItem,
    required this.onOpenTension,
  });

  final MapRequest request;
  final MapView view;
  final MapExportHandle exportHandle;
  final void Function(String valueId) onOpenTopic;
  final void Function(String itemId) onOpenItem;
  final VoidCallback onOpenTension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Los vínculos no esperan al grafo de temas: no lo usan.
    if (view == MapView.links) return _fade(context, _links());
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
      MapView.links => _links(),
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
        exportHandle: exportHandle,
        onOpenTopic: onOpenTopic,
        onOpenItem: onOpenItem,
      ),
      MapView.graph => MapGraphView(
        key: const ValueKey('map-graph'),
        snapshot: snapshot,
        exportHandle: exportHandle,
        onOpenTopic: onOpenTopic,
        onOpenItem: onOpenItem,
      ),
    };

    final animated = _fade(context, body);
    if (!stale) return animated;
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
        Expanded(child: animated),
      ],
    );
  }

  Widget _links() => MapLinksView(
    key: const ValueKey('map-links'),
    filter: request.filter,
    exportHandle: exportHandle,
    onOpenItem: onOpenItem,
  );

  /// Un fundido corto entre vistas, salvo que el sistema pida menos
  /// movimiento.
  Widget _fade(BuildContext context, Widget body) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    child: KeyedSubtree(key: ValueKey(view), child: body),
  );
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
