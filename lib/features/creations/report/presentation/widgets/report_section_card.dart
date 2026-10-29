import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_question_card.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una sección del informe (F43, punto 5 del plan): su número y su título,
/// que se pliega con «⌃» como la «Introducción» de la captura; debajo, el
/// texto con sus viñetas, negritas y palabras clave en rosa, los términos
/// del glosario y, en el interactivo, sus preguntas con el puntaje de la
/// sección.
class ReportSectionCard extends StatelessWidget {
  const ReportSectionCard({
    required this.section,
    required this.index,
    required this.title,
    required this.folded,
    required this.onToggle,
    required this.keywords,
    required this.interactive,
    required this.answers,
    required this.onAnswer,
    required this.typography,
    super.key,
  });

  final ReportSection section;

  /// Su lugar (desde 0).
  final int index;

  /// Su título, o «Sección N» si la IA no le puso.
  final String title;
  final bool folded;
  final VoidCallback onToggle;
  final ReportKeywords keywords;

  /// Si se muestran sus preguntas.
  final bool interactive;

  /// Lo respondido en sus preguntas: pregunta → opción.
  final Map<int, int> answers;
  final void Function(int question, int option) onAnswer;
  final ReportTypography typography;

  /// Cuántas respondió bien.
  int get correct => [
    for (final (q, question) in section.questions.indexed)
      if (answers[q] == question.answer) q,
  ].length;

  bool get _allAnswered =>
      section.questions.isNotEmpty &&
      answers.length == section.questions.length;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final t = typography;
    final questions = interactive
        ? section.questions
        : const <ReportQuestion>[];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            onTap: onToggle,
            expanded: !folded,
            label: folded
                ? l10n.f43ReportUnfold(title)
                : l10n.f43ReportFold(title),
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('report-section-toggle-$index'),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Number(index + 1, typography: t),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(title, style: t.sectionTitle),
                      ),
                    ),
                    if (interactive && _allAnswered) ...[
                      const SizedBox(width: 8),
                      _ScoreBadge(
                        correct: correct,
                        total: section.questions.length,
                        typography: t,
                      ),
                    ],
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        // «⌃» abierta; «⌄» plegada.
                        folded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        size: 28,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!folded)
            Padding(
              key: ValueKey('report-section-body-$index'),
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (section.body.trim().isNotEmpty)
                    ReportBlocks(
                      blocks: reportBlocksWithKeywords(section.body, keywords),
                      typography: t,
                    ),
                  if (section.entries.isNotEmpty) ...[
                    if (section.body.trim().isNotEmpty)
                      const SizedBox(height: 12),
                    for (final (i, entry) in section.entries.indexed)
                      _EntryTile(
                        entry: entry,
                        first: i == 0,
                        keywords: keywords,
                        typography: t,
                      ),
                  ],
                  if (questions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.quiz_outlined, size: 20, color: t.accent),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            l10n.f43ReportQuestionsTitle,
                            style: t.kicker,
                          ),
                        ),
                      ],
                    ),
                    for (final (q, question) in questions.indexed) ...[
                      const SizedBox(height: 10),
                      ReportQuestionCard(
                        key: ValueKey('report-question-$index-$q'),
                        question: question,
                        number: q + 1,
                        total: questions.length,
                        picked: answers[q],
                        onPick: (option) => onAnswer(q, option),
                        typography: t,
                      ),
                    ],
                    if (_allAnswered) ...[
                      const SizedBox(height: 12),
                      Text(
                        l10n.f43ReportSectionScore(correct, questions.length),
                        key: ValueKey('report-section-score-$index'),
                        style: t.small.copyWith(
                          color: t.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// El número de la sección, en un círculo del color del informe.
class _Number extends StatelessWidget {
  const _Number(this.number, {required this.typography});

  final int number;
  final ReportTypography typography;

  @override
  Widget build(BuildContext context) {
    final t = typography;
    final side = MediaQuery.textScalerOf(context).scale(30);
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: t.small.copyWith(
          color: t.accent,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// «2/3»: lo respondido bien en la sección, junto a su título.
class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({
    required this.correct,
    required this.total,
    required this.typography,
  });

  final int correct;
  final int total;
  final ReportTypography typography;

  @override
  Widget build(BuildContext context) {
    final t = typography;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$correct/$total',
        style: t.small.copyWith(color: t.accent, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Un término del glosario: el término destacado y su definición debajo.
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.first,
    required this.keywords,
    required this.typography,
  });

  final ReportEntry entry;
  final bool first;
  final ReportKeywords keywords;
  final ReportTypography typography;

  @override
  Widget build(BuildContext context) {
    final t = typography;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.only(top: first ? 0 : 12, bottom: 12),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(entry.term, style: t.term.copyWith(color: t.accent)),
          if (entry.definition.isNotEmpty) ...[
            const SizedBox(height: 4),
            ReportRichText(
              inlines: withReportKeywords(
                parseReportInlines(entry.definition),
                keywords,
              ),
              style: t.body,
              typography: t,
            ),
          ],
        ],
      ),
    );
  }
}
