/// Las piezas del visor del cuestionario (F43, paso 8), cada una con su
/// forma: la cabecera con «6 / 14», la pregunta, las opciones A–D con su
/// explicación, el veredicto, lo escrito, la espera de la IA, la navegación
/// y el puntaje.
library;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/study_viewer_parts.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_card_faces.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El botón ancho de comprobar.
ButtonStyle quizWideButtonStyle() => FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
);

/// El nombre de un tipo de pregunta: los de la hoja de personalizar.
String quizTypeLabel(AppLocalizations l10n, QuizQuestionType type) =>
    switch (type) {
      QuizQuestionType.single => l10n.f43StudioOptSingle,
      QuizQuestionType.multiple => l10n.f43StudioOptMultiple,
      QuizQuestionType.fillBlank => l10n.f43StudioOptFillBlank,
      QuizQuestionType.shortAnswer => l10n.f43StudioOptShortAnswer,
    };

/// La letra de la opción [index]: A, B, C…
String quizLetter(int index) => String.fromCharCode(65 + index);

/// «6 / 14», el tipo de la pregunta y la barra de avance; en una vuelta de
/// las falladas, lo dice.
class QuizHeader extends StatelessWidget {
  const QuizHeader({
    required this.index,
    required this.total,
    required this.type,
    required this.accent,
    required this.retry,
    super.key,
  });

  final int index;
  final int total;
  final QuizQuestionType type;
  final Color accent;
  final bool retry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Semantics(
                liveRegion: true,
                label: l10n.f43QuizProgressSemantics(index + 1, total),
                excludeSemantics: true,
                child: Text(
                  l10n.f43QuizProgress(index + 1, total),
                  key: const Key('quiz-progress'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  quizTypeLabel(l10n, type),
                  key: const Key('quiz-type'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (retry) ...[
            const SizedBox(height: 4),
            Text(
              l10n.f43QuizRetryRound,
              key: const Key('quiz-retry-round'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (index + 1) / total,
              minHeight: 4,
              color: accent,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// La pregunta; en una de completar, con el espacio a la vista.
class QuizPrompt extends StatelessWidget {
  const QuizPrompt({required this.question, required this.accent, super.key});

  final QuizQuestion question;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleLarge?.copyWith(height: 1.3);
    if (question.type != QuizQuestionType.fillBlank) {
      return Text(question.prompt, key: const Key('quiz-prompt'), style: style);
    }
    final pieces = question.prompt.split(kQuizBlank);
    return Text.rich(
      key: const Key('quiz-prompt'),
      TextSpan(
        children: [
          for (final (i, piece) in pieces.indexed) ...[
            TextSpan(text: piece),
            if (i < pieces.length - 1)
              TextSpan(
                text: '      ',
                semanticsLabel: kQuizBlank,
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  decorationColor: accent,
                  decorationThickness: 2.5,
                  backgroundColor: accent.withValues(alpha: 0.12),
                ),
              ),
          ],
        ],
      ),
      style: style,
    );
  }
}

/// «Elegí una opción», «Escribí lo que falta»…
class QuizInstruction extends StatelessWidget {
  const QuizInstruction(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Una opción con su letra. Respondida, la correcta en verde, la elegida que
/// no era en rojo, y debajo de cada una su explicación.
class QuizOptionTile extends StatelessWidget {
  const QuizOptionTile({
    required this.index,
    required this.option,
    required this.multiple,
    required this.selected,
    required this.answered,
    required this.accent,
    required this.onTap,
    super.key,
  });

  final int index;
  final QuizOption option;
  final bool multiple;
  final bool selected;
  final bool answered;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final verdict = studyVerdictColors(context);
    final correct = answered && option.correct;
    final wrong = answered && selected && !option.correct;

    final Color border;
    final Color fill;
    if (correct) {
      border = verdict.good;
      fill = verdict.good.withValues(alpha: 0.12);
    } else if (wrong) {
      border = verdict.bad;
      fill = verdict.bad.withValues(alpha: 0.10);
    } else if (selected) {
      border = accent;
      fill = accent.withValues(alpha: 0.10);
    } else {
      border = scheme.outlineVariant;
      fill = scheme.surfaceContainerLow;
    }
    final dimmed = answered && !correct && !wrong;

    final mark = correct
        ? Icons.check_circle
        : wrong
        ? Icons.cancel
        : multiple && !answered
        ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
        : null;
    final markColor = correct
        ? verdict.good
        : wrong
        ? verdict.bad
        : selected
        ? accent
        : scheme.onSurfaceVariant;

    final state = [
      if (correct) l10n.f43QuizCorrectOption,
      if (wrong) l10n.f43QuizWrongOption,
      if (selected) l10n.f43QuizYourChoice,
    ].join(', ');

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: [
        l10n.f43QuizOptionSemantics(quizLetter(index), option.text),
        if (state.isNotEmpty) state,
        if (answered && option.explanation.isNotEmpty) option.explanation,
      ].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: border,
            width: correct || wrong || selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: correct
                        ? verdict.good
                        : wrong
                        ? verdict.bad
                        : scheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    quizLetter(index),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: correct
                          ? verdict.onGood
                          : wrong
                          ? verdict.onBad
                          : scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          option.text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: dimmed
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      if (answered && option.explanation.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          option.explanation,
                          key: Key('quiz-option-explanation-$index'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (mark != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(mark, size: 22, color: markColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «¡Exacto!» en verde o «No es así» en rojo; `null` en [correct] es un
/// aviso neutro (un «casi», calificar a mano).
class QuizVerdictBanner extends StatelessWidget {
  const QuizVerdictBanner({
    required this.correct,
    required this.title,
    this.detail,
    this.reason = '',
    super.key,
  });

  final bool? correct;
  final String title;
  final String? detail;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final verdict = studyVerdictColors(context);
    final color = switch (correct) {
      true => verdict.good,
      false => verdict.bad,
      null => scheme.tertiary,
    };
    final icon = switch (correct) {
      true => Icons.check_circle,
      false => Icons.cancel,
      null => Icons.rule,
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: Key(switch (correct) {
          true => 'quiz-verdict-right',
          false => 'quiz-verdict-wrong',
          null => 'quiz-verdict-pending',
        }),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail case final detail?) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      reason,
                      key: const Key('quiz-verdict-reason'),
                      style: theme.textTheme.bodyMedium,
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

/// «Por qué»: la explicación de la pregunta.
class QuizExplanation extends StatelessWidget {
  const QuizExplanation({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _QuizNote(
      key: const Key('quiz-explanation'),
      icon: Icons.lightbulb_outline,
      label: l10n.f43QuizExplanation,
      text: text,
    );
  }
}

/// «Respuesta esperada».
class QuizExpectedAnswer extends StatelessWidget {
  const QuizExpectedAnswer({required this.answer, super.key});

  final String answer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _QuizNote(
      key: const Key('quiz-expected'),
      icon: Icons.task_alt,
      label: l10n.f43QuizExpected,
      text: answer,
    );
  }
}

class _QuizNote extends StatelessWidget {
  const _QuizNote({
    required this.icon,
    required this.label,
    required this.text,
    super.key,
  });

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Donde se escribe la respuesta.
class QuizTypedField extends StatelessWidget {
  const QuizTypedField({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.onSubmitted,
    this.multiline = false,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool multiline;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('quiz-typed-field'),
      controller: controller,
      enabled: enabled,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 6 : 2,
      textInputAction: multiline
          ? TextInputAction.newline
          : TextInputAction.done,
      onSubmitted: multiline ? null : (_) => onSubmitted(),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

/// Lo escrito y lo esperado, con la diferencia marcada: la de «Escribí la
/// respuesta» del repaso (F31).
class QuizTypedComparison extends StatelessWidget {
  const QuizTypedComparison({required this.result, super.key});

  final TypedAnswerResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('quiz-comparison'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ReviewTypedResult(result: result),
    );
  }
}

/// «La tenía bien» y «No la tenía».
class QuizSelfGradeRow extends StatelessWidget {
  const QuizSelfGradeRow({
    required this.onRight,
    required this.onWrong,
    super.key,
  });

  final VoidCallback onRight;
  final VoidCallback onWrong;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final verdict = studyVerdictColors(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    );
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        OutlinedButton.icon(
          key: const Key('quiz-self-wrong'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: shape,
            foregroundColor: verdict.bad,
          ),
          onPressed: onWrong,
          icon: const Icon(Icons.close),
          label: Text(l10n.f43QuizSelfGradeNo),
        ),
        FilledButton.icon(
          key: const Key('quiz-self-right'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: shape,
            backgroundColor: verdict.good,
            foregroundColor: verdict.onGood,
          ),
          onPressed: onRight,
          icon: const Icon(Icons.check),
          label: Text(l10n.f43QuizSelfGradeYes),
        ),
      ],
    );
  }
}

/// «La IA está revisando tu respuesta…», con Cancelar. Sin animaciones, la
/// rueda queda quieta.
class QuizGradingCard extends StatelessWidget {
  const QuizGradingCard({required this.onCancel, super.key});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('quiz-grading'),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: still ? 0.66 : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.f43QuizGrading,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            TextButton(
              key: const Key('quiz-grading-cancel'),
              onPressed: onCancel,
              child: Text(l10n.f43QuizGradingCancel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anterior y Siguiente (o «Ver el resultado» en la última).
class QuizNavigation extends StatelessWidget {
  const QuizNavigation({
    required this.canGoBack,
    required this.isLast,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final bool canGoBack;
  final bool isLast;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('quiz-previous'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: shape,
                  ),
                  onPressed: canGoBack ? onPrevious : null,
                  child: Text(
                    l10n.f43QuizPrevious,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('quiz-next'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: shape,
                  ),
                  onPressed: onNext,
                  child: Text(
                    isLast ? l10n.f43QuizFinish : l10n.f43QuizNext,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El puntaje al final: «9 de 14», el porcentaje en un anillo y «Repetir
/// solo las que fallé».
class QuizScoreView extends StatelessWidget {
  const QuizScoreView({
    required this.correct,
    required this.total,
    required this.missed,
    required this.accent,
    required this.onRetryMissed,
    required this.onRestart,
    super.key,
  });

  final int correct;
  final int total;
  final int missed;
  final Color accent;
  final VoidCallback onRetryMissed;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final percent = total == 0 ? 0 : (correct * 100 / total).round();
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.f43QuizScoreTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: SizedBox.square(
                  dimension: 148,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: total == 0 ? 0 : correct / total,
                        strokeWidth: 10,
                        strokeCap: StrokeCap.round,
                        color: accent,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: FittedBox(
                            child: Text(
                              l10n.f43QuizScore(correct, total),
                              key: const Key('quiz-score-value'),
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.f43QuizScorePercent(percent),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                missed == 0 ? l10n.f43QuizScoreAll : l10n.f43QuizScoreSome,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              if (missed > 0) ...[
                FilledButton.icon(
                  key: const Key('quiz-retry-missed'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: shape,
                  ),
                  onPressed: onRetryMissed,
                  icon: const Icon(Icons.replay),
                  label: Text(
                    l10n.f43QuizRetryMissed(missed),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                key: const Key('quiz-restart'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: shape,
                ),
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt),
                label: Text(l10n.f43QuizRestart, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
