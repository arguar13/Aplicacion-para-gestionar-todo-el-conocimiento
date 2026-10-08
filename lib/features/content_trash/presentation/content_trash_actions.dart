import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/content_trash/domain/repositories/content_trash_repository.dart';
import 'package:sinapsis/features/content_trash/presentation/providers/content_trash_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Borrar archivo, quedarme con el texto» (F30, decisión 68): el archivo va a
/// la papelera de la app por 30 días —no se borra del disco— y el aviso trae
/// «Deshacer». Sin pregunta de antes: no hay nada que no se pueda recuperar.
Future<void> trashOriginalFile(
  BuildContext context,
  WidgetRef ref,
  KnowledgeItem item,
) {
  final repository = ref.read(contentTrashRepositoryProvider);
  return _trash(
    context,
    repository: repository,
    result: repository.keepOnlyText(item.id),
    message: AppLocalizations.of(context)!.detailOriginalFileTrashed,
  );
}

/// «Borrar el texto, quedarme con el libro» (F30, decisión 68): el texto va a
/// la papelera de la app por 30 días, con sus subrayados, y el libro no se
/// vuelve a extraer solo. El aviso trae «Deshacer».
Future<void> trashExtractedText(
  BuildContext context,
  WidgetRef ref,
  KnowledgeItem item,
) {
  final repository = ref.read(contentTrashRepositoryProvider);
  return _trash(
    context,
    repository: repository,
    result: repository.keepOnlyFile(item.id),
    message: AppLocalizations.of(context)!.detailTextTrashed,
  );
}

/// «Recuperar el archivo» y «Recuperar el texto»: lo de la papelera del
/// contenido vuelve a su elemento, y el aviso dice cómo salió.
Future<void> restoreTrashedContent(
  BuildContext context,
  WidgetRef ref,
  TrashedContent content,
) => _restore(
  ScaffoldMessenger.of(context),
  AppLocalizations.of(context)!,
  ref.read(contentTrashRepositoryProvider),
  [content],
);

Future<void> _trash(
  BuildContext context, {
  required ContentTrashRepository repository,
  required Future<Either<Failure, List<TrashedContent>>> result,
  required String message,
}) async {
  // Lo que se necesita después de esperar se toma ahora: el aviso puede
  // tocarse cuando la pantalla ya no está.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;
  final outcome = await result;
  messenger.hideCurrentSnackBar();
  final failure = outcome.getLeft().toNullable();
  if (failure != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(failure.localizedMessage(l10n))),
    );
    return;
  }
  final trashed = outcome.getRight().getOrElse(() => const []);
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: l10n.contentTrashUndo,
        onPressed: () =>
            unawaited(_restore(messenger, l10n, repository, trashed)),
      ),
    ),
  );
}

Future<void> _restore(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  ContentTrashRepository repository,
  List<TrashedContent> contents,
) async {
  for (final content in contents) {
    final result = await repository.restore(content.id);
    messenger.hideCurrentSnackBar();
    final failure = result.getLeft().toNullable();
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      );
      continue;
    }
    final message = switch (result.getRight().toNullable()!) {
      ContentRestoreOutcome.restored => switch (content.kind) {
        TrashedContentKind.file => l10n.contentTrashFileRestored,
        TrashedContentKind.text => l10n.contentTrashTextRestored,
      },
      ContentRestoreOutcome.fileMissing => l10n.contentTrashFileMissing,
      ContentRestoreOutcome.alreadyHasFile => l10n.contentTrashAlreadyHasFile,
      ContentRestoreOutcome.gone => l10n.contentTrashGone,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
