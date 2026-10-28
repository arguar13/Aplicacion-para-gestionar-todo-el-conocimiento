import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Either, Unit;
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_readable.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una parte de un documento procesado (F41): una página del texto, una
/// oración del resumen o de la síntesis, una nota o un fragmento.
///
/// - Su texto, seleccionable con el menú de siempre y resaltado en amarillo
///   mientras el lector en voz alta lo lee (`ReadAloudText`).
/// - Si la persona la cambió, o la escribió ella, lo dice: es lo que
///   «Actualizar» no pisa.
/// - **«Abrir en el original»** la abre en la fuente, justo en su lugar, por
///   el mismo camino de las tarjetas y las citas (`RoutePaths.reading`). En un
///   fragmento se ve a la vista —es para lo que se cortó—; en lo demás, en su
///   menú.
/// - **Editar** y **Quitar**, cada uno con «Deshacer».
class ProcessedPartTile extends ConsumerWidget {
  const ProcessedPartTile({
    required this.part,
    required this.sourceItemId,
    super.key,
  });

  final ProcessedPart part;

  /// La fuente, si se puede abrir: viva y fuera de la papelera. Sin ella no
  /// hay a dónde llevar «Abrir en el original».
  final String? sourceItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final anchor = part.anchor;
    final sourceId = sourceItemId;
    final openInOriginal = anchor == null || sourceId == null
        ? null
        : () => context.push(
            RoutePaths.reading(sourceId, start: anchor.start, end: anchor.end),
          );
    final mark = part.origin == ProcessedPartOrigin.user
        ? l10n.processedPartOwn
        : part.edited
        ? l10n.processedPartEdited
        : null;
    final isFragment = part.section == ProcessedSection.fragments;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ReadAloudText(
                    part.content,
                    sourceKey: processedPartReadKey(part.id),
                    style: theme.textTheme.bodyLarge,
                    selectable: true,
                  ),
                ),
              ),
              _PartMenu(
                part: part,
                onOpenInOriginal: isFragment ? null : openInOriginal,
              ),
            ],
          ),
          if (mark != null || (isFragment && openInOriginal != null))
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                if (mark != null)
                  Text(
                    mark,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (isFragment && openInOriginal != null)
                  TextButton.icon(
                    key: Key('processed-open-original-${part.id}'),
                    onPressed: openInOriginal,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: Text(l10n.processedOpenInOriginal),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _PartAction { openInOriginal, edit, remove }

class _PartMenu extends ConsumerWidget {
  const _PartMenu({required this.part, required this.onOpenInOriginal});

  final ProcessedPart part;
  final VoidCallback? onOpenInOriginal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return PopupMenuButton<_PartAction>(
      key: Key('processed-part-menu-${part.id}'),
      tooltip: l10n.processedPartMenu,
      onSelected: (action) => switch (action) {
        _PartAction.openInOriginal => onOpenInOriginal?.call(),
        _PartAction.edit => unawaited(editProcessedPart(context, ref, part)),
        _PartAction.remove => unawaited(
          removeProcessedPart(context, ref, part),
        ),
      },
      itemBuilder: (context) => [
        if (onOpenInOriginal != null)
          PopupMenuItem(
            value: _PartAction.openInOriginal,
            child: ListTile(
              leading: const Icon(Icons.my_location),
              title: Text(l10n.processedOpenInOriginal),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: _PartAction.edit,
          child: ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.processedPartEdit),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _PartAction.remove,
          child: ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: Text(l10n.processedPartRemove),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// Edita [part] en un diálogo y, si se guarda, avisa con «Deshacer», que la
/// devuelve tal como estaba (`ProcessedRepository.restorePart`). Una parte
/// copiada de la fuente queda «con cambios tuyos»: «Actualizar» ya no la pisa.
Future<void> editProcessedPart(
  BuildContext context,
  WidgetRef ref,
  ProcessedPart part,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(processedRepositoryProvider);

  final content = await showDialog<String>(
    context: context,
    builder: (context) => _EditPartDialog(
      title: l10n.processedPartEditTitle(part.section.label(l10n)),
      initial: part.content,
    ),
  );
  if (content == null || content == part.content) return;

  _reportWithUndo(
    messenger,
    l10n,
    await repository.editPart(part.id, content),
    done: l10n.processedPartSaved,
    undo: repository.restorePart,
  );
}

/// Quita [part] y avisa con «Deshacer», que la devuelve a su lugar.
Future<void> removeProcessedPart(
  BuildContext context,
  WidgetRef ref,
  ProcessedPart part,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(processedRepositoryProvider);

  _reportWithUndo(
    messenger,
    l10n,
    await repository.removePart(part.id),
    done: l10n.processedPartRemoved,
    undo: repository.restorePart,
  );
}

/// Dice cómo salió un cambio a una parte, con «Deshacer» si salió. Toma el
/// aviso de antes de esperar: la parte —o la sección— pudo irse de la
/// pantalla mientras tanto, y el aviso tiene que salir igual.
void _reportWithUndo(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  Either<Failure, ProcessedPart> result, {
  required String done,
  required Future<Either<Failure, Unit>> Function(ProcessedPart) undo,
}) {
  messenger.hideCurrentSnackBar();
  result.match(
    (failure) => messenger.showSnackBar(
      SnackBar(content: Text(failure.localizedMessage(l10n))),
    ),
    (before) => messenger.showSnackBar(
      SnackBar(
        content: Text(done),
        action: SnackBarAction(
          label: l10n.trashUndo,
          onPressed: () async {
            final undone = await undo(before);
            final failure = undone.getLeft().toNullable();
            if (failure != null) {
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(failure.localizedMessage(l10n))),
                );
            }
          },
        ),
      ),
    ),
  );
}

class _EditPartDialog extends StatefulWidget {
  const _EditPartDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_EditPartDialog> createState() => _EditPartDialogState();
}

class _EditPartDialogState extends State<_EditPartDialog> {
  late final _controller = TextEditingController(text: widget.initial);

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
      content: SizedBox(
        width: 560,
        child: TextField(
          key: const Key('processed-part-editor'),
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 14,
          keyboardType: TextInputType.multiline,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        // Vacía no se guarda: para sacarla está «Quitar», con su «Deshacer».
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_controller.text),
            child: Text(l10n.processedPartSave),
          ),
        ),
      ],
    );
  }
}
