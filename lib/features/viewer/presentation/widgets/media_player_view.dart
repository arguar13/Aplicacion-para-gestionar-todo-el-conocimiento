import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:video_player/video_player.dart';

/// Reproductor de audio y video integrado, con controles propios en vez de
/// delegar en la app que el sistema tenga asociada.
///
/// El mismo widget sirve para las dos cosas: `video_player` reproduce
/// cualquier contenedor que entienda el motor nativo de la plataforma
/// —ExoPlayer en Android—, tenga pista de video o no. Cuando no la tiene
/// —una nota de voz, un podcast— el tamaño del video queda en `Size.zero` y
/// se muestra una carátula en su lugar; cuando sí, se ve el video como
/// cualquier reproductor.
///
/// Los controles son los de un reproductor de videos de internet: retroceder
/// y avanzar [mediaSkipStep], y la velocidad —de 0,25× a 3×— en un panel
/// con los valores de siempre a un toque y un ajuste fino.
///
/// Sin `Scaffold` propio a propósito: `MediaPlayerScreen` lo envuelve para
/// mostrarlo a pantalla completa, y `EmbeddedFileViewer` lo embebe tal cual
/// dentro de un marco acotado en el detalle del elemento.
class MediaPlayerView extends ConsumerStatefulWidget {
  const MediaPlayerView({required this.path, required this.isVideo, super.key});

  final String path;

  /// Solo decide el ícono de la carátula mientras no hay video real que
  /// mostrar: si el archivo sí trae una pista de video, igual se ve.
  final bool isVideo;

  @override
  ConsumerState<MediaPlayerView> createState() => _MediaPlayerViewState();
}

/// Cuánto saltan los botones de retroceder y avanzar.
const mediaSkipStep = Duration(seconds: 10);

/// Las velocidades a un toque, como en un reproductor de videos de
/// internet.
const mediaSpeedPresets = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];

/// La velocidad mínima y máxima, y el paso del ajuste fino.
const mediaMinSpeed = 0.25;
const mediaMaxSpeed = 3.0;
const mediaSpeedStep = 0.05;

/// [position] movida [delta] —hacia atrás si es negativo—, sin salirse del
/// audio.
Duration skipWithin(Duration position, Duration delta, Duration duration) {
  final target = position + delta;
  if (target < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && target > duration) return duration;
  return target;
}

/// [speed] redondeada al paso del ajuste fino y dentro de los límites: sin
/// esto, sumar 0,05 diez veces daría 1,4999999.
double clampSpeed(double speed) {
  final steps = (speed / mediaSpeedStep).round();
  return (steps * mediaSpeedStep).clamp(mediaMinSpeed, mediaMaxSpeed);
}

/// "1,25×" en español, "1.25×" en inglés; "1×", no "1,00×".
String formatSpeed(double speed, String locale) =>
    '${NumberFormat('0.##', locale).format(speed)}×';

class _MediaPlayerViewState extends ConsumerState<MediaPlayerView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // El mismo reproductor que siguen el mini reproductor y el texto (F23):
    // ver `playbackSessionProvider`.
    final session = ref.watch(playbackSessionProvider(widget.path));
    final controller = session.controller;

    return ColoredBox(
      color: Colors.black,
      child: FutureBuilder<bool>(
        future: session.initialized,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (snapshot.data != true) {
            return const Center(
              child: Icon(Icons.error_outline, size: 48, color: Colors.white70),
            );
          }

          final hasVideo = controller.value.size.width > 0;
          void togglePlay() => setState(() {
            controller.value.isPlaying ? controller.pause() : controller.play();
          });

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Center(
                  child: hasVideo
                      ? AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: GestureDetector(
                            onTap: togglePlay,
                            child: VideoPlayer(controller),
                          ),
                        )
                      : _AudioCover(theme: theme, onTap: togglePlay),
                ),
              ),
              _Controls(controller: controller),
            ],
          );
        },
      ),
    );
  }
}

/// La carátula que se muestra en vez del video cuando el archivo es solo
/// audio: un ícono grande, tocable, en vez de una pantalla negra vacía que
/// hace pensar que algo se rompió.
class _AudioCover extends StatelessWidget {
  const _AudioCover({required this.theme, required this.onTap});

  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.graphic_eq,
          size: 64,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _Controls extends StatefulWidget {
  const _Controls({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  /// Dónde está el dedo mientras arrastra la barra: se salta al soltar, no
  /// en cada movimiento —cada salto le pide al motor que busque y
  /// decodifique de nuevo—.
  double? _dragging;

  VideoPlayerController get _controller => widget.controller;

  void _skip(Duration delta) {
    final value = _controller.value;
    _controller.seekTo(skipWithin(value.position, delta, value.duration));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final max = duration.inMilliseconds.toDouble().clamp(
          1.0,
          double.infinity,
        );
        final shown = _dragging ?? value.position.inMilliseconds.toDouble();

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                ),
                child: Slider(
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  max: max,
                  value: shown.clamp(0, max),
                  onChanged: (v) => setState(() => _dragging = v),
                  onChangeEnd: (v) {
                    _controller.seekTo(Duration(milliseconds: v.round()));
                    setState(() => _dragging = null);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _format(Duration(milliseconds: shown.round())),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      _format(duration),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        key: const Key('media-replay'),
                        iconSize: 30,
                        color: Colors.white,
                        tooltip: l10n.mediaPlayerReplay,
                        icon: const Icon(Icons.replay_10),
                        onPressed: () => _skip(-mediaSkipStep),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        key: const Key('media-play'),
                        iconSize: 48,
                        color: Colors.white,
                        tooltip: value.isPlaying
                            ? l10n.mediaPlayerPause
                            : l10n.mediaPlayerPlay,
                        icon: Icon(
                          value.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                        ),
                        onPressed: () => value.isPlaying
                            ? _controller.pause()
                            : _controller.play(),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        key: const Key('media-forward'),
                        iconSize: 30,
                        color: Colors.white,
                        tooltip: l10n.mediaPlayerForward,
                        icon: const Icon(Icons.forward_10),
                        onPressed: () => _skip(mediaSkipStep),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _SpeedButton(
                      label: formatSpeed(value.playbackSpeed, locale),
                      tooltip: l10n.mediaPlayerSpeed,
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (_) =>
                            MediaSpeedSheet(controller: _controller),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}

/// La velocidad actual, como una pastilla: tocarla abre el panel.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        key: const Key('media-speed'),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white12,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(48, 32),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

/// El panel de la velocidad: el valor en grande, menos y más de a
/// [mediaSpeedStep] con una barra entre medio, y las velocidades de siempre
/// a un toque. Cada cambio se aplica en el acto, con el audio sonando.
class MediaSpeedSheet extends StatelessWidget {
  const MediaSpeedSheet({required this.controller, super.key});

  final VideoPlayerController controller;

  void _set(double speed) => controller.setPlaybackSpeed(clampSpeed(speed));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final speed = value.playbackSpeed;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.mediaPlayerSpeed, style: text.titleMedium),
                const SizedBox(height: 12),
                Text(
                  formatSpeed(speed, locale),
                  key: const Key('media-speed-value'),
                  style: text.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton.filledTonal(
                      key: const Key('media-speed-down'),
                      tooltip: l10n.mediaPlayerSpeedDown,
                      onPressed: speed > mediaMinSpeed
                          ? () => _set(speed - mediaSpeedStep)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Slider(
                        min: mediaMinSpeed,
                        max: mediaMaxSpeed,
                        divisions:
                            ((mediaMaxSpeed - mediaMinSpeed) / mediaSpeedStep)
                                .round(),
                        value: speed.clamp(mediaMinSpeed, mediaMaxSpeed),
                        onChanged: _set,
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const Key('media-speed-up'),
                      tooltip: l10n.mediaPlayerSpeedUp,
                      onPressed: speed < mediaMaxSpeed
                          ? () => _set(speed + mediaSpeedStep)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in mediaSpeedPresets)
                      ChoiceChip(
                        key: Key('media-speed-$preset'),
                        label: Text(
                          preset == 1.0
                              ? l10n.mediaPlayerSpeedNormal
                              : formatSpeed(preset, locale),
                        ),
                        selected: (speed - preset).abs() < 0.001,
                        selectedColor: scheme.primaryContainer,
                        onSelected: (_) => _set(preset),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
