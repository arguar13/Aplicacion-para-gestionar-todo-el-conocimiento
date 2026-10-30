import 'dart:async';
import 'dart:io';

import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:video_player/video_player.dart';

/// [SpeechClipPlayer] sobre `video_player`, el reproductor que la app ya usa
/// para el audio y el video (F23): ExoPlayer en Android. Un controlador por
/// tramo, que se suelta apenas termina: un tramo es una oración, y mantener
/// abiertos los de antes no sirve de nada.
class VideoPlayerSpeechClipPlayer implements SpeechClipPlayer {
  VideoPlayerSpeechClipPlayer({
    VideoPlayerController Function(SpeechClip clip)? open,
  }) : _open = open ?? _controllerOf;

  final VideoPlayerController Function(SpeechClip clip) _open;

  static VideoPlayerController _controllerOf(SpeechClip clip) => switch (clip) {
    FileSpeechClip(:final path) => VideoPlayerController.file(File(path)),
    UrlSpeechClip(:final url) => VideoPlayerController.networkUrl(
      Uri.parse(url),
    ),
  };

  _Playback? _current;

  @override
  Future<bool> play(
    SpeechClip clip, {
    void Function(double)? onProgress,
  }) async {
    await stop();
    final playback = _current = _Playback(_open(clip), onProgress);
    return playback.run();
  }

  @override
  Future<void> stop() async {
    final playback = _current;
    _current = null;
    await playback?.cancel();
  }

  @override
  Future<void> dispose() => stop();
}

class _Playback {
  _Playback(this._controller, this._onProgress);

  final VideoPlayerController _controller;
  final void Function(double)? _onProgress;
  final _done = Completer<bool>();
  var _released = false;

  Future<bool> run() async {
    try {
      await _controller.initialize();
      // Cortado mientras se abría: no suena.
      if (!_done.isCompleted) {
        _controller.addListener(_onChange);
        await _controller.play();
      }
    } on Object catch (error, stackTrace) {
      await _release();
      if (!_done.isCompleted) _done.completeError(error, stackTrace);
    }
    return _done.future;
  }

  void _onChange() {
    final value = _controller.value;
    if (value.hasError) {
      unawaited(_finish(error: value.errorDescription ?? 'error'));
      return;
    }
    final total = value.duration;
    if (total <= Duration.zero) return;
    // Terminado: con la marca de terminado de `video_player` —que no siempre
    // mueve la posición hasta el final— o quieto en el final.
    if (value.isCompleted || (!value.isPlaying && value.position >= total)) {
      _onProgress?.call(1);
      unawaited(_finish(played: true));
      return;
    }
    final fraction = value.position.inMicroseconds / total.inMicroseconds;
    _onProgress?.call(fraction.clamp(0, 1).toDouble());
  }

  Future<void> _finish({bool played = false, String? error}) async {
    if (_done.isCompleted) return;
    if (error != null) {
      _done.completeError(StateError(error));
    } else {
      _done.complete(played);
    }
    await _release();
  }

  Future<void> cancel() => _finish();

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    _controller.removeListener(_onChange);
    await _controller.dispose();
  }
}
