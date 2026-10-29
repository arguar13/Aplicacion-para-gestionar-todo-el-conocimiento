import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/widgets/scope_creations_section.dart';
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
///
/// Arriba de los documentos, **«En Repasar»** (F43, M6): lo creado con el
/// cuaderno como recorte, sus tarjetas para hoy con «Empezar» y «Crear en
/// Repasar», con el cuaderno ya elegido. Va primero porque es lo del cuaderno
/// entero —sus documentos juntos—, y la lista de abajo puede ser larga.
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
      body: Column(
        children: [
          if (notebook.showsEmptiedNotice)
            _EmptiedNotice(
              notebook: notebook,
              onDismiss: () => ref
                  .read(notebookRepositoryProvider)
                  .dismissEmptiedNotice(notebook.id),
            ),
          Expanded(child: _NotebookItemsPanel(notebook: notebook)),
        ],
      ),
      floatingActionButton: notebook.mode == NotebookMode.manual
          ? FloatingActionButton(
              // Sin héroe: el botón no vuela a ninguna parte, y con el de la
              // Biblioteca —otra pestaña, también a la vista para el
              // navegador principal— repetiría la etiqueta por defecto al
              // abrir encima un visor o un documento.
              heroTag: null,
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

    // Una sola lista que se desplaza: con letra grande, la sección no queda
    // fija tapando los documentos.
    return CustomScrollView(
      key: const Key('notebook-detail-list'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(
            child: ScopeCreationsSection(
              scope: CreationScope.notebook(notebook.id),
              // Vacío, no hay sobre qué crear: la sección aparece solo si ya
              // se creó algo, para no esconderlo.
              hideWhenEmpty: documents.isEmpty,
            ),
          ),
        ),
        if (documents.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyNotebook(mode: notebook.mode),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: SliverList.builder(
              itemCount: documents.length,
              itemBuilder: (context, index) =>
                  _MemberTile(notebook: notebook, document: documents[index]),
            ),
          ),
      ],
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

/// El aviso de un cuaderno que se vació al llegar F41 (v46): por qué quedó
/// vacío y cómo volver a llenarlo. Se ve mientras el cuaderno tenga la marca
/// (`Notebook.showsEmptiedNotice`) y «Entendido» la saca para siempre.
///
/// Es un aviso tranquilo, en la superficie y con un ícono que informa, no una
/// alarma: no se perdió nada —la Biblioteca sigue entera—, cambió de qué se
/// arma un cuaderno.
class _EmptiedNotice extends StatelessWidget {
  const _EmptiedNotice({required this.notebook, required this.onDismiss});

  final Notebook notebook;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const Key('notebook-emptied-notice'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.info_outline,
                    color: scheme.onSecondaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.notebookEmptiedTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                notebook.mode == NotebookMode.manual
                    ? l10n.notebookEmptiedManual
                    : l10n.notebookEmptiedQuery,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    key: const Key('notebook-emptied-dismiss'),
                    onPressed: onDismiss,
                    child: Text(l10n.notebookEmptiedDismiss),
                  ),
                  FilledButton.tonal(
                    key: const Key('notebook-emptied-inbox'),
                    onPressed: () => openInboxToTriage(context),
                    child: Text(l10n.notebookDetailGoToInbox),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El vacío de un cuaderno (F41, paso 5): se llena con documentos procesados,
/// y lleva a donde se consiguen —«Procesado», a elegir, y la Bandeja, a
/// triar—. El mismo vacío de toda la app (`EmptyStateView`).
class _EmptyNotebook extends StatelessWidget {
  const _EmptyNotebook({required this.mode});

  final NotebookMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return EmptyStateView(
      key: const Key('notebook-detail-empty'),
      icon: Icons.auto_stories_outlined,
      title: l10n.notebookDetailEmptyTitle,
      message: mode == NotebookMode.manual
          ? l10n.notebookDetailEmptyManual
          : l10n.notebookDetailEmptyQuery,
      actionLabel: l10n.notebookDetailGoToProcessed,
      onAction: () => openProcessedList(context),
      secondary: OutlinedButton.icon(
        key: const Key('notebook-empty-inbox'),
        onPressed: () => openInboxToTriage(context),
        icon: const Icon(Icons.inbox_outlined),
        label: Text(l10n.notebookDetailGoToInbox),
      ),
    );
  }
}
