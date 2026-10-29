import 'package:flutter/material.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';
import 'package:sinapsis/features/creations/report/domain/report_order.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una pregunta del interactivo, para probarse ahí mismo al final de su
/// sección (F43, punto 5 del plan): las opciones A, B, C y D —mezcladas,
/// siempre en el mismo orden (`reportOptionOrder`)—; al tocar una, la
/// correcta en verde con «¡Exacto!» o la elegida en rojo, y debajo el porqué
/// de la elegida y la explicación. La primera respuesta es la que cuenta.
class ReportQuestionCard extends StatelessWidget {
  const ReportQuestionCard({
    required this.question,
    required this.number,
    required this.total,
    required this.picked,
    required this.onPick,
    required this.typography,
    super.key,
  });

  final ReportQuestion question;

  /// Su número en la sección (desde 1) y cuántas hay.
  final int number;
  final int total;

  /// La opción elegida —por su lugar en `question.options`—, o `null` si
  /// todavía no se respondió.
  final int? picked;

  /// Al elegir la opción —por su lugar en `question.options`—.
  final ValueChanged<int> onPick;

  final ReportTypography typography;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic =
        theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final t = typography;
    final order = reportOptionOrder(question);
    final answered = picked != null;
    final pickedOption = answered ? question.options[picked!] : null;
    final right = answered && picked == question.answer;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.f43ReportQuestionOf(number, total),
            style: t.small.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ReportRichText(
            inlines: parseReportInlines(question.question),
            style: t.subheading,
            typography: t,
          ),
          const SizedBox(height: 12),
          for (final (index, option) in order.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            _OptionTile(
              key: ValueKey(
                'report-option-${question.options.indexOf(option)}',
              ),
              letter: reportOptionLetter(index),
              option: option,
              state: !answered
                  ? _OptionState.open
                  : option == question.correct
                  ? _OptionState.correct
                  : option == pickedOption
                  ? _OptionState.wrong
                  : _OptionState.other,
              success: semantic.success,
              typography: t,
              onTap: answered
                  ? null
                  : () => onPick(question.options.indexOf(option)),
            ),
          ],
          if (answered) ...[
            const SizedBox(height: 14),
            _Feedback(
              key: const Key('report-question-feedback'),
              right: right,
              picked: pickedOption!,
              question: question,
              letterOfCorrect: reportOptionLetter(
                order.indexOf(question.correct),
              ),
              success: semantic.success,
              typography: t,
            ),
          ],
        ],
      ),
    );
  }
}

enum _OptionState { open, correct, wrong, other }

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.option,
    required this.state,
    required this.success,
    required this.typography,
    required this.onTap,
    super.key,
  });

  final String letter;
  final ReportOption option;
  final _OptionState state;
  final Color success;
  final ReportTypography typography;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final t = typography;
    final (
      Color background,
      Color border,
      Color badge,
      IconData? icon,
    ) = switch (state) {
      _OptionState.open => (
        scheme.surfaceContainerLow,
        scheme.outlineVariant,
        scheme.onSurfaceVariant,
        null,
      ),
      _OptionState.correct => (
        Color.alphaBlend(
          success.withValues(alpha: 0.16),
          scheme.surfaceContainerLow,
        ),
        success,
        success,
        Icons.check_circle,
      ),
      _OptionState.wrong => (
        Color.alphaBlend(
          scheme.error.withValues(alpha: 0.14),
          scheme.surfaceContainerLow,
        ),
        scheme.error,
        scheme.error,
        Icons.cancel,
      ),
      _OptionState.other => (
        scheme.surfaceContainerLow,
        scheme.outlineVariant.withValues(alpha: 0.4),
        scheme.onSurfaceVariant.withValues(alpha: 0.7),
        null,
      ),
    };
    final value = switch (state) {
      _OptionState.correct => l10n.f43ReportOptionCorrect,
      _OptionState.wrong => l10n.f43ReportOptionPicked,
      _ => null,
    };
    return Semantics(
      button: onTap != null,
      onTap: onTap,
      label: l10n.f43ReportOption(letter, option.text),
      value: value,
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: border,
                width:
                    state == _OptionState.correct || state == _OptionState.wrong
                    ? 1.6
                    : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: badge, width: 1.4),
                  ),
                  child: Text(
                    letter,
                    textScaler: TextScaler.noScaling,
                    style: t.small.copyWith(
                      color: badge,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      option.text,
                      style: t.body.copyWith(
                        height: 1.4,
                        color: state == _OptionState.other ? t.muted : t.ink,
                      ),
                    ),
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, color: border, size: 22),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se dice al responder: «¡Exacto!» o «No es esa», el porqué de la
/// elegida, cuál era la correcta y la explicación.
class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.right,
    required this.picked,
    required this.question,
    required this.letterOfCorrect,
    required this.success,
    required this.typography,
    super.key,
  });

  final bool right;
  final ReportOption picked;
  final ReportQuestion question;
  final String letterOfCorrect;
  final Color success;
  final ReportTypography typography;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final t = typography;
    final color = right ? success : scheme.error;
    final lines = <String>[
      if (!right && picked.why.isNotEmpty) picked.why,
      if (!right)
        l10n.f43ReportCorrectWas(letterOfCorrect, question.correct.text),
      if (question.explanation.isNotEmpty)
        question.explanation
      else if (right && question.correct.why.isNotEmpty)
        question.correct.why,
    ];
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                right ? Icons.check_circle : Icons.info_outline,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  right ? l10n.f43ReportCorrect : l10n.f43ReportWrong,
                  style: t.subheading.copyWith(color: color),
                ),
              ),
            ],
          ),
          for (final line in lines) ...[
            const SizedBox(height: 6),
            Text(line, style: t.body.copyWith(fontSize: 15.5, height: 1.5)),
          ],
        ],
      ),
    );
  }
}
