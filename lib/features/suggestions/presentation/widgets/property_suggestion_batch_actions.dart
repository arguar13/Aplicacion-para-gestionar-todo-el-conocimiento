import 'package:flutter/material.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Aplica en lote las sugerencias de propiedad [ids] —o las descarta— y avisa
/// cómo salió. Devuelve cuántas se resolvieron, o `null` si nada se aplicó: el
/// lote es atómico, así que un fallo deja todo como estaba y las marcas para
/// reintentar.
///
/// Si se aceptaron, el aviso trae «Deshacer»: quita lo que esa aceptación
/// puso, de todas juntas, y las deja pendientes otra vez. Lo comparten la
/// pantalla del lote y la hoja de la Bandeja, así que las dos avisan y
/// deshacen igual.
///
/// Con [onFailure] un fallo se cuenta ahí, con su texto, en vez de con un
/// aviso: la hoja de la Bandeja lo muestra adentro, porque la barrera de una
/// hoja modal tapa los avisos de la pantalla de abajo.
///
/// Lo que necesita del contexto —el aviso, los textos— se toma ANTES de
/// esperar: la pantalla que lo pidió puede haberse cerrado cuando termine, y el
/// «Deshacer» tiene que seguir andando en la que quedó abajo.
Future<int?> applyPropertySuggestionBatch({
  required BuildContext context,
  required SuggestionRepository repository,
  required List<String> ids,
  required bool accept,
  void Function(String message)? onFailure,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final result = accept
      ? await repository.acceptMany(ids)
      : await repository.rejectMany(ids);

  messenger.hideCurrentSnackBar();
  final failure = result.getLeft().toNullable();
  if (failure != null) {
    final message = failure.localizedMessage(l10n);
    if (onFailure != null) {
      onFailure(message);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
    return null;
  }

  final count = result.getRight().toNullable() ?? 0;
  if (!accept) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.suggestionReviewRejected(count))),
    );
    return count;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.suggestionReviewAccepted(count)),
      // Más que un aviso común: deshacer un lote es una decisión, no un
      // reflejo.
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: l10n.suggestionReviewUndo,
        onPressed: () => _undoAccepted(messenger, l10n, repository, ids),
      ),
    ),
  );
  return count;
}

Future<void> _undoAccepted(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  SuggestionRepository repository,
  List<String> ids,
) async {
  final result = await repository.revertAcceptedMany(ids);
  messenger.hideCurrentSnackBar();

  final failure = result.getLeft().toNullable();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        failure != null
            ? failure.localizedMessage(l10n)
            : l10n.suggestionReviewUndone(result.getRight().toNullable() ?? 0),
      ),
    ),
  );
}
