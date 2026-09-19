import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/health/domain/entities/health_thresholds.dart';
import 'package:sinapsis/features/health/domain/entities/note_composition.dart';
import 'package:sinapsis/features/health/presentation/providers/health_providers.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El estado de la bóveda de un vistazo: cuatro indicadores, cada uno tocable y
/// con la pantalla donde se actúa sobre él, y tres accesos a lo que también
/// pide mantenimiento. Vive al tope de la Biblioteca, que es la pantalla de
/// inicio: no es un octavo destino de navegación.
///
/// Un número que no lleva a ninguna acción es decoración, así que no hay
/// ninguno de esos: la Bandeja lleva a la Bandeja, el vocabulario a
/// Vocabulario y las contradicciones a Tensión. Las notas por madurez llevan a
/// las notas que crecieron esta semana, que es donde se consolidan.
///
/// Plegado por defecto, pero con los cuatro números a la vista: una sola fila
/// de píldoras tocables. La barra de la Biblioteca ya ocupa mucho alto y una
/// lista sin lugar es peor que un panel que se despliega; desplegado agrega las
/// etiquetas, el desglose por madurez, los avisos y los accesos, con una altura
/// acotada.
///
/// Mientras un indicador se calcula muestra `…` en vez de un indicador de
/// carga: el panel no anima nada mientras espera.
class HealthPanel extends ConsumerStatefulWidget {
  const HealthPanel({this.initiallyExpanded = false, super.key});

  final bool initiallyExpanded;

  @override
  ConsumerState<HealthPanel> createState() => _HealthPanelState();
}

class _HealthPanelState extends ConsumerState<HealthPanel> {
  late var _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final inbox = ref.watch(inboxPendingIdsProvider).valueOrNull?.length;
    final composition = ref.watch(noteCompositionProvider).valueOrNull;
    final vocabulary = ref
        .watch(mergeCandidateGroupsProvider)
        .valueOrNull
        ?.length;
    final contradictions = ref
        .watch(unreviewedContradictionCountProvider)
        .valueOrNull;
    final grown = ref.watch(grownNotesProvider).valueOrNull?.length;
    final brokenLinks = ref.watch(brokenLinkCountProvider).valueOrNull;
    final suggestions = ref
        .watch(pendingPropertySuggestionGroupsProvider)
        .valueOrNull
        ?.fold<int>(0, (total, group) => total + group.suggestions.length);

    String show(int? value) => value == null ? '…' : '$value';

    final inboxAlert = inbox != null && inbox > kInboxWarningThreshold;
    final notesAlert = composition?.fragmentsOutweighSynthesis ?? false;

    // Adónde lleva cada indicador. La Bandeja es una pestaña de la app: se
    // cambia a ella; el resto se abre encima.
    void openInbox() => context.go(RoutePaths.inbox);
    void openNotes() => context.push(RoutePaths.grownNotes);
    void openVocabulary() => context.push(RoutePaths.vocabulary);
    void openTension() => context.push(RoutePaths.graphTension);
    // El mismo ícono que usa la pantalla de Tensión.
    final contradictionIcon = RelationKind.contradicts.icon;

    final pills = [
      _HealthPill(
        icon: Icons.inbox_outlined,
        text: show(inbox),
        tooltip: l10n.healthInboxLabel,
        alert: inboxAlert,
        onTap: openInbox,
      ),
      _HealthPill(
        icon: Icons.spa_outlined,
        text: show(composition?.total),
        tooltip: l10n.healthNotesLabel,
        alert: notesAlert,
        onTap: openNotes,
      ),
      _HealthPill(
        icon: Icons.spellcheck_outlined,
        text: show(vocabulary),
        tooltip: l10n.healthVocabularyLabel,
        onTap: openVocabulary,
      ),
      _HealthPill(
        icon: contradictionIcon,
        text: show(contradictions),
        tooltip: l10n.healthContradictionsLabel,
        onTap: openTension,
      ),
    ];

    final tiles = [
      _HealthTile(
        icon: Icons.inbox_outlined,
        label: l10n.healthInboxLabel,
        value: Text(show(inbox), style: theme.textTheme.headlineSmall),
        warning: inboxAlert ? l10n.healthInboxWarning : null,
        onTap: openInbox,
      ),
      _HealthTile(
        icon: Icons.spa_outlined,
        label: l10n.healthNotesLabel,
        value: composition == null
            ? Text('…', style: theme.textTheme.headlineSmall)
            : _MaturityCounts(composition: composition),
        detail: composition == null
            ? null
            : l10n.healthNotesKinds(
                composition.kindCount(NoteKind.atomic),
                composition.kindCount(NoteKind.living),
              ),
        warning: notesAlert ? l10n.healthNotesWarning : null,
        onTap: openNotes,
      ),
      _HealthTile(
        icon: Icons.spellcheck_outlined,
        label: l10n.healthVocabularyLabel,
        value: Text(show(vocabulary), style: theme.textTheme.headlineSmall),
        onTap: openVocabulary,
      ),
      _HealthTile(
        icon: contradictionIcon,
        label: l10n.healthContradictionsLabel,
        value: Text(show(contradictions), style: theme.textTheme.headlineSmall),
        onTap: openTension,
      ),
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Tooltip(
                    message: l10n.healthPanelTitle,
                    child: Icon(
                      Icons.monitor_heart_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _expanded
                        ? Text(
                            l10n.healthPanelTitle,
                            style: theme.textTheme.titleSmall,
                          )
                        // Plegado, los cuatro números a la vista. Si no
                        // caben —una pantalla muy angosta— se desplazan.
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final pill in pills) ...[
                                  pill,
                                  const SizedBox(width: 6),
                                ],
                              ],
                            ),
                          ),
                  ),
                  IconButton(
                    tooltip: _expanded
                        ? l10n.healthPanelHide
                        : l10n.healthPanelShow,
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: _toggle,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              // Nunca más de la mitad del alto: la lista de abajo tiene que
              // seguir teniendo lugar aunque la pantalla sea baja.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 8.0;
                        // Cuatro en fila si hay lugar; dos por fila en un
                        // teléfono.
                        final columns = constraints.maxWidth >= 640 ? 4 : 2;
                        final width =
                            (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            for (final tile in tiles)
                              SizedBox(width: width, child: tile),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (grown != null)
                          ActionChip(
                            avatar: const Icon(Icons.trending_up, size: 18),
                            label: Text(l10n.healthGrownNotes(grown)),
                            onPressed: openNotes,
                          ),
                        if (brokenLinks != null)
                          ActionChip(
                            avatar: const Icon(Icons.link_off, size: 18),
                            label: Text(l10n.healthBrokenLinks(brokenLinks)),
                            onPressed: () =>
                                context.push(RoutePaths.brokenLinks),
                          ),
                        if (suggestions != null)
                          ActionChip(
                            avatar: const Icon(Icons.checklist, size: 18),
                            label: Text(l10n.healthSuggestions(suggestions)),
                            onPressed: () =>
                                context.push(RoutePaths.suggestionReview),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Un indicador en su forma más chica: un ícono y su número, tocable. Es lo que
/// se ve con el panel plegado. En alerta se pinta como el resto de los avisos.
class _HealthPill extends StatelessWidget {
  const _HealthPill({
    required this.icon,
    required this.text,
    required this.tooltip,
    required this.onTap,
    this.alert = false,
  });

  final IconData icon;
  final String text;
  final String tooltip;
  final bool alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = alert ? scheme.onErrorContainer : scheme.onSurface;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: alert ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
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

/// Un indicador: su número —o lo que lo represente—, su nombre, una línea de
/// detalle y, si hay algo que señalar, un aviso que lo pinta en alerta.
class _HealthTile extends StatelessWidget {
  const _HealthTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.detail,
    this.warning,
  });

  final IconData icon;
  final String label;
  final Widget value;
  final String? detail;

  /// Si está, el indicador se pinta en alerta y lo dice.
  final String? warning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final alert = warning != null;
    final foreground = alert ? scheme.onErrorContainer : scheme.onSurface;

    return Material(
      color: alert ? scheme.errorContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foreground),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: foreground),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                value,
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
                if (warning != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber, size: 14, color: foreground),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          warning!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cuántas notas hay en cada etapa de madurez, con el tono de cada etapa.
class _MaturityCounts extends StatelessWidget {
  const _MaturityCounts({required this.composition});

  final NoteComposition composition;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        for (final maturity in NoteMaturity.values)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${composition.maturityCount(maturity)}',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: maturity.color(theme.colorScheme),
                ),
              ),
              Text(maturity.label(l10n), style: theme.textTheme.labelSmall),
            ],
          ),
      ],
    );
  }
}
