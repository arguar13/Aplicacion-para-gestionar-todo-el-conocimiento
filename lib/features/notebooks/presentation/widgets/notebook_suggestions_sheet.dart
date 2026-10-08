import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_suggestions_controller.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre los cuadernos sugeridos (F30). Devuelve los cuadernos que se crearon;
/// vacío si se cerró sin crear ninguno.
Future<List<Notebook>> showNotebookSuggestionsSheet(
  BuildContext context,
) async {
  final created = await showModalBottomSheet<List<Notebook>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const NotebookSuggestionsSheet(),
  );
  return created ?? const [];
}

/// La hoja de cuadernos sugeridos (F30, decisión B): los temas y las
/// etiquetas que juntan elementos de sobra, para que la persona elija cuáles
/// crear. Cada uno nace por consulta, así que se mantiene al día solo.
class NotebookSuggestionsSheet extends ConsumerStatefulWidget {
  const NotebookSuggestionsSheet({super.key});

  @override
  ConsumerState<NotebookSuggestionsSheet> createState() =>
      _NotebookSuggestionsSheetState();
}

class _NotebookSuggestionsSheetState
    extends ConsumerState<NotebookSuggestionsSheet> {
  var _creating = false;

  @override
  void initState() {
    super.initState();
    // La IA nombra mientras la persona ya está mirando la lista.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(notebookSuggestionsControllerProvider.notifier).nameWithAi();
      }
    });
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    final created = await ref
        .read(notebookSuggestionsControllerProvider.notifier)
        .create();
    if (!mounted) return;
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(notebookSuggestionsControllerProvider);
    final controller = ref.read(notebookSuggestionsControllerProvider.notifier);
    final languageReady = ref
        .watch(notebookAiModelsProvider)
        .valueOrNull
        ?.language;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.suggestedNotebooksTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Text(
            state.drafts.isEmpty
                ? l10n.suggestedNotebooksEmpty
                : l10n.suggestedNotebooksIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        if (state.naming)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Text(l10n.suggestedNotebooksNaming, style: muted),
              ],
            ),
          )
        else if (state.namingFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              l10n.suggestedNotebooksNamingFailed,
              style: muted?.copyWith(color: scheme.error),
            ),
          )
        else if (languageReady == false && state.drafts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(l10n.suggestedNotebooksNoModel, style: muted),
          ),
        if (state.drafts.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                key: const Key('suggested-notebooks-toggle-all'),
                onPressed: controller.toggleAll,
                child: Text(
                  state.checkedCount == state.drafts.length
                      ? l10n.suggestedNotebooksSelectNone
                      : l10n.suggestedNotebooksSelectAll,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: state.drafts.length,
              itemBuilder: (context, index) => _DraftTile(
                draft: state.drafts[index],
                onToggle: () =>
                    controller.toggle(state.drafts[index].suggestion.key),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: FilledButton.icon(
              key: const Key('suggested-notebooks-create'),
              onPressed: _creating || state.checkedCount == 0 ? null : _create,
              icon: const Icon(Icons.auto_stories_outlined),
              label: Text(l10n.suggestedNotebooksCreate(state.checkedCount)),
            ),
          ),
        ] else
          const SizedBox(height: 24),
      ],
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft, required this.onToggle});

  final SuggestedNotebookDraft draft;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final topic = draft.suggestion.topic;
    final kind = switch (topic.kind) {
      NotebookTopicKind.space => l10n.suggestedNotebooksKindSpace(
        topic.itemCount,
      ),
      NotebookTopicKind.tag => l10n.suggestedNotebooksKindTag(topic.itemCount),
    };

    return CheckboxListTile(
      key: Key('suggested-notebook-${draft.suggestion.key}'),
      value: draft.checked,
      onChanged: (_) => onToggle(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      secondary: Icon(
        topic.kind == NotebookTopicKind.space
            ? Icons.folder_outlined
            : Icons.label_outline,
      ),
      title: Text(draft.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (draft.description != null)
            Text(
              draft.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            draft.named ? '$kind · ${topic.name}' : kind,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
