import 'package:flutter/material.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué pasa a la siguiente fase al triar un libro o un documento (F30,
/// decisión 68): se guardaron su archivo y el texto que se le sacó, y no
/// siempre hacen falta los dos.
enum InboxKeep {
  /// Los dos, como hasta ahora.
  both,

  /// El texto: el archivo va a la papelera de la app y se libera su lugar.
  onlyText,

  /// El libro: el texto va a la papelera de la app y no se vuelve a extraer
  /// solo.
  onlyFile,
}

/// Pregunta qué sigue con un libro o un documento al triarlo (F30, decisión
/// 68). Devuelve lo elegido, o `null` si se cerró la hoja sin elegir: triar
/// no pasa y la fuente sigue en la Bandeja.
///
/// [fileBytes] es cuánto pesa el archivo, para decir cuánto se libera.
Future<InboxKeep?> showInboxKeepSheet(BuildContext context, {int? fileBytes}) {
  return showModalBottomSheet<InboxKeep>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _InboxKeepSheet(fileBytes: fileBytes),
  );
}

class _InboxKeepSheet extends StatelessWidget {
  const _InboxKeepSheet({required this.fileBytes});

  final int? fileBytes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bytes = fileBytes;
    // Un archivo de menos de medio mega se dice «0 MB»: mejor no prometer
    // un número que no dice nada.
    final freed = bytes == null || bytes < 512 * 1024
        ? l10n.inboxKeepOnlyTextHint
        : l10n.inboxKeepOnlyTextSizeHint(
            (bytes / (1024 * 1024)).toStringAsFixed(
              bytes < 10 * 1024 * 1024 ? 1 : 0,
            ),
          );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n.inboxKeepTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(
                l10n.inboxKeepBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            _KeepOption(
              optionKey: const Key('inbox-keep-both'),
              icon: Icons.auto_stories_outlined,
              title: l10n.inboxKeepBoth,
              hint: l10n.inboxKeepBothHint,
              keep: InboxKeep.both,
            ),
            _KeepOption(
              optionKey: const Key('inbox-keep-only-text'),
              icon: Icons.notes,
              title: l10n.inboxKeepOnlyText,
              hint: freed,
              keep: InboxKeep.onlyText,
            ),
            _KeepOption(
              optionKey: const Key('inbox-keep-only-file'),
              icon: Icons.menu_book_outlined,
              title: l10n.inboxKeepOnlyFile,
              hint: l10n.inboxKeepOnlyFileHint,
              keep: InboxKeep.onlyFile,
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepOption extends StatelessWidget {
  const _KeepOption({
    required this.optionKey,
    required this.icon,
    required this.title,
    required this.hint,
    required this.keep,
  });

  final Key optionKey;
  final IconData icon;
  final String title;
  final String hint;
  final InboxKeep keep;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: optionKey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: SourcePanelIconCircle(icon: icon),
      title: Text(title),
      subtitle: Text(hint),
      onTap: () => Navigator.of(context).pop(keep),
    );
  }
}
