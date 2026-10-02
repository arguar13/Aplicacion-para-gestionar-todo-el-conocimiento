import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart'
    show formatSpeed, mediaSkipStep;
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El lado del botón redondo del lector flotante.
const readAloudButtonSize = 56.0;

/// El botón redondo del lector flotante (F25), abajo a la derecha.
///
/// Quieto —sin [reading]—, empieza a leer el texto de la pantalla. Leyendo
/// —el reproductor achicado—, lleva un anillo con cuánto leyó y una marca
/// chica de si suena o está en pausa, y tocarlo vuelve a abrir el
/// reproductor.
class ReadAloudButton extends StatelessWidget {
  const ReadAloudButton({
    required this.reading,
    required this.playing,
    required this.onPressed,
    super.key,
  });

  final bool reading;
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: readAloudButtonSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: FloatingActionButton(
              key: const Key('read-aloud-button'),
              // Por encima del `Navigator`: no hay ruta con la que volar.
              heroTag: null,
              tooltip: reading ? l10n.readAloudExpand : l10n.readAloudTooltip,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              shape: const CircleBorder(),
              onPressed: onPressed,
              child: const Icon(Icons.record_voice_over_rounded),
            ),
          ),
          if (reading) ...[
            // El anillo va sobre el borde del botón, sin taparle el toque.
            const Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: _ProgressRing(),
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: IgnorePointer(child: _StateBadge(playing: playing)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cuánto leyó, alrededor del botón. Lo único que se redibuja palabra por
/// palabra.
class _ProgressRing extends ConsumerWidget {
  const _ProgressRing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final progress = ref.watch(
      readAloudControllerProvider.select((s) => s.progress),
    );
    return CircularProgressIndicator(
      key: const Key('read-aloud-ring'),
      value: progress,
      strokeWidth: 3,
      strokeCap: StrokeCap.round,
      color: scheme.primary,
      backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.12),
    );
  }
}

/// La marca chica en la esquina del botón: suena o está en pausa.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.playing});

  final bool playing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('read-aloud-badge'),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 2),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          playing ? Icons.graphic_eq_rounded : Icons.pause_rounded,
          key: ValueKey(playing),
          size: 12,
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}

/// El mini reproductor de lectura (F25): la misma familia que el mini
/// reproductor del audio —`MiniPlayer`—, una tarjeta en vez de una pastilla
/// porque lleva más controles.
///
/// Arriba, qué se lee y si suena —o el aviso, si el motor de voz falló—,
/// con minimizar y cerrar; el avance como un hilo; y abajo los controles de
/// un reproductor: la velocidad, retroceder y avanzar 10 s alrededor de
/// reproducir o pausar, y la voz y el acento.
class ReadAloudPlayer extends ConsumerWidget {
  const ReadAloudPlayer({
    required this.title,
    required this.onSpeed,
    required this.onVoice,
    super.key,
  });

  /// Lo que se lee. Viene de afuera y no del estado: al cerrar, el estado ya
  /// no tiene documento pero el reproductor todavía se está yendo.
  final String title;

  final VoidCallback onSpeed;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final locale = Localizations.localeOf(context).toString();
    final controller = ref.read(readAloudControllerProvider.notifier);
    final (playing, failed, speed) = ref.watch(
      readAloudControllerProvider.select((s) => (s.playing, s.failed, s.speed)),
    );

    return Material(
      key: const Key('read-aloud-player'),
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: scheme.shadow.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Artwork(playing: playing),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [...previous, ?current],
                        ),
                        child: Text(
                          failed
                              ? l10n.readAloudFailed
                              : playing
                              ? l10n.readAloudReading
                              : l10n.readAloudPaused,
                          key: ValueKey((failed, playing)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: failed
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('read-aloud-minimize'),
                  tooltip: l10n.readAloudMinimize,
                  onPressed: controller.minimize,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                IconButton(
                  key: const Key('read-aloud-close'),
                  tooltip: l10n.readAloudClose,
                  onPressed: () => unawaited(controller.close()),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: _ProgressBar(),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message: l10n.mediaPlayerSpeed,
                      child: FilledButton.tonal(
                        key: const Key('read-aloud-speed'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(52, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        onPressed: onSpeed,
                        child: Text(formatSpeed(speed, locale)),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('read-aloud-replay'),
                  tooltip: l10n.readAloudReplay,
                  iconSize: 28,
                  onPressed: () => unawaited(controller.skip(-mediaSkipStep)),
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('read-aloud-play'),
                  tooltip: playing
                      ? l10n.mediaPlayerPause
                      : l10n.mediaPlayerPlay,
                  iconSize: 32,
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(readAloudButtonSize),
                  ),
                  onPressed: () => unawaited(
                    playing ? controller.pause() : controller.play(),
                  ),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(playing),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('read-aloud-forward'),
                  tooltip: l10n.readAloudForward,
                  iconSize: 28,
                  onPressed: () => unawaited(controller.skip(mediaSkipStep)),
                  icon: const Icon(Icons.forward_10_rounded),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      key: const Key('read-aloud-voice'),
                      tooltip: l10n.readAloudVoice,
                      onPressed: onVoice,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// La carátula: lo que en el mini reproductor del audio sería la tapa del
/// disco. Mientras suena, un ecualizador; en pausa, la voz.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.playing});

  final bool playing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          playing ? Icons.graphic_eq_rounded : Icons.record_voice_over_rounded,
          key: ValueKey(playing),
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// El avance, como un hilo debajo del título. Lo único del reproductor que
/// se redibuja palabra por palabra.
class _ProgressBar extends ConsumerWidget {
  const _ProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final progress = ref.watch(
      readAloudControllerProvider.select((s) => s.progress),
    );
    return LinearProgressIndicator(
      key: const Key('read-aloud-progress'),
      value: progress,
      minHeight: 4,
      borderRadius: BorderRadius.circular(2),
      backgroundColor: scheme.surfaceContainerHighest,
    );
  }
}
