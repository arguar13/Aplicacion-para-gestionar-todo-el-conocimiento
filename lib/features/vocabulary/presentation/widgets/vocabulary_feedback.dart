import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Either;
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_operation.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El texto que cuenta qué hizo [operation], localizado.
String vocabularyOperationMessage(
  AppLocalizations l10n,
  VocabularyOperation operation,
) => switch (operation.kind) {
  VocabularyOperationKind.merge => l10n.vocabularyOperationMerged(
    operation.valueCount,
    operation.label,
  ),
  VocabularyOperationKind.rename => l10n.vocabularyOperationRenamed(
    operation.label,
  ),
  VocabularyOperationKind.delete => l10n.vocabularyOperationDeleted(
    operation.valueCount,
  ),
  VocabularyOperationKind.deleteCategory =>
    l10n.vocabularyOperationCategoriesDeleted(operation.valueCount),
  VocabularyOperationKind.addAlias => l10n.vocabularyOperationAliasAdded(
    operation.label,
  ),
  VocabularyOperationKind.removeAlias => l10n.vocabularyOperationAliasRemoved(
    operation.label,
  ),
  VocabularyOperationKind.move => l10n.vocabularyOperationMoved(
    operation.valueCount,
    operation.label,
  ),
};

/// Cómo se le cuenta a quien mira lo que pasó con una operación de
/// mantenimiento: el aviso de qué se hizo, con su "Deshacer" a mano, o de por
/// qué no se pudo.
///
/// Se arma ANTES de esperar la operación, con [VocabularyFeedback.of], y se
/// usa después. No es un detalle: una operación cambia el vocabulario, y con
/// eso la tarjeta o la fila que la disparó puede reconstruirse o desaparecer
/// —fusionar dos valores cambia el grupo, y borrar la última categoría vacía
/// borra su fila—. Un `BuildContext` de ese widget ya no sirve al terminar, y
/// el "Deshacer" del aviso se toca todavía más tarde. Lo que se captura acá
/// —el `ScaffoldMessenger`, los textos, el controlador— sobrevive a todo eso.
class VocabularyFeedback {
  const VocabularyFeedback._(this._messenger, this._l10n, this._controller);

  factory VocabularyFeedback.of(BuildContext context, WidgetRef ref) {
    return VocabularyFeedback._(
      ScaffoldMessenger.of(context),
      AppLocalizations.of(context)!,
      ref.read(vocabularyControllerProvider.notifier),
    );
  }

  final ScaffoldMessengerState _messenger;
  final AppLocalizations _l10n;
  final VocabularyController _controller;

  /// Avisa cómo salió [result].
  void report(Either<Failure, VocabularyOperation> result) {
    _messenger.hideCurrentSnackBar();
    result.fold(
      (failure) => _messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(_l10n))),
      ),
      (operation) => _messenger.showSnackBar(
        SnackBar(
          content: Text(vocabularyOperationMessage(_l10n, operation)),
          action: SnackBarAction(
            label: _l10n.vocabularyUndoAction,
            onPressed: undo,
          ),
        ),
      ),
    );
  }

  /// Deshace la última operación y avisa cómo salió.
  Future<void> undo() async {
    final result = await _controller.undo();

    _messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.isRight()
                ? _l10n.vocabularyUndone
                : _l10n.vocabularyUndoFailed,
          ),
        ),
      );
  }
}

/// Pide una confirmación con [title] y [body]; `true` si se confirmó.
Future<bool> confirmVocabularyAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Pide el nombre nuevo de un valor; `null` si se canceló.
Future<String?> askNewValueName(BuildContext context, String current) {
  return showDialog<String>(
    context: context,
    builder: (context) => _RenameDialog(current: current),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.vocabularyRenameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.vocabularyRenameLabel),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.commonRename),
        ),
      ],
    );
  }
}
