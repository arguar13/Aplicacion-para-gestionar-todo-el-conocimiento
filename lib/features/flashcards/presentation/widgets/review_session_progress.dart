import 'package:flutter/material.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_session_controller.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La cabecera de una sesión (F31, ola 2): una barra de avance, cuántas
/// quedan y los tres contadores de siempre —nuevas, aprendiendo, por
/// repasar—, con subrayado el de la cola de la que sale la tarjeta que se ve.
class ReviewSessionProgress extends StatelessWidget {
  const ReviewSessionProgress({required this.session, super.key});

  final StudySessionState session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = session.counts ?? const StudyCounts.empty();
    final total = session.answered + counts.total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: l10n.reviewSessionProgressSemantics(session.answered, total),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: session.progress),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, value, _) => LinearProgressIndicator(
                  key: const Key('review-progress-bar'),
                  value: value,
                  minHeight: 6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.reviewRemaining(counts.total),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _Counter(
                key: const Key('review-counter-new'),
                label: l10n.reviewSessionQueueNew,
                count: counts.newCards,
                color: scheme.primary,
                active: session.queue == StudyQueueKind.newCard,
              ),
              _Counter(
                key: const Key('review-counter-learning'),
                label: l10n.reviewSessionQueueLearning,
                count: counts.learning,
                color: scheme.error,
                active: session.queue == StudyQueueKind.learning,
              ),
              _Counter(
                key: const Key('review-counter-review'),
                label: l10n.reviewSessionQueueReview,
                count: counts.reviews,
                color: scheme.tertiary,
                active: session.queue == StudyQueueKind.review,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.count,
    required this.color,
    required this.active,
    super.key,
  });

  final String label;
  final int count;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        label: '$label: $count',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                decoration: active ? TextDecoration.underline : null,
                decorationColor: color,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
