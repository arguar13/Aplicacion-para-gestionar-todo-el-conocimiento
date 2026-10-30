import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/audio/media_session.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// El motor nativo, falso: un audio de [duration] que anota qué le pidieron
/// y deja que la prueba lo haga sonar.
class _FakePlayer extends VideoPlayerPlatform {
  _FakePlayer(this.duration);

  final Duration duration;
  Duration position = Duration.zero;
  final seeks = <Duration>[];
  final calls = <String>[];
  final _events = StreamController<VideoEvent>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    scheduleMicrotask(
      () => _events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          size: Size.zero,
        ),
      ),
    );
    return _events.stream;
  }

  /// Termina de sonar, como avisa el motor.
  void complete() =>
      _events.add(VideoEvent(eventType: VideoEventType.completed));

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    this.position = position;
    seeks.add(position);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

const _path = '/boveda/archivos/clase.opus';

/// Un audio en la tarjeta de lo que suena (F47, paso 2b).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePlayer player;
  late ProviderContainer container;
  late ProviderSubscription<PlaybackSession> keep;

  setUp(() {
    player = _FakePlayer(const Duration(minutes: 3));
    VideoPlayerPlatform.instance = player;
    container = ProviderContainer();
    addTearDown(container.dispose);
    keep = container.listen(playbackSessionProvider(_path), (_, _) {});
  });

  MediaSessionSource? source() =>
      container.read(mediaSessionSourcesProvider)[keep.read()];

  test('se registra con su testigo, y sigue sonando con la app '
      'minimizada', () async {
    final session = keep.read();
    await pumpEventQueue();

    expect(source(), isNotNull);
    expect(
      session.controller.videoPlayerOptions?.allowBackgroundPlayback,
      isTrue,
    );
  });

  test('muestra el título que le dicen, o el nombre del archivo, y el '
      'tiempo real', () async {
    final session = keep.read();
    await session.initialized;
    await pumpEventQueue();
    final card = source()!.state;

    expect(card.value?.title, 'clase.opus');
    expect(card.value?.duration, const Duration(minutes: 3));
    expect(card.value?.requestsAudioFocus, isFalse);

    session.title = 'Clase grabada';
    await session.controller.play();
    expect(card.value?.title, 'Clase grabada');
    expect(card.value?.playing, isTrue);
  });

  test('lo que se toca en la tarjeta mueve el audio, sin salirse', () async {
    final session = keep.read();
    await session.initialized;
    await pumpEventQueue();
    // Al abrirse, `video_player` deja el motor en pausa: no es la tarjeta.
    player.calls.clear();
    final card = source()!..handle(const MediaPlay());
    await pumpEventQueue();
    expect(player.calls, ['play']);

    card
      ..handle(const MediaSkip(Duration(seconds: -10)))
      ..handle(const MediaSeek(Duration(minutes: 9)));
    await pumpEventQueue();
    expect(player.seeks, [Duration.zero, const Duration(minutes: 3)]);

    card
      ..handle(const MediaStop())
      ..handle(const MediaNext());
    await pumpEventQueue();
    expect(player.calls, ['play', 'pause']);
  });

  test('al terminar de sonar, la tarjeta se va', () async {
    final session = keep.read();
    await session.initialized;
    await session.controller.play();
    await pumpEventQueue();
    expect(source()!.state.value, isNotNull);

    await session.controller.seekTo(const Duration(minutes: 3));
    player.complete();
    await pumpEventQueue();

    expect(source()!.state.value, isNull);
  });

  test('al soltar el audio, deja de estar en la tarjeta', () async {
    final session = keep.read();
    await pumpEventQueue();
    expect(container.read(mediaSessionSourcesProvider), contains(session));

    keep.close();
    await pumpEventQueue();

    expect(container.read(mediaSessionSourcesProvider), isEmpty);
  });
}
