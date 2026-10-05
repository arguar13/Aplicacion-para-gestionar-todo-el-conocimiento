import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notes/presentation/widgets/generate_derived_note_button.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_item_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El panel de un cuaderno (F16, D1): sus elementos, y en modo manual,
/// agregar y sacar sin tocar la bóveda —solo la pertenencia a este
/// cuaderno—. En modo por consulta la lista es de solo lectura: cambia sola
/// con lo que la consulta guardada trae.
class NotebookDetailScreen extends ConsumerWidget {
  const NotebookDetailScreen({required this.notebookId, super.key});

  final String notebookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notebook = ref.watch(notebookByIdProvider(notebookId)).valueOrNull;

    if (notebook == null) {
      // Se borró —acá o desde otro lado—: nada que mostrar mientras el
      // `pop` de quien borra saca de la pantalla.
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(notebook.name),
        actions: [
          GenerateDerivedNoteButton(
            sourceTitle: notebook.name,
            notebookId: notebook.id,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.notebooksRenameTooltip,
            onPressed: () => _rename(context, ref, notebook),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.notebooksDeleteTooltip,
            onPressed: () => _delete(context, ref, notebook),
          ),
        ],
      ),
      body: _NotebookItemsPanel(notebook: notebook),
      floatingActionButton: notebook.mode == NotebookMode.manual
          ? FloatingActionButton(
              onPressed: () => _addItem(context, ref, notebook),
              tooltip: l10n.notebookDetailAddItems,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Notebook notebook,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: notebook.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.notebooksRenameTooltip),
        content: TextField(
          key: const Key('notebook-rename-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('notebook-confirm-rename'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.notebooksRenameTooltip),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(notebookRepositoryProvider)
        .rename(id: notebook.id, name: name.trim());
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Notebook notebook,
  ) async {
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
    if (confirmed != true || !context.mounted) return;
    await ref.read(notebookRepositoryProvider).delete(notebook.id);
    if (context.mounted) context.pop();
  }

  Future<void> _addItem(
    BuildContext context,
    WidgetRef ref,
    Notebook notebook,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final inside =
        ref.read(notebookItemIdsProvider(notebook.id)).valueOrNull ?? const {};
    final itemIds = await showDialog<Set<String>>(
      context: context,
      builder: (context) => PickItemsDialog(
        title: l10n.notebookDetailAddItems,
        alreadyIn: inside,
      ),
    );
    if (itemIds == null || itemIds.isEmpty) return;
    await ref
        .read(notebookRepositoryProvider)
        .addItems(notebookId: notebook.id, itemIds: itemIds);
  }
}

class _NotebookItemsPanel extends ConsumerWidget {
  const _NotebookItemsPanel({required this.notebook});

  final Notebook notebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = notebook.mode == NotebookMode.query
        ? (notebook.query ?? const LibraryQuery())
        : LibraryQuery(
            ids:
                ref.watch(notebookItemIdsProvider(notebook.id)).valueOrNull ??
                const {},
          );
    final items = ref.watch(libraryItemsProvider(query)).valueOrNull;

    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.notebookDetailEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          key: Key('notebook-item-${item.id}'),
          leading: Icon(item.source.kind.icon),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: notebook.mode == NotebookMode.manual
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.notebookDetailRemoveItem,
                  onPressed: () => ref
                      .read(notebookRepositoryProvider)
                      .removeItem(notebookId: notebook.id, itemId: item.id),
                )
              : null,
          onTap: () => context.push(RoutePaths.itemDetail(item.id)),
        );
      },
    );
  }
}
