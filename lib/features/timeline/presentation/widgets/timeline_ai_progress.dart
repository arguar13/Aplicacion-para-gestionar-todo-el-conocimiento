import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_dates_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo va «Organizar con IA» (F40), debajo de la fila de recortes de la línea
/// de tiempo: una franja discreta con cuántos elementos van, cuántas fechas
/// nuevas salieron y una barra fina. Los hechos aparecen en el eje a medida que
/// la IA los pone; esto solo dice que sigue.
///
/// Sin pedido no ocupa lugar. Al terminar queda el resultado hasta que se
/// cierre. Con la IA en pausa lo dice y ofrece reanudarla.
class TimelineAiProgress extends ConsumerWidget {
  const TimelineAiProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(aiDatesBatchProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: batch == null
          ? const SizedBox(width: double.infinity)
          : _Strip(batch: batch),
    );
  }
}

class _Strip extends ConsumerWidget {
  const _Strip({required this.batch});

  final AiDatesBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = ref.read(aiOrganizeQueueProvider);
    final aiOn = ref.watch(aiOrganizeSettingsProvider.select((s) => s.enabled));
    final finished = batch.finished;

    final title = finished ? l10n.timelineAiDone : l10n.timelineAiWorking;
    final detail = [
      if (!finished) l10n.reviewAiBatchProgress(batch.done, batch.total),
      l10n.timelineAiFound(batch.created),
    ].join(' · ');
    final current = batch.currentTitle;

    final statusLine = !aiOn && !finished
        ? l10n.reviewAiBatchAiPaused
        : current != null && !finished
        ? l10n.reviewAiBatchCurrent(current)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        // Al terminar, el lector de pantalla lo dice solo: la persona no tiene
        // por qué estar mirando la franja.
        liveRegion: finished,
        container: true,
        child: DecoratedBox(
          key: const Key('timeline-ai-progress'),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  finished ? Icons.check_circle_outline : Icons.auto_awesome,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.labelLarge),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (statusLine != null)
                        Text(
                          statusLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (!finished) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          key: const Key('timeline-ai-progress-bar'),
                          value: batch.total == 0
                              ? null
                              : batch.done / batch.total,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!aiOn && !finished)
                  TextButton(
                    key: const Key('timeline-ai-resume'),
                    onPressed: () => unawaited(
                      ref
                          .read(aiOrganizeSettingsProvider.notifier)
                          .set(AiOrganizeToggle.enabled, on: true),
                    ),
                    child: Text(l10n.reviewAiResumeAi),
                  ),
                if (finished)
                  TextButton(
                    key: const Key('timeline-ai-dismiss'),
                    onPressed: queue.dismissDates,
                    child: Text(l10n.reviewAiBatchDismiss),
                  )
                else
                  TextButton(
                    key: const Key('timeline-ai-cancel'),
                    onPressed: queue.cancelDates,
                    child: Text(l10n.reviewAiBatchCancel),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
