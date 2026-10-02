import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/floating_mini_player.dart';
import 'package:sinapsis/features/library/presentation/widgets/playback_synced_text.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// El motor nativo, falso: un audio de [duration] que anota qué le pidieron.
class _FakePlayer extends VideoPlayerPlatform {
  _FakePlayer(this.duration);

  final Duration duration;
  Duration position = Duration.zero;
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
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

const _path = '/boveda/archivos/clase.opus';

final _item = KnowledgeItem(
  id: 'item-1',
  title: 'Clase grabada',
  source: Source(
    id: 'src-1',
    kind: SourceKind.audio,
    capturedAt: DateTime(2026, 10),
  ),
  processingState: ProcessingState.ready,
  createdAt: DateTime(2026, 10),
  updatedAt: DateTime(2026, 10),
);

/// El mini reproductor flotante del detalle de un audio (F23, decisión B):
/// aparece cuando el audio ya empezó y el reproductor quedó fuera de la
/// pantalla, y maneja el **mismo** reproductor que el del detalle.
void main() {
  final es = AppLocalizationsEs();
  late _FakePlayer player;

  setUp(() {
    player = _FakePlayer(const Duration(minutes: 3));
    VideoPlayerPlatform.instance = player;
  });

  /// Arma lo mismo que el detalle: el reproductor arriba de todo, mucho
  /// texto abajo para desplazarse, y el mini reproductor encima.
  Future<({ScrollController scroll, ProviderContainer container})> pump(
    WidgetTester tester, {
    PlaybackFollowLink? link,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final playerKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          resolvedFileViewerProvider.overrideWith(
            (ref, item) async =>
                const MediaResolvedViewer(path: _path, isVideo: false),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(
              children: [
                SingleChildScrollView(
                  controller: scroll,
                  child: Column(
                    children: [
                      SizedBox(
                        key: playerKey,
                        height: 300,
                        child: const MediaPlayerView(
                          path: _path,
                          isVideo: false,
                        ),
                      ),
                      const SizedBox(height: 3000),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: FloatingMiniPlayer(
                    item: _item,
                    scrollController: scroll,
                    playerKey: playerKey,
                    link: link,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FloatingMiniPlayer)),
    );
    return (scroll: scroll, container: container);
  }

  /// Si el mini reproductor se ve y se puede tocar.
  bool miniVisible(WidgetTester tester) {
    final mini = find.byKey(const Key('mini-player'));
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(of: mini, matching: find.byType(AnimatedOpacity)),
    );
    final ignore = tester.widget<IgnorePointer>(
      find.ancestor(of: mini, matching: find.byType(IgnorePointer)).first,
    );
    final visible = opacity.opacity == 1 && !ignore.ignoring;
    final hidden = opacity.opacity == 0 && ignore.ignoring;
    expect(
      visible || hidden,
      isTrue,
      reason: 'la opacidad y si se puede tocar tienen que ir juntas',
    );
    return visible;
  }

  Finder inMini(Finder finder) => find.descendant(
    of: find.byKey(const Key('mini-player')),
    matching: finder,
  );

  Finder inPlayer(Finder finder) =>
      find.descendant(of: find.byType(MediaPlayerView), matching: finder);

  /// Empieza a sonar desde el botón del reproductor del detalle, y deja
  /// avanzar el audio hasta [at].
  Future<void> startPlaying(WidgetTester tester, {Duration? at}) async {
    await tester.tap(find.byKey(const Key('media-play')));
    await tester.pumpAndSettle();
    player.position = at ?? const Duration(seconds: 12);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
  }

  Future<void> scrollAway(WidgetTester tester, ScrollController scroll) async {
    scroll.jumpTo(1500);
    await tester.pumpAndSettle();
  }

  testWidgets('antes de que el audio empiece no aparece, aunque el '
      'reproductor haya quedado fuera de la pantalla', (tester) async {
    final (:scroll, container: _) = await pump(tester);

    expect(miniVisible(tester), isFalse);
    await scrollAway(tester, scroll);
    expect(miniVisible(tester), isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con el audio sonando aparece al bajar a leer y se va al '
      'volver a ver el reproductor', (tester) async {
    final (:scroll, container: _) = await pump(tester);
    await startPlaying(tester);

    // Sonando, pero con el reproductor a la vista: no hace falta.
    expect(miniVisible(tester), isFalse);

    await scrollAway(tester, scroll);
    expect(miniVisible(tester), isTrue);
    expect(find.text('00:12 / 03:00'), findsOneWidget);
    expect(find.text(es.mediaPlayerBackToAudio), findsOneWidget);

    // Con un tercio del reproductor a la vista ya alcanza para manejarlo
    // ahí: de 300 px, se ven 150.
    scroll.jumpTo(150);
    await tester.pumpAndSettle();
    expect(miniVisible(tester), isFalse);

    await scrollAway(tester, scroll);
    expect(miniVisible(tester), isTrue);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(miniVisible(tester), isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pausar y reanudar desde el mini reproductor maneja el mismo '
      'reproductor que el del detalle', (tester) async {
    final (:scroll, :container) = await pump(tester);
    final controller = container
        .read(playbackSessionProvider(_path))
        .controller;
    await startPlaying(tester);
    await scrollAway(tester, scroll);
    expect(controller.value.isPlaying, isTrue);

    await tester.tap(find.byKey(const Key('mini-player-play')));
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isFalse);
    // En pausa, pero ya empezado: sigue a mano para retomar.
    expect(miniVisible(tester), isTrue);
    // Es el mismo audio: el reproductor del detalle, aunque no se vea, quedó
    // en pausa también.
    expect(inMini(find.byTooltip(es.mediaPlayerPlay)), findsOneWidget);
    expect(inPlayer(find.byTooltip(es.mediaPlayerPlay)), findsOneWidget);

    await tester.tap(find.byKey(const Key('mini-player-play')));
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isTrue);
    expect(inMini(find.byTooltip(es.mediaPlayerPause)), findsOneWidget);
    expect(inPlayer(find.byTooltip(es.mediaPlayerPause)), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Volver al audio" deja que el texto muestre lo que suena, '
      'sin subir hasta el reproductor', (tester) async {
    var revealed = 0;
    final link = PlaybackFollowLink()
      ..revealPlaying = () {
        revealed++;
        return true;
      };
    final (:scroll, container: _) = await pump(tester, link: link);
    await startPlaying(tester);
    await scrollAway(tester, scroll);

    await tester.tap(find.byKey(const Key('mini-player-back')));
    await tester.pumpAndSettle();

    expect(revealed, 1);
    expect(scroll.offset, 1500);
    expect(miniVisible(tester), isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Volver al audio" sin un texto que siga al audio sube hasta '
      'el reproductor, y el mini reproductor se va', (tester) async {
    final (:scroll, container: _) = await pump(tester);
    await startPlaying(tester);
    await scrollAway(tester, scroll);

    await tester.tap(find.byKey(const Key('mini-player-back')));
    await tester.pumpAndSettle();

    expect(scroll.offset, 0);
    expect(miniVisible(tester), isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('si el texto no tiene nada que mostrar, "Volver al audio" '
      'también sube hasta el reproductor', (tester) async {
    final link = PlaybackFollowLink()..revealPlaying = () => false;
    final (:scroll, container: _) = await pump(tester, link: link);
    await startPlaying(tester);
    await scrollAway(tester, scroll);

    await tester.tap(find.byKey(const Key('mini-player-back')));
    await tester.pumpAndSettle();

    expect(scroll.offset, 0);
    expect(miniVisible(tester), isFalse);

    await tester.pumpWidget(const SizedBox());
  });
}
