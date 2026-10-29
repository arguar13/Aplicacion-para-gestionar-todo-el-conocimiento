import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las fuentes de una creación como chips tocables (F43, M6): el cuaderno o
/// el tema sobre el que se creó, si no fue sobre un documento, y cada
/// documento que se leyó. Tocar uno abre su pantalla; uno que ya no existe lo
/// dice («Fuente borrada») y no abre nada.
///
/// Con [maxDocuments], los que no entran van en un «+N» que abre la lista
/// entera ([showCreationSources]).
class CreationSourceChips extends ConsumerWidget {
  const CreationSourceChips({
    required this.creation,
    this.maxDocuments,
    super.key,
  });

  final StudyCreation creation;
  final int? maxDocuments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scope = creation.scope;
    final sources =
        ref
            .watch(
              creationSourcesProvider(CreationSourceIds(creation.sourceIds)),
            )
            .valueOrNull ??
        const <CreationSource>[];
    final limit = maxDocuments;
    final shown = limit == null ? sources : sources.take(limit).toList();
    final hidden = sources.length - shown.length;
    final showsScope =
        scope is! AllProcessed && scope is! ProcessedDocumentScope;

    if (!showsScope && sources.isEmpty) return const SizedBox.shrink();
    return Wrap(
      key: ValueKey('creation-sources-${creation.id}'),
      spacing: 6,
      runSpacing: 6,
      children: [
        if (showsScope) _ScopeChip(scope: scope),
        for (final source in shown)
          if (source.isLive)
            _SourceChip(
              key: ValueKey('creation-source-${source.documentId}'),
              icon: Icons.description_outlined,
              label: source.title,
              onTap: () => openProcessedSource(context, source.documentId),
            )
          else
            _DeletedChip(
              key: ValueKey('creation-source-${source.documentId}'),
              label: l10n.f43StudioSourceDeleted,
            ),
        if (hidden > 0)
          _SourceChip(
            key: ValueKey('creation-sources-more-${creation.id}'),
            label: l10n.f43StudioMoreSources(hidden),
            onTap: () => unawaited(showCreationSources(context, creation)),
          ),
      ],
    );
  }
}

/// El cuaderno, el tema o el espacio sobre el que se creó.
class _ScopeChip extends ConsumerWidget {
  const _ScopeChip({required this.scope});

  final CreationScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final summary = ref.watch(creationScopeSummaryProvider(scope)).valueOrNull;
    final key = ValueKey('creation-scope-chip-${scope.storageKey}');
    if (summary == null) return const SizedBox.shrink();
    if (!summary.exists) {
      return _DeletedChip(key: key, label: l10n.f43StudioSourceDeleted);
    }
    return _SourceChip(
      key: key,
      icon: creationScopeIcon(scope),
      label: summary.name ?? l10n.f43StudioScopeAll,
      onTap: () => openCreationScope(context, scope),
    );
  }
}

/// El ícono de un recorte: el de Procesado para todo y para un documento, un
/// cuaderno, una etiqueta para un valor y una carpeta para un tema.
IconData creationScopeIcon(CreationScope scope) => switch (scope) {
  AllProcessed() => Icons.summarize_outlined,
  ProcessedDocumentScope() => Icons.description_outlined,
  NotebookScope() => Icons.menu_book_outlined,
  TopicScope() => Icons.label_outline,
  SpaceScope() => Icons.folder_outlined,
};

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: icon == null ? null : Icon(icon, size: 16),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      visualDensity: VisualDensity.compact,
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      shape: const StadiumBorder(),
      onPressed: onTap,
    );
  }
}

/// Una fuente que ya no existe: se dice, tachada y sin abrir nada.
class _DeletedChip extends StatelessWidget {
  const _DeletedChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(Icons.link_off, size: 16, color: scheme.onSurfaceVariant),
      label: Text(
        label,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      shape: const StadiumBorder(),
    );
  }
}

/// La hoja con todas las fuentes de [creation], cada una tocable.
Future<void> showCreationSources(
  BuildContext context,
  StudyCreation creation,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => _SourcesSheet(creation: creation),
);

class _SourcesSheet extends StatelessWidget {
  const _SourcesSheet({required this.creation});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        key: const Key('creation-sources-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.f43StudioSourcesTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                CreationCloseButton(tooltip: l10n.f43StudioClose),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: CreationSourceChips(creation: creation),
            ),
          ),
        ],
      ),
    );
  }
}
