import 'dart:io';

import 'package:flutter/material.dart';
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
/// Sin `Scaffold` propio a propósito: `MediaPlayerScreen` lo envuelve para
/// mostrarlo a pantalla completa, y `EmbeddedFileViewer` lo embebe tal cual
/// dentro de un marco acotado en el detalle del elemento.
class MediaPlayerView extends StatefulWidget {
  const MediaPlayerView({required this.path, required this.isVideo, super.key});

  final String path;

  /// Solo decide el ícono de la carátula mientras no hay video real que
  /// mostrar: si el archivo sí trae una pista de video, igual se ve.
  final bool isVideo;

  @override
  State<MediaPlayerView> createState() => _MediaPlayerViewState();
}

class _MediaPlayerViewState extends State<MediaPlayerView> {
  late final _controller = VideoPlayerController.file(File(widget.path));

  /// `Either`-a-mano con un booleano de error en vez de dejar que
  /// `initialize()` rechace la `Future` sin más: un archivo movido o
  /// corrompido después de guardarse no debería tumbar el `FutureBuilder`
  /// con una excepción sin atrapar, sino mostrar un aviso con sentido.
  late final Future<bool> _initialization = _controller
      .initialize()
      .then((_) => true)
      .catchError((_) => false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: Colors.black,
      child: FutureBuilder<bool>(
        future: _initialization,
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

          final hasVideo = _controller.value.size.width > 0;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Center(
                  child: hasVideo
                      ? AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: GestureDetector(
                            onTap: _togglePlay,
                            child: VideoPlayer(_controller),
                          ),
                        )
                      : _AudioCover(theme: theme, onTap: _togglePlay),
                ),
              ),
              _Controls(controller: _controller),
            ],
          );
        },
      ),
    );
  }

  void _togglePlay() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
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

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final position = value.position;
        final duration = value.duration;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                  max: duration.inMilliseconds.toDouble().clamp(
                    1,
                    double.infinity,
                  ),
                  value: position.inMilliseconds.toDouble().clamp(
                    0,
                    duration.inMilliseconds.toDouble(),
                  ),
                  onChanged: (value) =>
                      controller.seekTo(Duration(milliseconds: value.round())),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _format(position),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  IconButton(
                    iconSize: 36,
                    color: Colors.white,
                    icon: Icon(
                      value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                    ),
                    onPressed: () => value.isPlaying
                        ? controller.pause()
                        : controller.play(),
                  ),
                  Text(
                    _format(duration),
                    style: const TextStyle(color: Colors.white70),
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
