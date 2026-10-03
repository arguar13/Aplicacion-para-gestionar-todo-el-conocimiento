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
/// organiza, con una línea que dice qué hace (F27). El de la biblioteca
/// existente lleva además cuánto le falta —ver [AiBackfillProgress]—.
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
                for (final (toggle, icon, title, subtitle) in _types(l10n)) ...[
                  SwitchListTile(
                    key: Key('ai-toggle-${toggle.name}'),
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: _typeStart,
                      end: 16,
                    ),
                    visualDensity: VisualDensity.compact,
                    secondary: Icon(icon, size: _typeIconSize),
                    title: Text(title, style: theme.textTheme.bodyLarge),
                    subtitle: Text(subtitle),
                    value: toggle.valueIn(settings),
                    onChanged: settings.enabled
                        ? (on) => notifier.set(toggle, on: on)
                        : null,
                  ),
                  if (toggle == AiOrganizeToggle.backfillWhileCharging)
                    const AiBackfillProgress(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Cuánto se sangran los de cada tipo y el tamaño de su ícono: la línea de
  /// la biblioteca existente se alinea con sus textos a partir de esto.
  static const _typeStart = 40.0;
  static const _typeIconSize = 20.0;

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

/// Cuánto le falta a la IA de la biblioteca que ya existía (F27), debajo de
/// su interruptor y alineado con su texto: cuántos quedan, si espera el
/// cargador para seguir y, mientras la recorre, una barra fina.
///
/// La cola no dice de dónde salió el elemento en curso. Lo nuevo va siempre
/// primero, así que si está organizando, no queda nada nuevo y sí queda de
/// antes, está con la biblioteca existente. Lo pedido a mano y las notas que
/// crecieron también pasan sin nada nuevo en la cola, pero de a uno: la barra
/// diría «ordenándola» durante esa sola pasada.
class AiBackfillProgress extends ConsumerWidget {
  const AiBackfillProgress({super.key});

  /// Donde empieza el texto de las filas de cada tipo: el sangrado, el ícono
  /// y el espacio que `ListTile` deja entre el ícono y el texto.
  static const _textStart =
      AiOrganizeSwitches._typeStart + AiOrganizeSwitches._typeIconSize + 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = ref.watch(aiBacklogCountProvider).valueOrNull;
    final status = ref.watch(aiOrganizeStatusProvider);
    final settings = ref.watch(aiOrganizeSettingsProvider);
    final on = settings.enabled && settings.backfillWhileCharging;

    final existing = count?.existing ?? 0;
    final working =
        on && existing > 0 && count?.fresh == 0 && status is AiOrganizeWorking;
    final waitingForCharger =
        status is AiOrganizePaused && status.waitingForCharger;
    final text = switch (count) {
      null => null,
      _ when existing == 0 => l10n.settingsAiBackfillDone,
      _ when !on => l10n.settingsAiBackfillOff(existing),
      _ when working => l10n.settingsAiBackfillWorking(existing),
      _ when waitingForCharger => l10n.settingsAiBackfillCharger(existing),
      _ => l10n.settingsAiBackfillRemaining(existing),
    };

    // Aparece cuando llega el número y crece o se achica con la barra, sin
    // saltos: la primera cuenta tarda lo que una consulta.
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: const Key('ai-backfill-progress'),
              padding: const EdgeInsetsDirectional.fromSTEB(
                _textStart,
                0,
                24,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      // Apagado, como el interruptor de arriba: es un dato,
                      // no una invitación.
                      color: on
                          ? scheme.onSurfaceVariant
                          : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  if (working) ...[
                    const SizedBox(height: 6),
                    // Indeterminada, como la de la cola: el total de la
                    // biblioteca de antes no se sabe, solo lo que falta.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        key: const Key('ai-backfill-progress-bar'),
                        minHeight: 3,
                        color: scheme.tertiary,
                        backgroundColor: scheme.tertiaryContainer.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
