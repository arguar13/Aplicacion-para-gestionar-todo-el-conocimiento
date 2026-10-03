import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la lista de todo lo que espera en la Bandeja (F28): lo que hay detrás
/// de «N pendientes», que antes era un texto sin acción.
///
/// Tocar una fuente la pone arriba del mazo —[inboxFocusedIdProvider]— y
/// cierra la lista: se elige qué triar sin tener que pasar las anteriores.
Future<void> showInboxQueueSheet(
  BuildContext context, {
  required String? showingId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => InboxQueueSheet(showingId: showingId),
  );
}

class InboxQueueSheet extends ConsumerWidget {
  const InboxQueueSheet({required this.showingId, super.key});

  /// La que está arriba del mazo en este momento, para marcarla.
  final String? showingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pending = ref.watch(inboxPendingProvider).valueOrNull;
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(locale);

    // Hasta casi toda la pantalla, y no más de lo que hace falta: con tres
    // pendientes, una hoja corta; con cien, una lista que se desplaza.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.inboxQueueTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (pending != null)
                    Text(
                      l10n.inboxPendingCount(pending.length),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (pending == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pending.length,
                  itemBuilder: (context, index) {
                    final source = pending[index];
                    final showing = source.id == showingId;
                    final captured = date.format(source.capturedAt);
                    return ListTile(
                      selected: showing,
                      leading: Icon(
                        source.kind.icon,
                        color: source.kind.role.accent(scheme),
                      ),
                      title: Text(
                        source.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${source.kind.label(l10n)} · '
                        '${l10n.inboxQueueCapturedOn(captured)}',
                      ),
                      trailing: showing ? Text(l10n.inboxQueueShowing) : null,
                      onTap: () {
                        ref.read(inboxFocusedIdProvider.notifier).state =
                            source.id;
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
