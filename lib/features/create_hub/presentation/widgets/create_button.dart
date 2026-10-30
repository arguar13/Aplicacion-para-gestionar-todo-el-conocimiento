import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/create_hub/domain/create_kind.dart';
import 'package:sinapsis/features/create_hub/presentation/create_actions.dart';
import 'package:sinapsis/features/create_hub/presentation/create_runs.dart';
import 'package:sinapsis/features/create_hub/presentation/widgets/create_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Crear», el ✨ de la barra de un documento (F45, paso 7b, mejora 14,
/// decisión G): el único lugar donde se crea algo de él, con la IA o a mano
/// ([showCreateSheet]).
///
/// **Mientras algo trabaja, lleva un anillo**, en vez de las ruedas sueltas de
/// antes: se llena con las partes que lleva leídas si se saben —una sola cosa
/// que se lee por partes— y, si no, gira; con las animaciones apagadas, queda
/// entero y quieto. El lector de pantalla dice que la IA está trabajando.
class CreateButton extends ConsumerWidget {
  const CreateButton({required this.target, super.key});

  final CreateTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final runs = ref.watch(createRunsProvider(target.item.id));
    final queued = queuedCreateOf(
      ref.watch(aiOrganizeStatusProvider),
      target.item.id,
    );
    final working = runs.isNotEmpty || queued != null;
    // El anillo se llena solo si hay una sola cosa trabajando y se sabe
    // cuánto lleva; con dos, o sin saberlo, gira.
    final fraction = runs.length == 1 && queued == null
        ? runs.values.single.fraction
        : null;
    final scheme = Theme.of(context).colorScheme;
    // Sin animaciones, sin saber cuánto lleva: el anillo entero, quieto.
    final still = MediaQuery.disableAnimationsOf(context);

    return IconButton(
      key: const Key('create-button'),
      tooltip: working ? l10n.f45S7bCreateBusy : l10n.f45S7bCreate,
      onPressed: () => unawaited(_open(context, ref)),
      icon: SizedBox.square(
        dimension: 30,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (working)
              Positioned.fill(
                child: CircularProgressIndicator(
                  key: const Key('create-button-ring'),
                  value: fraction ?? (still ? 1 : null),
                  strokeWidth: 2.5,
                  color: scheme.primary,
                  backgroundColor: scheme.primary.withValues(alpha: 0.15),
                ),
              ),
            Icon(
              working ? Icons.auto_awesome : Icons.auto_awesome_outlined,
              size: working ? 18 : 24,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final kind = await showCreateSheet(context, target);
    if (kind == null || !context.mounted) return;
    await startCreate(context, ref, target, kind);
  }
}
