import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/review_entry_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/ai_flashcards_banner.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/ai_flashcards_sheet.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_empty_state.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_grade_row.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/study_scope_picker.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_preferences.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La entrada a Repasar (F31, ola 2): cuánto hay para estudiar hoy —nuevas,
/// aprendiendo, por repasar—, qué estudiar (todo, un tema, una etiqueta, un
/// cuaderno o un elemento) y el botón «Empezar». Desde acá también se llega a
/// «Mis tarjetas» y a las estadísticas, a las insignias, al historial, a crear
/// tarjetas con IA y a exportar a Anki.
class ReviewEntryScreen extends ConsumerStatefulWidget {
  const ReviewEntryScreen({super.key});

  @override
  ConsumerState<ReviewEntryScreen> createState() => _ReviewEntryScreenState();
}

class _ReviewEntryScreenState extends ConsumerState<ReviewEntryScreen> {
  var _exporting = false;

  Future<void> _chooseScope() async {
    final chosen = await showStudyScopePicker(context);
    if (chosen == null || !mounted) return;
    ref.read(reviewEntryScopeProvider.notifier).state = chosen;
  }

  void _start(StudyScope scope, {bool practice = false}) {
    unawaited(
      context.push(
        RoutePaths.reviewSessionFor(
          kind: scope.kind.name,
          id: scope.id,
          practice: practice,
        ),
      ),
    );
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
    final scope = ref.watch(reviewEntryScopeProvider);
    final counts = ref.watch(studyCountsProvider(scope));
    final habitFeaturesEnabled = ref.watch(habitFeaturesEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reviewTitle),
        actions: [
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              key: const Key('review-entry'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Column(
                    children: [
                      // Cómo va el pedido de tarjetas con IA (F30), si hay uno.
                      const AiFlashcardsBanner(),
                      _ScopeTile(scope: scope, onTap: _chooseScope),
                    ],
                  ),
                ),
                Expanded(
                  child: _Today(
                    counts: counts,
                    scope: scope,
                    onStart: () => _start(scope),
                    onPractice: () => _start(scope, practice: true),
                    onResetScope: () =>
                        ref.read(reviewEntryScopeProvider.notifier).state =
                            const StudyScope.all(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('review-entry-cards'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () => unawaited(context.push(kRouteCards)),
                          icon: const Icon(Icons.style_outlined),
                          label: Text(l10n.reviewEntryMyCards),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('review-entry-stats'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () =>
                              unawaited(context.push(kRouteReviewStats)),
                          icon: const Icon(Icons.insights_outlined),
                          label: Text(l10n.reviewEntryStats),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Qué se estudia ahora, y cómo cambiarlo.
class _ScopeTile extends ConsumerWidget {
  const _ScopeTile({required this.scope, required this.onTap});

  final StudyScope scope;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = ref.watch(studyScopeNameProvider(scope));
    // Para un recorte que apunta a algo, el nombre; si ya no existe, lo dice.
    final title = scope.isAll
        ? l10n.reviewEntryScopeAll
        : (name.valueOrNull ??
              (name.isLoading ? '…' : l10n.reviewEntryScopeMissing));

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('review-entry-scope'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(studyScopeKindIcon(scope.kind), color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.reviewEntryScopeTitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      title,
                      key: const Key('review-entry-scope-name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onTap,
                child: Text(l10n.reviewEntryScopeChange),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo que hay para hoy en el recorte, con el botón de empezar; o por qué no
/// hay nada.
class _Today extends ConsumerWidget {
  const _Today({
    required this.counts,
    required this.scope,
    required this.onStart,
    required this.onPractice,
    required this.onResetScope,
  });

  final AsyncValue<StudyCounts> counts;
  final StudyScope scope;
  final VoidCallback onStart;
  final VoidCallback onPractice;
  final VoidCallback onResetScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (counts.hasError && !counts.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('review-entry-count-failed'),
          children: [
            Text(
              l10n.reviewEntryCountFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
            if (!scope.isAll)
              TextButton(
                onPressed: onResetScope,
                child: Text(l10n.reviewEntryScopeReset),
              ),
          ],
        ),
      );
    }
    final value = counts.valueOrNull;
    if (value == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (value.isEmpty) {
      // Nada para hoy: el vacío de siempre, que dice por qué (F30).
      return ReviewEmptyState(onPractice: onPractice);
    }

    final minutes = value.nextLearningDue == null
        ? null
        : (value.nextLearningDue!
                      .difference(ref.read(clockProvider)())
                      .inSeconds /
                  60)
              .ceil();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        key: const Key('review-entry-counts'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          children: [
            Text(
              l10n.reviewEntryTodayTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _BigCount(
                  key: const Key('review-entry-new'),
                  label: l10n.reviewSessionQueueNew,
                  count: value.newCards,
                  color: scheme.primary,
                ),
                _BigCount(
                  key: const Key('review-entry-learning'),
                  label: l10n.reviewSessionQueueLearning,
                  count: value.learning,
                  color: scheme.error,
                ),
                _BigCount(
                  key: const Key('review-entry-review'),
                  label: l10n.reviewSessionQueueReview,
                  count: value.reviews,
                  color: scheme.tertiary,
                ),
              ],
            ),
            if (value.newBeyondLimit > 0)
              _Note(
                key: const Key('review-entry-new-beyond'),
                text: l10n.reviewEntryNewBeyond(value.newBeyondLimit),
              ),
            if (value.reviewsBeyondLimit > 0)
              _Note(
                key: const Key('review-entry-reviews-beyond'),
                text: l10n.reviewEntryReviewsBeyond(value.reviewsBeyondLimit),
              ),
            if (minutes != null && minutes > 0)
              _Note(
                key: const Key('review-entry-next-learning'),
                text: l10n.reviewEntryNextLearning(minutes),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('review-entry-start'),
              style: reviewWideButtonStyle(),
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.reviewEntryStart),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigCount extends StatelessWidget {
  const _BigCount({
    required this.label,
    required this.count,
    required this.color,
    super.key,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        label: '$label: $count',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(
              '$count',
              style: theme.textTheme.displaySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
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
