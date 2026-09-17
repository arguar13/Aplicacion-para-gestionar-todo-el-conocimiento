import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/explorer/domain/entities/folder.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';
import 'package:sinapsis/features/explorer/presentation/widgets/folder_picker_sheet.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El Explorador: lo ya procesado, organizado en carpetas al estilo de un
/// explorador de archivos.
///
/// A diferencia de la Biblioteca —todo lo guardado, en cualquier estado,
/// filtrable por tipo y etiqueta— acá solo entra lo que ya terminó de
/// procesarse (`ProcessingState.ready`): esto es la vitrina de resultados,
/// no la cola de trabajo. Un elemento que no se llevó todavía a ninguna
/// carpeta aparece igual, en la raíz, para que nada quede inalcanzable
/// desde acá — el mismo criterio que un explorador de archivos de verdad,
/// donde un archivo siempre vive en algún lado, aunque sea el escritorio.
class ExplorerScreen extends ConsumerStatefulWidget {
  const ExplorerScreen({super.key});

  @override
  ConsumerState<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends ConsumerState<ExplorerScreen> {
  /// `null` es la raíz. Estado local y no de router: navegar la jerarquía es
  /// un ida y vuelta rápido dentro de la misma pestaña, no algo que merezca
  /// su propia URL — a diferencia del detalle de un elemento, que sí puede
  /// llegar por un enlace directo.
  String? _currentFolderId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final folders =
        ref.watch(allFoldersProvider).valueOrNull ?? const <Folder>[];
    final itemIds = ref
        .watch(folderItemIdsProvider(_currentFolderId))
        .valueOrNull;
    final allItems = ref
        .watch(libraryItemsProvider(const LibraryQuery()))
        .valueOrNull;

    final path = _pathTo(folders, _currentFolderId);
    final subfolders =
        folders.where((f) => f.parentId == _currentFolderId).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    final items = (itemIds == null || allItems == null)
        ? null
        : allItems
              .where(
                (i) =>
                    itemIds.contains(i.id) &&
                    i.processingState == ProcessingState.ready,
              )
              .toList();

    return Scaffold(
      // Sin `title`: el breadcrumb de abajo ya dice "Explorador" en la raíz
      // y la carpeta actual en cualquier otro nivel — repetirlo en la barra
      // sería el mismo texto dos veces, una encima de la otra.
      appBar: AppBar(
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _Breadcrumb(
            path: path,
            onSelect: (id) => setState(() => _currentFolderId = id),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createFolder(context),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: Text(l10n.explorerNewFolder),
      ),
      body: (itemIds == null || allItems == null)
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context, subfolders: subfolders, items: items!),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required List<Folder> subfolders,
    required List<KnowledgeItem> items,
  }) {
    final l10n = AppLocalizations.of(context)!;

    if (subfolders.isEmpty && items.isEmpty) {
      return EmptyStateView(
        icon: Icons.folder_open_outlined,
        title: _currentFolderId == null
            ? l10n.explorerEmptyRootTitle
            : l10n.explorerEmptyFolderMessage,
        message: _currentFolderId == null
            ? l10n.explorerEmptyRootMessage
            : null,
        actionLabel: _currentFolderId == null ? l10n.explorerNewFolder : null,
        onAction: _currentFolderId == null
            ? () => _createFolder(context)
            : null,
      );
    }

    return CustomScrollView(
      slivers: [
        if (subfolders.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            sliver: SliverToBoxAdapter(
              child: _SectionLabel(l10n.explorerFoldersSectionTitle),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 72,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _FolderTile(
                  folder: subfolders[index],
                  onOpen: () =>
                      setState(() => _currentFolderId = subfolders[index].id),
                  onRename: () => _renameFolder(context, subfolders[index]),
                  onDelete: () => _deleteFolder(context, subfolders[index]),
                ),
                childCount: subfolders.length,
              ),
            ),
          ),
        ],
        if (items.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            sliver: SliverToBoxAdapter(
              child: _SectionLabel(l10n.explorerItemsSectionTitle),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return LibraryItemCard(
                  item: item,
                  onTap: () => context.push(RoutePaths.itemDetail(item.id)),
                  onLongPress: () => _showItemFolderActions(context, item),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  List<Folder> _pathTo(List<Folder> all, String? folderId) {
    if (folderId == null) return const [];
    final byId = {for (final f in all) f.id: f};
    final path = <Folder>[];
    var current = byId[folderId];
    while (current != null) {
      path.insert(0, current);
      current = current.parentId == null ? null : byId[current.parentId];
    }
    return path;
  }

  Future<void> _createFolder(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final name = await showDialog<String>(
      context: context,
      builder: (context) => _FolderNameDialog(
        title: l10n.explorerNewFolder,
        confirmLabel: l10n.commonCreate,
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    final result = await ref
        .read(explorerRepositoryProvider)
        .createFolder(name: name, parentId: _currentFolderId);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) {},
    );
  }

  Future<void> _renameFolder(BuildContext context, Folder folder) async {
    final l10n = AppLocalizations.of(context)!;

    final name = await showDialog<String>(
      context: context,
      builder: (context) => _FolderNameDialog(
        title: l10n.explorerRenameFolder,
        confirmLabel: l10n.commonRename,
        initialValue: folder.name,
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    final result = await ref
        .read(explorerRepositoryProvider)
        .renameFolder(id: folder.id, name: name);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) {},
    );
  }

  Future<void> _deleteFolder(BuildContext context, Folder folder) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.explorerDeleteFolderConfirm(folder.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(explorerRepositoryProvider).deleteFolder(folder.id);
  }

  Future<void> _showItemFolderActions(
    BuildContext context,
    KnowledgeItem item,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final currentFolderId = _currentFolderId;

    final action = await showModalBottomSheet<_ItemFolderAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(l10n.explorerAddToFolder),
              onTap: () =>
                  Navigator.of(context).pop(const _ItemFolderAction.add()),
            ),
            if (currentFolderId != null)
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: Text(l10n.explorerRemoveFromFolder),
                onTap: () =>
                    Navigator.of(context).pop(const _ItemFolderAction.remove()),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _AddAction():
        await _addToFolder(context, item);
      case _RemoveAction():
        await _removeFromCurrentFolder(context, item);
    }
  }

  Future<void> _addToFolder(BuildContext context, KnowledgeItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final folders =
        ref.read(allFoldersProvider).valueOrNull ?? const <Folder>[];

    final chosen = await showFolderPickerSheet(context, folders: folders);
    if (chosen == null || !context.mounted) return;

    final result = await ref
        .read(explorerRepositoryProvider)
        .addItemToFolder(itemId: item.id, folderId: chosen);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) {
        final folderName = folders
            .where((f) => f.id == chosen)
            .firstOrNull
            ?.name;
        if (folderName == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.explorerItemAddedToFolder(folderName))),
          );
      },
    );
  }

  Future<void> _removeFromCurrentFolder(
    BuildContext context,
    KnowledgeItem item,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final folderId = _currentFolderId;
    if (folderId == null) return;

    final result = await ref
        .read(explorerRepositoryProvider)
        .removeItemFromFolder(itemId: item.id, folderId: folderId);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.explorerItemRemovedFromFolder)),
        ),
    );
  }
}

sealed class _ItemFolderAction {
  const _ItemFolderAction();
  const factory _ItemFolderAction.add() = _AddAction;
  const factory _ItemFolderAction.remove() = _RemoveAction;
}

class _AddAction extends _ItemFolderAction {
  const _AddAction();
}

class _RemoveAction extends _ItemFolderAction {
  const _RemoveAction();
}

/// Las migas de pan: la raíz y cada carpeta hasta la actual, tocables para
/// volver a cualquiera de ellas de un salto.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.path, required this.onSelect});

  final List<Folder> path;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _BreadcrumbChip(
            label: l10n.explorerRootBreadcrumb,
            isCurrent: path.isEmpty,
            onTap: () => onSelect(null),
          ),
          for (final folder in path) ...[
            Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceVariant),
            _BreadcrumbChip(
              label: folder.name,
              isCurrent: folder.id == path.last.id,
              onTap: () => onSelect(folder.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    required this.label,
    required this.isCurrent,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isCurrent ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: isCurrent ? colors.onSurface : colors.primary,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Una carpeta dentro de la grilla: tocarla entra, el menú renombra o
/// elimina.
class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final Folder folder;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
          child: Row(
            children: [
              Icon(Icons.folder, color: colors.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<VoidCallback>(
                icon: const Icon(Icons.more_vert, size: 18),
                tooltip: l10n.libraryItemMenuTooltip,
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: onRename,
                    child: ListTile(
                      leading: const Icon(Icons.drive_file_rename_outline),
                      title: Text(l10n.explorerRenameFolder),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: onDelete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: colors.error),
                      title: Text(
                        l10n.explorerDeleteFolder,
                        style: TextStyle(color: colors.error),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
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

/// Un diálogo con un solo campo de texto, para crear o renombrar una
/// carpeta.
///
/// Mismo criterio que `_TextPromptDialog` en `library_screen.dart`: el
/// controller vive atado al `State` de este widget, no al método que abre el
/// diálogo, para no destruirlo mientras la ruta todavía está animando su
/// salida.
class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialValue,
  });

  final String title;
  final String confirmLabel;
  final String? initialValue;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: l10n.explorerFolderName),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
