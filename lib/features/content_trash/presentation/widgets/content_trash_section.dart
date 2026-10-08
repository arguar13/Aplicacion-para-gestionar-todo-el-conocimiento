import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/content_trash/presentation/content_trash_actions.dart';
import 'package:sinapsis/features/content_trash/presentation/providers/content_trash_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se soltó de un elemento y espera en la papelera de la app (F30,
/// decisión 68): su archivo original o su texto, con cuánto pesa, hasta
/// cuándo se puede recuperar y «Recuperar».
///
/// Sin nada en la papelera no dibuja nada, ni el espacio de arriba.
class ContentTrashSection extends ConsumerWidget {
  const ContentTrashSection({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashed =
        ref.watch(trashedContentProvider(itemId)).valueOrNull ?? const [];
    if (trashed.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      key: const Key('content-trash-section'),
      // El espacio de arriba va con la sección: sin ella, no queda un hueco.
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.contentTrashTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            for (final content in trashed) _TrashedTile(content: content),
          ],
        ),
      ),
    );
  }
}

class _TrashedTile extends ConsumerWidget {
  const _TrashedTile({required this.content});

  final TrashedContent content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = l10n.localeName;
    final isFile = content.kind == TrashedContentKind.file;
    final size = content.sizeBytes;
    final expires = DateFormat.yMMMd(
      locale,
    ).format(content.expiresAt.toLocal());

    return ListTile(
      key: Key('content-trash-${content.kind.name}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(isFile ? Icons.insert_drive_file_outlined : Icons.notes),
      title: Text(isFile ? l10n.contentTrashFile : l10n.contentTrashText),
      subtitle: Text(
        [
          if (isFile && size != null) formatFileSize(size, locale),
          l10n.contentTrashExpires(expires),
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: TextButton(
        onPressed: () => restoreTrashedContent(context, ref, content),
        child: Text(
          isFile ? l10n.contentTrashRestoreFile : l10n.contentTrashRestoreText,
        ),
      ),
    );
  }
}
