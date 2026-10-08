import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/ai_flashcards_providers.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/fill_notebook_controller.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El botón «Llenar con IA» del detalle de un cuaderno (F30): abre la hoja
/// que arma la nota y las tarjetas.
class FillNotebookButton extends StatelessWidget {
  const FillNotebookButton({required this.notebook, super.key});

  final Notebook notebook;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('fill-notebook'),
      icon: const Icon(Icons.auto_awesome_outlined),
      tooltip: l10n.fillNotebookTooltip,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => FillNotebookSheet(notebook: notebook),
      ),
    );
  }
}

/// La hoja de «Llenar» un cuaderno (F30, decisión B): una nota de estudio que
/// queda adentro y las tarjetas de repaso de lo que tiene. Se elige qué hacer
/// y se ve cómo va; mientras corre no se cierra por accidente.
class FillNotebookSheet extends ConsumerWidget {
  const FillNotebookSheet({required this.notebook, super.key});

  final Notebook notebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(fillNotebookControllerProvider(notebook.id));
    final controller = ref.read(
      fillNotebookControllerProvider(notebook.id).notifier,
    );
    final modelReady = ref
        .watch(notebookAiModelsProvider)
        .valueOrNull
        ?.language;
    final coverage = ref
        .watch(
          aiFlashcardsCoverageProvider(
            AiFlashcardsScope(AiFlashcardsScopeKind.notebook, notebook.id),
          ),
        )
        .valueOrNull
        ?.getRight()
        .toNullable();

    return PopScope(
      canPop: !state.running,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.fillNotebookTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.fillNotebookIntro,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('fill-notebook-guide'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: state.guide,
                onChanged: state.running
                    ? null
                    : (value) => controller.setGuide(value: value ?? false),
                title: Text(l10n.fillNotebookGuideTitle),
                subtitle: Text(l10n.fillNotebookGuideHint),
              ),
              if (state.guide)
                Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final type in DerivedNoteType.values)
                        ChoiceChip(
                          key: Key('fill-notebook-type-${type.name}'),
                          label: Text(_typeLabel(l10n, type)),
                          selected: state.type == type,
                          onSelected: state.running
                              ? null
                              : (_) => controller.setType(type),
                        ),
                    ],
                  ),
                ),
              CheckboxListTile(
                key: const Key('fill-notebook-cards'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: state.cards,
                onChanged: state.running
                    ? null
                    : (value) => controller.setCards(value: value ?? false),
                title: Text(l10n.fillNotebookCardsTitle),
                subtitle: Text(
                  [
                    l10n.fillNotebookCardsHint,
                    if (coverage != null)
                      l10n.reviewAiCoverage(coverage.eligible.length),
                    if (coverage != null && coverage.eligible.isNotEmpty)
                      l10n.reviewAiCoverageWithCards(coverage.withCards.length),
                  ].join(' · '),
                ),
              ),
              if (modelReady == false) ...[
                const SizedBox(height: 8),
                _ModelMissing(l10n: l10n),
              ],
              if (state.running) ...[
                const SizedBox(height: 12),
                _Progress(state: state),
              ],
              if (state.cardsOutcome != null || state.guideOutcome != null) ...[
                const SizedBox(height: 12),
                _Results(state: state),
              ],
              const SizedBox(height: 16),
              if (state.finished)
                FilledButton(
                  key: const Key('fill-notebook-close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.fillNotebookClose),
                )
              else
                FilledButton.icon(
                  key: const Key('fill-notebook-start'),
                  onPressed: state.canStart && (modelReady ?? false)
                      ? () => controller.start(
                          guideTitle: _guideTitle(l10n, state.type),
                          model: ref.read(chatModelOptionNotifierProvider).name,
                        )
                      : null,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(l10n.fillNotebookStart),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _guideTitle(AppLocalizations l10n, DerivedNoteType type) =>
      switch (type) {
        DerivedNoteType.studyGuide => l10n.derivedNoteTitleStudyGuide(
          notebook.name,
        ),
        DerivedNoteType.openQuestions => l10n.derivedNoteTitleOpenQuestions(
          notebook.name,
        ),
        DerivedNoteType.outline => l10n.derivedNoteTitleOutline(notebook.name),
        DerivedNoteType.timeline => l10n.derivedNoteTitleTimeline(
          notebook.name,
        ),
      };

  static String _typeLabel(AppLocalizations l10n, DerivedNoteType type) =>
      switch (type) {
        DerivedNoteType.studyGuide => l10n.derivedNoteTypeStudyGuide,
        DerivedNoteType.openQuestions => l10n.derivedNoteTypeOpenQuestions,
        DerivedNoteType.outline => l10n.derivedNoteTypeOutline,
        DerivedNoteType.timeline => l10n.derivedNoteTypeTimeline,
      };
}

/// Falta bajar el modelo de lenguaje: sin él no hay nota ni tarjetas.
class _ModelMissing extends StatelessWidget {
  const _ModelMissing({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.download_for_offline_outlined, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.derivedNoteModelRequired)),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(RoutePaths.chatModel);
            },
            child: Text(l10n.derivedNoteDownloadAction),
          ),
        ],
      ),
    );
  }
}

/// Cómo va: las tarjetas se piden en el acto; la nota se lee por partes.
class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final FillNotebookState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final total = state.partsTotal;
    return Column(
      key: const Key('fill-notebook-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: total > 0 ? state.partsRead / total : null,
        ),
        const SizedBox(height: 6),
        Text(
          total > 0
              ? l10n.fillNotebookReading(state.partsRead, total)
              : l10n.fillNotebookPreparing,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Qué quedó hecho.
class _Results extends StatelessWidget {
  const _Results({required this.state});

  final FillNotebookState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cards = state.cardsOutcome;
    final guide = state.guideOutcome;

    Widget line(
      IconData icon,
      String text, {
      Widget? action,
      bool bad = false,
    }) {
      final scheme = Theme.of(context).colorScheme;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 18,
              color: bad ? scheme.error : scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          if (action != null) action,
        ],
      );
    }

    return Container(
      key: const Key('fill-notebook-results'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (cards != null)
            switch (cards) {
              FillCardsOutcome(:final failure?) => line(
                Icons.error_outline,
                failure.localizedMessage(l10n),
                bad: true,
              ),
              FillCardsOutcome(nothingToMake: true) => line(
                Icons.info_outline,
                l10n.fillNotebookCardsNothing,
              ),
              FillCardsOutcome(alreadyHadAll: true) => line(
                Icons.check_circle_outline,
                l10n.fillNotebookCardsAlreadyHad,
              ),
              FillCardsOutcome(:final queued) => line(
                Icons.style_outlined,
                l10n.fillNotebookCardsQueued(queued),
              ),
            },
          if (guide != null) _guideLine(context, l10n, guide, line),
        ],
      ),
    );
  }

  Widget _guideLine(
    BuildContext context,
    AppLocalizations l10n,
    FillGuideOutcome guide,
    Widget Function(IconData, String, {Widget? action, bool bad}) line,
  ) {
    final failure = guide.failure;
    if (failure != null) {
      return line(
        Icons.error_outline,
        failure is ValidationFailure
            ? l10n.fillNotebookGuideNothingToCite
            : failure.localizedMessage(l10n),
        bad: true,
      );
    }
    final result = guide.result!;
    final note = result.note;
    return line(
      Icons.description_outlined,
      result.inNotebook == false
          ? l10n.fillNotebookGuideElsewhere(note.title)
          : l10n.fillNotebookGuideDone(note.title),
      action: TextButton(
        key: const Key('fill-notebook-view-note'),
        onPressed: () {
          Navigator.of(context).pop();
          context.push(RoutePaths.itemDetail(note.id));
        },
        child: Text(l10n.derivedNoteViewAction),
      ),
    );
  }
}
