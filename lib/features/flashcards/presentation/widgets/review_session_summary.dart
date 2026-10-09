import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_session_controller.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_preferences.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La pantalla de resumen de una sesión (F31, ola 2): lo que se hizo —cuántas
/// tarjetas, cuánto se tardó, cuántas se acertaron, la racha— y qué sigue:
/// nada por hoy, una espera de unos minutos («Seguir ahora») o un límite del
/// día («Estudiar más hoy»).
///
/// Solo se muestra si se contestó al menos una tarjeta; una sesión que abre
/// y no tiene nada para estudiar usa las pantallas de siempre (vacío, espera,
/// límite).
class ReviewSessionSummary extends ConsumerWidget {
  const ReviewSessionSummary({
    required this.session,
    required this.onFinish,
    required this.onUndo,
    required this.onStudyMore,
    required this.onContinueNow,
    super.key,
  });

  /// La sesión terminada o en pausa; su `next` es una [StudyNextWait] o una
  /// [StudyNextDone].
  final StudySessionState session;

  final VoidCallback onFinish;
  final VoidCallback onUndo;
  final VoidCallback onStudyMore;
  final VoidCallback onContinueNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = session.next;

    final (IconData icon, String title, String message) = switch (next) {
      StudyNextWait(:final until, :final learningLeft) => (
        Icons.hourglass_bottom,
        l10n.reviewWaitTitle,
        l10n.reviewWaitMessage(
          learningLeft,
          (until.difference(ref.read(clockProvider)()).inSeconds / 60)
              .ceil()
              .clamp(1, 24 * 60),
        ),
      ),
      StudyNextDone(
        hitLimit: true,
        :final newBeyondLimit,
        :final reviewsBeyondLimit,
      ) =>
        (
          Icons.flag_outlined,
          l10n.reviewLimitTitle,
          l10n.reviewLimitMessage(newBeyondLimit, reviewsBeyondLimit),
        ),
      _ => (
        Icons.celebration_outlined,
        l10n.reviewSessionSummaryTitle,
        l10n.reviewSessionSummaryRest,
      ),
    };
    final waiting = next is StudyNextWait;
    final beyondLimit = switch (next) {
      StudyNextWait(:final newBeyondLimit, :final reviewsBeyondLimit) =>
        newBeyondLimit > 0 || reviewsBeyondLimit > 0,
      StudyNextDone(:final hitLimit) => hitLimit,
      _ => false,
    };
    final streak = ref.watch(habitFeaturesEnabledProvider)
        ? ref.watch(currentStreakProvider).valueOrNull
        : null;
    final accuracy = session.answered == 0
        ? 0
        : (session.correct * 100 / session.answered).round();

    return Center(
      child: SingleChildScrollView(
        key: const Key('review-summary'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              key: waiting
                  ? const Key('review-waiting')
                  : (beyondLimit ? const Key('review-limit-reached') : null),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _Stat(
                  key: const Key('review-stat-cards'),
                  icon: Icons.style_outlined,
                  label: l10n.reviewSessionStatCards,
                  value: '${session.answered}',
                ),
                _Stat(
                  key: const Key('review-stat-time'),
                  icon: Icons.timer_outlined,
                  label: l10n.reviewSessionStatTime,
                  value: _duration(l10n, session.studied),
                ),
                _Stat(
                  key: const Key('review-stat-correct'),
                  icon: Icons.check_circle_outline,
                  label: l10n.reviewSessionStatCorrect,
                  value: l10n.reviewSessionPercent(accuracy),
                ),
                if (streak != null && streak.days > 0)
                  _Stat(
                    key: const Key('review-stat-streak'),
                    icon: Icons.local_fire_department,
                    label: l10n.reviewSessionStatStreak,
                    value: l10n.reviewSessionStreakDays(streak.days),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (waiting)
              FilledButton.icon(
                key: const Key('review-summary-continue'),
                onPressed: onContinueNow,
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.reviewWaitNow),
              ),
            if (beyondLimit) ...[
              if (waiting) const SizedBox(height: 8),
              if (waiting)
                FilledButton.tonalIcon(
                  key: const Key('review-summary-more'),
                  onPressed: onStudyMore,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.reviewLimitMore),
                )
              else
                FilledButton.icon(
                  key: const Key('review-summary-more'),
                  onPressed: onStudyMore,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.reviewLimitMore),
                ),
            ],
            const SizedBox(height: 8),
            if (session.answers.isNotEmpty)
              TextButton.icon(
                key: const Key('review-summary-undo'),
                onPressed: session.busy ? null : onUndo,
                icon: const Icon(Icons.undo),
                label: Text(l10n.reviewSessionUndoTooltip),
              ),
            OutlinedButton(
              key: const Key('review-summary-finish'),
              onPressed: onFinish,
              child: Text(l10n.reviewSessionFinish),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(AppLocalizations l10n, Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return l10n.reviewSessionDurationSeconds(seconds);
    return l10n.reviewSessionDurationMinutes(seconds ~/ 60, seconds % 60);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        width: 132,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: scheme.primary, size: 22),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
