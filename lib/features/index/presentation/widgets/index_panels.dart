import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/presentation/index_opening.dart';
import 'package:sinapsis/features/index/presentation/providers/index_providers.dart';
import 'package:sinapsis/features/index/presentation/providers/index_view.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Por tema · Por documento» y «Niveles: 1 · 2 · 3 · Todo», arriba del
/// árbol. Se van con él al desplazarse: en un teléfono con la letra grande,
/// el lugar es para el índice.
class IndexControls extends ConsumerWidget {
  const IndexControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final arrangement = ref.watch(
      indexViewProvider.select((v) => v.arrangement),
    );
    final depth = ref.watch(indexViewProvider.select((v) => v.depth));
    final controller = ref.read(indexViewProvider.notifier);

    String levelLabel(IndexDepth depth) =>
        depth.levels?.toString() ?? l10n.f46P3LevelsAll;
    String levelHint(IndexDepth depth) => switch (depth.levels) {
      final levels? => l10n.f46P3LevelSemantics(levels),
      null => l10n.f46P3LevelsAllSemantics,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in [
                (IndexArrangement.byTopic, l10n.f46P3ByTopic),
                (IndexArrangement.byDocument, l10n.f46P3ByDocument),
              ])
                ChoiceChip(
                  key: ValueKey('index-arrangement-${value.name}'),
                  label: Text(label),
                  selected: arrangement == value,
                  onSelected: (_) => controller.arrange(value),
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 2),
                child: Text(
                  l10n.f46P3Levels,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final value in IndexDepth.values)
                ChoiceChip(
                  key: ValueKey('index-depth-${value.name}'),
                  label: Text(levelLabel(value)),
                  tooltip: levelHint(value),
                  showCheckmark: false,
                  selected: depth == value,
                  onSelected: (_) => controller.showDepth(value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// La línea discreta de cómo va el relleno (F46, decisión F): mientras se
/// indexa lo que ya estaba procesado, cuánto falta; cuando termina, se va.
class IndexProgressLine extends ConsumerWidget {
  const IndexProgressLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final progress = ref.watch(indexProgressProvider).valueOrNull;
    final showing = progress != null && !progress.isComplete;

    Widget line(IndexProgress progress) {
      final documentsLeft = progress.indexedDocuments < progress.documents;
      final text = documentsLeft
          ? l10n.f46P3Progress(progress.indexedDocuments, progress.documents)
          : l10n.f46P3ProgressImages(progress.untitledImages);
      return Semantics(
        key: const Key('index-progress'),
        liveRegion: true,
        label: text,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                text,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                minHeight: 2,
                borderRadius: BorderRadius.circular(1),
                value: documentsLeft && progress.documents > 0
                    ? progress.indexedDocuments / progress.documents
                    : null,
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: showing ? line(progress) : const SizedBox(width: double.infinity),
    );
  }
}

/// Lo que se abre al costado del Índice: el texto de [opening] en el lector
/// único, con ✕ para cerrarlo. El paso 4 le pasa al lector el lugar de la
/// entrada ([IndexOpening.entry]).
typedef IndexReaderBuilder =
    Widget Function(IndexOpening opening, VoidCallback onClose);

/// Cómo se arma el panel de la derecha. Las pruebas de la pantalla lo
/// cambian por uno que no necesita el lector entero.
final indexReaderBuilderProvider = Provider<IndexReaderBuilder>(
  (ref) =>
      (opening, onClose) => ProcessedReaderScreen(
        key: ValueKey('index-reader-${opening.documentId}'),
        kind: StudyCreationKind.fullText,
        documentIds: [opening.documentId],
        onClose: onClose,
      ),
);

/// El panel de la derecha en una pantalla ancha: el documento abierto, o
/// qué hacer para abrir uno.
class IndexDocumentPane extends ConsumerWidget {
  const IndexDocumentPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selection = ref.watch(indexSelectionProvider);
    if (selection == null) {
      return EmptyStateView(
        key: const Key('index-pane-empty'),
        icon: Icons.chrome_reader_mode_outlined,
        title: l10n.f46P3PaneEmptyTitle,
        message: l10n.f46P3PaneEmptyMessage,
      );
    }
    return ref.watch(indexReaderBuilderProvider)(
      selection,
      () => ref.read(indexSelectionProvider.notifier).state = null,
    );
  }
}
