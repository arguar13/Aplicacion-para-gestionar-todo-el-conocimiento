import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// El motor nativo, falso: un audio de [duration] que anota qué le pidieron.
class _FakePlayer extends VideoPlayerPlatform {
  _FakePlayer(this.duration);

  final Duration duration;
  Duration position = Duration.zero;
  double speed = 1;
  final seeks = <Duration>[];

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
          size: Size.zero,
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
  Future<void> seekTo(int playerId, Duration position) async {
    this.position = position;
    seeks.add(position);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      this.speed = speed;

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

void main() {
  final es = AppLocalizationsEs();

  group('las cuentas', () {
    test('retroceder y avanzar no se salen del audio', () {
      const duration = Duration(minutes: 1, seconds: 51);

      expect(
        skipWithin(const Duration(seconds: 4), -mediaSkipStep, duration),
        Duration.zero,
      );
      expect(
        skipWithin(const Duration(seconds: 105), mediaSkipStep, duration),
        duration,
      );
      expect(
        skipWithin(const Duration(seconds: 30), mediaSkipStep, duration),
        const Duration(seconds: 40),
      );
    });

    test('la velocidad va de a 0,05, sin restos, y no sale de 0,25× a 3×', () {
      var speed = 1.0;
      for (var i = 0; i < 10; i++) {
        speed = clampSpeed(speed + mediaSpeedStep);
      }

      expect(speed, 1.5);
      expect(clampSpeed(0.1), mediaMinSpeed);
      expect(clampSpeed(5), mediaMaxSpeed);
    });

    test('la velocidad se escribe como en cada idioma, sin ceros de más', () {
      expect(formatSpeed(1, 'es'), '1×');
      expect(formatSpeed(1.25, 'es'), '1,25×');
      expect(formatSpeed(0.5, 'en'), '0.5×');
    });
  });

  group('el reproductor', () {
    late _FakePlayer player;

    setUp(() {
      player = _FakePlayer(const Duration(minutes: 1, seconds: 51));
      VideoPlayerPlatform.instance = player;
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: MediaPlayerView(path: 'nota.opus', isVideo: false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('avanzar y retroceder saltan 10 segundos', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('media-forward')));
      await tester.tap(find.byKey(const Key('media-forward')));
      await tester.pumpAndSettle();
      expect(player.seeks.last, const Duration(seconds: 20));

      await tester.tap(find.byKey(const Key('media-replay')));
      await tester.pumpAndSettle();
      expect(player.seeks.last, const Duration(seconds: 10));
      expect(find.byTooltip(es.mediaPlayerReplay), findsOneWidget);
      expect(find.byTooltip(es.mediaPlayerForward), findsOneWidget);
    });

    testWidgets('la velocidad: un panel con las de siempre a un toque y el '
        'ajuste fino, que se aplica en el acto', (tester) async {
      await pump(tester);
      expect(find.text('1×'), findsOneWidget);
      // `video_player` le pasa la velocidad al motor mientras suena; en
      // pausa la guarda y la aplica al reproducir.
      await tester.tap(find.byKey(const Key('media-play')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('media-speed')));
      await tester.pumpAndSettle();
      expect(find.text(es.mediaPlayerSpeed), findsOneWidget);
      expect(find.text(es.mediaPlayerSpeedNormal), findsOneWidget);

      await tester.tap(find.byKey(const Key('media-speed-2.0')));
      await tester.pumpAndSettle();
      expect(player.speed, 2.0);
      expect(
        tester.widget<Text>(find.byKey(const Key('media-speed-value'))).data,
        '2×',
      );

      await tester.tap(find.byKey(const Key('media-speed-down')));
      await tester.pumpAndSettle();
      expect(player.speed, closeTo(1.95, 1e-9));

      await tester.tap(find.byKey(const Key('media-speed-0.5')));
      await tester.pumpAndSettle();
      expect(player.speed, 0.5);

      // Cerrado el panel, la pastilla muestra la velocidad elegida.
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();
      expect(find.text('0,5×'), findsOneWidget);

      // Sin el reproductor, sin el temporizador que sigue la posición.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
