import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/embedded_file_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// El motor nativo, falso: un archivo de [size] —cero si es solo audio—
/// que anota qué le pidieron.
class _FakePlayer extends VideoPlayerPlatform {
  _FakePlayer({required this.size});

  final Size size;
  int created = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      ++created;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    late final StreamController<VideoEvent> events;
    events = StreamController<VideoEvent>(
      onListen: () => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 2),
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

KnowledgeItem _item(SourceKind kind, String file) => KnowledgeItem(
  id: 'item-1',
  title: 'Un archivo del teléfono',
  source: Source(
    id: 'src-1',
    kind: kind,
    capturedAt: DateTime(2026, 10),
    originalFilePath: file,
  ),
  processingState: ProcessingState.ready,
  createdAt: DateTime(2026, 10),
  updatedAt: DateTime(2026, 10),
);

/// Un video en el detalle: el video, y debajo el mismo reproductor que un
/// audio, solo con su audio (F24, decisión B). Los dos manejan **un** solo
/// reproductor.
void main() {
  final es = AppLocalizationsEs();
  late _FakePlayer player;

  /// Muestra el archivo de [item], resuelto como audio o video según
  /// [isVideo], en `path`.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required KnowledgeItem item,
    required String path,
    required bool isVideo,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          resolvedFileViewerProvider.overrideWith(
            (ref, item) async =>
                MediaResolvedViewer(path: path, isVideo: isVideo),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: EmbeddedFileViewer(item: item)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(EmbeddedFileViewer)),
    );
  }

  final audioPlayer = find.byKey(const Key('video-audio-player'));
  final videoPlayer = find.byWidgetPredicate(
    (widget) => widget is MediaPlayerView && !widget.audioOnly,
  );

  Finder inside(Finder player, Finder finder) =>
      find.descendant(of: player, matching: finder);

  group('un video', () {
    const path = '/boveda/archivos/reel.mp4';

    setUp(() {
      player = _FakePlayer(size: const Size(1080, 1920));
      VideoPlayerPlatform.instance = player;
    });

    testWidgets('se ve el video y, debajo, un reproductor solo con su '
        'audio', (tester) async {
      await pump(
        tester,
        item: _item(SourceKind.video, 'src-1.mp4'),
        path: path,
        isVideo: true,
      );

      expect(find.byType(MediaPlayerView), findsNWidgets(2));
      final audio = tester.widget<MediaPlayerView>(audioPlayer);
      expect(audio.audioOnly, isTrue);
      expect(audio.path, path);
      final video = tester.widget<MediaPlayerView>(videoPlayer);
      expect(video.isVideo, isTrue);
      expect(video.path, path);

      // La imagen, una sola vez: arriba. Abajo, la carátula del audio.
      expect(inside(videoPlayer, find.byType(VideoPlayer)), findsOneWidget);
      expect(inside(audioPlayer, find.byType(VideoPlayer)), findsNothing);
      expect(
        inside(audioPlayer, find.byIcon(Icons.graphic_eq)),
        findsOneWidget,
      );
      // Debajo, no encima: el video es lo principal.
      expect(
        tester.getTopLeft(audioPlayer).dy,
        greaterThan(tester.getBottomLeft(videoPlayer).dy),
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('los dos manejan el mismo audio: darle play abajo lo hace '
        'sonar también arriba, y pausarlo arriba lo pausa abajo', (
      tester,
    ) async {
      final container = await pump(
        tester,
        item: _item(SourceKind.video, 'src-1.mp4'),
        path: path,
        isVideo: true,
      );
      final controller = container
          .read(playbackSessionProvider(path))
          .controller;
      // Un solo reproductor para los dos, no uno por cada uno.
      expect(player.created, 1);

      await tester.tap(
        inside(audioPlayer, find.byKey(const Key('media-play'))),
      );
      await tester.pumpAndSettle();

      expect(controller.value.isPlaying, isTrue);
      expect(
        inside(audioPlayer, find.byTooltip(es.mediaPlayerPause)),
        findsOne,
      );
      expect(
        inside(videoPlayer, find.byTooltip(es.mediaPlayerPause)),
        findsOne,
      );

      await tester.tap(
        inside(videoPlayer, find.byKey(const Key('media-play'))),
      );
      await tester.pumpAndSettle();

      expect(controller.value.isPlaying, isFalse);
      expect(inside(audioPlayer, find.byTooltip(es.mediaPlayerPlay)), findsOne);
      expect(inside(videoPlayer, find.byTooltip(es.mediaPlayerPlay)), findsOne);

      // Sin el reproductor, sin el temporizador que sigue la posición.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('un audio', () {
    setUp(() {
      player = _FakePlayer(size: Size.zero);
      VideoPlayerPlatform.instance = player;
    });

    testWidgets('tiene un solo reproductor: no hay un video que '
        'acompañar', (tester) async {
      await pump(
        tester,
        item: _item(SourceKind.audio, 'src-1.opus'),
        path: '/boveda/archivos/clase.opus',
        isVideo: false,
      );

      expect(find.byType(MediaPlayerView), findsOneWidget);
      expect(audioPlayer, findsNothing);
      expect(
        tester.widget<MediaPlayerView>(find.byType(MediaPlayerView)).audioOnly,
        isFalse,
      );

      await tester.pumpWidget(const SizedBox());
    });
  });
}
