import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_flashcards_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo va el pedido de «Crear tarjetas con IA» (F30), arriba de Repasar:
/// cuántos elementos van de cuántos, qué está leyendo, cuántas tarjetas
/// nuevas y cuántas para revisar, con pausar, seguir y cancelar. Al
/// terminar, el resultado y, si quedó algo dudoso, el camino a «Para
/// revisar». Sin pedido, no ocupa lugar.
///
/// Las tarjetas nuevas entran solas a la pila de abajo: nacen listas para
/// repasar.
class AiFlashcardsBanner extends ConsumerWidget {
  const AiFlashcardsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(aiFlashcardsBatchProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: batch == null
          ? const SizedBox(width: double.infinity)
          : _Banner(batch: batch),
    );
  }
}

class _Banner extends ConsumerWidget {
  const _Banner({required this.batch});

  final AiFlashcardsBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = ref.read(aiOrganizeQueueProvider);
    final aiOn = ref.watch(aiOrganizeSettingsProvider.select((s) => s.enabled));
    final finished = batch.finished;
    final waiting = !finished && (batch.paused || !aiOn);

    final title = finished
        ? l10n.reviewAiBatchDone
        : waiting
        ? l10n.reviewAiBatchPaused
        : l10n.reviewAiBatchWorking;
    final current = batch.currentTitle;
    final detail = [
      if (!finished) l10n.reviewAiBatchProgress(batch.done, batch.total),
      l10n.reviewAiBatchCreated(batch.created),
      if (batch.forReview > 0) l10n.reviewAiBatchForReview(batch.forReview),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        key: const Key('ai-cards-banner'),
        margin: EdgeInsets.zero,
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    finished ? Icons.check_circle_outline : Icons.auto_awesome,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!aiOn && !finished)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Text(
                    l10n.reviewAiBatchAiPaused,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else if (current != null && !waiting)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Text(
                    l10n.reviewAiBatchCurrent(current),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (!finished) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: LinearProgressIndicator(
                    value: batch.total == 0 ? null : batch.done / batch.total,
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
                    if (finished) ...[
                      if (batch.forReview > 0)
                        TextButton(
                          onPressed: () => context.push(RoutePaths.aiActivity),
                          child: Text(l10n.reviewAiBatchSeeReview),
                        ),
                      TextButton(
                        key: const Key('ai-cards-dismiss'),
                        onPressed: queue.dismissFlashcards,
                        child: Text(l10n.reviewAiBatchDismiss),
                      ),
                    ] else ...[
                      TextButton(
                        key: const Key('ai-cards-cancel'),
                        onPressed: queue.cancelFlashcards,
                        child: Text(l10n.reviewAiBatchCancel),
                      ),
                      if (!aiOn)
                        FilledButton.tonal(
                          onPressed: () => unawaited(
                            ref
                                .read(aiOrganizeSettingsProvider.notifier)
                                .set(AiOrganizeToggle.enabled, on: true),
                          ),
                          child: Text(l10n.reviewAiResumeAi),
                        )
                      else if (batch.paused)
                        FilledButton.tonal(
                          key: const Key('ai-cards-resume'),
                          onPressed: queue.resumeFlashcards,
                          child: Text(l10n.reviewAiBatchResume),
                        )
                      else
                        FilledButton.tonal(
                          key: const Key('ai-cards-pause'),
                          onPressed: queue.pauseFlashcards,
                          child: Text(l10n.reviewAiBatchPause),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
