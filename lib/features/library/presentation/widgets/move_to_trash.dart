import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Manda [ids] a la papelera y avisa con un «Deshacer» (F11).
///
/// Sin diálogo de confirmación: mandar algo a la papelera no destruye nada —se
/// restaura tal cual—, y preguntar antes de una acción que se puede deshacer es
/// fricción; lo que sí pide confirmación es borrar para siempre, en la
/// papelera. El aviso lleva el botón que lo revierte.
///
/// Devuelve `true` si se pudo. Toma del contexto todo lo que necesita ANTES de
/// esperar: quien llama puede desaparecer mientras tanto —el detalle se cierra
/// justo después—, y el aviso tiene que salir igual, en la pantalla a la que
/// se vuelve.
Future<bool> moveToTrashWithUndo(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(libraryRepositoryProvider);

  final result = await repository.deleteMany(ids);

  messenger.hideCurrentSnackBar();
  final failure = result.getLeft().toNullable();
  if (failure != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(failure.localizedMessage(l10n))),
    );
    return false;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.trashMoved(ids.length)),
      action: SnackBarAction(
        label: l10n.trashUndo,
        onPressed: () async {
          final undone = await repository.restoreMany(ids);
          final undoFailure = undone.getLeft().toNullable();
          if (undoFailure != null) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(undoFailure.localizedMessage(l10n))),
              );
          }
        },
      ),
    ),
  );
  return true;
}
