import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/reading_queue.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/sleep_timer.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La cola del lector en voz alta (F47, paso 2, captura 7), en una hoja:
///
/// - **Ahora suena**, con «Leer: Todo · Resumen · Síntesis · Palabras clave»
///   (F39) y «Dejar de leer»;
/// - **En esta pantalla**, si la que se ve ofrece otro texto: sumarlo a la
///   cola o leerlo ya;
/// - **Siguiente**, en orden, para reordenar arrastrando, sacar de a uno o
///   «Limpiar cola»; tocar uno lo lee ya;
/// - **Repetir** y el **Temporizador para dormir**.
class ReadAloudQueueSheet extends ConsumerWidget {
  const ReadAloudQueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final controller = ref.read(readAloudControllerProvider.notifier);
    final (document, scope, queue) = ref.watch(
      readAloudControllerProvider.select((s) => (s.document, s.scope, s.queue)),
    );
    final offered = ref.watch(currentReadableProvider);
    final upcoming = queue.upcoming;
    // La pantalla ofrece otra cosa que lo que suena: se puede sumar.
    final onScreen = offered != null && offered.id != document?.id
        ? offered
        : null;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: CustomScrollView(
        key: const Key('read-aloud-queue-sheet'),
        shrinkWrap: true,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                l10n.f47P2Queue,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (document != null) ...[
            _Header(l10n.f47P2NowPlaying),
            SliverToBoxAdapter(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const Icon(Icons.graphic_eq_rounded),
                title: Text(document.title),
                subtitle: scope == ReadScope.all
                    ? null
                    : Text(readScopeLabel(scope, l10n)),
              ),
            ),
            SliverToBoxAdapter(child: _ScopeChoice(document: document)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const Key('read-aloud-close'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      unawaited(controller.close());
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(l10n.readAloudClose),
                  ),
                ),
              ),
            ),
          ],
          if (onScreen != null) ...[
            _Header(l10n.f47P2OnThisScreen),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(onScreen.title, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        FilledButton.tonalIcon(
                          key: const Key('read-aloud-queue-add'),
                          onPressed: () =>
                              unawaited(controller.enqueue(onScreen)),
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: Text(l10n.f47P2AddToQueue),
                        ),
                        TextButton.icon(
                          key: const Key('read-aloud-queue-read-now'),
                          onPressed: () {
                            Navigator.of(context).pop();
                            unawaited(controller.open(onScreen));
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(l10n.f47P2ReadNow),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    l10n.f47P2Next,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (upcoming.isNotEmpty)
                    TextButton(
                      key: const Key('read-aloud-queue-clear'),
                      onPressed: controller.clearQueue,
                      child: Text(l10n.f47P2ClearQueue),
                    ),
                ],
              ),
            ),
          ),
          if (upcoming.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  l10n.f47P2QueueEmpty,
                  key: const Key('read-aloud-queue-empty'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else ...[
            if (upcoming.length > 1)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    l10n.f47P2Reorder,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            SliverReorderableList(
              itemCount: upcoming.length,
              onReorderItem: controller.moveInQueue,
              itemBuilder: (context, index) {
                final reading = upcoming[index];
                return _QueuedTile(
                  key: ValueKey('${reading.document.id}·${reading.scope.name}'),
                  index: index,
                  reading: reading,
                );
              },
            ),
          ],
          _Header(l10n.f47P2Repeat),
          SliverToBoxAdapter(child: _RepeatChoice(repeat: queue.repeat)),
          _Header(l10n.f47P2SleepTimer),
          const SliverToBoxAdapter(child: _SleepChoice()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// El nombre de cada parte de un texto que se estudia (F39).
String readScopeLabel(ReadScope scope, AppLocalizations l10n) =>
    switch (scope) {
      ReadScope.all => l10n.readAloudScopeAll,
      ReadScope.summary => l10n.readAloudScopeSummary,
      ReadScope.synthesis => l10n.readAloudScopeSynthesis,
      ReadScope.keywords => l10n.readAloudScopeKeywords,
    };

class _Header extends StatelessWidget {
  const _Header(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      sliver: SliverToBoxAdapter(
        child: Semantics(
          header: true,
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// «Leer: Todo · Resumen · Síntesis · Palabras clave» (F39): qué parte del
/// texto se lee. Solo la lleva un texto que se estudia; la parte que todavía
/// no tiene nada —no hay resumen, o el texto está plegado— aparece apagada.
/// Elegir una empieza a leerla desde el principio.
class _ScopeChoice extends ConsumerWidget {
  const _ScopeChoice({required this.document});

  final ReadableDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!document.hasScopes) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final controller = ref.read(readAloudControllerProvider.notifier);
    final scope = ref.watch(readAloudControllerProvider.select((s) => s.scope));

    return Padding(
      key: const Key('read-aloud-scopes'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.readAloudScopeLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final option in ReadScope.values)
            ChoiceChip(
              key: Key('read-aloud-scope-${option.name}'),
              label: Text(readScopeLabel(option, l10n)),
              selected: option == scope,
              // Sin onSelected, el chip queda apagado.
              onSelected: document.offers(option)
                  ? (_) => unawaited(controller.setScope(option))
                  : null,
            ),
        ],
      ),
    );
  }
}

class _QueuedTile extends ConsumerWidget {
  const _QueuedTile({required this.index, required this.reading, super.key});

  final int index;
  final QueuedReading reading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(readAloudControllerProvider.notifier);
    final title = reading.document.title;
    return ReorderableDelayedDragStartListener(
      index: index,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: Key('read-aloud-queued-$index'),
          contentPadding: const EdgeInsetsDirectional.only(start: 8, end: 8),
          leading: ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_indicator_rounded),
            ),
          ),
          title: Text(title),
          subtitle: reading.scope == ReadScope.all
              ? null
              : Text(readScopeLabel(reading.scope, l10n)),
          onTap: () => unawaited(controller.playQueued(index)),
          trailing: IconButton(
            key: Key('read-aloud-queue-remove-$index'),
            tooltip: l10n.f47P2RemoveFromQueue(title),
            onPressed: () => controller.removeFromQueue(index),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ),
    );
  }
}

class _RepeatChoice extends ConsumerWidget {
  const _RepeatChoice({required this.repeat});

  final ReadAloudRepeat repeat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(readAloudControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final option in ReadAloudRepeat.values)
            ChoiceChip(
              key: Key('read-aloud-repeat-${option.name}'),
              label: Text(switch (option) {
                ReadAloudRepeat.off => l10n.f47P2RepeatChoiceOff,
                ReadAloudRepeat.all => l10n.f47P2RepeatChoiceAll,
                ReadAloudRepeat.one => l10n.f47P2RepeatChoiceOne,
              }),
              selected: option == repeat,
              onSelected: (_) => controller.setRepeat(option),
            ),
        ],
      ),
    );
  }
}

class _SleepChoice extends ConsumerWidget {
  const _SleepChoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(readAloudControllerProvider.notifier);
    final sleep = ref.watch(readAloudControllerProvider.select((s) => s.sleep));
    final reading = ref.watch(
      readAloudControllerProvider.select((s) => s.document != null),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sleep != null) _SleepLeft(sleep: sleep),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                key: const Key('read-aloud-sleep-off'),
                label: Text(l10n.f47P2SleepOff),
                selected: sleep == null,
                onSelected: (_) => controller.setSleepTimer(null),
              ),
              for (final choice in SleepTimerChoice.values)
                ChoiceChip(
                  key: Key('read-aloud-sleep-${choice.name}'),
                  label: Text(switch (choice.after) {
                    final after? => l10n.f47P2SleepMinutes(after.inMinutes),
                    null => l10n.f47P2SleepEndOfReading,
                  }),
                  selected: sleep?.choice == choice,
                  onSelected: reading
                      ? (_) => controller.setSleepTimer(choice)
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cuánto falta para que el Temporizador para dormir pause: se vuelve a
/// contar cada medio minuto, solo mientras se ve.
class _SleepLeft extends ConsumerStatefulWidget {
  const _SleepLeft({required this.sleep});

  final SleepTimer sleep;

  @override
  ConsumerState<_SleepLeft> createState() => _SleepLeftState();
}

class _SleepLeftState extends ConsumerState<_SleepLeft> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_SleepLeft oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sleep != widget.sleep) _schedule();
  }

  /// «Al terminar esto» no tiene minutos que contar.
  void _schedule() {
    _tick?.cancel();
    _tick = widget.sleep.atEndOfReading
        ? null
        : Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
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
    final minutes = widget.sleep.minutesLeft(
      ref.read(narrationClockProvider)(),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.bedtime_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              minutes == null
                  ? l10n.f47P2SleepAtEnd
                  : l10n.f47P2SleepLeft(minutes),
              key: const Key('read-aloud-sleep-left'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
