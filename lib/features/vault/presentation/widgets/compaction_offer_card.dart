import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/vault/presentation/providers/compaction_offer_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La oferta única de compactar la bóveda (F12), sobre la Biblioteca.
///
/// Aparece cuando hay bastante para devolver —tras una migración, por ejemplo,
/// que deja páginas libres de las tablas que reemplazó— y hay disco para
/// hacerlo. Se contesta una sola vez: «Ver» abre la pantalla y «Ahora no» la
/// descarta, y en los dos casos no vuelve. Nadie tiene que pensar en el
/// espacio de la bóveda mientras no le pese, pero cuando pesa, alguien se lo
/// dice; después, la ficha «Espacio de la bóveda» de Ajustes sigue ahí.
///
/// Sin oferta no ocupa nada.
class CompactionOfferCard extends ConsumerWidget {
  const CompactionOfferCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(compactionOfferProvider).valueOrNull;
    if (offer == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Future<void> answer() =>
        ref.read(compactionOfferAnsweredProvider.notifier).markAnswered();

    return Card(
      key: const ValueKey('compaction-offer'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.vaultCompactionOfferTitle(
                      formatFileSize(offer.reclaimableBytes),
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.vaultCompactionOfferBody,
              style: theme.textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: answer,
                    child: Text(l10n.vaultCompactionOfferNotNow),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await answer();
                      if (context.mounted) {
                        unawaited(context.push(RoutePaths.vaultCompaction));
                      }
                    },
                    child: Text(l10n.vaultCompactionOfferReview),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
