/// Lo que se hace con una creación (F43): desde el menú de mantener apretada
/// su fila en «Lo creado», los botones que aparecen al deslizarla, el ⋮ del
/// visor y la sección «En Repasar» de un documento o un cuaderno. Un solo
/// lugar, para que diga y haga lo mismo en todos.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_customize_sheet.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_details_sheet.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se puede hacer con una creación, en el orden del menú de las
/// capturas de NotebookLM: Compartir, Descargar, Cambiar nombre, Ver petición
/// y fuentes y Eliminar —con abrir, reintentar, cancelar y volver a generar
/// donde corresponden—.
enum CreationAction {
  open,
  share,
  download,
  rename,
  details,
  retry,
  cancel,
  regenerate,
  trash,
}

/// Lo que se ofrece para [creation]: abrir y exportar solo lo listo
/// —compartir y descargar, además, solo si su tipo arma su archivo
/// ([canDownload]) y la app tiene cómo compartir ([canShare])—, reintentar lo
/// fallido, cancelar lo pendiente y volver a generar lo terminado.
List<CreationAction> creationActionsFor(
  StudyCreation creation, {
  required bool canShare,
  required bool canDownload,
  bool includeOpen = true,
}) {
  final status = creation.status;
  final ready = status == CreationStatus.ready;
  return [
    if (includeOpen && ready) CreationAction.open,
    if (ready && canShare) CreationAction.share,
    if (ready && canDownload) CreationAction.download,
    CreationAction.rename,
    CreationAction.details,
    if (status == CreationStatus.failed) CreationAction.retry,
    if (status.isPending) CreationAction.cancel,
    if (!status.isPending) CreationAction.regenerate,
    CreationAction.trash,
  ];
}

/// [creationActionsFor] con lo que dice el registro de su tipo y si la app
/// tiene cómo compartir.
List<CreationAction> availableCreationActions(
  WidgetRef ref,
  StudyCreation creation, {
  bool includeOpen = true,
}) {
  final spec = ref.watch(creationKindRegistryProvider).of(creation.kind);
  final exports = spec.exporter != null;
  return creationActionsFor(
    creation,
    canShare: exports && ref.watch(creationSharerProvider) != null,
    canDownload: exports,
    includeOpen: includeOpen,
  );
}

String creationActionLabel(AppLocalizations l10n, CreationAction action) =>
    switch (action) {
      CreationAction.open => l10n.f43StudioMenuOpen,
      CreationAction.share => l10n.f43StudioMenuShare,
      CreationAction.download => l10n.f43StudioMenuDownload,
      CreationAction.rename => l10n.f43StudioMenuRename,
      CreationAction.details => l10n.f43StudioMenuDetails,
      CreationAction.retry => l10n.f43StudioMenuRetry,
      CreationAction.cancel => l10n.f43StudioMenuCancel,
      CreationAction.regenerate => l10n.f43StudioMenuRegenerate,
      CreationAction.trash => l10n.f43StudioMenuTrash,
    };

IconData creationActionIcon(CreationAction action) => switch (action) {
  CreationAction.open => Icons.open_in_new,
  CreationAction.share => Icons.share_outlined,
  CreationAction.download => Icons.file_download_outlined,
  CreationAction.rename => Icons.edit_outlined,
  CreationAction.details => Icons.info_outline,
  CreationAction.retry => Icons.refresh,
  CreationAction.cancel => Icons.stop_circle_outlined,
  CreationAction.regenerate => Icons.tune,
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
    case CreationAction.share:
      await _share(context, ref, creation);
    case CreationAction.download:
      await _download(context, ref, creation);
    case CreationAction.rename:
      await _rename(context, ref, creation);
    case CreationAction.details:
      await showCreationDetails(context, creation);
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
    case CreationAction.trash:
      await _trash(context, ref, creation);
  }
}

/// El archivo de [creation], con lo que dice su tipo; `null` si no tiene o
/// no se pudo armar (lo dice).
Future<CreationExportFile?> _exportOf(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final exporter = ref
      .read(creationKindRegistryProvider)
      .of(creation.kind)
      .exporter;
  if (exporter == null) return null;
  try {
    return await exporter(context, ref, creation);
    // El archivo lo arma el tipo, con lo suyo: cualquier cosa que falle ahí
    // se dice en una línea, sin tumbar la lista.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    _say(messenger, l10n.f43StudioActionFailed);
    return null;
  }
}

Future<void> _share(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final sharer = ref.read(creationSharerProvider);
  if (sharer == null) return;
  // De dónde sale la hoja en un iPad o una Mac: lo que se tocó. Se mide antes
  // de armar el archivo, que puede tardar y cerrar el menú.
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final file = await _exportOf(context, ref, creation);
  if (file == null) return;
  try {
    await sharer(
      file,
      title: studyCreationTitle(l10n, creation),
      origin: origin,
    );
    // Igual que al descargar: lo que falla al compartir se dice, nunca se
    // cae. Cerrar la hoja sin elegir no llega acá.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    _say(messenger, l10n.f43StudioActionFailed);
  }
}

/// La guarda donde la persona elija, con el selector de siempre.
Future<void> _download(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final saver = ref.read(fileSaverProvider);
  final file = await _exportOf(context, ref, creation);
  if (file == null) return;
  try {
    final path = await saver.saveFile(
      fileName: file.fileName,
      bytes: file.bytes,
    );
    // Cancelar el diálogo no es un error: no se dice nada.
    if (path != null) _say(messenger, l10n.f43StudioDownloaded(file.fileName));
    // Igual que el resto de las exportaciones: lo que falla al guardar se
    // dice, nunca se cae.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    _say(messenger, l10n.f43StudioActionFailed);
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
        AppSnackBar(
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

/// El ⋮ del visor de una creación, con lo mismo que su menú en la lista.
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
    final actions = availableCreationActions(
      ref,
      creation,
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

/// El menú flotante de una creación (como el de NotebookLM al mantener
/// apretada una fila): una superficie muy redondeada junto a la fila, con el
/// fondo oscurecido. Devuelve lo elegido —ya hecho— o `null`.
///
/// [anchor] es dónde está la fila en la pantalla: el menú se centra a su
/// altura sin salirse de los bordes. Con «sin animaciones» aparece de una.
Future<CreationAction?> showCreationActionsMenu(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation, {
  Rect? anchor,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final actions = availableCreationActions(ref, creation);
  final still = MediaQuery.disableAnimationsOf(context);
  final chosen = await showGeneralDialog<CreationAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: still
        ? Duration.zero
        : const Duration(milliseconds: 120),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    // Sin `SafeArea`: [anchor] está en coordenadas de la pantalla entera, y
    // los bordes del sistema los respeta el propio acomodo.
    pageBuilder: (context, _, _) => CustomSingleChildLayout(
      delegate: _MenuLayout(
        anchor: anchor,
        padding: MediaQuery.paddingOf(context),
      ),
      child: _ActionsMenu(
        key: ValueKey('creation-actions-menu-${creation.id}'),
        labels: {
          for (final action in actions)
            action: creationActionLabel(l10n, action),
        },
      ),
    ),
  );
  if (chosen == null || !context.mounted) return null;
  await runCreationAction(context, ref, creation, chosen);
  return chosen;
}

/// Dónde va el menú: a la altura de la fila, centrado de lado a lado y sin
/// salirse de la pantalla.
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.anchor, required this.padding});

  final Rect? anchor;

  /// Lo que ocupan las barras del sistema.
  final EdgeInsets padding;

  static const _margin = 16.0;

  double get _top => padding.top + _margin;
  double get _bottom => padding.bottom + _margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
          0,
          math.min(
            360,
            constraints.maxWidth - padding.horizontal - 2 * _margin,
          ),
        ),
        maxHeight: math.max(0, constraints.maxHeight - _top - _bottom),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (size.width - childSize.width) / 2;
    final centre = anchor?.center.dy ?? size.height / 2;
    final y = (centre - childSize.height / 2).clamp(
      _top,
      math.max<double>(_top, size.height - childSize.height - _bottom),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.padding != padding;
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.labels, super.key});

  final Map<CreationAction, String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final MapEntry(key: action, value: label) in labels.entries)
              InkWell(
                key: ValueKey('creation-action-${action.name}'),
                onTap: () => Navigator.of(context).pop(action),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          creationActionIcon(action),
                          color: action == CreationAction.trash
                              ? scheme.error
                              : scheme.onSurface,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(label, style: theme.textTheme.bodyLarge),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
