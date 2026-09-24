import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/widgets/create_notebook_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Todos los cuadernos (F16, D1): un subconjunto con nombre de la bóveda,
/// manual o por consulta guardada.
class NotebooksScreen extends ConsumerWidget {
  const NotebooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navNotebooks)),
      body: notebooks.isEmpty
          ? _EmptyState(l10n: l10n)
          : ListView.builder(
              itemCount: notebooks.length,
              itemBuilder: (context, index) =>
                  _NotebookTile(notebook: notebooks[index]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.notebooksCreateAction),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final notebook = await showCreateNotebookDialog(context);
    if (notebook == null || !context.mounted) return;
    unawaited(context.push(RoutePaths.notebookDetail(notebook.id)));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.notebooksEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.notebooksEmptyMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotebookTile extends ConsumerWidget {
  const _NotebookTile({required this.notebook});

  final Notebook notebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return ListTile(
      key: Key('notebook-${notebook.id}'),
      leading: Icon(
        notebook.mode == NotebookMode.manual
            ? Icons.auto_stories_outlined
            : Icons.saved_search_outlined,
      ),
      title: Text(notebook.name),
      subtitle: Text(
        notebook.mode == NotebookMode.manual
            ? l10n.notebooksModeManual
            : l10n.notebooksModeQuery,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.notebooksDeleteTooltip,
        onPressed: () => _delete(context, ref),
      ),
      onTap: () => context.push(RoutePaths.notebookDetail(notebook.id)),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.notebooksDeleteConfirmTitle(notebook.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('notebook-confirm-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.notebooksDeleteTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(notebookRepositoryProvider).delete(notebook.id);
  }
}
