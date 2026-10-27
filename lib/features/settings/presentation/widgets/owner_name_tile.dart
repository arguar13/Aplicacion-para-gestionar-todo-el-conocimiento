import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/settings/presentation/providers/owner_name.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Cómo te llamo», en Ajustes (F42): el nombre con que el chat saluda. Sin
/// nombre, dice para qué sirve.
class OwnerNameTile extends ConsumerWidget {
  const OwnerNameTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final name = ref.watch(ownerNameProvider);
    return ListTile(
      key: const Key('settings-owner-name'),
      leading: const Icon(Icons.waving_hand_outlined),
      title: Text(l10n.ownerNameTitle),
      subtitle: Text(name ?? l10n.ownerNameEmpty),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => unawaited(showOwnerNameDialog(context, ref)),
    );
  }
}

/// Pregunta cómo llamar a la persona y lo guarda (F42). Lo abren Ajustes y
/// el pie del panel de conversaciones.
Future<void> showOwnerNameDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(ownerNameProvider);
  final result = await showDialog<_OwnerNameResult>(
    context: context,
    builder: (context) => _OwnerNameDialog(initial: current),
  );
  if (result == null) return;
  await ref.read(ownerNameProvider.notifier).rename(result.name);
}

/// Lo que se eligió en el diálogo: un nombre, o `null` para quitarlo.
typedef _OwnerNameResult = ({String? name});

class _OwnerNameDialog extends StatefulWidget {
  const _OwnerNameDialog({required this.initial});

  final String? initial;

  @override
  State<_OwnerNameDialog> createState() => _OwnerNameDialogState();
}

class _OwnerNameDialogState extends State<_OwnerNameDialog> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop((name: _controller.text));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.waving_hand_outlined, color: theme.colorScheme.primary),
      title: Text(l10n.ownerNameDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('owner-name-field'),
            controller: _controller,
            autofocus: true,
            maxLength: OwnerNameNotifier.maxLength,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: l10n.ownerNameDialogHint),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.ownerNameDialogPrivacy,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            key: const Key('owner-name-remove'),
            onPressed: () => Navigator.of(context).pop((name: null)),
            child: Text(l10n.ownerNameRemove),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('owner-name-save'),
          onPressed: _save,
          child: Text(l10n.ownerNameSave),
        ),
      ],
    );
  }
}
