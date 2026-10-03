import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/design/widgets/topic_dimension_menu.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organize_now.dart';
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

/// El mapa de conocimiento (F14): la bóveda vista por temas, en una dimensión
/// a la vez (F28): los **temas** —lo que se elige al guardar— si hay alguno, o
/// las **etiquetas**, u otra categoría de texto.
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
  /// La dimensión que se mira. `null` hasta la primera vez que se sabe cuál
  /// toca por defecto; desde ahí queda fija hasta que se elija otra, así un
  /// tema que se crea mientras se mira no cambia el Mapa de golpe.
  String? _dimensionId;

  MapView _view = MapView.board;

  /// El elemento en foco en la vista «Vínculos»: el último que se pidió ver
  /// con «Ver en el Mapa» (F28).
  String? _focusId;

  /// Lo que la vista de ahora ofrece para exportarse.
  final _exportHandle = MapExportHandle();

  @override
  void initState() {
    super.initState();
    // Un pedido que llegó con el Mapa cerrado se atiende al abrirlo; uno que
    // llega con el Mapa abierto, en el acto.
    ref.listenManual(mapLinksFocusRequestProvider, (_, itemId) {
      if (itemId != null) _focusOn(itemId);
    }, fireImmediately: true);
  }

  /// Pasa a la vista «Vínculos» con el foco en [itemId], y da el pedido por
  /// atendido. Un proveedor no se modifica mientras se arma el árbol: se
  /// vuelve a `null` apenas termina.
  void _focusOn(String itemId) {
    setState(() {
      _view = MapView.links;
      _focusId = itemId;
    });
    scheduleMicrotask(() {
      if (!mounted) return;
      ref.read(mapLinksFocusRequestProvider.notifier).state = null;
    });
  }

  /// Abre el material de un tema: el Explorador parado en ese espacio, o
  /// filtrado por ese valor y sus subtemas.
  void _openTopic(TopicDimension dimension, String valueId) => context.go(
    dimension.isSpaces
        ? RoutePaths.explorerForSpace(valueId)
        : RoutePaths.explorerFor(valueId),
  );

  void _openItem(String itemId) => context.push(RoutePaths.itemDetail(itemId));

  void _openTension() => context.push(RoutePaths.graphTension);

  /// Guarda el dibujo de la vista de ahora como [format] —`png` o `svg`—,
  /// donde el usuario elija.
  Future<void> _export(String format, TopicDimension dimension) async {
    // Antes de esperar nada: al terminar, esta pantalla puede haber cambiado.
    final l10n = AppLocalizations.of(context)!;
    // «Vínculos» no depende de la dimensión: su archivo no la nombra.
    final subject = _view == MapView.links
        ? ''
        : '-${_fileSlug(topicDimensionLabel(l10n, dimension))}';
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
        fileName: 'mapa-${_viewSlug(_view)}$subject.$format',
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

  /// El nombre de la dimensión como parte de un nombre de archivo: en
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
    final definitions = ref.watch(allPropertyDefinitionsProvider).valueOrNull;
    final spaces = ref.watch(allSpacesProvider).valueOrNull;
    // El filtro de la biblioteca sobre el que se calcula el mapa: sin
    // restricciones, abarca todo.
    final filter = ref.watch(mapFilterProvider);
    final activeFilters = activeMapFilters(filter);

    // Hasta saber si hay temas no se sabe qué mirar por defecto: elegir antes
    // sería calcular un mapa para tirarlo.
    if (definitions == null || spaces == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.mapTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final (:options, :selected) = topicDimensionsOf(
      definitions,
      hasSpaces: spaces.isNotEmpty,
      chosenId: _dimensionId,
    );
    // La de por defecto queda fija desde ahora: ver [_dimensionId]. Es un
    // recuerdo, no algo que se dibuje, así que no hace falta `setState`.
    _dimensionId ??= selected.id;

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
          // El tablero no es un dibujo que se pueda guardar; las otras vistas,
          // sí.
          PopupMenuButton<String>(
            key: const ValueKey('map-export'),
            enabled: _view != MapView.board,
            tooltip: _view == MapView.board
                ? l10n.mapExportUnavailable
                : l10n.mapExportAction,
            icon: const Icon(Icons.ios_share),
            onSelected: (format) => unawaited(_export(format, selected)),
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
        ],
      ),
      body: Column(
        children: [
          _viewSelector(l10n),
          // La dimensión solo importa a las vistas de temas: «Vínculos» no
          // agrupa.
          if (_view != MapView.links || activeFilters > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_view != MapView.links)
                    TopicDimensionMenu(
                      key: const ValueKey('map-category'),
                      options: options,
                      selected: selected,
                      onSelected: (dimension) =>
                          setState(() => _dimensionId = dimension.id),
                    ),
                  if (activeFilters > 0)
                    InputChip(
                      key: const ValueKey('map-filter-active'),
                      avatar: const Icon(Icons.filter_list, size: 18),
                      label: Text(l10n.mapFilterActive(activeFilters)),
                      deleteButtonTooltipMessage: l10n.mapFilterClear,
                      onDeleted: ref.read(mapFilterProvider.notifier).clear,
                      onPressed: () => showMapFilters(context),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _MapBody(
              request: MapRequest(selected.id, filter: filter),
              dimension: selected,
              view: _view,
              focusId: _focusId,
              exportHandle: _exportHandle,
              unassignedLabel: (count) =>
                  _unassignedLabel(l10n, selected, count),
              onOpenTopic: (valueId) => _openTopic(selected, valueId),
              onOpenItem: _openItem,
              onOpenTension: _openTension,
              onShowLinks: () => setState(() => _view = MapView.links),
            ),
          ),
        ],
      ),
    );
  }

  /// Cómo se dice que [count] elementos quedaron afuera de [dimension].
  static String _unassignedLabel(
    AppLocalizations l10n,
    TopicDimension dimension,
    int count,
  ) {
    if (dimension.isSpaces) return l10n.mapUnassignedSpaces(count);
    if (dimension.isTags) return l10n.mapUnassignedTags(count);
    return l10n.mapUnassignedCategory(count, dimension.category!.name);
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
///
/// Nunca es un vacío mudo (F28): sin temas, el tablero y la vista «Vínculos»
/// siguen ahí, el esquema y el grafo dicen por qué no tienen nada y llevan a
/// los vínculos, y arriba se cuenta lo que quedó sin ubicar con «Organizar con
/// IA».
class _MapBody extends ConsumerWidget {
  const _MapBody({
    required this.request,
    required this.dimension,
    required this.view,
    required this.exportHandle,
    required this.unassignedLabel,
    required this.onOpenTopic,
    required this.onOpenItem,
    required this.onOpenTension,
    required this.onShowLinks,
    this.focusId,
  });

  final MapRequest request;

  /// Lo que se mira: los textos dicen «temas», «etiquetas» o «valores».
  final TopicDimension dimension;
  final MapView view;
  final MapExportHandle exportHandle;

  /// Cómo se dice que tantos elementos quedaron sin ubicar en lo que se mira:
  /// «sin etiquetas», «sin «Época»».
  final String Function(int count) unassignedLabel;
  final void Function(String valueId) onOpenTopic;
  final void Function(String itemId) onOpenItem;
  final VoidCallback onOpenTension;
  final VoidCallback onShowLinks;

  /// El elemento en foco en la vista «Vínculos».
  final String? focusId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Los vínculos no esperan al grafo de temas: no lo usan.
    if (view == MapView.links) {
      return Column(children: [Expanded(child: _fade(context, _links()))]);
    }
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
    final dashboard = ref.watch(mapDashboardProvider(request)).valueOrNull;
    final noTopics = snapshot.graph.nodes.isEmpty;
    final body = switch (view) {
      MapView.links => _links(),
      MapView.board => MapBoardView(
        snapshot: snapshot,
        dimension: dimension,
        dashboard: dashboard,
        onOpenTopic: onOpenTopic,
        onOpenItem: onOpenItem,
        onOpenTension: onOpenTension,
      ),
      // El esquema y el grafo dibujan temas: sin ninguno no hay qué, pero los
      // vínculos se ven igual en su vista.
      MapView.schema || MapView.graph when noTopics => EmptyStateView(
        key: const ValueKey('map-no-topics'),
        icon: Icons.hub_outlined,
        title: l10n.mapEmptyTitle(topicSelectKind(dimension)),
        message: l10n.mapEmptyMessage(topicSelectKind(dimension)),
        actionLabel: l10n.mapSeeLinksAction,
        onAction: onShowLinks,
      ),
      MapView.schema => MapSchemaView(
        key: const ValueKey('map-schema'),
        snapshot: snapshot,
        dimension: dimension,
        exportHandle: exportHandle,
        onOpenTopic: onOpenTopic,
        onOpenItem: onOpenItem,
      ),
      MapView.graph => MapGraphView(
        key: const ValueKey('map-graph'),
        snapshot: snapshot,
        dimension: dimension,
        exportHandle: exportHandle,
        onOpenTopic: onOpenTopic,
        onOpenItem: onOpenItem,
      ),
    };

    final unassigned = snapshot.unassignedItemIds;
    return Column(
      children: [
        if (stale)
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
        if (unassigned.isNotEmpty)
          _UnassignedNotice(
            label: unassignedLabel(unassigned.length),
            onOrganize: () => unawaited(
              organizeAllNowWithAi(context, ref, itemIds: unassigned),
            ),
          ),
        Expanded(child: _fade(context, body)),
      ],
    );
  }

  Widget _links() => MapLinksView(
    key: const ValueKey('map-links'),
    filter: request.filter,
    focusId: focusId,
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

/// Cuántos elementos quedaron sin ubicar en lo que se mira, con «Organizar con
/// IA» (F28): lo que el grafo de temas no puede dibujar, dicho en vez de
/// callado. Una fila, y no un cartel que tape: el tablero y las vistas siguen
/// abajo.
class _UnassignedNotice extends StatelessWidget {
  const _UnassignedNotice({required this.label, required this.onOrganize});

  final String label;
  final VoidCallback onOrganize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      key: const ValueKey('map-unassigned'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(
                Icons.label_off_outlined,
                size: 20,
                color: colors.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('map-organize-with-ai'),
                onPressed: onOrganize,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(l10n.mapOrganizeWithAi),
              ),
            ],
          ),
        ),
      ),
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
