import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_activity_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_activity_feed.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_queue_status.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_review_cards.dart';
import 'package:sinapsis/features/ai_review/domain/entities/pending_review_item.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Lo que hizo la IA» (F27): todo lo que la IA organizó sola, a la vista y
/// reversible.
///
/// De arriba abajo:
///
/// 1. **La cola**: en qué anda, y el botón que resuelve lo que la frena
///    —reanudar, bajar un modelo—. Ver [AiQueueStatusCard].
/// 2. **Para revisar** (decisión B): lo que la IA no aplicó porque dudaba,
///    por elemento, con aceptar o descartar de un toque, o todo junto con
///    «Deshacer».
/// 3. **La actividad**: las pasadas por día y por elemento, con lo que sigue
///    siendo de la IA y su «Deshacer», de a páginas al bajar.
///
/// Con [itemId], solo lo de ese elemento: es a donde lleva «Ver» desde su
/// detalle.
class AiActivityScreen extends ConsumerStatefulWidget {
  const AiActivityScreen({this.itemId, super.key});

  final String? itemId;

  @override
  ConsumerState<AiActivityScreen> createState() => _AiActivityScreenState();
}

class _AiActivityScreenState extends ConsumerState<AiActivityScreen> {
  /// Las sugerencias que la persona ya resolvió y la base todavía no sacó: se
  /// pliegan enseguida, sin esperar la consulta.
  final _hidden = <String>{};

  /// Las pasadas que se están deshaciendo.
  final _busyRuns = <String>{};

  /// Cuánto dura el «Deshacer» de aceptar o descartar todo.
  static const _batchUndoWindow = Duration(seconds: 6);

  AiActivityController get _activity =>
      ref.read(aiActivityControllerProvider(widget.itemId).notifier);

  // -------------------------------------------------------------------------
  // Para revisar
  // -------------------------------------------------------------------------

  /// Acepta o descarta UNA sugerencia, de un toque: se pliega ya, y vuelve
  /// con el motivo si la base no la pudo resolver.
  Future<void> _resolveOne(
    Suggestion suggestion, {
    required bool accept,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(suggestionRepositoryProvider);
    setState(() => _hidden.add(suggestion.id));

    final result = accept
        ? await repository.accept(suggestion.id)
        : await repository.reject(suggestion.id);
    final failure = result.getLeft().toNullable();
    if (failure == null) return;

    if (mounted) setState(() => _hidden.remove(suggestion.id));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
  }

  /// Acepta o descarta todo lo de [items], con «Deshacer».
  ///
  /// La base no se toca hasta que el aviso se cierra sin «Deshacer»: aceptar
  /// un vínculo lo crea y descartar no tiene vuelta en el repositorio, así que
  /// la única forma de que «Deshacer» deshaga exactamente lo que se hizo
  /// —para los tres tipos por igual— es no haberlo hecho todavía. Si la app
  /// se cierra antes, no se perdió nada: siguen para revisar.
  ///
  /// Lo que se necesita del contexto se toma antes de esperar: la pantalla
  /// puede cerrarse con el aviso a la vista, y el lote tiene que aplicarse
  /// igual.
  Future<void> _resolveAll(
    List<PendingReviewItem> items, {
    required bool accept,
  }) async {
    final ids = [
      for (final item in items)
        for (final id in item.suggestionIds)
          if (!_hidden.contains(id)) id,
    ];
    if (ids.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(suggestionRepositoryProvider);
    setState(() => _hidden.addAll(ids));

    messenger.hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? l10n.aiReviewAcceptedAll(ids.length)
                  : l10n.aiReviewDiscardedAll(ids.length),
            ),
            duration: _batchUndoWindow,
            // Un aviso con acción se queda hasta que lo cierren, salvo que
            // se pida lo contrario: el lote se aplica al cerrarse, y sin esto
            // esperaría para siempre a un aviso que nadie toca.
            persist: false,
            action: SnackBarAction(
              key: const Key('ai-review-batch-undo'),
              label: l10n.aiReviewUndo,
              // El «Deshacer» es no aplicar: lo resuelve `closed`, abajo.
              onPressed: () {},
            ),
          ),
        )
        .closed;
    if (reason == SnackBarClosedReason.action) {
      if (mounted) setState(() => _hidden.removeAll(ids));
      return;
    }

    final failed = await _commit(repository, ids, accept: accept);
    if (failed.isEmpty) return;
    if (mounted) setState(() => _hidden.removeAll(failed));
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.aiReviewSomeFailed(failed.length))),
    );
  }

  /// Aplica el lote y devuelve las que no se pudieron resolver.
  ///
  /// Aceptar va de a una: cada tipo se aplica distinto —un vínculo, una
  /// propiedad, una referencia— y `acceptMany` es solo de propiedades. Una que
  /// falla no frena a las demás; queda para revisar.
  static Future<List<String>> _commit(
    SuggestionRepository repository,
    List<String> ids, {
    required bool accept,
  }) async {
    if (!accept) {
      final rejected = await repository.rejectMany(ids);
      return rejected.isLeft() ? ids : const [];
    }
    final failed = <String>[];
    for (final id in ids) {
      if ((await repository.accept(id)).isLeft()) failed.add(id);
    }
    return failed;
  }

  // -------------------------------------------------------------------------
  // Actividad
  // -------------------------------------------------------------------------

  Future<void> _undoRun(AiRun run) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAiUndo(
      context,
      itemTitle: run.itemTitle,
      tally: run.remaining,
    );
    if (!confirmed || !mounted) return;

    final activity = _activity;
    setState(() => _busyRuns.add(run.id));
    final result = await activity.undoRun(run.id);
    if (mounted) setState(() => _busyRuns.remove(run.id));
    showAiUndoResult(messenger, l10n, result);
  }

  Future<void> _undoItem(String itemId, String itemTitle) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // Lo que se ve del elemento, de todas las páginas leídas: lo mismo que
    // `undoItem` se va a llevar.
    final runs = [
      for (final run
          in ref.read(aiActivityControllerProvider(widget.itemId)).runs)
        if (run.itemId == itemId && !run.isUndone) run,
    ];
    final confirmed = await confirmAiUndo(
      context,
      itemTitle: itemTitle,
      tally: runs.fold(const AiRunTally(), (sum, run) => sum + run.remaining),
      wholeItem: true,
    );
    if (!confirmed || !mounted) return;

    final activity = _activity;
    setState(() => _busyRuns.addAll(runs.map((run) => run.id)));
    final result = await activity.undoItem(itemId);
    if (mounted) setState(() => _busyRuns.removeAll(runs.map((r) => r.id)));
    showAiUndoResult(messenger, l10n, result);
  }

  void _open(String itemId) =>
      unawaited(context.push(RoutePaths.itemDetail(itemId)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final itemId = widget.itemId;
    final activity = ref.watch(aiActivityControllerProvider(itemId));
    final allReview = ref.watch(pendingReviewItemsProvider).valueOrNull;
    final review = [
      for (final item in allReview ?? const <PendingReviewItem>[])
        if (itemId == null || item.itemId == itemId) item,
    ];
    final reviewCount = review.fold(
      0,
      (sum, item) =>
          sum + item.suggestionIds.where((id) => !_hidden.contains(id)).length,
    );
    final queue = ref.watch(aiQueueViewProvider);
    final workingTitle = queue is AiQueueWorkingView ? queue.itemTitle : null;
    final now = ref.watch(clockProvider)();
    final entries = groupAiActivity(activity.runs);
    final nothingAtAll =
        !activity.loading &&
        activity.failure == null &&
        activity.runs.isEmpty &&
        allReview != null &&
        review.isEmpty;

    const gutter = EdgeInsets.symmetric(horizontal: 16);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiActivityTitle)),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverList.list(
              children: [
                if (itemId != null) _ItemFilter(itemId: itemId),
                const AiQueueStatusCard(),
              ],
            ),
          ),
          if (review.isNotEmpty) ...[
            SliverPadding(
              padding: gutter,
              sliver: SliverToBoxAdapter(
                child: AiCollapse(
                  visible: reviewCount > 0,
                  child: AiReviewHeader(
                    count: reviewCount,
                    onAcceptAll: () =>
                        unawaited(_resolveAll(review, accept: true)),
                    onDiscardAll: () =>
                        unawaited(_resolveAll(review, accept: false)),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: gutter,
              sliver: SliverList.builder(
                itemCount: review.length,
                itemBuilder: (context, index) {
                  final item = review[index];
                  return AiReviewItemCard(
                    key: ValueKey(item.itemId),
                    item: item,
                    hidden: _hidden,
                    onOpen: itemId == null ? () => _open(item.itemId) : null,
                    onAccept: (s) => unawaited(_resolveOne(s, accept: true)),
                    onDiscard: (s) => unawaited(_resolveOne(s, accept: false)),
                  );
                },
              ),
            ),
          ],
          if (nothingAtAll)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateView(
                key: const Key('ai-activity-empty'),
                icon: Icons.auto_awesome,
                title: l10n.aiActivityEmptyTitle,
                message: itemId == null
                    ? l10n.aiActivityEmptyMessage
                    : l10n.aiActivityItemEmptyMessage,
              ),
            )
          else if (activity.isFirstLoad)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (activity.runs.isEmpty && activity.failure != null)
            SliverToBoxAdapter(child: _LoadError(onRetry: _activity.refresh))
          else if (activity.runs.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.builder(
                // El encabezado de la sección, las filas y el pie que trae
                // la página siguiente.
                itemCount: entries.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) return const _SectionTitle();
                  if (index == entries.length + 1) {
                    return _PageFooter(
                      // Uno nuevo por página: el que pide la siguiente es el
                      // que se construye al llegar al final de la anterior.
                      key: ValueKey(activity.runs.length),
                      state: activity,
                      onLoadMore: _activity.loadMore,
                    );
                  }
                  return switch (entries[index - 1]) {
                    AiActivityDayEntry(:final day) => AiActivityDayHeader(
                      day: day,
                      now: now,
                    ),
                    final AiActivityItemEntry entry => AiActivityItemCard(
                      key: ValueKey((entry.itemId, entry.runs.first.id)),
                      entry: entry,
                      busyRunIds: _busyRuns,
                      workingTitle: workingTitle,
                      onOpen: itemId == null ? () => _open(entry.itemId) : null,
                      onUndoRun: (run) => unawaited(_undoRun(run)),
                      onUndoItem: () =>
                          unawaited(_undoItem(entry.itemId, entry.itemTitle)),
                    ),
                  };
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// El filtro por elemento, cuando se llegó desde su detalle: la cruz vuelve a
/// mostrar todo.
class _ItemFilter extends ConsumerWidget {
  const _ItemFilter({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final title = ref.watch(libraryItemProvider(itemId)).valueOrNull?.title;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: InputChip(
          key: const Key('ai-activity-item-filter'),
          avatar: const Icon(Icons.filter_alt_outlined, size: 18),
          label: Text(title ?? '', overflow: TextOverflow.ellipsis),
          deleteButtonTooltipMessage: l10n.aiActivityShowAll,
          onDeleted: () => context.pushReplacement(RoutePaths.aiActivity),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: Text(
        AppLocalizations.of(context)!.aiActivitySection,
        style: theme.textTheme.titleMedium,
      ),
    );
  }
}

/// El final de la lista: si puede haber más pasadas, las pide apenas se
/// construye —o sea, cuando la persona llega cerca del final—; si la lectura
/// falló, ofrece reintentar.
class _PageFooter extends StatefulWidget {
  const _PageFooter({required this.state, required this.onLoadMore, super.key});

  final AiActivityState state;
  final Future<void> Function() onLoadMore;

  @override
  State<_PageFooter> createState() => _PageFooterState();
}

class _PageFooterState extends State<_PageFooter> {
  @override
  void initState() {
    super.initState();
    if (widget.state.hasMore && widget.state.failure == null) {
      // Después del cuadro: pedir la página cambia el estado que se está
      // construyendo.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.onLoadMore());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.failure != null) {
      return _LoadError(onRetry: widget.onLoadMore);
    }
    if (!state.hasMore) return const SizedBox(height: 8);
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            l10n.aiActivityLoadError,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('ai-activity-retry'),
            onPressed: () => unawaited(onRetry()),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.aiActivityRetry),
          ),
        ],
      ),
    );
  }
}
