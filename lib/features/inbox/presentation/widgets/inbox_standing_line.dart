import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_standing.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_status_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En el detalle de una fuente, qué se decidió en la Bandeja y cuándo (F28):
/// «Triado el 3 oct» con «Volver a la Bandeja», o «En la Bandeja» con
/// «Triar ahora».
///
/// Es la otra mitad de la sección «Bandeja» de los filtros: lo triado se
/// encuentra filtrando, y al abrirlo se ve que se trió y se puede deshacer
/// desde ahí, sin volver a la Bandeja a buscarlo. No dibuja nada —ni el
/// espacio de arriba— en lo que no pasó por la Bandeja: una nota, o una
/// fuente que todavía se procesa.
class InboxStandingLine extends ConsumerWidget {
  const InboxStandingLine({
    required this.itemId,
    required this.itemTitle,
    super.key,
  });

  final String itemId;

  /// Para el aviso de «Volver a la Bandeja».
  final String itemTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(inboxStandingProvider(itemId)).valueOrNull;
    if (standing == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = standing.status.color(theme.colorScheme);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // El mismo lenguaje que la insignia de madurez de una nota: un
          // rótulo teñido, sin borde, que se lee de un vistazo.
          Container(
            key: const Key('inbox-standing-chip'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(standing.status.icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  _label(
                    context,
                    l10n,
                    standing,
                    now: ref.read(clockProvider)(),
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
              ],
            ),
          ),
          if (standing.status == InboxStatus.pending)
            TextButton.icon(
              onPressed: () {
                ref.read(inboxFocusedIdProvider.notifier).state = itemId;
                context.go(RoutePaths.inbox);
              },
              icon: const Icon(Icons.inbox_outlined, size: 18),
              label: Text(l10n.inboxTriageNow),
            )
          else
            TextButton.icon(
              onPressed: () => _backToInbox(context, ref),
              icon: const Icon(Icons.undo, size: 18),
              label: Text(l10n.inboxBackToInbox),
            ),
        ],
      ),
    );
  }

  /// «Triado el 3 oct»: el día y el mes, y el año solo si no es este —«el 3
  /// oct» de hace dos años no es el de esta semana—.
  static String _label(
    BuildContext context,
    AppLocalizations l10n,
    InboxStanding standing, {
    required DateTime now,
  }) {
    final since = standing.since;
    final locale = Localizations.localeOf(context).toString();
    String date(DateTime at) =>
        (at.year == now.year
                ? DateFormat.MMMd(locale)
                : DateFormat.yMMMd(locale))
            .format(at.toLocal());

    return switch (standing.status) {
      InboxStatus.pending => l10n.inboxStandingPending,
      InboxStatus.triaged =>
        since == null
            ? l10n.inboxStandingTriaged
            : l10n.inboxStandingTriagedOn(date(since)),
      InboxStatus.discarded =>
        since == null
            ? l10n.inboxStandingDiscarded
            : l10n.inboxStandingDiscardedOn(date(since)),
    };
  }

  Future<void> _backToInbox(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: itemId, to: ItemState.processed);

    messenger.hideCurrentSnackBar();
    result.match(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      ),
      (_) => messenger.showSnackBar(
        SnackBar(content: Text(l10n.inboxBackToInboxSnack(itemTitle))),
      ),
    );
  }
}
