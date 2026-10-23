import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «12 elementos sin tema · Ordenarlos» (F37), arriba de la Biblioteca.
///
/// Lo que ya estaba guardado sin tema no se mueve solo —decisión C—: la
/// tarjeta lo cuenta y lleva a la lista para ordenarlo cuando la persona
/// quiera. Sin nada sin tema no ocupa nada, así que desaparece sola al
/// ordenar lo último.
class UnsortedItemsCard extends ConsumerWidget {
  const UnsortedItemsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unsortedCountProvider).valueOrNull ?? 0;
    if (count == 0) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      key: const ValueKey('unsorted-items'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_off_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.libraryUnsortedTitle(count),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.libraryUnsortedBody, style: theme.textTheme.bodySmall),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => unawaited(context.push(RoutePaths.unsorted)),
                child: Text(l10n.libraryUnsortedAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
