import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/inbox/domain/usecases/triage_into_processed.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/retriage/retriage_picker.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_triage_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Volver a triar» (F41, paso 4): qué hacer al tocarlo.
///
/// Es el único punto por el que pasa todo «Volver a triar» —el de arriba de
/// la Bandeja, el del documento procesado, el del vacío de «Procesado» y el
/// del detalle de una fuente—:
///
/// - con [sourceItemId], vuelve a triar esa fuente ([retriageSource]);
/// - sin él, abre el selector con todas las fuentes de la Biblioteca
///   ([showRetriagePicker]) y, al elegir una, lo mismo.
VoidCallback retriageAction(
  BuildContext context,
  WidgetRef ref, {
  String? sourceItemId,
}) =>
    () => unawaited(
      sourceItemId == null
          ? _pickAndRetriage(context, ref)
          : retriageSource(context, ref, sourceItemId),
    );

Future<void> _pickAndRetriage(BuildContext context, WidgetRef ref) async {
  final chosen = await showRetriagePicker(context);
  if (chosen == null || !context.mounted) return;
  await retriageSource(context, ref, chosen);
}

/// Lo que se le puede pedir a una sección que ya tiene partes: agregar,
/// actualizar, reemplazar o quitar. La hoja ofrece solo «Agregar» donde no hay
/// nada todavía, y «Actualizar» solo donde la fuente tiene una versión que
/// traer.
final Set<ProcessedChange> kRetriageChanges = ProcessedChange.values.toSet();

/// Vuelve a triar la fuente [sourceItemId]: abre la hoja «¿Qué va a
/// Procesado?», que lee lo que su documento ya tiene, y por cada sección se
/// elige agregar, actualizar, reemplazar o quitar, con la vista previa en
/// vivo.
///
/// Con «Listo», `TriageIntoProcessed.retriage`: si la fuente no estaba
/// triada, queda triada, las dos cosas o ninguna; si ya lo estaba, su estado
/// no se toca. El aviso lleva «Ver» —el documento, si no se lo está mirando
/// ya— y «Deshacer», que deja el documento y la fuente como estaban.
///
/// Devuelve si se terminó con «Listo».
Future<bool> retriageSource(
  BuildContext context,
  WidgetRef ref,
  String sourceItemId,
) {
  // Lo que se usa después de la hoja se resuelve ahora: quien abrió
  // «Volver a triar» puede no estar más —el vacío de «Procesado» deja de
  // estarlo con el primer documento—.
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final router = ref.read(goRouterProvider);
  final triage = ref.read(triageIntoProcessedProvider);
  final repository = ref.read(processedRepositoryProvider);

  return showProcessedTriageSheet(
    context,
    sourceItemId: sourceItemId,
    changes: kRetriageChanges,
    onDone: (edits, original) async {
      final result = await triage.retriage(
        sourceItemId,
        edits,
        original: original,
      );
      if (result.getLeft().toNullable() case final failure?) return failure;
      final outcome = result.getRight().toNullable()!;
      // El nombre de ahora de la fuente, como en el aviso de la Bandeja: si
      // se procesó, existe.
      final material = await repository.materialOf(
        sourceItemId,
        countWords: false,
      );
      _announce(
        outcome,
        title: material.match((_) => '', (material) => material.title),
        l10n: l10n,
        messenger: messenger,
        router: router,
        triage: triage,
      );
      return null;
    },
  );
}

/// El aviso de lo que dejó volver a triar: qué pasó, «Ver» y «Deshacer».
void _announce(
  RetriageOutcome outcome, {
  required String title,
  required AppLocalizations l10n,
  required ScaffoldMessengerState messenger,
  required GoRouter router,
  required TriageIntoProcessed triage,
}) {
  final processed = outcome.processed;
  final unchanged = processed.unchanged && outcome.triagedFrom == null;
  final message = outcome.triagedFrom != null
      ? l10n.processedRetriageTriagedSnack(title)
      : unchanged
      ? l10n.processedRetriageUnchangedSnack(title)
      : l10n.processedRetriageUpdatedSnack(title);
  final document = RoutePaths.processedDocument(processed.documentId);
  // «Ver» lleva al documento, salvo que sea lo que ya se está mirando: lo de
  // arriba de todo, también si se abrió apilado (`push`), que no cambia la
  // dirección de la pila.
  final top = router.routerDelegate.currentConfiguration;
  final looking = top.isNotEmpty && top.last.matchedLocation == document;

  Future<void> undo() async {
    final undone = await triage.undoRetriage(outcome);
    messenger.hideCurrentSnackBar();
    if (undone.getLeft().toNullable() case final failure?) {
      messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      );
    }
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('retriage-snack'),
        // Como el aviso de la Bandeja: «Ver» al lado del texto, porque el
        // aviso admite una sola acción y esa es «Deshacer».
        content: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            return Row(
              children: [
                Expanded(child: Text(message)),
                if (!looking)
                  TextButton(
                    key: const Key('retriage-view'),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          theme.snackBarTheme.actionTextColor ??
                          theme.colorScheme.inversePrimary,
                    ),
                    onPressed: () {
                      messenger.hideCurrentSnackBar();
                      unawaited(router.push(document));
                    },
                    child: Text(l10n.inboxView),
                  ),
              ],
            );
          },
        ),
        // Pedir lo que ya estaba no cambió nada: no hay qué deshacer.
        action: unchanged
            ? null
            : SnackBarAction(
                label: l10n.inboxUndo,
                onPressed: () => unawaited(undo()),
              ),
      ),
    );
}

/// El botón «Volver a triar». Con [disabledReason], apagado y diciendo por
/// qué —también al lector de pantalla, por su ayuda—: la fuente está en la
/// papelera, por ejemplo.
class RetriageButton extends ConsumerWidget {
  const RetriageButton({
    this.sourceItemId,
    this.filled = false,
    this.disabledReason,
    super.key,
  });

  /// La fuente a volver a triar; `null` para elegirla en toda la Biblioteca.
  final String? sourceItemId;

  /// Relleno —la acción principal de un vacío— o de contorno.
  final bool filled;

  /// Por qué no se puede, o `null` si se puede.
  final String? disabledReason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final reason = disabledReason;
    final action = reason != null
        ? null
        : retriageAction(context, ref, sourceItemId: sourceItemId);
    final label = Text(l10n.processedRetriage);
    const icon = Icon(Icons.replay_outlined);
    final button = filled
        ? FilledButton.tonalIcon(onPressed: action, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: action, icon: icon, label: label);
    if (reason == null) return button;
    // Un botón apagado sin explicación no dice si falta algo o si no se puede.
    return Tooltip(message: reason, child: button);
  }
}
