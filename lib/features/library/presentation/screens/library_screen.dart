import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/citations/presentation/export_bibliography_action.dart';
import 'package:sinapsis/features/export/domain/entities/notebooklm_export_result.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/health/presentation/widgets/health_panel.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/search_citation.dart';
import 'package:sinapsis/features/library/domain/entities/search_hit.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_calendar_view.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_kanban_view.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_table_view.dart';
import 'package:sinapsis/features/library/presentation/widgets/move_to_trash.dart';
import 'package:sinapsis/features/library/presentation/widgets/saved_views_sheet.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_filter_section.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_picker_sheet.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/reference/presentation/export_references_action.dart';
import 'package:sinapsis/features/reference/presentation/import_references_action.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/vault/presentation/widgets/compaction_offer_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La pantalla principal: todo lo guardado, con búsqueda y filtros.
///
/// Reemplaza al panel de demostración que había antes. Aquel traía una barra
/// de navegación con destinos "Perfil" y "Ajustes" que no llevaban a ninguna
/// parte; se quitó en vez de conservarla vacía, porque una navegación cuyos
/// botones no hacen nada enseña a desconfiar de los que sí funcionan. Vuelve
/// cuando haya secciones de verdad a las que ir.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

extension _LibraryViewModePresentation on LibraryViewMode {
  IconData get icon => switch (this) {
    LibraryViewMode.list => Icons.view_list_outlined,
    LibraryViewMode.table => Icons.table_chart_outlined,
    LibraryViewMode.kanban => Icons.view_kanban_outlined,
    LibraryViewMode.calendar => Icons.calendar_month_outlined,
  };

  String label(AppLocalizations l10n) => switch (this) {
    LibraryViewMode.list => l10n.libraryViewList,
    LibraryViewMode.table => l10n.libraryViewTable,
    LibraryViewMode.kanban => l10n.libraryViewKanban,
    LibraryViewMode.calendar => l10n.libraryViewCalendar,
  };
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  /// DÓNDE está lo encontrado en cada resultado de la búsqueda en curso, por
  /// id de elemento. Vacío fuera de una búsqueda.
  Map<String, SearchCitation> _citations = const {};

  /// Vacío significa "no está en modo selección", no "seleccionó todo y
  /// después nada". Entrar al modo pasando por acá, y no por un booleano
  /// aparte, evita el estado imposible de "modo activo, pero no se sabe con
  /// qué arrancó".
  final Set<String> _selectedIds = {};
  var _selectionModeActive = false;
  var _viewMode = LibraryViewMode.list;

  /// La última tanda que sí llegó a buen puerto, y con qué consulta.
  ///
  /// `libraryItemsProvider` es `family` por consulta (ver el comentario en
  /// `library_providers.dart`): pedir "cargar más" cambia el límite, y eso es
  /// una consulta distinta para Riverpod, así que por un instante no hay
  /// ningún valor todavía. Sin este resguardo, la lista entera parpadearía a
  /// un spinner cada vez que se pide la próxima tanda — se guarda lo último
  /// que sí se vio para seguir mostrándolo mientras se trae lo nuevo, pero
  /// solo cuando la consulta nueva es la misma de antes con más límite: un
  /// cambio de filtro de verdad no debe mostrar por un instante la lista del
  /// filtro anterior.
  LibraryQuery? _lastLoadedQuery;
  List<KnowledgeItem> _lastLoadedItems = const [];

  bool _isMorePageOf(LibraryQuery query) {
    final last = _lastLoadedQuery;
    return last != null && last.copyWith(limit: query.limit) == query;
  }

  @override
  void initState() {
    super.initState();

    // Retoma lo que quedó a medias en sesiones anteriores: alguien pudo
    // capturar cinco enlaces sin conexión y cerrar la app, o el sistema pudo
    // cerrarla a mitad de procesar algo. Al volver, eso se completa solo, sin
    // que haya que acordarse de pedirlo.
    //
    // Diferido al post-frame por la regla de Riverpod de no tocar providers
    // mientras se construye el árbol de widgets.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(processingQueueProvider.notifier).resume());
    });
  }

  void _enterSelectionMode(String itemId) {
    setState(() {
      _selectionModeActive = true;
      _selectedIds.add(itemId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionModeActive = false;
      _selectedIds.clear();
    });
  }

  void _setSelected(String itemId, {required bool selected}) {
    setState(() {
      if (selected) {
        _selectedIds.add(itemId);
      } else {
        _selectedIds.remove(itemId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(libraryQueryNotifierProvider);
    // Con texto buscado, los resultados traen DÓNDE está lo encontrado; sin
    // él, es la lista de siempre.
    final hits = query.hasSearchText
        ? ref.watch(librarySearchProvider(query))
        : null;
    final items = hits != null
        ? hits.whenData((found) => [for (final hit in found) hit.item])
        : ref.watch(libraryItemsProvider(query));
    _citations = {
      for (final hit in hits?.valueOrNull ?? const <SearchHit>[])
        if (hit.citation != null) hit.item.id: hit.citation!,
    };
    // Se mira acá y no solo en la hoja de "mover a tema", que también lo
    // mira: `allSpacesProvider` es `autoDispose`, y en modo selección nada
    // más lo mantiene vivo —la barra pasa a ser `_SelectionAppBar`—. Sin
    // este `watch`, entrar al modo de selección lo descartaría, y la hoja
    // arrancaría vacía hasta volver a leer los temas de la base.
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];
    // El tema en el que se está parado, con su nombre; `null` también si el
    // `id` elegido todavía no llegó con la lista.
    final currentSpace = spaces
        .where((space) => space.id == query.spaceId)
        .firstOrNull;

    if (items.hasValue) {
      _lastLoadedQuery = query;
      _lastLoadedItems = items.value!;
    }
    final isLoadingMore = !items.hasValue && _isMorePageOf(query);
    final loadedItems =
        items.valueOrNull ??
        (isLoadingMore ? _lastLoadedItems : const <KnowledgeItem>[]);

    return Scaffold(
      appBar: _selectionModeActive
          ? _SelectionAppBar(
              selectedCount: _selectedIds.length,
              onCancel: _exitSelectionMode,
              onExport: () => _exportSelection(context, loadedItems),
              onExportBibliography: _exportBibliographySelection,
              onExportReferences: _exportReferencesSelection,
              onMove: () => _moveSelection(context),
              onDelete: () => _deleteSelection(context),
            )
          : AppBar(
              title: Text(l10n.libraryTitle),
              actions: [
                PopupMenuButton<LibraryViewMode>(
                  icon: Icon(_viewMode.icon),
                  tooltip: l10n.libraryViewList,
                  initialValue: _viewMode,
                  onSelected: (mode) => setState(() => _viewMode = mode),
                  itemBuilder: (context) => [
                    for (final mode in LibraryViewMode.values)
                      PopupMenuItem(
                        value: mode,
                        child: ListTile(
                          leading: Icon(mode.icon),
                          title: Text(mode.label(l10n)),
                          selected: mode == _viewMode,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.timeline),
                  tooltip: l10n.libraryTimelineTooltip,
                  onPressed: () => context.push(RoutePaths.timeline),
                ),
                IconButton(
                  icon: const Icon(Icons.file_download_outlined),
                  tooltip: l10n.libraryImportReferencesAction,
                  onPressed: () => importReferences(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.bookmark_border_outlined),
                  tooltip: l10n.libraryViewsAction,
                  onPressed: () => showSavedViewsSheet(
                    context,
                    ref,
                    currentQuery: query,
                    currentViewMode: _viewMode,
                    onApplyViewMode: (mode) => setState(() => _viewMode = mode),
                  ),
                ),
                // Seleccionar de a varios solo tiene sentido en la lista: en
                // la tabla no hay casillas que ofrecer, y en el tablero
                // arrastrar una tarjeta ya es la forma de actuar sobre ella.
                if (_viewMode == LibraryViewMode.list)
                  IconButton(
                    icon: const Icon(Icons.checklist),
                    tooltip: l10n.librarySelectTooltip,
                    // Sin nada elegido todavía: entrar al modo alcanza, no
                    // hace falta que el primer toque también elija algo.
                    onPressed: () =>
                        setState(() => _selectionModeActive = true),
                  ),
              ],
              // La búsqueda —con el botón de filtros al lado, no una fila
              // propia— y, solo mientras se esté parado en un tema, el chip
              // que lo dice. Tema, tipo y etiquetas viven en el panel que
              // abre ese botón —ver `_FiltersSheet`—, así que esta barra no
              // crece según cuántos haya de cada uno.
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(
                  _SearchAndFilters.heightFor(currentSpace: currentSpace),
                ),
                child: _SearchAndFilters(currentSpace: currentSpace),
              ),
            ),
      floatingActionButton: _selectionModeActive
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(RoutePaths.capture),
              icon: const Icon(Icons.add),
              label: Text(l10n.captureAction),
            ),
      // Mientras se trae la próxima tanda de "cargar más" se sigue mostrando
      // lo que ya había —ver `_lastLoadedItems`— en vez de reemplazarlo por
      // el spinner de carga inicial: no hay nada "cargando" desde el punto
      // de vista de quien mira, solo se está por sumar un poco más.
      body: isLoadingMore
          ? _buildLoadedBody(query, loadedItems, isLoadingMore: true)
          : items.when(
              // Solo se ve en el primer instante: después, el stream
              // re-emite sin volver a pasar por "cargando", así que la
              // lista no parpadea cada vez que se guarda algo.
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _LibraryError(error: error),
              data: (list) =>
                  _buildLoadedBody(query, list, isLoadingMore: false),
            ),
    );
  }

  Widget _buildLoadedBody(
    LibraryQuery query,
    List<KnowledgeItem> list, {
    required bool isLoadingMore,
  }) {
    if (list.isEmpty) return _EmptyState(query: query);

    // Con `limit`, "vinieron tantas como se pidieron" es la única pista
    // disponible sin una consulta de conteo aparte: si vinieron menos, no
    // hay más que traer. Si vinieron justo las pedidas puede que sí haya
    // más — y si no las hay, el próximo toque de "cargar más" lo aclara
    // solo, sin costarle al usuario nada peor que un toque de más.
    final canLoadMore = query.limit != null && list.length >= query.limit!;

    return Column(
      children: [
        // La oferta única de devolver espacio (F12): solo cuando hay bastante
        // para devolver, y una sola vez. Sin oferta no ocupa nada.
        const CompactionOfferCard(),
        // El estado de la bóveda de un vistazo, al tope de la pantalla de
        // inicio. Solo con elementos: en una bóveda vacía no hay nada que
        // mantener, y con una búsqueda sin resultados el panel sería ruido.
        const HealthPanel(),
        Expanded(
          child: switch (_viewMode) {
            LibraryViewMode.list => _ItemList(
              items: list,
              citations: _citations,
              selectionMode: _selectionModeActive,
              selectedIds: _selectedIds,
              onLongPressItem: _enterSelectionMode,
              onSelectedChanged: _setSelected,
            ),
            LibraryViewMode.table => LibraryTableView(items: list),
            LibraryViewMode.kanban => LibraryKanbanView(items: list),
            LibraryViewMode.calendar => LibraryCalendarView(items: list),
          },
        ),
        if (canLoadMore)
          _LoadMoreBar(
            isLoading: isLoadingMore,
            onPressed: () =>
                ref.read(libraryQueryNotifierProvider.notifier).loadMore(),
          ),
      ],
    );
  }

  Future<void> _exportSelection(
    BuildContext context,
    List<KnowledgeItem> allItems,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = allItems
        .where((item) => _selectedIds.contains(item.id))
        .toList();

    final result = await ref.read(exportNotebookLmPackageUseCaseProvider)(
      selected,
    );
    if (!context.mounted) return;

    result.match(
      (failure) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(failure.localizedMessage(l10n))),
          );
      },
      (exportResult) {
        // Cancelar el selector de carpeta no es un error: se deja el modo
        // de selección tal como estaba, por si quiere intentarlo de nuevo.
        if (exportResult is! NotebookLmExportCompleted) return;

        setState(() {
          _selectionModeActive = false;
          _selectedIds.clear();
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                l10n.libraryExportPackageSaved(
                  exportResult.fileCount,
                  exportResult.directoryPath,
                ),
              ),
            ),
          );
      },
    );
  }

  /// La bibliografía de lo seleccionado (F15, D13): sin un título propio
  /// —a diferencia de un espacio o una nota—, así que el archivo se sugiere
  /// como «Bibliografía» a secas.
  Future<void> _exportBibliographySelection() async {
    final l10n = AppLocalizations.of(context)!;
    final sources = await ref
        .read(bibliographyRepositoryProvider)
        .sourcesOf(_selectedIds);
    if (!mounted) return;

    await exportBibliography(
      context,
      ref,
      sources: sources,
      suggestedName: l10n.bibliographyExportSelectionName,
    );
  }

  /// El `.bib`/`.ris` de lo seleccionado (F15, D15).
  Future<void> _exportReferencesSelection() async {
    await exportReferences(context, ref, itemIds: _selectedIds.toList());
  }

  Future<void> _moveSelection(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedIds.length;
    if (count == 0) return;

    // Sin `selectedSpaceId`: los elementos elegidos pueden estar hoy en
    // temas distintos —o algunos sin clasificar—, así que no hay una sola
    // fila que tenga sentido resaltar como "la actual".
    final chosen = await showSpacePickerSheet(context);
    if (chosen == null || !context.mounted) return;

    final (space,) = chosen;
    final result = await ref
        .read(libraryRepositoryProvider)
        .assignSpaceMany(itemIds: _selectedIds.toList(), spaceId: space?.id);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) {
        setState(() {
          _selectionModeActive = false;
          _selectedIds.clear();
        });
        final spaceName = space?.name ?? l10n.detailSpaceNone;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.libraryBulkMoved(count, spaceName))),
          );
      },
    );
  }

  /// Manda lo elegido a la papelera, con su «Deshacer»: no destruye nada, así
  /// que no pregunta.
  Future<void> _deleteSelection(BuildContext context) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    final moved = await moveToTrashWithUndo(context, ref, ids);
    if (!moved || !mounted) return;

    setState(() {
      _selectionModeActive = false;
      _selectedIds.clear();
    });
  }
}

/// La barra superior mientras se seleccionan elementos: cuenta cuántos hay,
/// deja cancelar y ofrece las acciones que tienen sentido en este modo.
class _SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SelectionAppBar({
    required this.selectedCount,
    required this.onCancel,
    required this.onExport,
    required this.onExportBibliography,
    required this.onExportReferences,
    required this.onMove,
    required this.onDelete,
  });

  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback onExport;

  /// La bibliografía de lo seleccionado —F15, D13—.
  final VoidCallback onExportBibliography;

  /// El `.bib`/`.ris` de lo seleccionado —F15, D15—.
  final VoidCallback onExportReferences;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Deshabilitadas en cero: pedirle al caso de uso una lista vacía solo
    // volvería con el mismo fallo de validación, sin que el usuario haya
    // podido hacer nada distinto para evitarlo.
    final hasSelection = selectedCount > 0;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.libraryExitSelectionTooltip,
        onPressed: onCancel,
      ),
      title: Text(l10n.librarySelectedCount(selectedCount)),
      actions: [
        IconButton(
          icon: const Icon(Icons.drive_file_move_outline),
          tooltip: l10n.libraryBulkMoveTooltip,
          onPressed: hasSelection ? onMove : null,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.libraryBulkDeleteTooltip,
          onPressed: hasSelection ? onDelete : null,
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_outlined),
          tooltip: l10n.libraryExportSelectedTooltip,
          onPressed: hasSelection ? onExport : null,
        ),
        IconButton(
          icon: const Icon(Icons.format_quote_outlined),
          tooltip: l10n.bibliographyExportAction,
          onPressed: hasSelection ? onExportBibliography : null,
        ),
        IconButton(
          icon: const Icon(Icons.file_upload_outlined),
          tooltip: l10n.libraryExportReferencesAction,
          onPressed: hasSelection ? onExportReferences : null,
        ),
      ],
    );
  }
}

class _SearchAndFilters extends ConsumerWidget {
  const _SearchAndFilters({required this.currentSpace});

  /// El tema en el que está parada la biblioteca, si hay uno: se muestra
  /// debajo de la búsqueda —ver [build]—.
  final Space? currentSpace;

  static const _searchRowHeight = 64.0;

  /// El alto que ocupa, que la barra de arriba necesita saber antes de
  /// construirla (`PreferredSize`): la fila de la búsqueda siempre, y la del
  /// tema solo mientras se esté parado en uno.
  static double heightFor({required Space? currentSpace}) =>
      _searchRowHeight + (currentSpace == null ? 0 : CurrentSpaceChip.extent);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(libraryQueryNotifierProvider);
    final notifier = ref.read(libraryQueryNotifierProvider.notifier);
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <Tag>[];
    final space = currentSpace;

    // Tema, tipo y etiquetas en un solo número: los tres viven en el mismo
    // panel y acotan qué se ve, así que los tres son "filtros" en el sentido
    // que les da `LibraryQueryNotifier.hasActiveFilters`.
    final activeFilterCount =
        query.sourceKinds.length +
        query.tagIds.length +
        (query.spaceId == null ? 0 : 1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Antes eran cuatro filas apiladas —búsqueda, temas, tipo y, si
        // había alguna, etiquetas— todas con el mismo peso visual y cada una
        // con su propio desplazamiento horizontal: mucho para leer de una, y
        // encima costaba distinguir cuál fila era cuál. Tipo y etiquetas se
        // mudaron primero a un panel aparte, detrás de un solo botón con un
        // número que dice cuántos hay activos; después también los temas, a
        // pedido del usuario, arriba de todo en ese mismo panel. Crear un
        // tema ya no vive acá: se crea donde se elige uno —al guardar algo o
        // al moverlo—, ver `showSpacePickerSheet`, salvo el primero, que la
        // sección de temas del panel ofrece mientras no haya ninguno.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: notifier.search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.librarySearchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Badge(
                label: Text('$activeFilterCount'),
                isLabelVisible: activeFilterCount > 0,
                child: IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: l10n.libraryFiltersTooltip,
                  isSelected: activeFilterCount > 0,
                  onPressed: () => _showFilters(context, tags),
                ),
              ),
            ],
          ),
        ),
        // Sin la fila de temas a la vista, esto es lo que dice en qué tema
        // se está parado —ver `CurrentSpaceChip`—.
        if (space != null)
          CurrentSpaceChip(
            space: space,
            onPressed: () => _showFilters(context, tags),
            onLeave: () => notifier.selectSpace(null),
          ),
      ],
    );
  }

  Future<void> _showFilters(BuildContext context, List<Tag> tags) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Sin esto, el panel queda topeado a la mitad de la pantalla aunque
      // haya de sobra más abajo: con muchas etiquetas puestas, ese tope fijo
      // es lo que obligaría a desplazarse antes de lo necesario.
      isScrollControlled: true,
      builder: (context) => _FiltersSheet(tags: tags),
    );
  }
}

/// El panel de filtros de tema, tipo y etiquetas, detrás del botón con el
/// ícono de perilla —ver `_SearchAndFilters`—.
///
/// `Wrap` y no un desplazamiento horizontal: acá no hay una altura de una
/// sola fila que cuidar, así que las opciones pueden quedar a la vista de
/// una, en las líneas que hagan falta, en vez de esconder las últimas detrás
/// de un scroll que nadie sabe que está ahí. La excepción son los temas, que
/// pueden ser muchos: ver `SpaceFilterSection`.
class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet({required this.tags});

  final List<Tag> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final query = ref.watch(libraryQueryNotifierProvider);
    final notifier = ref.read(libraryQueryNotifierProvider.notifier);

    // `SingleChildScrollView` y no un `Column` a secas: cuántas líneas
    // ocupan los chips de tipo y de etiquetas depende de cuántas etiquetas
    // existan y de qué tan angosta sea la pantalla, y un panel que no puede
    // crecer más allá de lo que el sistema le da de entrada —un teléfono en
    // horizontal, una ventana partida— tiene que poder desplazarse en vez de
    // desbordar.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.libraryFiltersTooltip,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (notifier.hasActiveFilters)
                  TextButton(
                    onPressed: notifier.clearFilters,
                    child: Text(l10n.libraryClearFilters),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Arriba de todo, a pedido del usuario: el tema es la forma
            // principal de recortar la biblioteca. A diferencia de las
            // etiquetas, más abajo, está aunque no haya ninguno: ver
            // `SpaceFilterSection`.
            _FilterSectionLabel(l10n.libraryFilterSpaceLabel),
            const SizedBox(height: 8),
            SpaceFilterSection(
              selectedSpaceId: query.spaceId,
              onChanged: notifier.selectSpace,
            ),
            const SizedBox(height: 20),
            _FilterSectionLabel(l10n.libraryFilterTypeLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in SourceKind.values)
                  FilterChip(
                    avatar: Icon(kind.icon, size: 18),
                    label: Text(kind.label(l10n)),
                    selected: query.sourceKinds.contains(kind),
                    onSelected: (_) => notifier.toggleSourceKind(kind),
                  ),
              ],
            ),
            // Sin nada en el vocabulario todavía, esta sección no tiene qué
            // mostrar: ocuparía lugar para decir "no hay etiquetas por las
            // que filtrar", que no es información que alguien necesite ver
            // siempre.
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 20),
              _FilterSectionLabel(l10n.libraryFilterTagsLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      avatar: const Icon(Icons.label_outline, size: 18),
                      label: Text(tag.name),
                      selected: query.tagIds.contains(tag.id),
                      onSelected: (_) => notifier.toggleTagId(tag.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({
    required this.items,
    required this.citations,
    required this.selectionMode,
    required this.selectedIds,
    required this.onLongPressItem,
    required this.onSelectedChanged,
  });

  final List<KnowledgeItem> items;
  final Map<String, SearchCitation> citations;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<String> onLongPressItem;
  final void Function(String itemId, {required bool selected})
  onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Sitio para que el botón flotante no tape la última fila, y aire a
      // los costados: cada fila es su propia tarjeta, no un renglón que
      // ocupa el ancho completo hasta el borde de la pantalla.
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final citation = citations[item.id];
        return LibraryItemCard(
          item: item,
          citation: citation,
          // La vista de lectura salta al fragmento: el texto de una fuente y
          // su transcripción tienen las mismas posiciones que los chunks.
          onCitationTap: citation == null
              ? null
              : () => context.push(
                  RoutePaths.reading(
                    item.id,
                    start: citation.charStart,
                    end: citation.charEnd,
                  ),
                ),
          onTap: () => context.push('${RoutePaths.library}/${item.id}'),
          onLongPress: () => onLongPressItem(item.id),
          selectionMode: selectionMode,
          selected: selectedIds.contains(item.id),
          onSelectedChanged: (value) =>
              onSelectedChanged(item.id, selected: value),
        );
      },
    );
  }
}

/// El pie de "cargar más": trae la próxima tanda sin tener que desplazarse
/// para descubrir que hay una.
///
/// Un botón explícito y no una carga automática al llegar al final del
/// scroll a propósito: las tres vistas —lista, tabla, tablero— comparten
/// este mismo pie, y solo una de ellas tiene un único scroll vertical del
/// que "llegar al final" tendría un sentido obvio.
class _LoadMoreBar extends StatelessWidget {
  const _LoadMoreBar({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: onPressed,
                  child: Text(l10n.libraryLoadMore),
                ),
        ),
      ),
    );
  }
}

/// Qué mostrar cuando no hay nada que mostrar.
///
/// Son tres situaciones distintas y confundirlas desorienta: una biblioteca
/// recién estrenada, una búsqueda sin coincidencias y unos filtros demasiado
/// estrechos. La última además ofrece la salida, porque el usuario puede no
/// darse cuenta de que dejó un filtro puesto.
class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.query});

  final LibraryQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(libraryQueryNotifierProvider.notifier);

    final (icon, title, message, action) = switch (query) {
      _ when query.hasSearchText => (
        Icons.search_off,
        l10n.librarySearchEmpty(query.searchText!),
        null,
        null,
      ),
      _ when notifier.hasActiveFilters => (
        Icons.filter_alt_off_outlined,
        l10n.libraryFilterEmpty,
        null,
        (l10n.libraryClearFilters, notifier.clearFilters),
      ),
      _ => (
        Icons.inbox_outlined,
        l10n.emptyLibraryTitle,
        l10n.emptyLibraryMessage,
        null,
      ),
    };

    return EmptyStateView(
      icon: icon,
      title: title,
      message: message,
      actionLabel: action?.$1,
      onAction: action?.$2,
    );
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // El repositorio manda los fallos por el stream como `Failure`, así que
    // se traducen por tipo. Cualquier otra cosa cae en el mensaje genérico:
    // mostrar el texto crudo de una excepción no le dice nada a nadie.
    final message = error is Failure
        ? (error as Failure).localizedMessage(l10n)
        : l10n.globalErrorUnexpected;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// El botón de repaso (con insignia), el de tema, el de idioma y el de
// bloquear la bóveda que vivían acá se mudaron a la navegación principal y a
// `SettingsScreen` — ver la decisión 22 en docs/arquitectura.md.
