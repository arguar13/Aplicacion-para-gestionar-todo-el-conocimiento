import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/list_controls.dart';
import 'package:sinapsis/features/library/presentation/widgets/move_to_trash.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_filter_section.dart';
import 'package:sinapsis/features/library/presentation/widgets/spaces_picker_sheet.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_query_notifier.dart';
import 'package:sinapsis/features/processed/presentation/retriage.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_document_card.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/features/transform/presentation/widgets/foreign_video_text_offers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Procesado» (F41): la información que se sacó de cada fuente al triarla,
/// un documento por fuente.
///
/// Se ve y se maneja como la Biblioteca —el mismo buscador con su botón de
/// filtros, el mismo panel, «Cargar más» y la misma selección de a varios
/// (`list_controls.dart`)—, con lo propio de acá: se filtra por tema, por el
/// tipo de la fuente de la que salió y por las partes que tiene, y se ordena
/// por lo último trabajado, por cuándo se procesó o por título.
///
/// La lista nunca trae el texto (`processedDocumentsProvider`): la fila de un
/// libro de millones de caracteres cuesta lo mismo que la de una nota.
class ProcessedScreen extends ConsumerStatefulWidget {
  const ProcessedScreen({super.key});

  @override
  ConsumerState<ProcessedScreen> createState() => _ProcessedScreenState();
}

class _ProcessedScreenState extends ConsumerState<ProcessedScreen> {
  /// Vacío fuera del modo selección, como en la Biblioteca.
  final Set<String> _selectedIds = {};
  var _selectionModeActive = false;

  /// La última tanda que llegó, y con qué consulta: «Cargar más» cambia el
  /// límite, que para Riverpod es otra consulta, y sin esto la lista
  /// parpadearía a la ruedita en cada tanda —ver `LibraryScreen`—.
  ProcessedQuery? _lastLoadedQuery;
  List<ProcessedDocumentSummary> _lastLoaded = const [];

  /// El desplazamiento de la lista: «Ver N resultados», en el panel de
  /// filtros, la deja desde arriba (F47, mejora 21) —ver `LibraryScreen`—.
  final _resultsScroll = ScrollController();

  bool _isMorePageOf(ProcessedQuery query) {
    final last = _lastLoadedQuery;
    return last != null && last.copyWith(limit: query.limit) == query;
  }

  @override
  void dispose() {
    _resultsScroll.dispose();
    super.dispose();
  }

  void _showResultsFromTop() {
    if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
  }

  void _enterSelectionMode(String id) => setState(() {
    _selectionModeActive = true;
    _selectedIds.add(id);
  });

  void _exitSelectionMode() => setState(() {
    _selectionModeActive = false;
    _selectedIds.clear();
  });

  void _setSelected(String id, {required bool selected}) => setState(() {
    if (selected) {
      _selectedIds.add(id);
    } else {
      _selectedIds.remove(id);
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(processedQueryNotifierProvider);
    final documents = ref.watch(processedDocumentsProvider(query));
    // Mirado acá y no solo en el panel: en modo selección nada más mantiene
    // viva la lista de temas, y la hoja arrancaría vacía —ver `LibraryScreen`—.
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];
    final currentSpace = spaces
        .where((space) => space.id == query.spaceId)
        .firstOrNull;

    if (documents.hasValue) {
      _lastLoadedQuery = query;
      _lastLoaded = documents.value!;
    }
    final isLoadingMore = !documents.hasValue && _isMorePageOf(query);
    final loaded =
        documents.valueOrNull ??
        (isLoadingMore ? _lastLoaded : const <ProcessedDocumentSummary>[]);
    final hasSelection = _selectedIds.isNotEmpty;

    return Scaffold(
      appBar: _selectionModeActive
          ? SelectionModeAppBar(
              selectedCount: _selectedIds.length,
              onCancel: _exitSelectionMode,
              actions: [
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outline),
                  tooltip: l10n.libraryBulkMoveTooltip,
                  onPressed: hasSelection ? () => _moveSelection(loaded) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.libraryBulkDeleteTooltip,
                  onPressed: hasSelection ? _deleteSelection : null,
                ),
              ],
            )
          : AppBar(
              title: Text(l10n.processedTitle),
              actions: [_SortButton(sort: query.sortBy)],
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(
                  ListSearchRow.height +
                      (currentSpace == null ? 0 : CurrentSpaceChip.extent),
                ),
                child: _SearchAndFilters(
                  currentSpace: currentSpace,
                  onShowResults: _showResultsFromTop,
                ),
              ),
            ),
      body: isLoadingMore
          ? _body(query, loaded, isLoadingMore: true)
          : documents.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ProcessedError(error: error),
              data: (list) => _body(query, list, isLoadingMore: false),
            ),
    );
  }

  Widget _body(
    ProcessedQuery query,
    List<ProcessedDocumentSummary> list, {
    required bool isLoadingMore,
  }) {
    if (list.isEmpty) return _ProcessedEmpty(query: query);
    // Vinieron tantas como se pidieron: puede haber más —ver `LibraryScreen`—.
    final canLoadMore = query.limit != null && list.length >= query.limit!;

    return Column(
      children: [
        // Los videos con el texto en otro idioma (F45, paso 4): volver a
        // extraerlos todos de una vez.
        if (!_selectionModeActive) const ForeignVideoTextsBanner.processed(),
        Expanded(
          child: ListView.separated(
            controller: _resultsScroll,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: list.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final document = list[index];
              return ProcessedDocumentCard(
                key: ValueKey(document.id),
                document: document,
                onTap: () =>
                    context.push(RoutePaths.processedDocument(document.id)),
                onLongPress: () => _enterSelectionMode(document.id),
                selectionMode: _selectionModeActive,
                selected: _selectedIds.contains(document.id),
                onSelectedChanged: (value) =>
                    _setSelected(document.id, selected: value),
              );
            },
          ),
        ),
        if (canLoadMore)
          LoadMoreBar(
            isLoading: isLoadingMore,
            onPressed: () =>
                ref.read(processedQueryNotifierProvider.notifier).loadMore(),
          ),
      ],
    );
  }

  /// Los temas de los elegidos, con la hoja de siempre y el mismo criterio que
  /// la Biblioteca: arranca con los que tienen todos, y solo se tocan esos.
  /// Un documento procesado es un elemento de la bóveda (decisión A): sus
  /// temas se cambian por el mismo camino que los de cualquiera.
  Future<void> _moveSelection(List<ProcessedDocumentSummary> loaded) async {
    final l10n = AppLocalizations.of(context)!;
    final ids = _selectedIds.toList();
    final chosen = [
      for (final document in loaded)
        if (_selectedIds.contains(document.id)) document,
    ];
    final common = chosen.isEmpty
        ? const <String>{}
        : chosen.map((d) => d.spaceIds).reduce((a, b) => a.intersection(b));
    final picked = await showSpacesPickerSheet(context, selected: common);
    if (picked == null || !mounted) return;

    final wanted = {for (final space in picked) space.id};
    final result = await ref
        .read(libraryRepositoryProvider)
        .changeSpaces(
          itemIds: ids,
          add: wanted.difference(common),
          remove: common.difference(wanted),
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    result.match(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      ),
      (_) {
        _exitSelectionMode();
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.libraryBulkSpacesChanged(ids.length))),
        );
      },
    );
  }

  /// A la papelera, con «Deshacer»: viaja ahí como cualquier elemento, y de la
  /// fuente no toca nada.
  Future<void> _deleteSelection() async {
    final moved = await moveToTrashWithUndo(
      context,
      ref,
      _selectedIds.toList(),
    );
    if (moved && mounted) _exitSelectionMode();
  }
}

/// El orden de la lista.
class _SortButton extends ConsumerWidget {
  const _SortButton({required this.sort});

  final ProcessedSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    String label(ProcessedSort sort) => switch (sort) {
      ProcessedSort.updatedAt => l10n.processedSortUpdatedAt,
      ProcessedSort.createdAt => l10n.processedSortCreatedAt,
      ProcessedSort.title => l10n.processedSortTitle,
    };

    return PopupMenuButton<ProcessedSort>(
      key: const Key('processed-sort'),
      icon: const Icon(Icons.sort),
      tooltip: l10n.processedSortTooltip,
      initialValue: sort,
      onSelected: ref.read(processedQueryNotifierProvider.notifier).sortBy,
      itemBuilder: (context) => [
        for (final option in ProcessedSort.values)
          CheckedPopupMenuItem(
            value: option,
            checked: option == sort,
            child: Text(label(option)),
          ),
      ],
    );
  }
}

/// La búsqueda y, mientras se esté parado en un tema, el chip que lo dice:
/// lo mismo que en la Biblioteca.
class _SearchAndFilters extends ConsumerWidget {
  const _SearchAndFilters({
    required this.currentSpace,
    required this.onShowResults,
  });

  final Space? currentSpace;

  /// Mostrar la lista desde arriba, al cerrar el panel con «Ver N
  /// resultados».
  final VoidCallback onShowResults;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(processedQueryNotifierProvider);
    final notifier = ref.read(processedQueryNotifierProvider.notifier);
    final space = currentSpace;
    final activeFilterCount =
        query.sourceKinds.length +
        query.sections.length +
        (query.withOriginal ? 1 : 0) +
        (query.spaceId == null ? 0 : 1);

    Future<void> openFilters() async {
      final showResults = await showListFiltersSheet(
        context,
        builder: (context) => const _FiltersSheet(),
      );
      if (showResults) onShowResults();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListSearchRow(
          hintText: l10n.processedSearchHint,
          onChanged: notifier.search,
          activeFilterCount: activeFilterCount,
          onOpenFilters: openFilters,
        ),
        if (space != null)
          CurrentSpaceChip(
            space: space,
            onPressed: openFilters,
            onLeave: () => notifier.selectSpace(null),
          ),
      ],
    );
  }
}

/// Los tipos de fuente que pueden tener un procesado: una nota no se procesa
/// —la escribió la persona, no hay qué sacar de ella—.
final _sourceKinds = [
  for (final kind in SourceKind.values)
    if (kind.role == EntityRole.source) kind,
];

/// El panel de filtros: tema, de qué fuente salió y qué partes tiene.
class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(processedQueryNotifierProvider);
    final notifier = ref.read(processedQueryNotifierProvider.notifier);

    return ListFiltersSheet(
      onClear: notifier.hasActiveFilters ? notifier.clearFilters : null,
      // Lo que va a mostrar la lista, con lo buscado: contado en la base,
      // sin armar ningún documento.
      results: ref.watch(processedCountProvider(query)),
      narrowed: query.hasSearchText || notifier.hasActiveFilters,
      children: [
        FilterSectionLabel(l10n.libraryFilterSpaceLabel),
        const SizedBox(height: 8),
        SpaceFilterSection(
          selectedSpaceId: query.spaceId,
          onChanged: notifier.selectSpace,
        ),
        const SizedBox(height: 20),
        FilterSectionLabel(l10n.processedFilterSourceLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in _sourceKinds)
              FilterChip(
                avatar: Icon(kind.icon, size: 18),
                label: Text(kind.label(l10n)),
                selected: query.sourceKinds.contains(kind),
                onSelected: (_) => notifier.toggleSourceKind(kind),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilterSectionLabel(l10n.processedFilterPartsLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final section in ProcessedSection.values)
              FilterChip(
                avatar: Icon(section.icon, size: 18),
                label: Text(section.label(l10n)),
                selected: query.sections.contains(section),
                onSelected: (_) => notifier.toggleSection(section),
              ),
            FilterChip(
              avatar: const Icon(Icons.file_copy_outlined, size: 18),
              label: Text(l10n.processedSectionOriginal),
              selected: query.withOriginal,
              onSelected: (_) => notifier.toggleOriginal(),
            ),
          ],
        ),
      ],
    );
  }
}

/// Las fuentes que se triaron y no tienen su documento procesado: las de
/// antes de F41 (decisión D) —o las que se triaron y se procesaron sin nada—.
/// Lo que cuenta el vacío para ofrecer «Volver a triar».
const _triagedQuery = LibraryQuery(inboxStatuses: {InboxStatus.triaged});

final _triagedCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(libraryRepositoryProvider).watchCount(_triagedQuery),
);

/// Qué mostrar sin nada que mostrar: una búsqueda sin resultados, filtros
/// demasiado estrechos —con su salida— o «Procesado» todavía vacío, que
/// lleva a la Bandeja y, si hay fuentes triadas antes de que existiera,
/// ofrece «Volver a triar» (decisión D: no se procesan solas, porque
/// inventar qué partes se querían sería decidir por la persona).
class _ProcessedEmpty extends ConsumerWidget {
  const _ProcessedEmpty({required this.query});

  final ProcessedQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(processedQueryNotifierProvider.notifier);

    if (query.hasSearchText) {
      return EmptyStateView(
        icon: Icons.search_off,
        title: l10n.processedSearchEmpty(query.searchText!),
      );
    }
    if (notifier.hasActiveFilters) {
      return EmptyStateView(
        icon: Icons.filter_alt_off_outlined,
        title: l10n.processedFilterEmpty,
        actionLabel: l10n.libraryClearFilters,
        onAction: notifier.clearFilters,
      );
    }
    // Lo vacío de verdad: con todo procesado en la papelera o sin nada
    // todavía, cada fuente triada es una que no tiene su procesado vivo.
    final triaged = ref.watch(_triagedCountProvider).valueOrNull ?? 0;
    return EmptyStateView(
      key: const Key('processed-empty'),
      icon: Icons.summarize_outlined,
      title: l10n.processedEmptyTitle,
      message: triaged > 0 ? l10n.processedEmptyPending(triaged) : null,
      actionLabel: l10n.processedEmptyAction,
      onAction: () => context.go(RoutePaths.inbox),
      secondary: triaged > 0 ? const RetriageButton() : null,
    );
  }
}

class _ProcessedError extends StatelessWidget {
  const _ProcessedError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final message = error is Failure
        ? (error as Failure).localizedMessage(l10n)
        : l10n.globalErrorUnexpected;
    return EmptyStateView(icon: Icons.error_outline, title: message);
  }
}
