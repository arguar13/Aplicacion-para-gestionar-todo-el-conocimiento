/// Lo que se hace con una creación desde su ⋮ (F43): en «Lo creado», en la
/// sección «En Repasar» de un documento o un cuaderno y en el visor. Un solo
/// lugar, para que diga y haga lo mismo en todos.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_customize_sheet.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que ofrece el ⋮ de una creación.
enum CreationAction {
  open,
  rename,
  regenerate,
  retry,
  cancel,
  export,
  sources,
  trash,
}

/// Lo que se ofrece para [creation], en su orden: abrir lo listo, reintentar
/// lo fallido, cancelar lo pendiente; renombrar, volver a generar, exportar
/// —si su tipo sabe—, ver fuentes y borrar, siempre que tenga sentido.
List<CreationAction> creationActionsFor(
  StudyCreation creation, {
  required bool canExport,
  bool includeOpen = true,
}) {
  final status = creation.status;
  return [
    if (includeOpen && status == CreationStatus.ready) CreationAction.open,
    if (status == CreationStatus.failed) CreationAction.retry,
    if (status.isPending) CreationAction.cancel,
    CreationAction.rename,
    if (!status.isPending) CreationAction.regenerate,
    if (canExport && status == CreationStatus.ready) CreationAction.export,
    CreationAction.sources,
    CreationAction.trash,
  ];
}

String creationActionLabel(AppLocalizations l10n, CreationAction action) =>
    switch (action) {
      CreationAction.open => l10n.f43StudioMenuOpen,
      CreationAction.rename => l10n.f43StudioMenuRename,
      CreationAction.regenerate => l10n.f43StudioMenuRegenerate,
      CreationAction.retry => l10n.f43StudioMenuRetry,
      CreationAction.cancel => l10n.f43StudioMenuCancel,
      CreationAction.export => l10n.f43StudioMenuExport,
      CreationAction.sources => l10n.f43StudioMenuSources,
      CreationAction.trash => l10n.f43StudioMenuTrash,
    };

IconData creationActionIcon(CreationAction action) => switch (action) {
  CreationAction.open => Icons.open_in_new,
  CreationAction.rename => Icons.drive_file_rename_outline,
  CreationAction.regenerate => Icons.tune,
  CreationAction.retry => Icons.refresh,
  CreationAction.cancel => Icons.stop_circle_outlined,
  CreationAction.export => Icons.ios_share,
  CreationAction.sources => Icons.source_outlined,
  CreationAction.trash => Icons.delete_outline,
};

/// Hace [action] sobre [creation]. Lo que falla se dice en una línea.
Future<void> runCreationAction(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
  CreationAction action,
) async {
  final queue = ref.read(creationQueueProvider);
  switch (action) {
    case CreationAction.open:
      openCreation(context, creation);
    case CreationAction.rename:
      await _rename(context, ref, creation);
    case CreationAction.regenerate:
      await showCreationCustomizeSheet(
        context,
        kind: creation.kind,
        scope: creation.scope,
        regenerating: creation,
      );
    case CreationAction.retry:
      final l10n = AppLocalizations.of(context)!;
      final messenger = ScaffoldMessenger.of(context);
      final retried = await queue.retry(creation.id);
      if (retried.isLeft()) _say(messenger, l10n.f43StudioActionFailed);
    case CreationAction.cancel:
      await queue.cancel(creation.id);
    case CreationAction.export:
      final export = ref.read(creationKindRegistryProvider).of(creation.kind);
      await export.onExport?.call(context, ref, creation);
    case CreationAction.sources:
      await showCreationSources(context, creation);
    case CreationAction.trash:
      await _trash(context, ref, creation);
  }
}

/// La manda a la papelera —si se generaba, la corta— y ofrece deshacerlo.
Future<void> _trash(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(studyCreationRepositoryProvider);
  final result = await ref.read(creationQueueProvider).trash(creation.id);
  result.match(
    (_) => _say(messenger, l10n.f43StudioActionFailed),
    (_) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.f43StudioTrashed),
          action: SnackBarAction(
            label: l10n.f43StudioUndo,
            onPressed: () => unawaited(repository.restore(creation.id)),
          ),
        ),
      ),
  );
}

Future<void> _rename(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final title = await showDialog<String>(
    context: context,
    builder: (context) =>
        _RenameDialog(initial: studyCreationTitle(l10n, creation)),
  );
  if (title == null) return;
  final result = await ref
      .read(studyCreationRepositoryProvider)
      .rename(creation.id, title);
  if (result.isLeft()) _say(messenger, l10n.f43StudioActionFailed);
}

void _say(ScaffoldMessengerState messenger, String text) => messenger
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.f43StudioRenameTitle),
      content: TextField(
        key: const Key('creation-rename-field'),
        controller: _controller,
        autofocus: true,
        maxLines: null,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: l10n.f43StudioRenameLabel),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            key: const Key('creation-rename-save'),
            onPressed: _controller.text.trim().isEmpty ? null : _save,
            child: Text(l10n.f43StudioRenameSave),
          ),
        ),
      ],
    );
  }
}

/// El ⋮ de una creación, con lo que se puede hacer con ella.
class CreationMenuButton extends ConsumerWidget {
  const CreationMenuButton({
    required this.creation,
    this.includeOpen = true,
    super.key,
  });

  final StudyCreation creation;

  /// Sin «Abrir»: en el visor ya está abierta.
  final bool includeOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final spec = ref.watch(creationKindRegistryProvider).of(creation.kind);
    final actions = creationActionsFor(
      creation,
      canExport: spec.onExport != null,
      includeOpen: includeOpen,
    );
    return PopupMenuButton<CreationAction>(
      key: ValueKey('creation-menu-${creation.id}'),
      tooltip: l10n.f43StudioMenuTooltip,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) =>
          unawaited(runCreationAction(context, ref, creation, action)),
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem(
            key: ValueKey('creation-action-${action.name}'),
            value: action,
            child: Row(
              children: [
                Icon(creationActionIcon(action), size: 20),
                const SizedBox(width: 12),
                Flexible(child: Text(creationActionLabel(l10n, action))),
              ],
            ),
          ),
      ],
    );
  }
}
