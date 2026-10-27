import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_task_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/ai_task_texts.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_queue_status.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La tarea que se muestra grande cuando la IA hace varias a la vez (F39): la
/// que la persona pidió antes que la de fondo, y entre iguales la que empezó
/// primero. `null` si no hace nada.
AiTask? primaryAiTask(List<AiTask> tasks) {
  if (tasks.isEmpty) return null;
  int rank(AiTask task) => switch (task.kind) {
    AiTaskKind.studyAnalysis => 0,
    AiTaskKind.review => 1,
    AiTaskKind.flashcards || AiTaskKind.dates => 2,
    AiTaskKind.organize => 3,
  };
  final sorted = [...tasks]
    ..sort((a, b) {
      final byKind = rank(a).compareTo(rank(b));
      return byKind != 0 ? byKind : a.startedAt.compareTo(b.startedAt);
    });
  return sorted.first;
}

/// «Ahora» (F39, paso 6): lo que la IA hace en este momento, arriba de «Lo que
/// hizo la IA». Una sola tarjeta —aunque la IA haga más de una cosa a la
/// vez—: qué hace, con qué modelo, cuánto va, cuánto lleva y cuántos tokens
/// gastó, y debajo, plegado, «Cómo lo hace» con los pasos y el que va.
///
/// Sin nada en curso no ocupa lugar. Sale de [aiLiveTasksProvider]: no sabe si
/// la tarea es un análisis para estudiar o la cola que organiza sola.
class AiNowCard extends ConsumerWidget {
  const AiNowCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(aiLiveTasksProvider);
    final primary = primaryAiTask(tasks);
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: primary == null
          ? const SizedBox(width: double.infinity)
          : _NowCard(
              key: const Key('ai-now-card'),
              task: primary,
              others: [
                for (final task in tasks)
                  if (task.id != primary.id) task,
              ],
            ),
    );
  }
}

class _NowCard extends ConsumerStatefulWidget {
  const _NowCard({required this.task, required this.others, super.key});

  final AiTask task;
  final List<AiTask> others;

  @override
  ConsumerState<_NowCard> createState() => _NowCardState();
}

class _NowCardState extends ConsumerState<_NowCard> {
  /// «Cómo lo hace» arranca plegado: el detalle no carga la pantalla.
  var _expanded = false;

  /// El tiempo que lleva corre solo, sin esperar a que cambie la tarea.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final task = widget.task;
    final now = ref.watch(clockProvider)();
    final percent = task.percent;
    final progress = task.progress;
    final retry = task.retry;
    final queue = ref.watch(aiQueueViewProvider);
    // Lo que sigue en la cola de fondo, cuando lo que se hace es de la cola.
    final pending =
        queue is AiQueueWorkingView &&
            (task.kind == AiTaskKind.organize ||
                task.kind == AiTaskKind.flashcards ||
                task.kind == AiTaskKind.dates)
        ? queue.pending
        : null;
    final model = task.model;

    return Card(
      color: scheme.tertiaryContainer.withValues(alpha: 0.35),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AiSparkCircle(size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.aiNowLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.tertiary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        aiTaskHeadline(l10n, task),
                        key: const Key('ai-now-headline'),
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (retry != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          aiRetryingText(
                            l10n,
                            attempt: retry.attempt,
                            maxAttempts: retry.maxAttempts,
                            failure: retry.failure,
                          ),
                          key: const Key('ai-now-retry'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ] else if (progress != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          aiProgressText(l10n, progress),
                          key: const Key('ai-now-progress'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (percent != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    l10n.aiNowPercent(percent),
                    key: const Key('ai-now-percent'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.tertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Determinada cuando se sabe cuánto va; si no, indeterminada.
          LinearProgressIndicator(
            key: const Key('ai-now-bar'),
            value: percent == null ? null : percent / 100,
            minHeight: 3,
            color: scheme.tertiary,
            backgroundColor: scheme.tertiaryContainer.withValues(alpha: 0.4),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (model != null && model.trim().isNotEmpty)
                  _Stat(
                    key: const Key('ai-now-model'),
                    icon: Icons.memory,
                    label: modelLabel(model),
                  ),
                _Stat(
                  key: const Key('ai-now-elapsed'),
                  icon: Icons.schedule,
                  label: l10n.aiNowElapsed(
                    aiDurationText(l10n, task.elapsed(now)),
                  ),
                ),
                _Stat(
                  key: const Key('ai-now-tokens'),
                  icon: Icons.token_outlined,
                  label: l10n.aiNowTokens(aiTokenCount(locale, task.tokens)),
                ),
              ],
            ),
          ),
          if (pending != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                l10n.aiStatusWorkingMessage(pending),
                key: const Key('ai-now-pending'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (task.steps.isNotEmpty) ...[
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            _HowHeader(
              expanded: _expanded,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? _Steps(task: task, locale: locale)
                  : const SizedBox(width: double.infinity),
            ),
          ],
          if (widget.others.isNotEmpty) _Others(others: widget.others),
        ],
      ),
    );
  }
}

/// Un dato de la tarea en una píldora tonal: el modelo, el tiempo, los tokens.
class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: scheme.surface.withValues(alpha: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El encabezado plegable de «Cómo lo hace».
class _HowHeader extends StatelessWidget {
  const _HowHeader({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      expanded: expanded,
      child: InkWell(
        key: const Key('ai-now-how'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.aiNowHow,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los pasos de la tarea, con el que va marcado, y los tokens leídos y
/// escritos.
class _Steps extends StatelessWidget {
  const _Steps({required this.task, required this.locale});

  final AiTask task;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final part = task.partProgress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in task.steps)
            _StepRow(
              key: Key('ai-now-step-${step.name}'),
              label: aiStepLabel(l10n, step),
              // El paso que manda cada parte dice cuál va.
              detail:
                  part != null &&
                      task.stateOf(step) == AiTaskStepState.running &&
                      step == AiTaskStepKind.studySend
                  ? l10n.aiNowStepInPart(part.current, part.total)
                  : null,
              state: task.stateOf(step),
            ),
          const SizedBox(height: 4),
          Text(
            l10n.aiNowTokensSplit(
              aiTokenCount(locale, task.inputTokens),
              aiTokenCount(locale, task.outputTokens),
            ),
            key: const Key('ai-now-tokens-split'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.state,
    this.detail,
    super.key,
  });

  final String label;
  final String? detail;
  final AiTaskStepState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = state == AiTaskStepState.running;
    final done = state == AiTaskStepState.done;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 18,
            child: switch (state) {
              AiTaskStepState.done => Icon(
                Icons.check_circle,
                size: 18,
                color: scheme.primary,
              ),
              AiTaskStepState.running => Padding(
                padding: const EdgeInsets.all(2),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.tertiary,
                ),
              ),
              AiTaskStepState.pending => Icon(
                Icons.radio_button_unchecked,
                size: 18,
                color: scheme.outline,
              ),
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (detail != null)
                    TextSpan(
                      text: ' · $detail',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: running ? FontWeight.w600 : FontWeight.w400,
                color: done || running
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Las otras tareas que la IA hace a la vez, en una línea cada una: la
/// tarjeta cuenta una sola.
class _Others extends StatelessWidget {
  const _Others({required this.others});

  final List<AiTask> others;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      key: const Key('ai-now-others'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.aiNowOthers(others.length), style: style),
          for (final task in others)
            Text(
              task.percent == null
                  ? task.title
                  : l10n.aiNowOtherTask(task.title, task.percent!),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
