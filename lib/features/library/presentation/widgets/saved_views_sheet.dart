import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/saved_view.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja de vistas guardadas (F16, D4): guardar la vista actual con
/// nombre, y elegir una ya guardada para aplicarla —las fijadas primero,
/// como el acceso rápido que «fijarla en la navegación» pide—.
///
/// [currentQuery] y [currentViewMode] son lo que se guarda si se toca
/// «Guardar la vista actual»: la pantalla los conoce —son su propio
/// estado—, la hoja no.
Future<void> showSavedViewsSheet(
  BuildContext context,
  WidgetRef ref, {
  required LibraryQuery currentQuery,
  required LibraryViewMode currentViewMode,
  required void Function(LibraryViewMode) onApplyViewMode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _SavedViewsSheet(
      currentQuery: currentQuery,
      currentViewMode: currentViewMode,
      onApplyViewMode: onApplyViewMode,
    ),
  );
}

class _SavedViewsSheet extends ConsumerWidget {
  const _SavedViewsSheet({
    required this.currentQuery,
    required this.currentViewMode,
    required this.onApplyViewMode,
  });

  final LibraryQuery currentQuery;
  final LibraryViewMode currentViewMode;
  final void Function(LibraryViewMode) onApplyViewMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final views = ref.watch(savedViewsProvider).valueOrNull ?? const [];
    final pinned = [
      for (final view in views)
        if (view.pinned) view,
    ];
    final rest = [
      for (final view in views)
        if (!view.pinned) view,
    ];

    void apply(SavedView view) {
      ref.read(libraryQueryNotifierProvider.notifier).apply(view.query);
      onApplyViewMode(view.viewMode);
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n.libraryViewsAction), dense: true),
            ListTile(
              leading: const Icon(Icons.add_outlined),
              title: Text(l10n.libraryViewsSaveCurrent),
              onTap: () => _saveCurrent(context, ref),
            ),
            if (views.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Text(
                  l10n.libraryViewsEmpty,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final view in [...pinned, ...rest])
                      _SavedViewTile(
                        key: Key('saved-view-${view.id}'),
                        view: view,
                        onTap: () => apply(view),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCurrent(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askViewName(context, l10n);
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    await ref
        .read(savedViewRepositoryProvider)
        .create(
          name: name.trim(),
          query: currentQuery,
          viewMode: currentViewMode,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.libraryViewsSavedConfirmation(name.trim())),
        ),
      );
  }

  Future<String?> _askViewName(BuildContext context, AppLocalizations l10n) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.libraryViewsSaveDialogTitle),
        content: TextField(
          key: const Key('saved-view-name-field'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.libraryViewsSaveDialogHint,
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('saved-view-confirm-save'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.libraryViewsSaveAction),
          ),
        ],
      ),
    );
  }
}

class _SavedViewTile extends ConsumerWidget {
  const _SavedViewTile({required this.view, required this.onTap, super.key});

  final SavedView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return ListTile(
      leading: IconButton(
        icon: Icon(view.pinned ? Icons.star : Icons.star_border_outlined),
        tooltip: view.pinned
            ? l10n.libraryViewsUnpinTooltip
            : l10n.libraryViewsPinTooltip,
        onPressed: () => ref
            .read(savedViewRepositoryProvider)
            .setPinned(view.id, pinned: !view.pinned),
      ),
      title: Text(view.name),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.libraryViewsDeleteTooltip,
        onPressed: () => ref.read(savedViewRepositoryProvider).delete(view.id),
      ),
      onTap: onTap,
    );
  }
}
