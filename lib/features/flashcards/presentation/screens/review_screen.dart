import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_session_controller.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/ai_flashcards_banner.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/ai_flashcards_sheet.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_empty_state.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_session_card.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_session_progress.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_session_summary.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_preferences.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Repasar las tarjetas que ya tocan, de a una: se lee la pregunta, se
/// intenta responder de memoria, se toca para revelar la respuesta, y se
/// califica qué tan bien salió. Esa calificación es lo único que decide
/// cuándo vuelve a aparecer (algoritmo SM-2, ver `scheduleNext`).
///
/// Qué toca lo decide la cola de estudio (`StudyRepository`) para [scope], y
/// el estado de la sesión vive en `StudySessionController`: esta pantalla lo
/// dibuja y le avisa lo que la persona hace.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({
    this.scope = const StudyScope.all(),
    this.startInPractice = false,
    super.key,
  });

  /// Qué se estudia.
  final StudyScope scope;

  /// Empezar directamente en «Practicar igual» (F30): repasar todas las
  /// tarjetas aunque no les toque, sin tocar su calendario.
  final bool startInPractice;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  var _exporting = false;

  /// «Practicar igual» (F30): las tarjetas que se están practicando sin que
  /// les toque, y cuál va. `null` fuera de la práctica.
  List<Flashcard>? _practice;
  var _practiceIndex = 0;
  var _practiceRevealed = false;

  StudySessionController get _session =>
      ref.read(studySessionProvider(widget.scope).notifier);

  @override
  void initState() {
    super.initState();
    unawaited(_session.start());
    if (widget.startInPractice) unawaited(_startPractice());
  }

  /// Practica todas las tarjetas, aunque no les toque: la que vence antes,
  /// primero. No califica: el calendario de cada una (SM-2) no cambia.
  Future<void> _startPractice() async {
    final all = await ref.read(flashcardRepositoryProvider).getAll();
    if (!mounted) return;
    final cards = all.getOrElse((_) => const <Flashcard>[]).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (cards.isEmpty) return;
    setState(() {
      _practice = cards;
      _practiceIndex = 0;
      _practiceRevealed = false;
    });
  }

  void _nextPractice() => setState(() {
    _practiceRevealed = false;
    final cards = _practice!;
    if (_practiceIndex + 1 >= cards.length) {
      _practice = null;
    } else {
      _practiceIndex++;
    }
  });

  void _stopPractice() => setState(() {
    _practice = null;
    _practiceRevealed = false;
  });

  void _showFailure(Failure failure) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
  }

  Future<void> _grade(ReviewGrade grade) async {
    final failure = await _session.grade(grade);
    if (failure != null && mounted) _showFailure(failure);
  }

  Future<void> _undo() async {
    final failure = await _session.undo();
    if (failure != null && mounted) _showFailure(failure);
  }

  /// Cierra la sesión.
  void _finish() => unawaited(Navigator.of(context).maybePop());

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

  /// Lo que muestra la sesión según lo que dice la cola.
  Widget _body(AppLocalizations l10n, StudySessionState session) {
    final practice = _practice;
    if (practice != null) {
      return ReviewSessionCard(
        key: ValueKey('practice-${practice[_practiceIndex].id}'),
        card: practice[_practiceIndex],
        revealed: _practiceRevealed,
        grading: false,
        practice: (
          done: _practiceIndex,
          total: practice.length,
          onNext: _nextPractice,
          onStop: _stopPractice,
        ),
        onReveal: () => setState(() => _practiceRevealed = true),
        onGrade: (_) {},
      );
    }

    final next = session.next;
    if (next == null) {
      final failure = session.failure;
      if (failure == null) return const CircularProgressIndicator();
      return EmptyStateView(
        key: const Key('review-load-failed'),
        icon: Icons.error_outline,
        title: l10n.reviewSessionLoadFailed,
        message: failure.localizedMessage(l10n),
        actionLabel: l10n.reviewSessionRetry,
        onAction: () => unawaited(_session.retry()),
      );
    }
    switch (next) {
      case StudyNextCard(:final card):
        return ReviewSessionCard(
          // La misma tarjeta vuelve en un minuto: otra clave, otro estado.
          key: ValueKey(
            '${card.id}:${card.lastReviewedAt?.millisecondsSinceEpoch}',
          ),
          card: card,
          revealed: session.revealed,
          grading: session.busy,
          onReveal: _session.reveal,
          onGrade: (grade) => unawaited(_grade(grade)),
        );
      case StudyNextWait(:final until, :final learningLeft):
        if (session.answered > 0) return _summary(session);
        final wait = until.difference(ref.read(clockProvider)());
        final minutes = (wait.inSeconds / 60).ceil().clamp(1, 24 * 60);
        return EmptyStateView(
          key: const Key('review-waiting'),
          icon: Icons.hourglass_bottom,
          title: l10n.reviewWaitTitle,
          message: l10n.reviewWaitMessage(learningLeft, minutes),
          actionLabel: l10n.reviewWaitNow,
          onAction: () => unawaited(_session.continueNow()),
        );
      case StudyNextDone(
        :final hitLimit,
        :final newBeyondLimit,
        :final reviewsBeyondLimit,
      ):
        if (session.answered > 0) return _summary(session);
        if (hitLimit) {
          return EmptyStateView(
            key: const Key('review-limit-reached'),
            icon: Icons.flag_outlined,
            title: l10n.reviewLimitTitle,
            message: l10n.reviewLimitMessage(
              newBeyondLimit,
              reviewsBeyondLimit,
            ),
            actionLabel: l10n.reviewLimitMore,
            onAction: () => unawaited(_session.studyMore()),
          );
        }
        // F30: si está vacío, dice por qué.
        return ReviewEmptyState(onPractice: () => unawaited(_startPractice()));
    }
  }

  Widget _summary(StudySessionState session) => ReviewSessionSummary(
    session: session,
    onFinish: _finish,
    onUndo: () => unawaited(_undo()),
    onStudyMore: () => unawaited(_session.studyMore()),
    onContinueNow: () => unawaited(_session.continueNow()),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = ref.watch(studySessionProvider(widget.scope));
    final habitFeaturesEnabled = ref.watch(habitFeaturesEnabledProvider);
    // Si no hay ninguna tarjeta a la vista y algo cambia (la IA hizo tarjetas,
    // se restauró un elemento, pasó el día), se vuelve a preguntar.
    ref.listen(studyCountsProvider(widget.scope), (previous, current) {
      if (_practice == null) _session.onStudyDataChanged();
    });
    final inSession = _practice == null && session.card != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reviewTitle),
        actions: [
          if (_practice == null)
            IconButton(
              key: const Key('review-undo'),
              icon: const Icon(Icons.undo),
              tooltip: l10n.reviewSessionUndoTooltip,
              onPressed: _session.canUndo ? () => unawaited(_undo()) : null,
            ),
          // F17, D9: el interruptor único de Ajustes apaga las tres de una
          // vez, no montando estos widgets en absoluto —así ni siquiera
          // consultan la base mientras está apagado—.
          if (habitFeaturesEnabled) ...[
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
          ],
          // F30: que la IA haga las tarjetas, además de a mano.
          IconButton(
            key: const Key('review-ai-create'),
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: l10n.reviewAiCreateTooltip,
            onPressed: () => unawaited(showAiFlashcardsSheet(context)),
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
        child: Column(
          children: [
            // Cómo va el pedido de tarjetas con IA (F30), si hay uno.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: const AiFlashcardsBanner(),
              ),
            ),
            if (inSession)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ReviewSessionProgress(session: session),
                ),
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _body(l10n, session),
                ),
              ),
            ),
          ],
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
