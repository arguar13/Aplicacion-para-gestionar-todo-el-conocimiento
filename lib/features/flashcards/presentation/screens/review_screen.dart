import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/open_flashcard_source.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
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
  var _exporting = false;

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

  /// Pregunta el alcance (F17, D4) y el formato (commit 5) antes de
  /// exportar: incremental por defecto —solo lo que nunca se exportó—, con
  /// «todo el mazo» como interruptor aparte, y el `.apkg` completo por
  /// defecto, con TSV/CSV como camino alternativo (D5). No distingue
  /// "canceló el diálogo de guardado" de "lo guardó" — igual que el resto
  /// de las exportaciones de la app (ver `ExportItemUseCase`). Solo avisa
  /// cuando algo salió mal de verdad.
  Future<void> _exportToAnki() async {
    final l10n = AppLocalizations.of(context)!;
    final scope = await _chooseExportScope(context, l10n);
    if (scope == null || !mounted) return;

    setState(() => _exporting = true);

    final result = await ref.read(exportFlashcardsToAnkiUseCaseProvider)(
      ExportFlashcardsToAnkiParams(
        exportAll: scope.exportAll,
        format: scope.format,
      ),
    );
    if (!mounted) return;
    setState(() => _exporting = false);

    result.match((failure) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    }, (_) {});
  }

  Future<({bool exportAll, AnkiExportFormat format})?> _chooseExportScope(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return showDialog(
      context: context,
      builder: (context) => _ExportScopeDialog(l10n: l10n),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final due = ref.watch(dueFlashcardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reviewTitle),
        actions: [
          const _StreakIndicator(),
          IconButton(
            icon: const Icon(Icons.military_tech_outlined),
            tooltip: l10n.reviewBadgesTooltip,
            onPressed: () => context.push(RoutePaths.reviewBadges),
          ),
          IconButton(
            icon: const Icon(Icons.query_stats_outlined),
            tooltip: l10n.reviewHistoryTooltip,
            onPressed: () => context.push(RoutePaths.reviewHistory),
          ),
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            tooltip: l10n.reviewExportToAnkiTooltip,
            onPressed: _exporting ? null : _exportToAnki,
          ),
        ],
      ),
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

/// La racha (F17, D3/D6/commit 8): oculto sin ninguna, mismo criterio que
/// la insignia de pendientes de `dueFlashcardCountProvider` —nada que
/// mostrar, nada que ocupar lugar—. El color marca si hoy ya cuenta o si
/// todavía hace falta hacer algo para mantenerla.
class _StreakIndicator extends ConsumerWidget {
  const _StreakIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(currentStreakProvider).valueOrNull;
    if (streak == null || streak.days == 0) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = streak.activeToday
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: streak.activeToday
          ? l10n.reviewStreakActiveTooltip(streak.days)
          : l10n.reviewStreakPendingTooltip(streak.days),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          key: const Key('review-streak-indicator'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, size: 18, color: color),
            const SizedBox(width: 4),
            Text(
              '${streak.days}',
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ],
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
    return EmptyStateView(icon: Icons.check_circle_outline, title: message);
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
          // Con la respuesta a la vista, se puede ir a ver de dónde salió.
          if (revealed && card.hasSourceRange) ...[
            TextButton.icon(
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(l10n.flashcardsViewSource),
              onPressed: () => openFlashcardSource(context, card),
            ),
            const SizedBox(height: 8),
          ],
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

/// El interruptor de F17, D4 —«exportar todo» empieza apagado, el camino
/// incremental es el que se ofrece por defecto— y el formato de F17,
/// commit 5 —el `.apkg` completo por defecto, TSV/CSV como camino
/// alternativo (D5)—.
class _ExportScopeDialog extends StatefulWidget {
  const _ExportScopeDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_ExportScopeDialog> createState() => _ExportScopeDialogState();
}

class _ExportScopeDialogState extends State<_ExportScopeDialog> {
  var _exportAll = false;
  var _format = AnkiExportFormat.apkg;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.reviewExportToAnkiTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('review-export-all-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.reviewExportToAnkiExportAll),
            value: _exportAll,
            onChanged: (value) => setState(() => _exportAll = value),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.reviewExportToAnkiFormatTitle,
            style: theme.textTheme.labelLarge,
          ),
          RadioGroup<AnkiExportFormat>(
            groupValue: _format,
            onChanged: (value) => setState(() => _format = value!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final format in AnkiExportFormat.values)
                  RadioListTile<AnkiExportFormat>(
                    key: Key('review-export-format-${format.name}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(_formatLabel(l10n, format)),
                    value: format,
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('review-export-confirm'),
          onPressed: () => Navigator.of(
            context,
          ).pop((exportAll: _exportAll, format: _format)),
          child: Text(l10n.reviewExportToAnkiConfirm),
        ),
      ],
    );
  }

  String _formatLabel(AppLocalizations l10n, AnkiExportFormat format) =>
      switch (format) {
        AnkiExportFormat.apkg => l10n.reviewExportToAnkiFormatApkg,
        AnkiExportFormat.tsv => l10n.reviewExportToAnkiFormatTsv,
        AnkiExportFormat.csv => l10n.reviewExportToAnkiFormatCsv,
      };
}
