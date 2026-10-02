import 'package:flutter/material.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:video_player/video_player.dart';

/// El mini reproductor flotante (F23, decisión B): cuando el reproductor
/// del detalle quedó arriba, fuera de la pantalla, porque se bajó a leer el
/// texto, el audio se maneja desde acá sin tener que volver a subir.
///
/// Una pastilla, como la de un reproductor de música: reproducir o pausar,
/// el avance con su tiempo, la velocidad —el mismo panel que el reproductor
/// grande— y "Volver al audio", que lleva hasta lo que está sonando. Maneja
/// el **mismo** reproductor que el del detalle: ver `playbackSessionProvider`.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    required this.controller,
    required this.onBackToAudio,
    super.key,
  });

  final VideoPlayerController controller;
  final VoidCallback onBackToAudio;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final fraction = duration.inMilliseconds == 0
            ? 0.0
            : (value.position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              );
        return Material(
          key: const Key('mini-player'),
          color: scheme.surfaceContainerHigh,
          elevation: 6,
          shadowColor: scheme.shadow.withValues(alpha: 0.3),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                child: Row(
                  children: [
                    IconButton.filled(
                      key: const Key('mini-player-play'),
                      tooltip: value.isPlaying
                          ? l10n.mediaPlayerPause
                          : l10n.mediaPlayerPlay,
                      onPressed: () => value.isPlaying
                          ? controller.pause()
                          : controller.play(),
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_format(value.position)} / ${_format(duration)}',
                        style: text.labelLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('mini-player-speed'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (_) => MediaSpeedSheet(controller: controller),
                      ),
                      child: Text(formatSpeed(value.playbackSpeed, locale)),
                    ),
                    FilledButton.tonalIcon(
                      key: const Key('mini-player-back'),
                      onPressed: onBackToAudio,
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: Text(l10n.mediaPlayerBackToAudio),
                    ),
                  ],
                ),
              ),
              // El avance, como un hilo en el borde de abajo de la pastilla.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}
