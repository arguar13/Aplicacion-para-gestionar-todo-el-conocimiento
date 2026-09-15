import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Reproductor de audio y video integrado, con controles propios en vez de
/// delegar en la app que el sistema tenga asociada.
///
/// El mismo widget sirve para las dos cosas: `video_player` reproduce
/// cualquier contenedor que entienda el motor nativo de la plataforma
/// —ExoPlayer en Android—, tenga pista de video o no. Cuando no la tiene
/// —una nota de voz, un podcast— el tamaño del video queda en `Size.zero`
/// y se muestra una carátula en su lugar; cuando sí, se ve el video como
/// cualquier reproductor.
class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({
    required this.path,
    required this.title,
    required this.isVideo,
    super.key,
  });

  final String path;
  final String title;

  /// Solo decide el ícono de la carátula mientras no hay video real que
  /// mostrar: si el archivo sí trae una pista de video, igual se ve.
  final bool isVideo;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late final _controller = VideoPlayerController.file(File(widget.path));
  late final Future<void> _initialization = _controller.initialize().then(
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final hasVideo = _controller.value.size.width > 0;

          return Column(
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
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.graphic_eq,
          size: 96,
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                  value: position.inMilliseconds
                      .toDouble()
                      .clamp(0, duration.inMilliseconds.toDouble()),
                  onChanged: (value) => controller.seekTo(
                    Duration(milliseconds: value.round()),
                  ),
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
                    iconSize: 40,
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
