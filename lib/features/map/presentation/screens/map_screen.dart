import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/topic_dimension_menu.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organize_now.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/usecases/export_map_usecase.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/features/map/presentation/providers/map_filter_provider.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/map/presentation/providers/map_tab_provider.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/map_canvas_view.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_pane.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_export_handle.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_filter_sheet.dart';
import 'package:sinapsis/features/organize/presentation/open_organized_item.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/fills_on_triage.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El mapa de conocimiento (F14; F44): lo procesado visto por temas, en una
/// dimensión a la vez (F28) —los **temas** si hay alguno, las **etiquetas** u
/// otra categoría de texto—, en dos pestañas: el **Resumen**, con lo que se
/// cuenta, y el **Mapa**, un solo lienzo que se recorre con el zoom (F44, paso
/// 2). Antes eran cuatro —Tablero, Vínculos, Esquema y Grafo— que dibujaban lo
/// mismo a tres alturas sin hablarse.
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

  /// Lo que el lienzo ofrece para exportarse.
  final _exportHandle = MapExportHandle();

  @override
  void initState() {
    super.initState();
    // Un pedido para el lienzo —«Ver en el Mapa», una fila del Resumen— lleva
    // a la pestaña Mapa; el pedido lo atiende y lo borra el lienzo.
    ref.listenManual(mapCanvasRequestProvider, (_, request) {
      if (request == null) return;
      scheduleMicrotask(() {
        if (mounted) ref.read(mapTabProvider.notifier).select(MapTab.map);
      });
    }, fireImmediately: true);
  }

  /// Abre el material de un tema: lo procesado de ese espacio, o de ese
  /// valor y sus subtemas, encima del Mapa.
  void _openTopic(TopicDimension dimension, String valueId) => context.push(
    dimension.isSpaces
        ? RoutePaths.explorerForSpace(valueId)
        : RoutePaths.explorerFor(valueId),
  );

  void _openItem(String itemId) => openOrganizedItem(context, itemId);

  void _openTension() => context.push(RoutePaths.graphTension);

  /// Lo que ofrece la capa «Parecidos» sin el modelo de vínculos (F30).
  void _openEmbeddingModel() => context.push(RoutePaths.embeddingModel);

  /// «✨ Preguntar al chat» desde la ficha de un nodo: una conversación nueva
  /// sobre lo procesado, con la pregunta hecha y a la vista; se manda sola al
  /// tocar el botón, como «Explicar» (F43, decisión L).
  void _ask(String question) =>
      askInChat(context, ChatHandoff(question: question));

  /// «🎓 Estudiar» desde la ficha: Repasar con [scope] en el selector, y el
  /// Mapa y Estudiar quedan conectados en los dos sentidos.
  void _study(CreationScope scope) => openRepasarWith(context, scope);

  /// Guarda el dibujo del lienzo como [format] —`png` o `svg`—, donde el
  /// usuario elija.
  Future<void> _export(String format, TopicDimension dimension) async {
    // Antes de esperar nada: al terminar, esta pantalla puede haber cambiado.
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final export = ref.read(exportMapUseCaseProvider);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

    // Visto como lista, no hay un dibujo que guardar.
    if (!_exportHandle.available) {
      say(l10n.f44S2ExportFromList);
      return;
    }
    final subject =
        _exportHandle.subject?.call() ?? (arrangement: 'red', links: false);
    // Los vínculos entre documentos no dependen de lo que se agrupa: su
    // archivo no nombra la dimensión.
    final what = subject.links
        ? 'vinculos'
        : _fileSlug(topicDimensionLabel(l10n, dimension));

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
        fileName: 'mapa-${subject.arrangement}-$what.$format',
        bytes: bytes,
      ),
    );
    say(
      result.fold(
        (failure) => failure.localizedMessage(l10n),
        (_) => l10n.mapExportSaved,
      ),
    );
  }

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
    final tab = ref.watch(mapTabProvider);
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
    final request = MapRequest(selected.id, filter: filter);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mapTitle),
        actions: [
          // Ola 2 (F44, paso 5): acá va «⚲ Buscar en el mapa», que deja un
          // `MapCanvasRequest` para que el lienzo vuele hasta lo elegido.
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
          // El Resumen no es un dibujo que se pueda guardar; el Mapa, sí.
          PopupMenuButton<String>(
            key: const ValueKey('map-export'),
            enabled: tab == MapTab.map,
            tooltip: tab == MapTab.map
                ? l10n.mapExportAction
                : l10n.mapExportUnavailable,
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
      // Empieza de cero (F41, paso 6): el Mapa se arma con lo procesado, y sin
      // nada procesado se dice cómo se llena.
      body: ref.watch(hasProcessedProvider) == false
          ? FillsOnTriage(
              icon: Icons.hub_outlined,
              title: l10n.mapFillsOnTriageTitle,
              message: l10n.mapFillsOnTriageMessage,
            )
          : _MapBody(
              request: request,
              tab: tab,
              dimension: selected,
              dimensionOptions: options,
              onDimension: (dimension) =>
                  setState(() => _dimensionId = dimension.id),
              activeFilters: activeFilters,
              exportHandle: _exportHandle,
              onOpenTopic: (valueId) => _openTopic(selected, valueId),
              onOpenItem: _openItem,
              onOpenTension: _openTension,
              onDownloadModel: _openEmbeddingModel,
              onAsk: _ask,
              onStudy: _study,
            ),
    );
  }
}

/// Las pestañas, la línea de arriba y lo que se mira, para un pedido al motor.
///
/// Nunca es un vacío mudo (F28): sin temas, el Resumen sigue ahí y el lienzo
/// dice por qué no tiene nada y lleva a los vínculos; arriba se cuenta lo que
/// quedó sin ubicar, con «Organizar con IA».
class _MapBody extends ConsumerWidget {
  const _MapBody({
    required this.request,
    required this.tab,
    required this.dimension,
    required this.dimensionOptions,
    required this.onDimension,
    required this.activeFilters,
    required this.exportHandle,
    required this.onOpenTopic,
    required this.onOpenItem,
    required this.onOpenTension,
    required this.onDownloadModel,
    required this.onAsk,
    required this.onStudy,
  });

  final MapRequest request;
  final MapTab tab;

  /// Lo que se mira: los textos dicen «temas», «etiquetas» o «valores».
  final TopicDimension dimension;
  final List<TopicDimension> dimensionOptions;
  final ValueChanged<TopicDimension> onDimension;
  final int activeFilters;
  final MapExportHandle exportHandle;
  final void Function(String valueId) onOpenTopic;
  final void Function(String itemId) onOpenItem;
  final VoidCallback onOpenTension;
  final VoidCallback onDownloadModel;
  final ValueChanged<String> onAsk;
  final ValueChanged<CreationScope> onStudy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(knowledgeMapProvider(request)).valueOrNull;
    final (snapshot, stale) = switch (state) {
      MapReady(:final snapshot) => (snapshot, false),
      MapFailed(:final lastGood?) => (lastGood, true),
      _ => (null, false),
    };

    final Widget content;
    if (snapshot == null) {
      content = state is MapFailed
          ? _Failed(
              l10n: l10n,
              onRetry: () => ref.invalidate(knowledgeMapProvider(request)),
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      content = switch (tab) {
        // Lo que se toca en el Resumen va al lienzo por su canal de pedidos
        // (`mapCanvasRequestProvider`), y eso pasa a la pestaña Mapa.
        MapTab.summary => MapBoardPane(
          snapshot: snapshot,
          dimension: dimension,
          dashboard: ref.watch(mapDashboardProvider(request)).valueOrNull,
          onOpenTension: onOpenTension,
        ),
        MapTab.map => MapCanvasView(
          key: const ValueKey('map-canvas-view'),
          snapshot: snapshot,
          dimension: dimension,
          filter: request.filter,
          exportHandle: exportHandle,
          onOpenTopic: onOpenTopic,
          onOpenItem: onOpenItem,
          onAsk: onAsk,
          onStudy: onStudy,
          onOpenTension: onOpenTension,
          onDownloadModel: onDownloadModel,
        ),
      };
    }

    final unassigned = snapshot?.unassignedItemIds ?? const <String>[];
    return Column(
      children: [
        _Tabs(tab: tab),
        SizedBox(
          width: double.infinity,
          child: _TopLine(
            dimension: dimension,
            options: dimensionOptions,
            onDimension: onDimension,
            activeFilters: activeFilters,
            unassignedLabel: unassigned.isEmpty
                ? null
                : _unassignedLabel(l10n, dimension, unassigned.length),
            onOrganize: () => unawaited(
              organizeAllNowWithAi(context, ref, itemIds: unassigned),
            ),
          ),
        ),
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
        Expanded(child: _fade(context, content)),
      ],
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

  /// Un fundido corto entre pestañas, salvo que el sistema pida menos
  /// movimiento.
  Widget _fade(BuildContext context, Widget body) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    child: KeyedSubtree(key: ValueKey(tab), child: body),
  );
}

/// Resumen · Mapa: dos pestañas que se reparten el ancho.
class _Tabs extends ConsumerWidget {
  const _Tabs({required this.tab});

  final MapTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        container: true,
        label: l10n.f44S2TabsLabel,
        child: SegmentedButton<MapTab>(
          key: const ValueKey('map-tabs'),
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: MapTab.summary,
              icon: const Icon(Icons.dashboard_outlined),
              label: Text(l10n.f44S2TabSummary, maxLines: 1, softWrap: false),
            ),
            ButtonSegment(
              value: MapTab.map,
              icon: const Icon(Icons.hub_outlined),
              label: Text(l10n.f44S2TabMap, maxLines: 1, softWrap: false),
            ),
          ],
          selected: {tab},
          onSelectionChanged: (tabs) =>
              ref.read(mapTabProvider.notifier).select(tabs.single),
        ),
      ),
    );
  }
}

/// La línea de arriba, compacta: «Agrupar por», los filtros puestos y cuántos
/// elementos quedaron sin ubicar, con «Organizar con IA» (F28). Antes eran
/// dos filas enteras, y la franja se repetía en cada pestaña; en lo angosto,
/// baja de renglón en vez de cortarse.
class _TopLine extends ConsumerWidget {
  const _TopLine({
    required this.dimension,
    required this.options,
    required this.onDimension,
    required this.activeFilters,
    required this.unassignedLabel,
    required this.onOrganize,
  });

  final TopicDimension dimension;
  final List<TopicDimension> options;
  final ValueChanged<TopicDimension> onDimension;
  final int activeFilters;
  final String? unassignedLabel;
  final VoidCallback onOrganize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unassigned = unassignedLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Wrap(
        // A lo ancho: lo que se agrupa a un lado y lo sin ubicar al otro.
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TopicDimensionMenu(
                key: const ValueKey('map-category'),
                options: options,
                selected: dimension,
                onSelected: onDimension,
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
          if (unassigned != null)
            Wrap(
              key: const ValueKey('map-unassigned'),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  Icons.label_off_outlined,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  unassigned,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
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
        ],
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
