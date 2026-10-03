import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En qué anda la cola de la IA, como se le cuenta a la persona (F27).
///
/// El interruptor general manda sobre lo que diga la cola: con la IA apagada
/// no importa que falte un modelo —no lo va a usar—, importa que está en
/// pausa y cómo reanudarla.
sealed class AiQueueView {
  const AiQueueView();

  factory AiQueueView.of(AiOrganizeStatus status, {required bool enabled}) {
    if (!enabled) {
      return AiQueuePausedView(
        pending: status is AiOrganizePaused ? status.pending : 0,
      );
    }
    return switch (status) {
      AiOrganizeIdle() => const AiQueueIdleView(),
      AiOrganizeWorking(:final itemTitle, :final pending) => AiQueueWorkingView(
        itemTitle: itemTitle,
        pending: pending,
      ),
      AiOrganizePaused(:final pending, waitingForCharger: true) =>
        AiQueueChargerView(pending: pending),
      AiOrganizePaused(:final pending) => AiQueuePausedView(pending: pending),
      AiOrganizeModelMissing(
        :final chatModelMissing,
        :final embeddingModelMissing,
      ) =>
        AiQueueModelView(
          chatModelMissing: chatModelMissing,
          embeddingModelMissing: embeddingModelMissing,
        ),
    };
  }

  /// La frase corta: el título de la tarjeta y la línea de Ajustes.
  String headline(AppLocalizations l10n);

  IconData get icon;
}

final class AiQueueIdleView extends AiQueueView {
  const AiQueueIdleView();

  @override
  String headline(AppLocalizations l10n) => l10n.aiStatusIdleTitle;

  @override
  IconData get icon => Icons.check_circle_outline;
}

final class AiQueuePausedView extends AiQueueView {
  const AiQueuePausedView({required this.pending});

  final int pending;

  @override
  String headline(AppLocalizations l10n) => l10n.aiStatusPausedTitle;

  @override
  IconData get icon => Icons.pause_circle_outline;
}

final class AiQueueWorkingView extends AiQueueView {
  const AiQueueWorkingView({required this.itemTitle, required this.pending});

  final String itemTitle;
  final int pending;

  @override
  String headline(AppLocalizations l10n) =>
      l10n.aiStatusWorkingTitle(itemTitle);

  @override
  IconData get icon => Icons.auto_awesome;
}

final class AiQueueChargerView extends AiQueueView {
  const AiQueueChargerView({required this.pending});

  final int pending;

  @override
  String headline(AppLocalizations l10n) => l10n.aiStatusChargerTitle;

  @override
  IconData get icon => Icons.battery_charging_full;
}

final class AiQueueModelView extends AiQueueView {
  const AiQueueModelView({
    required this.chatModelMissing,
    required this.embeddingModelMissing,
  });

  final bool chatModelMissing;
  final bool embeddingModelMissing;

  @override
  String headline(AppLocalizations l10n) => l10n.aiStatusModelTitle;

  @override
  IconData get icon => Icons.download_for_offline_outlined;
}

/// Lo que muestra la cola ahora, ya resuelto contra el interruptor general.
final aiQueueViewProvider = Provider.autoDispose<AiQueueView>((ref) {
  return AiQueueView.of(
    ref.watch(aiOrganizeStatusProvider),
    enabled: ref.watch(aiOrganizeSettingsProvider.select((s) => s.enabled)),
  );
});

/// La tarjeta del estado de la cola, arriba de «Lo que hizo la IA» (F27).
///
/// Cada estado dice qué pasa y, si hay algo que hacer, el único botón que lo
/// resuelve: reanudar la pausa, bajar el modelo que falta. Pasar de un estado
/// a otro se funde, sin saltos de alto.
class AiQueueStatusCard extends ConsumerWidget {
  const AiQueueStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(aiQueueViewProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey(view.runtimeType),
          child: _StatusCard(view: view),
        ),
      ),
    );
  }
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.view});

  final AiQueueView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Lo que falta bajar es lo único que pide algo con urgencia: se distingue
    // con el color terciario, el mismo del ✨ de la IA, y no con el de error
    // —no falló nada—.
    final attention = view is AiQueueModelView;

    final message = switch (view) {
      AiQueueIdleView() => l10n.aiStatusIdleMessage,
      AiQueuePausedView(:final pending) => l10n.aiStatusPausedMessage(pending),
      AiQueueWorkingView(:final pending) => l10n.aiStatusWorkingMessage(
        pending,
      ),
      AiQueueChargerView(:final pending) => l10n.aiStatusChargerMessage(
        pending,
      ),
      AiQueueModelView(:final chatModelMissing, :final embeddingModelMissing) =>
        [
          if (chatModelMissing) l10n.aiStatusModelChat,
          if (embeddingModelMissing) l10n.aiStatusModelEmbedding,
        ].join(' '),
    };

    final actions = <Widget>[
      if (view is AiQueuePausedView)
        FilledButton.tonalIcon(
          key: const Key('ai-status-resume'),
          onPressed: () => ref
              .read(aiOrganizeSettingsProvider.notifier)
              .set(AiOrganizeToggle.enabled, on: true),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: Text(l10n.aiStatusResume),
        ),
      if (view case AiQueueModelView(chatModelMissing: true))
        FilledButton.tonalIcon(
          key: const Key('ai-status-download-chat'),
          onPressed: () => context.push(RoutePaths.chatModel),
          icon: const Icon(Icons.download, size: 18),
          label: Text(l10n.aiStatusDownloadChat),
        ),
      if (view case AiQueueModelView(embeddingModelMissing: true))
        FilledButton.tonalIcon(
          key: const Key('ai-status-download-embedding'),
          onPressed: () => context.push(RoutePaths.embeddingModel),
          icon: const Icon(Icons.download, size: 18),
          label: Text(l10n.aiStatusDownloadEmbedding),
        ),
    ];

    return Card(
      key: const Key('ai-status-card'),
      color: attention
          ? scheme.tertiaryContainer.withValues(alpha: 0.55)
          : null,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: attention || view is AiQueueWorkingView
                        ? scheme.tertiaryContainer
                        : scheme.surfaceContainerHighest,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    view.icon,
                    size: 22,
                    color: attention || view is AiQueueWorkingView
                        ? scheme.onTertiaryContainer
                        : scheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view.headline(l10n),
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: actions),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Mientras organiza, una barra fina en el borde de abajo: dice que
          // algo se mueve sin pedir atención. No hay avance que medir —una
          // pasada no sabe cuánto le falta—, así que es indeterminada.
          if (view is AiQueueWorkingView)
            LinearProgressIndicator(
              minHeight: 3,
              color: scheme.tertiary,
              backgroundColor: scheme.tertiaryContainer.withValues(alpha: 0.4),
            ),
        ],
      ),
    );
  }
}
