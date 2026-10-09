import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Either;
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/card_browser_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/my_cards_controller.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_edit_dialog.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/my_cards_formatting.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/my_cards_row.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/my_cards_scope_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuánto se espera tras la última letra tipeada antes de buscar.
const kMyCardsSearchDelay = Duration(milliseconds: 300);

/// «Mis tarjetas» (F31, ola 2, decisión 72): todas las tarjetas, con búsqueda,
/// filtros por estado y por recorte, orden, y acciones sobre varias a la vez.
/// La lista se lee de a páginas (`MyCardsController`): con 10.000 tarjetas
/// nunca hay más de unos cientos cargadas.
class MyCardsScreen extends ConsumerStatefulWidget {
  const MyCardsScreen({this.initialScope = const StudyScope.all(), super.key});

  /// Con qué recorte abrir (por ejemplo, el de un elemento).
  final StudyScope initialScope;

  @override
  ConsumerState<MyCardsScreen> createState() => _MyCardsScreenState();
}

class _MyCardsScreenState extends ConsumerState<MyCardsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (!widget.initialScope.isAll) {
      // Fuera del armado inicial: el control escribe su estado.
      scheduleMicrotask(() {
        if (mounted) {
          ref
              .read(myCardsControllerProvider.notifier)
              .setScope(widget.initialScope);
        }
      });
    }
  }

  @override
  void didUpdateWidget(MyCardsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Un enlace a otro recorte (`/cards?item=…`) con la pantalla ya abierta
    // reutiliza el estado: hay que aplicarlo acá.
    if (widget.initialScope != oldWidget.initialScope) {
      // Fuera del armado: un proveedor no se modifica mientras se construye.
      scheduleMicrotask(() {
        if (mounted) _controller.setScope(widget.initialScope);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  MyCardsController get _controller =>
      ref.read(myCardsControllerProvider.notifier);

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(kMyCardsSearchDelay, () => _controller.setText(text));
  }

  void _clearFilters() {
    _debounce?.cancel();
    _search.clear();
    _controller
      ..setText('')
      ..setStatus(null)
      ..setScope(const StudyScope.all());
  }

  Future<void> _pickScope(StudyScope current) async {
    final picked = await showMyCardsScopeSheet(context, current: current);
    if (picked != null) _controller.setScope(picked);
  }

  /// Toca una tarjeta: abre el editor de siempre. Guardar la adopta si era de
  /// la IA, igual que desde el detalle del elemento.
  Future<void> _edit(Flashcard card) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showFlashcardEditDialog(context, card: card);
    if (result == null || !mounted) return;
    final (front, back) = result;
    if (front.trim() == card.front && back.trim() == card.back) return;
    final saved = await ref
        .read(flashcardRepositoryProvider)
        .update(id: card.id, front: front, back: back);
    if (!mounted) return;
    saved.match((failure) => _say(failure.localizedMessage(l10n)), (_) {});
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Corre una acción sobre las elegidas y avisa cómo salió. [message] dice
  /// cuántas se tocaron.
  Future<void> _act(
    Future<Either<Failure, Object?>> Function(List<String> ids) action,
    String Function(AppLocalizations l10n, int count) message,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final ids = ref.read(myCardsControllerProvider).selected.toList();
    if (ids.isEmpty) return;
    final result = await action(ids);
    if (!mounted) return;
    result.match((failure) => _say(failure.localizedMessage(l10n)), (_) {
      _controller.clearSelection();
      _say(message(l10n, ids.length));
    });
  }

  Future<void> _suspend() => _act(
    ref.read(flashcardRepositoryProvider).suspend,
    (l10n, n) => l10n.myCardsDoneSuspended(n),
  );

  Future<void> _unsuspend() => _act(
    ref.read(flashcardRepositoryProvider).unsuspend,
    (l10n, n) => l10n.myCardsDoneUnsuspended(n),
  );

  Future<void> _bury() => _act(
    ref.read(flashcardRepositoryProvider).buryUntilTomorrow,
    (l10n, n) => l10n.myCardsDoneBuried(n),
  );

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    required Key actionKey,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            key: const Key('my-cards-confirm-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.myCardsCancel),
          ),
          FilledButton(
            key: actionKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context)!;
    final count = ref.read(myCardsControllerProvider).selected.length;
    if (count == 0) return;
    final ok = await _confirm(
      title: l10n.myCardsResetTitle,
      body: l10n.myCardsResetBody(count),
      action: l10n.myCardsResetConfirm,
      actionKey: const Key('my-cards-confirm-reset'),
    );
    if (!ok || !mounted) return;
    await _act(
      ref.read(cardBrowserRepositoryProvider).resetSchedule,
      (l10n, n) => l10n.myCardsDoneReset(n),
    );
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final count = ref.read(myCardsControllerProvider).selected.length;
    if (count == 0) return;
    final ok = await _confirm(
      title: l10n.myCardsDeleteTitle(count),
      body: l10n.myCardsDeleteBody,
      action: l10n.myCardsDeleteConfirm,
      actionKey: const Key('my-cards-confirm-delete'),
    );
    if (!ok || !mounted) return;
    await _act(
      ref.read(cardBrowserRepositoryProvider).deleteMany,
      (l10n, n) => l10n.myCardsDoneDeleted(n),
    );
  }

  Future<void> _selectAll() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await _controller.selectAll();
    if (picked == null && mounted) _say(l10n.myCardsLoadError);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(myCardsControllerProvider);

    return PopScope(
      canPop: !state.selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && state.selecting) _controller.clearSelection();
      },
      child: Scaffold(
        appBar: state.selecting
            ? _selectionBar(l10n, state)
            : AppBar(
                title: Text(l10n.myCardsTitle),
                actions: [_SortMenu(query: state.query)],
              ),
        body: Column(
          children: [
            if (!state.selecting) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  key: const Key('my-cards-search'),
                  controller: _search,
                  onChanged: (text) {
                    setState(() {});
                    _onSearchChanged(text);
                  },
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.myCardsSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('my-cards-search-clear'),
                            icon: const Icon(Icons.close),
                            tooltip: l10n.myCardsSearchClear,
                            onPressed: () {
                              _debounce?.cancel();
                              _search.clear();
                              _controller.setText('');
                              setState(() {});
                            },
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              _FilterBar(
                state: state,
                onPickScope: () => _pickScope(state.query.scope),
              ),
            ],
            Expanded(child: _body(l10n, state)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _selectionBar(AppLocalizations l10n, MyCardsState state) {
    return AppBar(
      leading: IconButton(
        key: const Key('my-cards-selection-close'),
        icon: const Icon(Icons.close),
        tooltip: l10n.myCardsClearSelection,
        onPressed: _controller.clearSelection,
      ),
      title: Text(l10n.myCardsSelectedCount(state.selected.length)),
      actions: [
        IconButton(
          key: const Key('my-cards-select-all'),
          icon: const Icon(Icons.select_all),
          tooltip: l10n.myCardsSelectAll(state.total ?? 0),
          onPressed: state.total == null || state.total == 0
              ? null
              : _selectAll,
        ),
        IconButton(
          key: const Key('my-cards-action-suspend'),
          icon: const Icon(Icons.pause_circle_outline),
          tooltip: l10n.myCardsActionSuspend,
          onPressed: state.selected.isEmpty ? null : _suspend,
        ),
        IconButton(
          key: const Key('my-cards-action-unsuspend'),
          icon: const Icon(Icons.play_circle_outline),
          tooltip: l10n.myCardsActionUnsuspend,
          onPressed: state.selected.isEmpty ? null : _unsuspend,
        ),
        PopupMenuButton<_BulkAction>(
          key: const Key('my-cards-action-more'),
          enabled: state.selected.isNotEmpty,
          onSelected: (action) => switch (action) {
            _BulkAction.bury => unawaited(_bury()),
            _BulkAction.reset => unawaited(_reset()),
            _BulkAction.delete => unawaited(_delete()),
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              key: const Key('my-cards-action-bury'),
              value: _BulkAction.bury,
              child: Text(l10n.myCardsActionBury),
            ),
            PopupMenuItem(
              key: const Key('my-cards-action-reset'),
              value: _BulkAction.reset,
              child: Text(l10n.myCardsActionReset),
            ),
            PopupMenuItem(
              key: const Key('my-cards-action-delete'),
              value: _BulkAction.delete,
              child: Text(l10n.myCardsActionDelete),
            ),
          ],
        ),
      ],
    );
  }

  Widget _body(AppLocalizations l10n, MyCardsState state) {
    if (state.failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.myCardsLoadError),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('my-cards-retry'),
              onPressed: _controller.retry,
              child: Text(l10n.myCardsRetry),
            ),
          ],
        ),
      );
    }
    final total = state.total;
    if (total == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (total == 0) {
      final filtered =
          state.query.text.trim().isNotEmpty ||
          state.query.status != null ||
          !state.query.scope.isAll;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                filtered ? l10n.myCardsEmptyFilter : l10n.myCardsEmptyVault,
                key: const Key('my-cards-empty'),
                textAlign: TextAlign.center,
              ),
              if (filtered) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('my-cards-clear-filters'),
                  onPressed: _clearFilters,
                  child: Text(l10n.myCardsClearFilters),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final now = ref.watch(clockProvider)();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.myCardsCount(total),
              key: const Key('my-cards-count'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('my-cards-list'),
            itemCount: total,
            itemExtent: myCardsRowExtent(context),
            itemBuilder: (context, index) {
              final row = _controller.rowAt(index);
              if (row == null) return const MyCardsRowPlaceholder();
              final id = row.card.id;
              return MyCardsRow(
                key: ValueKey('my-cards-row-$id'),
                row: row,
                now: now,
                selecting: state.selecting,
                selected: state.selected.contains(id),
                onTap: () => state.selecting
                    ? _controller.toggle(id)
                    : unawaited(_edit(row.card)),
                onLongPress: () => state.selecting
                    ? _controller.toggle(id)
                    : _controller.startSelecting(id),
              );
            },
          ),
        ),
      ],
    );
  }
}

enum _BulkAction { bury, reset, delete }

/// El recorte y el estado: lo que se puede cambiar sin escribir.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.state, required this.onPickScope});

  final MyCardsState state;
  final VoidCallback onPickScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(myCardsControllerProvider.notifier);
    final scope = state.query.scope;
    final counts = state.statusCounts;
    // Las cinco etapas son una partición: sumadas dan todas.
    final allCount = counts == null
        ? null
        : [
            CardBrowserStatus.newCards,
            CardBrowserStatus.learning,
            CardBrowserStatus.young,
            CardBrowserStatus.mature,
            CardBrowserStatus.suspended,
          ].fold(0, (sum, status) => sum + (counts[status] ?? 0));
    final scopeName = myCardsScopeName(ref, scope);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: scope.isAll
              ? ActionChip(
                  key: const Key('my-cards-scope'),
                  avatar: const Icon(Icons.folder_open, size: 18),
                  label: Text(l10n.myCardsScopeAll),
                  onPressed: onPickScope,
                )
              : InputChip(
                  key: const Key('my-cards-scope'),
                  avatar: const Icon(Icons.folder_open, size: 18),
                  label: Text(scopeName ?? l10n.myCardsScopeMissing),
                  onPressed: onPickScope,
                  onDeleted: () => controller.setScope(const StudyScope.all()),
                  deleteButtonTooltipMessage: l10n.myCardsScopeClear,
                ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              ChoiceChip(
                key: const Key('my-cards-status-all'),
                label: Text(
                  allCount == null
                      ? l10n.myCardsStatusAll
                      : l10n.myCardsStatusChip(l10n.myCardsStatusAll, allCount),
                ),
                selected: state.query.status == null,
                onSelected: (_) => controller.setStatus(null),
              ),
              for (final status in CardBrowserStatus.values) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  key: Key('my-cards-status-${status.name}'),
                  label: Text(
                    counts == null
                        ? statusFilterLabel(l10n, status)
                        : l10n.myCardsStatusChip(
                            statusFilterLabel(l10n, status),
                            counts[status] ?? 0,
                          ),
                  ),
                  selected: state.query.status == status,
                  onSelected: (picked) =>
                      controller.setStatus(picked ? status : null),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// El orden: elegir por qué columna, y elegir la misma otra vez lo invierte.
class _SortMenu extends ConsumerWidget {
  const _SortMenu({required this.query});

  final CardBrowserQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<CardBrowserSort>(
      key: const Key('my-cards-sort'),
      icon: const Icon(Icons.sort),
      tooltip: l10n.myCardsSortTooltip,
      onSelected: ref.read(myCardsControllerProvider.notifier).setSort,
      itemBuilder: (context) => [
        for (final sort in CardBrowserSort.values)
          CheckedPopupMenuItem(
            key: Key('my-cards-sort-${sort.name}'),
            value: sort,
            checked: sort == query.sort,
            child: Row(
              children: [
                Expanded(child: Text(sortLabel(l10n, sort))),
                if (sort == query.sort)
                  Icon(
                    query.descending
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    size: 18,
                    semanticLabel: query.descending
                        ? l10n.myCardsSortDescending
                        : l10n.myCardsSortAscending,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
