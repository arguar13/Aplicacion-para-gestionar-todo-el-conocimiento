import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_picker_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La fila de recortes de la línea de tiempo (F40): **Todo** (el de entrada),
/// **Tema ▾** y **Documento ▾**.
///
/// El recorte es uno solo: elegir un tema deja el documento y al revés, y
/// «Todo» los quita. El que está puesto se ve como un chip con su nombre y una
/// «×» para quitarlo. Una rama del Atlas —que llega de afuera— toma el lugar
/// del recorte con su propio chip, así queda a la vista qué se está mirando.
class TimelineScopeBar extends ConsumerWidget {
  const TimelineScopeBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scope = ref.watch(timelineFilterProvider.select((f) => f.scope));
    final notifier = ref.read(timelineFilterProvider.notifier);

    Future<void> pick(
      Future<TimelineScope?> Function(BuildContext) opener,
    ) async {
      final picked = await opener(context);
      if (picked != null) notifier.setScope(picked);
    }

    Widget scoped({
      required Key key,
      required TimelineScopeKind kind,
      required String emptyLabel,
      required IconData icon,
      required Future<TimelineScope?> Function(BuildContext) opener,
    }) {
      final active = scope?.kind == kind;
      return InputChip(
        key: key,
        avatar: Icon(icon, size: 18),
        label: active
            ? Text(scope!.label, overflow: TextOverflow.ellipsis)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emptyLabel),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
        selected: active,
        showCheckmark: false,
        onPressed: () => pick(opener),
        onDeleted: active ? () => notifier.setScope(null) : null,
        deleteButtonTooltipMessage: l10n.timelineBranchFilterTooltip,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          ChoiceChip(
            key: const ValueKey('timeline-scope-all'),
            label: Text(l10n.timelineScopeAll),
            selected: scope == null,
            onSelected: (_) => notifier.setScope(null),
          ),
          const SizedBox(width: 8),
          scoped(
            key: const ValueKey('timeline-scope-topic'),
            kind: TimelineScopeKind.topic,
            emptyLabel: l10n.timelineScopeTopic,
            icon: Icons.folder_outlined,
            opener: showTimelineTopicPicker,
          ),
          const SizedBox(width: 8),
          scoped(
            key: const ValueKey('timeline-scope-document'),
            kind: TimelineScopeKind.document,
            emptyLabel: l10n.timelineScopeDocument,
            icon: Icons.description_outlined,
            opener: showTimelineDocumentPicker,
          ),
          // Una rama del Atlas no se elige acá —se llega a ella desde el
          // Atlas—, pero una vez puesta se tiene que ver y poder quitar.
          if (scope?.kind == TimelineScopeKind.branch) ...[
            const SizedBox(width: 8),
            InputChip(
              key: const ValueKey('timeline-scope-branch'),
              avatar: const Icon(Icons.account_tree_outlined, size: 18),
              label: Text(scope!.label, overflow: TextOverflow.ellipsis),
              selected: true,
              showCheckmark: false,
              onDeleted: () => notifier.setScope(null),
              deleteButtonTooltipMessage: l10n.timelineBranchFilterTooltip,
            ),
          ],
        ],
      ),
    );
  }
}
