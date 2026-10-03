import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La tarjeta que explica qué es triar y adónde va lo procesado, la primera
/// vez que se abre la Bandeja (F28).
///
/// Sin ella, triar parecía hacer desaparecer las cosas: la tarjeta se iba y
/// nada decía que lo triado seguía en la Biblioteca. Se cierra con
/// «Entendido» y no vuelve —se recuerda entre reinicios, ver
/// [inboxIntroDismissedProvider]—; no dibuja nada después.
class InboxIntroCard extends ConsumerWidget {
  const InboxIntroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(inboxIntroDismissedProvider)) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        // El mismo ancho que la tarjeta del mazo, para que se lean juntas.
        constraints: const BoxConstraints(maxWidth: 640),
        child: Card(
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          elevation: 0,
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.inboxIntroTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.inboxIntroBody,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => ref
                        .read(inboxIntroDismissedProvider.notifier)
                        .dismiss(),
                    child: Text(l10n.inboxIntroDismiss),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
