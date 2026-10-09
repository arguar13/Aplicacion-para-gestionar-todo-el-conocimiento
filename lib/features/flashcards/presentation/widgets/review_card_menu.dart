import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_session_controller.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_edit_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se puede hacer con la tarjeta que se ve (F31, ola 2), sin salir del
/// repaso.
enum ReviewCardAction { edit, suspend, bury, delete }

/// El menú de la tarjeta que se ve: editarla, pausarla, posponerla hasta
/// mañana y borrarla.
///
/// Pausar y posponer avisan con un «Deshacer»: son fáciles de tocar sin querer
/// y se revierten sin costo. Borrar pide confirmación, porque se lleva el
/// historial y no vuelve. Editar no está en una tarjeta de opción múltiple
/// (sus opciones no se editan desde acá).
class ReviewCardMenu extends ConsumerWidget {
  const ReviewCardMenu({required this.scope, required this.card, super.key});

  final StudyScope scope;
  final Flashcard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<ReviewCardAction>(
      key: const Key('review-card-menu'),
      tooltip: l10n.reviewSessionMenuTooltip,
      onSelected: (action) => unawaited(_run(context, ref, action)),
      itemBuilder: (context) => [
        if (card.kind != FlashcardKind.multipleChoice)
          PopupMenuItem(
            key: const Key('review-menu-edit'),
            value: ReviewCardAction.edit,
            child: _Item(Icons.edit_outlined, l10n.reviewSessionMenuEdit),
          ),
        PopupMenuItem(
          key: const Key('review-menu-suspend'),
          value: ReviewCardAction.suspend,
          child: _Item(
            Icons.pause_circle_outline,
            l10n.reviewSessionMenuSuspend,
          ),
        ),
        PopupMenuItem(
          key: const Key('review-menu-bury'),
          value: ReviewCardAction.bury,
          child: _Item(Icons.snooze_outlined, l10n.reviewSessionMenuBury),
        ),
        PopupMenuItem(
          key: const Key('review-menu-delete'),
          value: ReviewCardAction.delete,
          child: _Item(Icons.delete_outline, l10n.reviewSessionMenuDelete),
        ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    ReviewCardAction action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(studySessionProvider(scope).notifier);

    void fail(Failure failure) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));

    /// El aviso con «Deshacer» de pausar y posponer.
    void notify(String message, String id, {required bool wasSuspended}) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: l10n.reviewSessionUndoAction,
              onPressed: () => unawaited(
                controller.restore(id, wasSuspended: wasSuspended).then((
                  failure,
                ) {
                  if (failure != null) fail(failure);
                }),
              ),
            ),
          ),
        );
    }

    switch (action) {
      case ReviewCardAction.edit:
        final edited = await showFlashcardEditDialog(context, card: card);
        if (edited == null) return;
        final failure = await controller.editCurrent(
          front: edited.$1,
          back: edited.$2,
        );
        if (failure != null) fail(failure);
      case ReviewCardAction.suspend:
        final result = await controller.suspendCurrent();
        final failure = result.failure;
        if (failure != null) return fail(failure);
        final id = result.id;
        if (id != null) {
          notify(l10n.reviewSessionSuspended, id, wasSuspended: true);
        }
      case ReviewCardAction.bury:
        final result = await controller.buryCurrent();
        final failure = result.failure;
        if (failure != null) return fail(failure);
        final id = result.id;
        if (id != null) {
          notify(l10n.reviewSessionBuried, id, wasSuspended: false);
        }
      case ReviewCardAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.reviewSessionDeleteTitle),
            content: Text(l10n.reviewSessionDeleteMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const Key('review-delete-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.reviewSessionDeleteConfirm),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final failure = await controller.deleteCurrent();
        if (failure != null) fail(failure);
    }
  }
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}
