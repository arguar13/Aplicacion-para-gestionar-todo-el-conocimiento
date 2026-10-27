import 'package:flutter/material.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_picker_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué recorre la IA en «Organizar con IA» (F40): [scope] es el tema, la rama
/// del Atlas o el documento; `null`, toda la biblioteca.
@immutable
class TimelineAiChoice {
  const TimelineAiChoice(this.scope);

  final TimelineScope? scope;

  @override
  bool operator ==(Object other) =>
      other is TimelineAiChoice && other.scope == scope;

  @override
  int get hashCode => scope.hashCode;
}

/// Abre la hoja «Organizar con IA» de la línea de tiempo. Devuelve lo elegido,
/// o `null` si se cerró sin elegir.
///
/// [initial] es el recorte que la línea ya tiene puesto: viene preelegido, así
/// que quien está mirando un tema o un documento pide su búsqueda con un solo
/// toque.
Future<TimelineAiChoice?> showTimelineAiSheet(
  BuildContext context, {
  TimelineScope? initial,
}) {
  return showModalBottomSheet<TimelineAiChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AiSheet(initial: initial),
  );
}

class _AiSheet extends StatefulWidget {
  const _AiSheet({this.initial});

  final TimelineScope? initial;

  @override
  State<_AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<_AiSheet> {
  /// El recorte elegido; `null` es «Todo». Un tema, un documento o una rama
  /// del Atlas: de a uno, como en la fila de chips de la línea.
  ///
  /// Una fila de tema o de documento solo se marca cuando ya hay uno elegido:
  /// tocarla abre la hoja para elegirlo, y si se cierra sin elegir, queda lo
  /// que estaba. Así lo marcado siempre se puede recorrer.
  TimelineScope? _scope;

  @override
  void initState() {
    super.initState();
    _scope = widget.initial;
  }

  Future<void> _pick(
    Future<TimelineScope?> Function(BuildContext) opener,
  ) async {
    final picked = await opener(context);
    if (picked == null || !mounted) return;
    setState(() => _scope = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scope = _scope;
    final kind = scope?.kind;
    final branch = widget.initial?.kind == TimelineScopeKind.branch
        ? widget.initial
        : null;

    String chosen(TimelineScopeKind wanted, String emptyHint) =>
        kind == wanted ? scope!.label : emptyHint;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(
                l10n.timelineAiAction,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.timelineAiSheetHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            _Choice(
              key: const ValueKey('timeline-ai-all'),
              icon: Icons.all_inclusive,
              title: l10n.timelineScopeAll,
              subtitle: l10n.timelineAiScopeAllHint,
              selected: scope == null,
              onTap: () => setState(() => _scope = null),
            ),
            _Choice(
              key: const ValueKey('timeline-ai-topic'),
              icon: Icons.folder_outlined,
              title: l10n.timelineScopeTopic,
              subtitle: chosen(
                TimelineScopeKind.topic,
                l10n.timelineAiScopeTopicHint,
              ),
              selected: kind == TimelineScopeKind.topic,
              picks: true,
              onTap: () => _pick(showTimelineTopicPicker),
            ),
            _Choice(
              key: const ValueKey('timeline-ai-document'),
              icon: Icons.description_outlined,
              title: l10n.timelineScopeDocument,
              subtitle: chosen(
                TimelineScopeKind.document,
                l10n.timelineAiScopeDocumentHint,
              ),
              selected: kind == TimelineScopeKind.document,
              picks: true,
              onTap: () => _pick(showTimelineAnyDocumentPicker),
            ),
            // Una rama del Atlas no se elige acá —se llega a ella desde el
            // Atlas—, pero si la línea la tiene puesta se puede recorrer.
            if (branch != null)
              _Choice(
                key: const ValueKey('timeline-ai-branch'),
                icon: Icons.account_tree_outlined,
                title: branch.label,
                subtitle: l10n.timelineAiScopeBranchHint,
                selected: kind == TimelineScopeKind.branch,
                onTap: () => setState(() => _scope = branch),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: FilledButton.icon(
                key: const ValueKey('timeline-ai-start'),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(l10n.timelineAiStart),
                onPressed: () =>
                    Navigator.of(context).pop(TimelineAiChoice(scope)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una fila de la hoja: una opción de qué recorrer, de a una. [picks] dice que
/// al tocarla se abre una hoja para elegir el tema o el documento.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.picks = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool picks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Una opción entre varias: el lector de pantalla la dice como un botón de
    // radio, marcada o no.
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: picks ? const Icon(Icons.arrow_drop_down) : null,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}
