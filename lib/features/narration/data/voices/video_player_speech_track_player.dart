import 'dart:async';
import 'dart:io';

import 'package:sinapsis/features/narration/domain/services/speech_track_player.dart';
import 'package:video_player/video_player.dart';

/// [SpeechTrackPlayer] sobre `video_player`, el reproductor que la app ya usa
/// para el audio y el video (F23): ExoPlayer en Android, que cambia la
/// velocidad sin cambiar el tono y pide el foco de audio por su cuenta —una
/// llamada lo pausa, y lo avisa como un `playing` en falso—.
class VideoPlayerSpeechTrackPlayer implements SpeechTrackPlayer {
  VideoPlayerSpeechTrackPlayer({
    VideoPlayerController Function(String path)? open,
  }) : _open = open ?? _controllerOf;

  final VideoPlayerController Function(String path) _open;

  static VideoPlayerController _controllerOf(String path) =>
      VideoPlayerController.file(File(path));

  final _positions = StreamController<SpeechTrackPosition>.broadcast();
  VideoPlayerController? _controller;
  SpeechTrackPosition? _last;

  @override
  Stream<SpeechTrackPosition> get positions => _positions.stream;

  @override
  Future<void> open(String path) async {
    await close();
    final controller = _open(path);
    try {
      await controller.initialize();
    } on Object {
      await controller.dispose();
      rethrow;
    }
    _controller = controller;
    controller.addListener(_onChange);
  }

  void _onChange() {
    final controller = _controller;
    if (controller == null || _positions.isClosed) return;
    final value = controller.value;
    final total = value.duration;
    final completed =
        value.isCompleted ||
        (total > Duration.zero && !value.isPlaying && value.position >= total);
    final now = SpeechTrackPosition(
      position: completed ? total : value.position,
      playing: value.isPlaying && !completed,
      completed: completed,
      failed: value.hasError,
    );
    if (now == _last) return;
    _last = now;
    _positions.add(now);
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seek(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setSpeed(double speed) async =>
      _controller?.setPlaybackSpeed(speed);

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    _last = null;
    if (controller == null) return;
    controller.removeListener(_onChange);
    await controller.dispose();
  }

  @override
  Future<void> dispose() async {
    await close();
    await _positions.close();
  }
}
