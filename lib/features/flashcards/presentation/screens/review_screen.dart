import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Repasar las tarjetas que ya tocan, de a una: se lee la pregunta, se
/// intenta responder de memoria, se toca para revelar la respuesta, y se
/// califica qué tan bien salió. Esa calificación es lo único que decide
/// cuándo vuelve a aparecer (algoritmo SM-2, ver `scheduleNext`).
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  var _revealed = false;
  var _grading = false;

  Future<void> _grade(String cardId, ReviewGrade grade) async {
    setState(() => _grading = true);
    await ref
        .read(flashcardRepositoryProvider)
        .review(id: cardId, grade: grade);
    if (!mounted) return;
    setState(() {
      _revealed = false;
      _grading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final due = ref.watch(dueFlashcardsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: due.when(
              loading: () => const CircularProgressIndicator(),
              error: (error, stackTrace) => Text('$error'),
              data: (cards) => cards.isEmpty
                  ? _AllDoneView(message: l10n.reviewAllDone)
                  : _CardView(
                      card: cards.first,
                      revealed: _revealed,
                      grading: _grading,
                      remaining: cards.length,
                      onReveal: () => setState(() => _revealed = true),
                      onGrade: (grade) => _grade(cards.first.id, grade),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AllDoneView extends StatelessWidget {
  const _AllDoneView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({
    required this.card,
    required this.revealed,
    required this.grading,
    required this.remaining,
    required this.onReveal,
    required this.onGrade,
  });

  final Flashcard card;
  final bool revealed;
  final bool grading;
  final int remaining;
  final VoidCallback onReveal;
  final ValueChanged<ReviewGrade> onGrade;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.reviewRemaining(remaining),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: revealed ? null : onReveal,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 200),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.front,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  if (revealed) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      card.back,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!revealed)
            OutlinedButton(
              onPressed: onReveal,
              child: Text(l10n.reviewShowAnswer),
            )
          else
            Row(
              children: [
                for (final grade in ReviewGrade.values) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: grading ? null : () => onGrade(grade),
                      child: Text(_labelFor(l10n, grade)),
                    ),
                  ),
                  if (grade != ReviewGrade.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
        ],
      ),
    );
  }

  String _labelFor(AppLocalizations l10n, ReviewGrade grade) => switch (grade) {
    ReviewGrade.again => l10n.reviewGradeAgain,
    ReviewGrade.hard => l10n.reviewGradeHard,
    ReviewGrade.good => l10n.reviewGradeGood,
    ReviewGrade.easy => l10n.reviewGradeEasy,
  };
}
