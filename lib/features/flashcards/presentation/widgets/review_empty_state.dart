import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_queue_status.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/ai_flashcards_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/ai_flashcards_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Repasar sin nada que repasar, diciendo **por qué** (F30).
///
/// Toda tarjeta nace lista para hoy: si no hay ninguna, es que no hay
/// tarjetas, no un problema de fechas. Cuando hay elementos con texto que
/// todavía no tienen ninguna, lo dice con el número, y el porqué de que la IA
/// no las haya hecho sola —falta un modelo, está en pausa, la biblioteca que
/// ya existía espera el cargador—, cada uno con lo que lo resuelve, y al lado
/// el ✨ que las pide ya. Si la IA ya las está haciendo, que están en camino.
/// Si no hay nada que hacer, el mensaje de siempre.
///
/// Con tarjetas que todavía no tocan, ofrece «Practicar igual»
/// ([onPractice]): repasarlas sin esperar, sin tocar su calendario.
class ReviewEmptyState extends ConsumerWidget {
  const ReviewEmptyState({this.onPractice, super.key});

  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final waiting = ref.watch(itemsWithoutCardsCountProvider).valueOrNull ?? 0;
    final batch = ref.watch(aiFlashcardsBatchProvider);
    final anyCard = ref.watch(hasFlashcardsProvider).valueOrNull ?? false;
    final practice = anyCard ? onPractice : null;

    if (batch != null && !batch.finished) {
      return EmptyStateView(
        key: const Key('review-empty-coming'),
        icon: Icons.auto_awesome,
        title: l10n.reviewEmptyBatchTitle,
        message: l10n.reviewEmptyBatchMessage,
      );
    }
    if (waiting == 0) {
      return EmptyStateView(
        key: const Key('review-empty-done'),
        icon: Icons.check_circle_outline,
        title: l10n.reviewAllDone,
        actionLabel: practice == null ? null : l10n.reviewPracticeAction,
        onAction: practice,
      );
    }
    return _WithoutCards(count: waiting, onPractice: practice);
  }
}

/// Hay [count] elementos sin tarjetas: por qué la IA no las hizo, y el ✨.
class _WithoutCards extends ConsumerWidget {
  const _WithoutCards({required this.count, required this.onPractice});

  final int count;
  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reasons = _reasons(context, ref, l10n);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          key: const Key('review-empty-without-cards'),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      scheme.primaryContainer.withValues(alpha: 0.9),
                      scheme.primaryContainer.withValues(alpha: 0.3),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.style_outlined,
                  size: 40,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.reviewEmptyWithoutCards(count),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.reviewEmptyWithoutCardsHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (reasons.isNotEmpty) ...[
                const SizedBox(height: 20),
                for (final reason in reasons) reason,
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('review-empty-create'),
                onPressed: () => unawaited(showAiFlashcardsSheet(context)),
                icon: const Icon(Icons.auto_awesome),
                label: Text(l10n.reviewAiCreateTooltip),
              ),
              if (onPractice != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('review-practice'),
                  onPressed: onPractice,
                  child: Text(l10n.reviewPracticeAction),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Por qué la IA no las hizo sola, según en qué anda su cola.
  List<Widget> _reasons(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    return switch (ref.watch(aiQueueViewProvider)) {
      AiQueueModelView(:final chatModelMissing, :final embeddingModelMissing) =>
        [
          if (chatModelMissing)
            _Reason(
              key: const Key('review-empty-chat-model'),
              icon: Icons.download_for_offline_outlined,
              text: l10n.reviewEmptyChatModelMissing,
              actionLabel: l10n.flashcardsDownloadModel,
              onAction: () => context.push(RoutePaths.chatModel),
            ),
          if (embeddingModelMissing)
            _Reason(
              key: const Key('review-empty-embedding-model'),
              icon: Icons.download_for_offline_outlined,
              text: l10n.reviewEmptyEmbeddingModelMissing,
              actionLabel: l10n.flashcardsDownloadModel,
              onAction: () => context.push(RoutePaths.embeddingModel),
            ),
        ],
      AiQueuePausedView() => [
        _Reason(
          key: const Key('review-empty-ai-paused'),
          icon: Icons.pause_circle_outline,
          text: l10n.reviewEmptyAiPaused,
          actionLabel: l10n.reviewAiResumeAi,
          onAction: () => unawaited(
            ref
                .read(aiOrganizeSettingsProvider.notifier)
                .set(AiOrganizeToggle.enabled, on: true),
          ),
        ),
      ],
      AiQueueChargerView(:final pending) => [
        _Reason(
          key: const Key('review-empty-charger'),
          icon: Icons.battery_charging_full,
          text: l10n.reviewEmptyWaitingCharger(pending),
        ),
      ],
      AiQueueIdleView() || AiQueueWorkingView() => const [],
    };
  }
}

/// Un porqué, con lo que lo resuelve si hay algo para hacer.
class _Reason extends StatelessWidget {
  const _Reason({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.secondary),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            if (actionLabel != null && onAction != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}
