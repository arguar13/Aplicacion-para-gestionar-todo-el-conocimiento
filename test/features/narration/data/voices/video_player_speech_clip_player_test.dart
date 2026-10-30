import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/data/voices/video_player_speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../../support/quiet_video_player.dart';

/// El reproductor de mentira, con los avisos en manos de la prueba: «terminó»
/// o «falló» cuando se le dice.
class _ScriptedPlayer extends QuietVideoPlayer {
  _ScriptedPlayer() : super(duration: const Duration(seconds: 2));

  final events = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  var _next = 0;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _next++;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final controller = events[playerId] = StreamController<VideoEvent>()
      ..add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          size: size,
        ),
      );
    return controller.stream;
  }

  void complete(int playerId) =>
      events[playerId]!.add(VideoEvent(eventType: VideoEventType.completed));

  void fail(int playerId) => events[playerId]!.addError(
    PlatformException(code: 'VideoError', message: 'no se pudo abrir'),
  );

  @override
  Future<void> dispose(int playerId) async => disposed.add(playerId);
}

void main() {
  // El controlador de `video_player` se anota en el ciclo de vida de la app.
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ScriptedPlayer platform;

  setUp(() {
    platform = _ScriptedPlayer();
    VideoPlayerPlatform.instance = platform;
  });

  group('hacer sonar un tramo (F47, paso 3)', () {
    test('suena hasta el final y suelta el reproductor', () async {
      final player = VideoPlayerSpeechClipPlayer();
      final progress = <double>[];
      bool? played;
      unawaited(
        player
            .play(const FileSpeechClip('tramo.wav'), onProgress: progress.add)
            .then((value) => played = value),
      );
      await pumpEventQueue();

      platform.complete(0);
      await pumpEventQueue();

      expect(played, isTrue);
      expect(progress.last, 1);
      expect(platform.disposed, [0]);
    });

    test('cortado, dice que no llegó al final', () async {
      final player = VideoPlayerSpeechClipPlayer();
      bool? played;
      unawaited(
        player
            .play(const FileSpeechClip('tramo.wav'))
            .then((value) => played = value),
      );
      await pumpEventQueue();

      await player.stop();
      await pumpEventQueue();

      expect(played, isFalse);
      expect(platform.disposed, [0]);
    });

    test('otro tramo corta el que sonaba', () async {
      final player = VideoPlayerSpeechClipPlayer();
      bool? first;
      unawaited(
        player
            .play(const FileSpeechClip('uno.wav'))
            .then((value) => first = value),
      );
      await pumpEventQueue();
      unawaited(player.play(const UrlSpeechClip('https://ejemplo.org/0.mp3')));
      await pumpEventQueue();

      expect(first, isFalse);
      expect(platform.disposed, [0]);
      await player.dispose();
    });

    test('si no se pudo abrir, falla', () async {
      final player = VideoPlayerSpeechClipPlayer();
      Object? error;
      unawaited(
        player
            .play(const FileSpeechClip('roto.wav'))
            .then<void>((_) {}, onError: (Object e) => error = e),
      );
      await pumpEventQueue();

      platform.fail(0);
      await pumpEventQueue();

      expect(error, isNotNull);
    });
  });
}
