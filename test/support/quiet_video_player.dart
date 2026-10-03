import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Un reproductor de video de mentira que no suena ni avanza: arranca listo,
/// con la duración y el tamaño dados, y acepta cualquier orden sin hacer
/// nada. Para las pruebas que muestran un audio o un video pero no prueban
/// el reproductor en sí.
class QuietVideoPlayer extends VideoPlayerPlatform {
  QuietVideoPlayer({
    this.duration = const Duration(minutes: 1),
    this.size = Size.zero,
  });

  final Duration duration;

  /// `Size.zero` para un audio.
  final Size size;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    late final StreamController<VideoEvent> events;
    events = StreamController<VideoEvent>(
      onListen: () => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          size: size,
        ),
      ),
    );
    return events.stream;
  }

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}
