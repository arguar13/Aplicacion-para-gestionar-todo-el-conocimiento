import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/presentation/notebook_navigation.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/widgets/fill_notebook_sheet.dart';
import 'package:sinapsis/features/notebooks/presentation/widgets/pick_processed_dialog.dart';
import 'package:sinapsis/features/notebooks/presentation/widgets/processed_member.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El panel de un cuaderno (F16, D1): sus documentos procesados (F41, paso 5),
/// y en modo manual, agregar y sacar sin tocar la bóveda —solo la pertenencia
/// a este cuaderno—. En modo por consulta la lista es de solo lectura: cambia
/// sola con los procesados que cumplen la consulta guardada.
///
/// Cada fila es un documento procesado —el ícono de su fuente, su título y
/// los chips de sus partes— y tocarla lo abre ([openProcessedDocument]).
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
          FillNotebookButton(notebook: notebook),
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
              tooltip: l10n.notebookPickProcessedTitle,
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
    final inside =
        ref.read(notebookItemIdsProvider(notebook.id)).valueOrNull ?? const {};
    final itemIds = await showPickProcessedDialog(context, alreadyIn: inside);
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
    final query = ref
        .watch(notebookProcessedQueryProvider(notebook.id))
        .valueOrNull;
    final documents = query == null
        ? null
        : ref.watch(processedDocumentsProvider(query)).valueOrNull;

    if (documents == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (documents.isEmpty) return _EmptyNotebook(mode: notebook.mode);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: documents.length,
      itemBuilder: (context, index) =>
          _MemberTile(notebook: notebook, document: documents[index]),
    );
  }
}

/// Un documento procesado del cuaderno: el ícono de su fuente, su título y
/// los chips de sus partes. Tocarlo lo abre; en modo manual, la «X» lo saca
/// del cuaderno sin tocarlo.
class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.notebook, required this.document});

  final Notebook notebook;
  final ProcessedDocumentSummary document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      key: Key('notebook-item-${document.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: ProcessedOriginBadge(document: document),
      // El ícono y los chips no se leen sueltos: el título dice todo junto.
      title: Semantics(
        label: processedMemberSemantics(l10n, document),
        excludeSemantics: true,
        child: Text(
          document.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ProcessedPartChips(document: document),
      ),
      trailing: notebook.mode == NotebookMode.manual
          ? IconButton(
              key: Key('notebook-remove-${document.id}'),
              icon: const Icon(Icons.close),
              tooltip: l10n.notebookDetailRemoveItem,
              onPressed: () => ref
                  .read(notebookRepositoryProvider)
                  .removeItem(notebookId: notebook.id, itemId: document.id),
            )
          : null,
      onTap: () => openProcessedDocument(context, document.id),
    );
  }
}

/// El vacío de un cuaderno (F41, paso 5): se llena con documentos procesados,
/// y lleva a donde se consiguen —«Procesado» y la Bandeja, a triar—.
class _EmptyNotebook extends StatelessWidget {
  const _EmptyNotebook({required this.mode});

  final NotebookMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            key: const Key('notebook-detail-empty'),
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.auto_stories_outlined,
                  size: 48,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.notebookDetailEmptyTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                mode == NotebookMode.manual
                    ? l10n.notebookDetailEmptyManual
                    : l10n.notebookDetailEmptyQuery,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (processedListPath case final path?)
                    FilledButton.tonalIcon(
                      key: const Key('notebook-empty-processed'),
                      onPressed: () => context.go(path),
                      icon: const Icon(Icons.article_outlined),
                      label: Text(l10n.notebookDetailGoToProcessed),
                    ),
                  OutlinedButton.icon(
                    key: const Key('notebook-empty-inbox'),
                    onPressed: () => openInboxToTriage(context),
                    icon: const Icon(Icons.inbox_outlined),
                    label: Text(l10n.notebookDetailGoToInbox),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
