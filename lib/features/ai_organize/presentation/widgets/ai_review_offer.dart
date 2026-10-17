import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_account_switcher.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_scope.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_queue_status.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Empieza «Revisar con otro modelo» (F33) con el modelo elegido ahora: busca
/// qué hay para revisar, muestra cuánto va a costar y, si la persona dice que
/// sí, lo deja en la cola de revisión.
///
/// - Sin [itemId], toda la biblioteca: deja afuera lo que hizo el mismo
///   modelo y lo que ya revisó. Con [madeBy], solo lo de ese modelo.
/// - Con [itemId], ese elemento entero, aunque lo haya hecho o revisado el
///   mismo modelo: lo pidió la persona ahí.
Future<void> startAiReview(
  BuildContext context,
  WidgetRef ref, {
  String? itemId,
  String? madeBy,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  // Para «Ver» en el aviso, que puede tocarse cuando quien lo pidió ya no
  // está en pantalla.
  final router = GoRouter.maybeOf(context);
  final reviewer = ref.read(aiReviewerNameProvider);
  final found = await ref
      .read(aiRunRepositoryProvider)
      .reviewCandidates(reviewer: reviewer, madeBy: madeBy, itemId: itemId);
  if (!context.mounted) return;
  final candidates = found.fold<List<AiReviewCandidate>?>((failure) {
    messenger.showSnackBar(
      SnackBar(content: Text(failure.localizedMessage(l10n))),
    );
    return null;
  }, (candidates) => candidates);
  if (candidates == null) return;
  if (candidates.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.aiRecheckNothing)));
    return;
  }

  final perCall = ref.read(languageModelTextBudgetProvider)().maxDraftsPerCall;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AiReviewCostDialog(
      model: modelLabel(reviewer),
      things: candidates.fold(0, (sum, c) => sum + c.things),
      items: candidates.length,
      requests: aiReviewRequests(candidates, perCall: perCall),
    ),
  );
  if (confirmed != true) return;

  ref.read(aiReviewQueueProvider).review([
    for (final candidate in candidates) candidate.itemId,
  ], skipOwnWork: itemId == null);
  if (itemId != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.aiRecheckQueued(modelLabel(reviewer))),
        action: router == null
            ? null
            : SnackBarAction(
                label: l10n.aiItemLineSee,
                onPressed: () =>
                    unawaited(router.push(RoutePaths.aiActivityFor(itemId))),
              ),
      ),
    );
  }
}

/// Antes de empezar, cuánto cuesta (decisión C): cuántas cosas en cuántos
/// elementos y cuántos pedidos al modelo; de qué cuota sale y lo que se sabe
/// de ella —lo gastado hoy, si las cuentas están sin cuota hasta una hora—.
/// Los proveedores no dicen cuánto queda de la capa gratuita: se lo dice así,
/// sin prometer.
class AiReviewCostDialog extends ConsumerWidget {
  const AiReviewCostDialog({
    required this.model,
    required this.things,
    required this.items,
    required this.requests,
    super.key,
  });

  /// El nombre lindo del modelo que revisa.
  final String model;
  final int things;
  final int items;
  final int requests;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cloud = ref.watch(aiModelSettingsProvider).provider.isCloud;

    final String quota;
    if (!cloud) {
      quota = l10n.aiRecheckCostLocal;
    } else {
      final view = ref.watch(aiAccountsViewProvider);
      final usage = [for (final a in view.accounts) view.usage[a.id]!];
      final spent = usage.fold(0, (sum, u) => sum + u.requests);
      final allOut =
          usage.isNotEmpty && usage.every((u) => u.isExhaustedAt(view.now));
      final until = allOut
          ? usage
                .map((u) => u.exhaustedUntil!)
                .reduce((a, b) => a.isBefore(b) ? a : b)
          : null;
      quota = [
        l10n.aiRecheckCostQuota,
        l10n.aiRecheckCostToday(spent),
        if (until != null)
          l10n.aiRecheckCostExhausted(
            aiResetTime(context, until, now: view.now),
          )
        else
          l10n.aiRecheckCostUnknownLeft,
      ].join(' ');
    }

    return AlertDialog(
      key: const Key('ai-review-cost-dialog'),
      icon: const AiSparkCircle(size: 40),
      title: Text(l10n.aiRecheckWith(model)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.aiRecheckCostScope(
              l10n.aiRecheckThings(things),
              l10n.aiRecheckItems(items),
              requests,
            ),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text(quota, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(
            l10n.aiRecheckCostNothingChanges,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('ai-review-cost-start'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.aiRecheckStart),
        ),
      ],
    );
  }
}

/// La oferta, arriba de «Lo que hizo la IA» (F33): cuánto hizo cada modelo
/// que el elegido ahora todavía no revisó —«12 tarjetas de Gemma 4 E4B en 5
/// elementos»—, con «Revisar con *el modelo*» para todo y, si hay de más de
/// un modelo, para lo de uno solo. No ocupa lugar si no hay nada, ni mientras
/// una revisión corre: ahí se ve su avance.
class AiReviewOfferCard extends ConsumerWidget {
  const AiReviewOfferCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(
      aiReviewBatchProvider.select((b) => b != null && !b.finished),
    );
    final work = running
        ? const <AiModelWork>[]
        : ref.watch(aiReviewOfferProvider).valueOrNull ?? const [];
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: work.isEmpty
          ? const SizedBox(width: double.infinity)
          : _Offer(work: work),
    );
  }
}

class _Offer extends ConsumerWidget {
  const _Offer({required this.work});

  final List<AiModelWork> work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reviewer = modelLabel(ref.watch(aiReviewerNameProvider));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Card(
      key: const Key('ai-review-offer'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AiSparkCircle(size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiRecheckOfferTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(l10n.aiRecheckOfferMessage, style: muted),
                  const SizedBox(height: 8),
                  for (final w in work)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l10n.aiRecheckOfferWork(
                          l10n.aiRecheckThings(w.things),
                          _madeBy(l10n, w.model),
                          l10n.aiRecheckItems(w.items),
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        key: const Key('ai-review-offer-all'),
                        onPressed: () => unawaited(startAiReview(context, ref)),
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(l10n.aiRecheckWith(reviewer)),
                      ),
                      if (work.length > 1)
                        for (final w in work)
                          if (w.model case final model?)
                            TextButton(
                              key: Key('ai-review-offer-only-$model'),
                              onPressed: () => unawaited(
                                startAiReview(context, ref, madeBy: model),
                              ),
                              child: Text(
                                l10n.aiRecheckOnlyModel(modelLabel(model)),
                              ),
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _madeBy(AppLocalizations l10n, String? model) =>
      model == null ? l10n.aiRecheckEarlierModel : modelLabel(model);
}

/// Cómo va la revisión (F33): cuántos elementos van de cuántos, cuántas
/// propuestas dejó, qué lee ahora o por qué espera, con la barra de avance y
/// pausar, seguir y cancelar. Al terminar, el resultado y «Cerrar». Sin
/// revisión, no ocupa lugar.
class AiReviewProgressCard extends ConsumerWidget {
  const AiReviewProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(aiReviewBatchProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: batch == null
          ? const SizedBox(width: double.infinity)
          : _Progress(batch: batch),
    );
  }
}

class _Progress extends ConsumerWidget {
  const _Progress({required this.batch});

  final AiReviewBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = ref.read(aiReviewQueueProvider);
    final model = modelLabel(ref.watch(aiReviewerNameProvider));
    final finished = batch.finished;
    final reason = batch.waiting;
    final waiting = !finished && (reason != null || batch.modelMissing);
    final waitingView = reason == null
        ? null
        : AiQueueWaitingView(
            reason: reason,
            pending: batch.total - batch.done,
            resumesAt: batch.resumesAt,
          );

    final title = finished
        ? l10n.aiRecheckDone
        : batch.paused
        ? l10n.aiRecheckPaused
        : waiting
        ? l10n.aiRecheckWaiting
        : l10n.aiRecheckWorking(model);
    final detail = [
      if (!finished) l10n.aiRecheckProgress(batch.done, batch.total),
      l10n.aiRecheckProposed(batch.proposed),
    ].join(' · ');
    final current = batch.currentTitle;
    final String? note;
    if (finished || batch.paused) {
      note = null;
    } else if (batch.modelMissing) {
      note = l10n.aiRecheckModelMissing;
    } else if (waitingView != null) {
      note = waitingView.reasonText(context);
    } else {
      note = current == null ? null : l10n.reviewAiBatchCurrent(current);
    }
    final opensModel =
        !finished &&
        (batch.modelMissing || (waitingView?.showsAccounts ?? false));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Card(
      key: const Key('ai-review-progress'),
      color: scheme.tertiaryContainer.withValues(alpha: 0.35),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  finished
                      ? Icons.check_circle_outline
                      : waiting
                      ? waitingView?.icon ?? Icons.hourglass_bottom
                      : Icons.auto_awesome,
                  size: 20,
                  color: scheme.tertiary,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(detail, style: muted),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Text(
                  note,
                  key: const Key('ai-review-progress-note'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
            if (!finished) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LinearProgressIndicator(
                  value: batch.total == 0 ? null : batch.done / batch.total,
                  color: scheme.tertiary,
                  backgroundColor: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  if (finished)
                    TextButton(
                      key: const Key('ai-review-dismiss'),
                      onPressed: queue.dismiss,
                      child: Text(l10n.reviewAiBatchDismiss),
                    )
                  else ...[
                    TextButton(
                      key: const Key('ai-review-cancel'),
                      onPressed: queue.cancel,
                      child: Text(l10n.reviewAiBatchCancel),
                    ),
                    if (opensModel)
                      FilledButton.tonal(
                        key: const Key('ai-review-open-model'),
                        onPressed: () =>
                            unawaited(context.push(RoutePaths.languageModel)),
                        child: Text(l10n.aiRecheckOpenModel),
                      )
                    else if (batch.paused)
                      FilledButton.tonal(
                        key: const Key('ai-review-resume'),
                        onPressed: queue.resume,
                        child: Text(l10n.reviewAiBatchResume),
                      )
                    else
                      FilledButton.tonal(
                        key: const Key('ai-review-pause'),
                        onPressed: queue.pause,
                        child: Text(l10n.reviewAiBatchPause),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
