import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_activity_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_queue_status.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Lo que hizo la IA» en Ajustes › IA (F27), con el estado de la cola en
/// una línea y cuántas cosas esperan revisión: lo que hay que saber de un
/// vistazo, y un toque para ver el resto.
class AiActivitySettingsTile extends ConsumerWidget {
  const AiActivitySettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final view = ref.watch(aiQueueViewProvider);
    final reviewCount = ref.watch(pendingReviewCountProvider).valueOrNull ?? 0;
    final queued = switch (view) {
      AiQueueWorkingView(:final pending) ||
      AiQueueChargerView(:final pending) ||
      AiQueuePausedView(:final pending) => pending,
      _ => 0,
    };

    return ListTile(
      key: const Key('settings-ai-activity'),
      leading: Icon(
        view.icon,
        color: view is AiQueueModelView || view is AiQueueWorkingView
            ? scheme.tertiary
            : null,
      ),
      title: Text(l10n.aiActivityTitle),
      subtitle: Text(
        [
          view.headline(l10n),
          if (queued > 0) l10n.aiStatusQueued(queued),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reviewCount > 0)
            Tooltip(
              message: l10n.aiReviewPendingCount(reviewCount),
              child: Badge(
                key: const Key('settings-ai-review-count'),
                backgroundColor: scheme.tertiary,
                textColor: scheme.onTertiary,
                label: Text('$reviewCount'),
              ),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => context.push(RoutePaths.aiActivity),
    );
  }
}

/// El interruptor general «Organizar con IA» y, debajo, uno por cada cosa que
/// organiza, con una línea que dice qué hace (F27).
///
/// Los de cada tipo cuelgan del general —sangrados, más chicos— y se apagan
/// con él: apagado el general, la cola no toma nada nuevo y elegir tipos no
/// cambiaría nada. Lo que cada uno tenía elegido se conserva para cuando se
/// vuelva a prender.
class AiOrganizeSwitches extends ConsumerWidget {
  const AiOrganizeSwitches({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.watch(aiOrganizeSettingsProvider);
    final notifier = ref.read(aiOrganizeSettingsProvider.notifier);

    return Column(
      children: [
        SwitchListTile(
          key: const Key('ai-toggle-enabled'),
          secondary: const Icon(Icons.auto_awesome_outlined),
          title: Text(l10n.settingsAiOrganize),
          subtitle: Text(l10n.settingsAiOrganizeSubtitle),
          value: settings.enabled,
          onChanged: (on) => notifier.set(AiOrganizeToggle.enabled, on: on),
        ),
        // El fondo un tono más hundido agrupa los de cada tipo bajo el
        // general sin otra tarjeta adentro de la tarjeta. `Material` y no una
        // caja pintada: cada fila dibuja su tinta en el `Material` más
        // cercano, y debajo de una caja con color quedaría tapada.
        Material(
          color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (toggle, icon, title, subtitle) in _types(l10n))
                  SwitchListTile(
                    key: Key('ai-toggle-${toggle.name}'),
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: 40,
                      end: 16,
                    ),
                    visualDensity: VisualDensity.compact,
                    secondary: Icon(icon, size: 20),
                    title: Text(title, style: theme.textTheme.bodyLarge),
                    subtitle: Text(subtitle),
                    value: toggle.valueIn(settings),
                    onChanged: settings.enabled
                        ? (on) => notifier.set(toggle, on: on)
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static List<(AiOrganizeToggle, IconData, String, String)> _types(
    AppLocalizations l10n,
  ) => [
    (
      AiOrganizeToggle.relations,
      Icons.link,
      l10n.settingsAiRelations,
      l10n.settingsAiRelationsSubtitle,
    ),
    (
      AiOrganizeToggle.flashcards,
      Icons.style_outlined,
      l10n.settingsAiFlashcards,
      l10n.settingsAiFlashcardsSubtitle,
    ),
    (
      AiOrganizeToggle.properties,
      Icons.sell_outlined,
      l10n.settingsAiProperties,
      l10n.settingsAiPropertiesSubtitle,
    ),
    (
      AiOrganizeToggle.space,
      Icons.folder_outlined,
      l10n.settingsAiSpace,
      l10n.settingsAiSpaceSubtitle,
    ),
    (
      AiOrganizeToggle.reference,
      Icons.menu_book_outlined,
      l10n.settingsAiReference,
      l10n.settingsAiReferenceSubtitle,
    ),
    (
      AiOrganizeToggle.atlas,
      Icons.account_tree_outlined,
      l10n.settingsAiAtlas,
      l10n.settingsAiAtlasSubtitle,
    ),
    (
      AiOrganizeToggle.backfillWhileCharging,
      Icons.battery_charging_full,
      l10n.settingsAiBackfill,
      l10n.settingsAiBackfillSubtitle,
    ),
  ];
}
