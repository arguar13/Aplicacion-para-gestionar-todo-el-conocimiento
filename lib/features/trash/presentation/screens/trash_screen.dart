import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Either, Unit;
import 'package:intl/intl.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/domain/entities/trashed_item.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/trash/presentation/providers/trash_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se borró y todavía se puede restaurar (F11).
///
/// Borrar manda un elemento acá y no destruye nada: conserva el texto, los
/// vínculos, las tarjetas y el archivo original. Solo lo que se borra desde
/// esta pantalla —un elemento, o todos con «Vaciar la papelera»— se pierde de
/// verdad, y pide confirmación: es lo único irreversible que la app hace.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    TrashedItem item,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(libraryRepositoryProvider).restore(item.id);
    _report(messenger, l10n, result, l10n.trashRestored);
  }

  Future<void> _deleteForever(
    BuildContext context,
    WidgetRef ref,
    TrashedItem item,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(libraryRepositoryProvider);

    final confirmed = await _confirm(
      context,
      message: l10n.trashDeleteForeverConfirm(item.title),
      action: l10n.trashDeleteForever,
    );
    if (!confirmed) return;

    final result = await repository.purge([item.id]);
    _report(messenger, l10n, result, l10n.trashDeletedForever);
  }

  Future<void> _empty(BuildContext context, WidgetRef ref, int count) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(libraryRepositoryProvider);

    final confirmed = await _confirm(
      context,
      message: l10n.trashEmptyConfirm(count),
      action: l10n.trashEmptyAction,
    );
    if (!confirmed) return;

    final result = await repository.emptyTrash();
    _report(messenger, l10n, result, l10n.trashEmptied);
  }

  /// La pregunta antes de borrar para siempre: lo único irreversible.
  Future<bool> _confirm(
    BuildContext context, {
    required String message,
    required String action,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              action,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _report(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    Either<Failure, Unit> result,
    String success,
  ) {
    messenger.hideCurrentSnackBar();
    final failure = result.getLeft().toNullable();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure == null ? success : failure.localizedMessage(l10n),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final trash = ref.watch(trashProvider);
    final items = trash.valueOrNull ?? const <TrashedItem>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trashTitle),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.trashEmptyAction,
              onPressed: () => _empty(context, ref, items.length),
            ),
        ],
      ),
      body: trash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _CenteredMessage(text: l10n.trashLoadError),
        data: (items) => items.isEmpty
            ? const _EmptyTrash()
            : ListView.builder(
                itemCount: items.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return _Hint(text: l10n.trashHint);
                  final item = items[index - 1];
                  return _TrashTile(
                    item: item,
                    onRestore: () => _restore(context, ref, item),
                    onDeleteForever: () => _deleteForever(context, ref, item),
                  );
                },
              ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TrashTile extends StatelessWidget {
  const _TrashTile({
    required this.item,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final TrashedItem item;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final date = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).format(item.deletedAt);

    return ListTile(
      leading: Icon(
        item.sourceKind.icon,
        color: item.sourceKind.role.accent(colors),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.trashDeletedOn(date)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: l10n.trashRestore,
            onPressed: onRestore,
          ),
          IconButton(
            icon: Icon(Icons.delete_forever_outlined, color: colors.error),
            tooltip: l10n.trashDeleteForever,
            onPressed: onDeleteForever,
          ),
        ],
      ),
    );
  }
}

class _EmptyTrash extends StatelessWidget {
  const _EmptyTrash();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.trashEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.trashEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
