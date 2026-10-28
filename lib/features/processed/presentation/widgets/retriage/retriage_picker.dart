import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_status_presentation.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/list_controls.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_filter_section.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre el selector de «Volver a triar» (F41, paso 4): todas las fuentes de
/// la Biblioteca, con su buscador y sus filtros, y lo ya procesado marcado con
/// un chip. Devuelve la fuente elegida, o `null` si se cerró sin elegir.
Future<String?> showRetriagePicker(BuildContext context) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      builder: (context, scroll) => RetriagePicker(scrollController: scroll),
    ),
  );
}

/// Lo que se busca y se filtra en el selector: una consulta de la Biblioteca,
/// con su mismo manejo —buscar ordena por relevancia, cada filtro vuelve a la
/// primera tanda, «Cargar más» suma otra—, propia de cada vez que se abre: no
/// toca los filtros de la pantalla de la Biblioteca, y al cerrarse se suelta.
final retriagePickerQueryProvider =
    StateNotifierProvider.autoDispose<LibraryQueryNotifier, LibraryQuery>((
      ref,
    ) {
      final notifier = LibraryQueryNotifier();
      // Un tema borrado mientras está abierto no deja la lista filtrando por
      // algo que ya no existe —ver `libraryQueryNotifierProvider`—.
      ref.listen(allSpacesProvider, (_, next) {
        final spaces = next.valueOrNull;
        if (spaces != null) notifier.releaseDeletedSpace(spaces);
      });
      return notifier;
    });

/// Lo que de verdad se le pide a la Biblioteca: [query], y solo fuentes. Una
/// nota propia no tiene documento procesado —no hay qué sacarle—, y lo
/// procesado ya está fuera de la Biblioteca.
///
/// Las fuentes son lo que pasa por la Bandeja: sin un filtro de la Bandeja
/// puesto, se piden las de los tres estados —esperando, triadas y
/// descartadas—, que es pedirlas todas.
LibraryQuery retriageCandidatesOf(LibraryQuery query) =>
    query.inboxStatuses.isNotEmpty
    ? query
    : query.copyWith(inboxStatuses: InboxStatus.values.toSet());

/// El selector de «Volver a triar»: el buscador con sus filtros arriba, fijos,
/// y la lista de las fuentes debajo, de a tandas, como la Biblioteca.
///
/// Nada de acá trae el texto de una fuente: la Biblioteca lista sin él, y lo
/// procesado se sabe por los ids de las fuentes que ya tienen su documento
/// (`processedSourceIdsProvider`). Elegir una cierra el selector con su id.
class RetriagePicker extends ConsumerStatefulWidget {
  const RetriagePicker({this.scrollController, super.key});

  final ScrollController? scrollController;

  @override
  ConsumerState<RetriagePicker> createState() => _RetriagePickerState();
}

class _RetriagePickerState extends ConsumerState<RetriagePicker> {
  /// La última tanda que llegó, y con qué consulta: «Cargar más» es otra
  /// consulta para Riverpod, y sin esto la lista parpadearía a la ruedita en
  /// cada tanda —ver `LibraryScreen`—.
  LibraryQuery? _lastLoadedQuery;
  List<KnowledgeItem> _lastLoaded = const [];

  bool _isMorePageOf(LibraryQuery query) {
    final last = _lastLoadedQuery;
    return last != null && last.copyWith(limit: query.limit) == query;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final query = ref.watch(retriagePickerQueryProvider);
    final notifier = ref.read(retriagePickerQueryProvider.notifier);
    final items = ref.watch(libraryItemsProvider(retriageCandidatesOf(query)));
    final processed =
        ref.watch(processedSourceIdsProvider).valueOrNull ?? const <String>{};

    if (items.hasValue) {
      _lastLoadedQuery = query;
      _lastLoaded = items.value!;
    }
    final isLoadingMore = !items.hasValue && _isMorePageOf(query);

    final activeFilterCount =
        query.sourceKinds.length +
        query.inboxStatuses.length +
        (query.spaceId == null ? 0 : 1);

    // Escape lo cierra sin elegir: lo hace la hoja de abajo misma
    // (`DismissIntent`), como cualquier ruta emergente.
    return Column(
      key: const Key('retriage-picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Semantics(
            header: true,
            child: Text(
              l10n.processedRetriage,
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ),
        ListSearchRow(
          hintText: l10n.processedRetriagePickerSearchHint,
          onChanged: notifier.search,
          activeFilterCount: activeFilterCount,
          onOpenFilters: () => showListFiltersSheet(
            context,
            builder: (_) => const _PickerFilters(),
          ),
        ),
        Expanded(
          child: isLoadingMore
              ? _list(query, _lastLoaded, processed, isLoadingMore: true)
              : items.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => EmptyStateView(
                    icon: Icons.error_outline,
                    title: error is Failure
                        ? error.localizedMessage(l10n)
                        : l10n.globalErrorUnexpected,
                  ),
                  data: (list) =>
                      _list(query, list, processed, isLoadingMore: false),
                ),
        ),
      ],
    );
  }

  Widget _list(
    LibraryQuery query,
    List<KnowledgeItem> list,
    Set<String> processed, {
    required bool isLoadingMore,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (list.isEmpty) return _PickerEmpty(query: query);
    // Vinieron tantas como se pidieron: puede haber más —ver `LibraryScreen`—.
    final canLoadMore = query.limit != null && list.length >= query.limit!;

    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      // La explicación, el resultado y el pie, en la misma lista: con la
      // letra grande, lo fijo arriba es solo el título y el buscador.
      itemCount: list.length + (canLoadMore ? 2 : 1),
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.processedRetriagePickerIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        if (index > list.length) {
          return LoadMoreBar(
            isLoading: isLoadingMore,
            onPressed: ref.read(retriagePickerQueryProvider.notifier).loadMore,
          );
        }
        final item = list[index - 1];
        return RetriageCandidateTile(
          key: ValueKey(item.id),
          item: item,
          processed: processed.contains(item.id),
          onTap: () => Navigator.of(context).pop(item.id),
        );
      },
    );
  }
}

/// Una fuente del selector: su ícono, su título, de qué tipo es y, si ya tiene
/// su documento procesado, el chip «Procesado». Se ve como una fila de la
/// Biblioteca —la misma superficie y el mismo contorno de una fuente—, sin su
/// menú: acá tocarla es elegirla.
///
/// Para el lector de pantalla es un solo botón, con todo en una frase.
class RetriageCandidateTile extends StatelessWidget {
  const RetriageCandidateTile({
    required this.item,
    required this.processed,
    required this.onTap,
    super.key,
  });

  final KnowledgeItem item;

  /// Si ya tiene su documento procesado.
  final bool processed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final kind = item.source.kind;
    final role = kind.role;
    final kindLabel = kind.label(l10n);

    return Semantics(
      button: true,
      label: [
        item.title,
        kindLabel,
        if (processed) l10n.processedRetriageProcessedChip,
      ].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: role.surface(colors),
        borderRadius: BorderRadius.circular(role.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(role.radius),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(role.radius),
              border: Border.all(color: role.outline(colors)),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(kind.icon, color: colors.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            item.subtitle ?? kindLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (processed) const _ProcessedChip(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Procesado»: un chip quieto, con el ícono de la pantalla «Procesado».
class _ProcessedChip extends StatelessWidget {
  const _ProcessedChip();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DecoratedBox(
      key: const Key('retriage-processed-chip'),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.summarize_outlined,
              size: 14,
              color: colors.onTertiaryContainer,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                l10n.processedRetriageProcessedChip,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las fuentes que pueden tener un procesado: todo menos una nota propia.
final _sourceKinds = [
  for (final kind in SourceKind.values)
    if (kind.role == EntityRole.source) kind,
];

/// El panel de filtros del selector, con el marco de la Biblioteca: tema,
/// tipo de fuente y dónde quedó en la Bandeja —«Triado» junta, por ejemplo,
/// lo que se trió antes de que existiera «Procesado» (decisión D)—.
class _PickerFilters extends ConsumerWidget {
  const _PickerFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(retriagePickerQueryProvider);
    final notifier = ref.read(retriagePickerQueryProvider.notifier);

    return ListFiltersSheet(
      onClear: notifier.hasActiveFilters ? notifier.clearFilters : null,
      children: [
        FilterSectionLabel(l10n.libraryFilterSpaceLabel),
        const SizedBox(height: 8),
        SpaceFilterSection(
          selectedSpaceId: query.spaceId,
          onChanged: notifier.selectSpace,
        ),
        const SizedBox(height: 20),
        FilterSectionLabel(l10n.libraryFilterTypeLabel),
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
        FilterSectionLabel(l10n.libraryFilterInboxLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in InboxStatus.values)
              FilterChip(
                key: Key('retriage-filter-${status.name}'),
                avatar: Icon(status.icon, size: 18),
                label: Text(status.filterLabel(l10n)),
                selected: query.inboxStatuses.contains(status),
                onSelected: (_) => notifier.toggleInboxStatus(status),
              ),
          ],
        ),
      ],
    );
  }
}

/// Sin nada que mostrar: una búsqueda sin resultados, filtros demasiado
/// estrechos —con su salida— o una Biblioteca sin fuentes.
class _PickerEmpty extends ConsumerWidget {
  const _PickerEmpty({required this.query});

  final LibraryQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(retriagePickerQueryProvider.notifier);

    if (query.hasSearchText) {
      return EmptyStateView(
        icon: Icons.search_off,
        title: l10n.librarySearchEmpty(query.searchText!),
      );
    }
    if (notifier.hasActiveFilters) {
      return EmptyStateView(
        icon: Icons.filter_alt_off_outlined,
        title: l10n.libraryFilterEmpty,
        actionLabel: l10n.libraryClearFilters,
        onAction: notifier.clearFilters,
      );
    }
    return EmptyStateView(
      icon: Icons.inventory_2_outlined,
      title: l10n.processedRetriagePickerEmpty,
    );
  }
}
