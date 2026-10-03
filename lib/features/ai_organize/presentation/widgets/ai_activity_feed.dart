import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una fila de la actividad de la IA (F27): el encabezado de un día o un
/// elemento con sus pasadas de ese día.
sealed class AiActivityEntry {
  const AiActivityEntry();
}

final class AiActivityDayEntry extends AiActivityEntry {
  const AiActivityDayEntry(this.day);

  /// El día, a la medianoche local.
  final DateTime day;
}

final class AiActivityItemEntry extends AiActivityEntry {
  const AiActivityItemEntry({
    required this.itemId,
    required this.itemTitle,
    required this.runs,
  });

  final String itemId;
  final String itemTitle;

  /// Las pasadas de ese elemento en ese día, de la más nueva a la más vieja.
  final List<AiRun> runs;
}

/// Ordena [runs] —de la más nueva a la más vieja, como llegan— en días y,
/// dentro de cada día, por elemento: «en orden de fecha y agrupada por
/// elemento», como pide el plan. Un elemento que la IA organizó dos veces el
/// mismo día es una sola tarjeta; en días distintos, una por día, porque la
/// actividad se lee como una línea de tiempo.
List<AiActivityEntry> groupAiActivity(List<AiRun> runs) {
  final entries = <AiActivityEntry>[];
  DateTime? currentDay;
  final itemsOfDay = <String, List<AiRun>>{};
  final titles = <String, String>{};

  void closeDay() {
    for (final MapEntry(key: itemId, value: dayRuns) in itemsOfDay.entries) {
      entries.add(
        AiActivityItemEntry(
          itemId: itemId,
          itemTitle: titles[itemId]!,
          runs: List.unmodifiable(dayRuns),
        ),
      );
    }
    itemsOfDay.clear();
  }

  for (final run in runs) {
    final local = run.startedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (day != currentDay) {
      closeDay();
      currentDay = day;
      entries.add(AiActivityDayEntry(day));
    }
    itemsOfDay.putIfAbsent(run.itemId, () => []).add(run);
    titles[run.itemId] = run.itemTitle;
  }
  closeDay();
  return entries;
}

/// «Hoy», «Ayer» o la fecha, sobre la lista de un día.
class AiActivityDayHeader extends StatelessWidget {
  const AiActivityDayHeader({required this.day, required this.now, super.key});

  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final today = DateTime(now.year, now.month, now.day);
    final label = switch (today.difference(day).inDays) {
      0 => l10n.aiActivityToday,
      1 => l10n.aiActivityYesterday,
      _ => DateFormat.MMMMEEEEd(locale).format(day),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Un elemento y lo que la IA hizo en él ese día: una tarjeta que lo abre,
/// con lo que sigue siendo de la IA de cada pasada y su «Deshacer».
///
/// Cuenta lo que queda (`AiRun.remaining`), no lo que se creó: lo que la
/// persona ya adoptó o borró no es algo que deshacer.
class AiActivityItemCard extends StatelessWidget {
  const AiActivityItemCard({
    required this.entry,
    required this.busyRunIds,
    required this.onUndoRun,
    this.workingTitle,
    this.onOpen,
    this.onUndoItem,
    super.key,
  });

  final AiActivityItemEntry entry;

  /// Las pasadas que se están deshaciendo: su botón espera.
  final Set<String> busyRunIds;
  final ValueChanged<AiRun> onUndoRun;

  /// El título de lo que la cola organiza ahora, para marcar la pasada en
  /// curso.
  final String? workingTitle;

  /// Abre el elemento; `null` si la actividad ya es solo de ese elemento.
  final VoidCallback? onOpen;

  /// «Deshacer todo» del elemento; aparece cuando hay más de una pasada que
  /// deshacer.
  final VoidCallback? onUndoItem;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.Hm(locale);
    final undoable = entry.runs.where(_isUndoable).length;
    final several = entry.runs.length > 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: Key('ai-activity-item-${entry.itemId}'),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                  child: Row(
                    children: [
                      const AiSparkCircle(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.itemTitle,
                              style: theme.textTheme.titleSmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              time.format(entry.runs.first.startedAt.toLocal()),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onOpen != null)
                        Tooltip(
                          message: l10n.aiActivityOpenItem,
                          child: Icon(
                            Icons.chevron_right,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              for (final (index, run) in entry.runs.indexed) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    indent: 60,
                    endIndent: 16,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(60, 8, 8, 10),
                  child: _RunRow(
                    run: run,
                    time: several ? time.format(run.startedAt.toLocal()) : null,
                    busy: busyRunIds.contains(run.id),
                    inProgress:
                        run.finishedAt == null &&
                        !run.isUndone &&
                        run.itemTitle == workingTitle,
                    onUndo: () => onUndoRun(run),
                  ),
                ),
              ],
              if (undoable > 1 && onUndoItem != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(52, 0, 8, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: Key('ai-activity-undo-item-${entry.itemId}'),
                      onPressed: onUndoItem,
                      icon: const Icon(Icons.undo, size: 18),
                      label: Text(l10n.aiItemUndoAll),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Si a [run] le queda algo de la IA que deshacer.
bool _isUndoable(AiRun run) => !run.isUndone && !run.remaining.isEmpty;

class _RunRow extends StatelessWidget {
  const _RunRow({
    required this.run,
    required this.time,
    required this.busy,
    required this.inProgress,
    required this.onUndo,
  });

  final AiRun run;

  /// La hora de la pasada, cuando la tarjeta tiene más de una.
  final String? time;
  final bool busy;
  final bool inProgress;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final Widget body;
    if (run.isUndone) {
      body = _QuietNote(icon: Icons.undo, text: l10n.aiRunUndone);
    } else if (run.remaining.isEmpty) {
      body = inProgress
          ? _QuietNote(icon: Icons.auto_awesome, text: l10n.aiRunInProgress)
          : _QuietNote(
              icon: Icons.check_circle_outline,
              text: l10n.aiRunNothingLeft,
            );
    } else {
      body = Row(
        children: [
          Expanded(child: AiTallyPills(tally: run.remaining)),
          const SizedBox(width: 8),
          TextButton.icon(
            key: Key('ai-run-undo-${run.id}'),
            onPressed: busy ? null : onUndo,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.undo, size: 18),
            label: Text(l10n.aiRunUndo),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (time != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(time!, style: theme.textTheme.labelSmall),
          ),
        // Deshacer cambia la fila de las píldoras a «Deshecha»: se funde.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(
            key: ValueKey((run.isUndone, run.remaining)),
            child: body,
          ),
        ),
      ],
    );
  }
}

/// Lo que ya no se puede deshacer —deshecha, o nada que siga siendo de la
/// IA—, dicho en voz baja.
class _QuietNote extends StatelessWidget {
  const _QuietNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
