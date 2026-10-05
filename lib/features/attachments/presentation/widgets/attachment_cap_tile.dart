import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_cap.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El ajuste del tope por elemento (decisión E de F30): cuánto puede bajar
/// como mucho cada página o publicación. Lo que no entra queda afuera, con
/// «Bajar el resto» en su «Contenido».
class AttachmentCapTile extends ConsumerWidget {
  const AttachmentCapTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cap = ref.watch(attachmentCapProvider);
    return ListTile(
      key: const Key('settings-attachment-cap'),
      leading: const Icon(Icons.download_for_offline_outlined),
      title: Text(l10n.settingsAttachmentCapTitle),
      subtitle: Text(
        l10n.settingsAttachmentCapSubtitle(
          formatFileSize(cap, l10n.localeName),
        ),
      ),
      onTap: () => _choose(context, ref, cap),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref, int current) async {
    final l10n = AppLocalizations.of(context)!;
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.settingsAttachmentCapDialogTitle),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(l10n.settingsAttachmentCapDialogBody),
          ),
          RadioGroup<int>(
            groupValue: current,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final bytes in AttachmentCapNotifier.choices)
                  RadioListTile<int>(
                    key: Key('attachment-cap-$bytes'),
                    value: bytes,
                    title: Text(formatFileSize(bytes, l10n.localeName)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen != null && chosen != current) {
      await ref.read(attachmentCapProvider.notifier).setBytes(chosen);
    }
  }
}
