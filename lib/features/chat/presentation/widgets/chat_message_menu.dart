import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Copia [text] y lo dice abajo (F42).
Future<void> copyChatText(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = AppLocalizations.of(context)!.chatAnswerCopied;
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(copied)));
}

/// Lo que se puede hacer al mantener apretado un mensaje (F42): copiarlo,
/// seleccionar una parte y —si es de la persona— editarlo para mandarlo de
/// nuevo.
///
/// [text] es lo que se copia, tal cual se guardó (con su Markdown, que se
/// pega bien en una nota); [readable] es lo que se ve, sin marcas, para
/// seleccionar. [onEdit] es `null` si el mensaje no se puede reenviar —no es
/// de la persona, o se está esperando otra respuesta—.
Future<void> showChatMessageMenu(
  BuildContext context, {
  required String text,
  required String readable,
  VoidCallback? onEdit,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('chat-menu-copy'),
            leading: const Icon(Icons.content_copy_rounded),
            title: Text(l10n.chatAnswerCopy),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(copyChatText(context, text));
            },
          ),
          if (onEdit != null)
            ListTile(
              key: const Key('chat-menu-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.chatMessageMenuEdit),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onEdit();
              },
            ),
          ListTile(
            key: const Key('chat-menu-select'),
            leading: const Icon(Icons.text_fields_rounded),
            title: Text(l10n.chatMessageMenuSelect),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_showSelectable(context, readable));
            },
          ),
        ],
      ),
    ),
  );
}

/// [text] para elegir con el dedo la parte que se quiera, con el menú de
/// copiar de siempre.
Future<void> _showSelectable(BuildContext context, String text) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  l10n.chatSelectTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SelectableText(
                    text,
                    key: const Key('chat-selectable-text'),
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
