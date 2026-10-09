import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_exception.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/presentation/providers/anki_import_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Traer un mazo de Anki (`.apkg`) a Sinapsis (F31, decisión 73): elegir el
/// archivo, ver qué trae, elegir dónde cae, e importar con su calendario.
class AnkiImportScreen extends ConsumerWidget {
  const AnkiImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(ankiImportProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.ankiImportTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: switch (state) {
              AnkiImportIdle() => _idle(context, ref, l10n),
              AnkiImportReading() => _busy(l10n.ankiImportReading, null),
              AnkiImportReady() => _ready(context, ref, l10n, state),
              AnkiImportRunning(:final done, :final total) => _busy(
                l10n.ankiImportRunning,
                total == 0 ? null : done / total,
                detail: total == 0
                    ? null
                    : l10n.ankiImportProgress(done, total),
              ),
              AnkiImportDone() => _done(context, ref, l10n, state),
              AnkiImportFailed() => _failed(context, ref, l10n, state),
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _idle(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    return [
      Text(l10n.ankiImportIntro, style: theme.textTheme.bodyLarge),
      const SizedBox(height: 12),
      Text(
        l10n.ankiImportHowTo,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 24),
      if (kIsWeb)
        Text(l10n.ankiImportWebUnavailable)
      else
        FilledButton.icon(
          key: const Key('anki-import-pick'),
          onPressed: () => ref.read(ankiImportProvider.notifier).pickAndRead(),
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(l10n.ankiImportPick),
        ),
    ];
  }

  List<Widget> _busy(String label, double? value, {String? detail}) => [
    const SizedBox(height: 48),
    LinearProgressIndicator(value: value),
    const SizedBox(height: 16),
    Text(label, textAlign: TextAlign.center),
    if (detail != null) ...[
      const SizedBox(height: 4),
      Text(detail, textAlign: TextAlign.center),
    ],
  ];

  List<Widget> _ready(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AnkiImportReady state,
  ) {
    final theme = Theme.of(context);
    final preview = state.preview;
    final notifier = ref.read(ankiImportProvider.notifier);
    final kinds = preview.kinds;

    Widget line(String text, {IconData icon = Icons.check, Color? color}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        );

    final warning = theme.colorScheme.tertiary;
    return [
      Text(l10n.ankiImportPreviewTitle, style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.ankiImportSummary(preview.cardCount, preview.deckCount),
                key: const Key('anki-import-summary'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              if (kinds.basic > 0) line(l10n.ankiImportKindBasic(kinds.basic)),
              if (kinds.reversed > 0)
                line(l10n.ankiImportKindReversed(kinds.reversed)),
              if (kinds.cloze > 0) line(l10n.ankiImportKindCloze(kinds.cloze)),
              if (kinds.typed > 0) line(l10n.ankiImportKindTyped(kinds.typed)),
              if (kinds.multipleChoice > 0)
                line(l10n.ankiImportKindChoice(kinds.multipleChoice)),
              const Divider(height: 24),
              line(
                l10n.ankiImportStages(
                  preview.newCards,
                  preview.learningCards,
                  preview.reviewCards,
                ),
                icon: Icons.event_repeat_outlined,
              ),
              if (preview.suspendedCards > 0)
                line(
                  l10n.ankiImportSuspended(preview.suspendedCards),
                  icon: Icons.pause_circle_outline,
                ),
              if (preview.postponedCards > 0)
                line(
                  l10n.ankiImportPostponed(preview.postponedCards),
                  icon: Icons.snooze_outlined,
                ),
              if (preview.hasUnimportedMedia)
                line(
                  l10n.ankiImportMediaWarning(
                    preview.imageCount,
                    preview.audioCount,
                    preview.videoCount,
                  ),
                  icon: Icons.image_not_supported_outlined,
                  color: warning,
                ),
              if (preview.hasFilteredDeck)
                line(
                  l10n.ankiImportFilteredWarning(preview.filteredDeckCards),
                  icon: Icons.filter_alt_outlined,
                  color: warning,
                ),
              if (preview.skippedCards > 0)
                line(
                  l10n.ankiImportSkipped(preview.skippedCards),
                  icon: Icons.info_outline,
                  color: warning,
                ),
              for (final text in preview.warnings)
                line(text, icon: Icons.info_outline, color: warning),
              if (preview.alreadyImported > 0)
                line(
                  l10n.ankiImportAlready(preview.alreadyImported),
                  icon: Icons.done_all,
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(l10n.ankiImportDestinationTitle, style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      RadioGroup<AnkiImportDestination>(
        groupValue: state.destination,
        onChanged: (value) {
          if (value != null) notifier.chooseDestination(value);
        },
        child: Column(
          children: [
            RadioListTile<AnkiImportDestination>(
              key: const Key('anki-import-dest-per-deck'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.ankiImportDestPerDeck),
              subtitle: Text(l10n.ankiImportDestPerDeckHint),
              value: AnkiImportDestination.perDeck,
            ),
            RadioListTile<AnkiImportDestination>(
              key: const Key('anki-import-dest-single'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.ankiImportDestSingle),
              subtitle: Text(l10n.ankiImportDestSingleHint),
              value: AnkiImportDestination.singleItem,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (preview.toImport > 0)
        FilledButton(
          key: const Key('anki-import-start'),
          onPressed: notifier.start,
          child: Text(l10n.ankiImportStart(preview.toImport)),
        )
      else
        Text(l10n.ankiImportNothingNew, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      TextButton(
        key: const Key('anki-import-pick-other'),
        onPressed: notifier.pickAndRead,
        child: Text(l10n.ankiImportChooseOther),
      ),
    ];
  }

  List<Widget> _done(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AnkiImportDone state,
  ) {
    final theme = Theme.of(context);
    final report = state.report;
    return [
      const SizedBox(height: 24),
      Icon(
        Icons.check_circle_outline,
        size: 56,
        color: theme.colorScheme.primary,
      ),
      const SizedBox(height: 12),
      Text(
        l10n.ankiImportDoneTitle,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        l10n.ankiImportDoneCards(report.cardsImported),
        key: const Key('anki-import-done-cards'),
        textAlign: TextAlign.center,
      ),
      if (report.alreadyImported > 0) ...[
        const SizedBox(height: 4),
        Text(
          l10n.ankiImportAlready(report.alreadyImported),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('anki-import-go-review'),
        onPressed: () => context.go(RoutePaths.review),
        child: Text(l10n.ankiImportGoReview),
      ),
    ];
  }

  List<Widget> _failed(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AnkiImportFailed state,
  ) {
    final theme = Theme.of(context);
    final exception = state.exception;
    final failure = state.failure;
    return [
      const SizedBox(height: 24),
      Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
      const SizedBox(height: 12),
      Text(
        l10n.ankiImportFailedTitle,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      // El mensaje del lector ya viene en español y dice qué hacer (por
      // ejemplo, exportar con «Compatibilidad con versiones antiguas»).
      Text(
        exception?.message ?? failure?.localizedMessage(l10n) ?? '',
        key: const Key('anki-import-error'),
        textAlign: TextAlign.center,
      ),
      if (exception == null) ...[
        const SizedBox(height: 4),
        Text(
          l10n.ankiImportFailedWrite,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
      if (exception?.failure == AnkiImportFailure.newFormatOnly) ...[
        const SizedBox(height: 12),
        Text(
          l10n.ankiImportHowTo,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('anki-import-try-again'),
        onPressed: () {
          ref.read(ankiImportProvider.notifier)
            ..reset()
            ..pickAndRead();
        },
        child: Text(l10n.ankiImportTryAgain),
      ),
    ];
  }
}
