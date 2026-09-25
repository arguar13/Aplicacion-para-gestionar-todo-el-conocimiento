import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_option.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/features/flashcards/domain/entities/topic_error_summary.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/multiple_choice_options.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una sesión SUELTA de quiz (F20, commit 8): practicar [cards] de punta a
/// punta sin esperar a que "toquen" por SM-2 —recién generadas, ya son
/// `dueAt: ahora` y aparecerían igual en el repaso normal (`ReviewScreen`),
/// pero repasarlas ahí Y de nuevo acá adelantaría su programación por una
/// sesión que no es un repaso espaciado de verdad—. Por eso NUNCA llama
/// `FlashcardRepository.review()`: cuenta para la racha por su cuenta
/// (`HabitEventKind.quiz`, una vez al terminar, no por pregunta) y no toca
/// el algoritmo en absoluto.
///
/// Al terminar, qué temas del Atlas concentraron los errores —con acceso
/// directo a la nota viva de cada uno, si tiene—.
class QuizSessionScreen extends ConsumerStatefulWidget {
  const QuizSessionScreen({required this.cards, super.key});

  /// Todas de opción múltiple; se asume no vacía —quien la abre ya
  /// comprobó que hay algo que practicar—.
  final List<Flashcard> cards;

  @override
  ConsumerState<QuizSessionScreen> createState() => _QuizSessionScreenState();
}

class _QuizSessionScreenState extends ConsumerState<QuizSessionScreen> {
  var _index = 0;
  var _answered = false;
  final _missedItemIds = <String>[];
  Future<List<TopicErrorSummary>>? _summary;

  Flashcard get _card => widget.cards[_index];

  void _onAnswered(FlashcardOption picked) {
    if (!picked.isCorrect) _missedItemIds.add(_card.itemId);
    setState(() => _answered = true);
  }

  void _next() {
    if (_index + 1 < widget.cards.length) {
      setState(() {
        _index++;
        _answered = false;
      });
      return;
    }
    unawaited(ref.read(habitEventRecorderProvider).record(HabitEventKind.quiz));
    setState(() {
      _summary = ref
          .read(quizSessionSummaryServiceProvider)
          .summarize(_missedItemIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.quizSessionTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: summary == null
                ? _QuestionView(
                    card: _card,
                    remaining: widget.cards.length - _index,
                    answered: _answered,
                    onAnswered: _onAnswered,
                    onNext: _next,
                    isLast: _index + 1 == widget.cards.length,
                  )
                : _SummaryView(
                    total: widget.cards.length,
                    missed: _missedItemIds.length,
                    summary: summary,
                  ),
          ),
        ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.card,
    required this.remaining,
    required this.answered,
    required this.onAnswered,
    required this.onNext,
    required this.isLast,
  });

  final Flashcard card;
  final int remaining;
  final bool answered;
  final ValueChanged<FlashcardOption> onAnswered;
  final VoidCallback onNext;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.quizSessionRemaining(remaining),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              card.front,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 24),
          // Clave por tarjeta: sin ella, `MultipleChoiceOptions` conserva
          // su estado de "ya contestada" de la pregunta anterior al pasar
          // a la siguiente —mismo tipo de widget en la misma posición del
          // árbol—.
          Consumer(
            builder: (context, ref, _) {
              final options = ref.watch(flashcardOptionsProvider(card.id));
              return options.when(
                loading: () => const SizedBox.shrink(),
                error: (error, stackTrace) => const SizedBox.shrink(),
                data: (options) => MultipleChoiceOptions(
                  key: ValueKey(card.id),
                  options: options,
                  onAnswered: onAnswered,
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          if (answered)
            FilledButton(
              onPressed: onNext,
              child: Text(
                isLast ? l10n.quizSessionFinish : l10n.quizSessionNext,
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({
    required this.total,
    required this.missed,
    required this.summary,
  });

  final int total;
  final int missed;
  final Future<List<TopicErrorSummary>> summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.quizSessionScore(total - missed, total),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          if (missed > 0) ...[
            Text(
              l10n.quizSessionMissedTopicsTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<TopicErrorSummary>>(
              future: summary,
              builder: (context, snapshot) {
                final topics = snapshot.data;
                if (topics == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (topics.isEmpty) {
                  return Text(l10n.quizSessionMissedTopicsEmpty);
                }
                return Column(
                  children: [
                    for (final topic in topics) _TopicErrorTile(topic: topic),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TopicErrorTile extends StatelessWidget {
  const _TopicErrorTile({required this.topic});

  final TopicErrorSummary topic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final noteId = topic.livingNoteItemId;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(topic.topicLabel),
      subtitle: Text(l10n.quizSessionMissedCount(topic.missedCount)),
      trailing: noteId == null
          ? null
          : TextButton(
              onPressed: () => context.push(RoutePaths.itemDetail(noteId)),
              child: Text(l10n.quizSessionOpenLivingNote),
            ),
    );
  }
}
