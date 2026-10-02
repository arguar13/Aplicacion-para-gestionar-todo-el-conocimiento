import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/youtube_audio_download.dart';
import 'package:sinapsis/features/transform/presentation/widgets/youtube_audio_download_section.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/transform_test_doubles.dart';

/// El motor nativo, falso: un audio de un minuto que se abre sin más. Hace
/// falta en cuanto el audio queda bajado y aparece el reproductor.
class _FakePlayer extends VideoPlayerPlatform {
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
          duration: const Duration(minutes: 1),
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

/// YouTube sin conexión la primera vez que se le pide el audio, y con
/// conexión de ahí en más: para ver que "Reintentar" de verdad reintenta.
class _FailsFirstAudioClient extends FakeYouTubeClient {
  var _failed = false;

  @override
  Future<YouTubeAudioStream> openAudio(String videoId) async {
    if (_failed) return super.openAudio(videoId);
    _failed = true;
    audioRequested.add(videoId);
    throw const NetworkException(message: 'sin red');
  }
}

const _videoId = 'dQw4w9WgXcQ';

/// El audio de un video de YouTube se baja solo (F24, decisión A): sin
/// botón, apenas se abre el video si todavía no lo tiene.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() => VideoPlayerPlatform.instance = _FakePlayer());

  /// Guarda un video de YouTube ya procesado —con su transcripción y, salvo
  /// [originalFilePath], sin audio—, con [client] como YouTube, y muestra
  /// [screen]: por defecto la sección sola, siguiendo al elemento en la
  /// base. [beforeShow] corre con el video ya guardado y antes de mostrarlo.
  Future<void> pumpVideo(
    WidgetTester tester,
    FakeYouTubeClient client, {
    Widget? screen,
    String? originalFilePath,
    void Function()? beforeShow,
  }) async {
    harness = await LibraryHarness.create(
      extraOverrides: [youTubeClientProvider.overrideWithValue(client)],
    );
    final now = DateTime(2026, 9, 29, 10);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'video-1',
            title: 'Un video largo',
            source: Source(
              id: 'src-1',
              kind: SourceKind.youtube,
              capturedAt: now,
              url: 'https://www.youtube.com/watch?v=$_videoId',
              originalFilePath: originalFilePath,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );
    beforeShow?.call();

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.wrap(
        screen ??
            Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final item = ref
                      .watch(libraryItemProvider('video-1'))
                      .valueOrNull;
                  return item == null
                      ? const SizedBox.shrink()
                      : YouTubeAudioDownloadSection(item: item);
                },
              ),
            ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el detalle de un video muestra su audio, bajándose solo, sin '
      'el viejo botón de descargar', (tester) async {
    final client = FakeYouTubeClient(
      // Una descarga que no termina: el detalle queda mostrando el avance.
      audioPausedAfterFirstChunk: Completer<void>().future,
    );
    await pumpVideo(
      tester,
      client,
      screen: const ItemDetailScreen(itemId: 'video-1'),
    );

    expect(find.byType(YouTubeAudioDownloadSection), findsOneWidget);
    expect(client.audioRequested, [_videoId]);
    expect(find.text(es.youtubeAudioDownloading(33)), findsOneWidget);
    expect(find.text(es.youtubeAudioDownloadAction), findsNothing);
    expect(find.text(es.youtubeAudioCancel), findsNothing);
  });

  testWidgets('se baja solo al abrir el video, sin tocar nada, y muestra '
      'cuánto va', (tester) async {
    final client = FakeYouTubeClient(
      // 6 bytes en partes de 2: tras la primera parte, un tercio.
      audioPausedAfterFirstChunk: Completer<void>().future,
    );
    await pumpVideo(tester, client);

    expect(client.audioRequested, [_videoId]);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(es.youtubeAudioDownloading(33)), findsOneWidget);
    // Ni el botón de antes ni uno para cancelar: no hay nada que decidir.
    expect(find.text(es.youtubeAudioDownloadAction), findsNothing);
    expect(find.text(es.youtubeAudioDownloadHint), findsNothing);
    expect(find.text(es.youtubeAudioCancel), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('antes de saber cuánto pesa, dice que está bajando sin '
      'inventar un porcentaje', (tester) async {
    final client = FakeYouTubeClient(
      audioPausedAfterFirstChunk: Completer<void>().future,
    );
    harness = await LibraryHarness.create(
      extraOverrides: [youTubeClientProvider.overrideWithValue(client)],
    );
    final now = DateTime(2026, 9, 29, 10);
    final item = KnowledgeItem(
      id: 'video-1',
      title: 'Un video largo',
      source: Source(
        id: 'src-1',
        kind: SourceKind.youtube,
        capturedAt: now,
        url: 'https://www.youtube.com/watch?v=$_videoId',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );

    // Sin pasar por la base ni dejar correr la descarga: el primer cuadro,
    // antes de que llegue ningún byte.
    await tester.pumpWidget(
      harness.wrap(Scaffold(body: YouTubeAudioDownloadSection(item: item))),
    );

    expect(find.text(es.youtubeAudioDownloadingUnknown), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(es.youtubeAudioDownloadAction), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('al terminar, el audio queda guardado y se escucha ahí '
      'mismo', (tester) async {
    final resume = Completer<void>();
    final client = FakeYouTubeClient(audioPausedAfterFirstChunk: resume.future);
    await pumpVideo(tester, client);
    expect(find.text(es.youtubeAudioDownloading(33)), findsOneWidget);

    resume.complete();
    await tester.pumpAndSettle();

    expect(find.text(es.youtubeAudioDownloaded), findsOneWidget);
    expect(find.byType(MediaPlayerView), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(es.youtubeAudioDownloadAction), findsNothing);
    expect(harness.files.paths, hasLength(1));
    expect(client.audioRequested, [_videoId]);

    // Sin el reproductor, sin el temporizador que sigue la posición.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('si no se puede, dice por qué y "Reintentar" lo vuelve a '
      'bajar', (tester) async {
    final client = _FailsFirstAudioClient();
    await pumpVideo(tester, client);

    expect(find.text(es.failureNetwork), findsOneWidget);
    expect(find.text(es.detailRetry), findsOneWidget);
    expect(find.text(es.youtubeAudioDownloadAction), findsNothing);
    expect(harness.files.paths, isEmpty);

    await tester.tap(find.text(es.detailRetry));
    await tester.pumpAndSettle();

    expect(client.audioRequested, [_videoId, _videoId]);
    expect(find.text(es.failureNetwork), findsNothing);
    expect(find.text(es.youtubeAudioDownloaded), findsOneWidget);
    expect(find.byType(MediaPlayerView), findsOneWidget);
    expect(harness.files.paths, hasLength(1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('si ya se está bajando —la cola lo empezó al quedar listo—, '
      'abrirlo no lo pide de nuevo', (tester) async {
    final client = FakeYouTubeClient(
      audioPausedAfterFirstChunk: Completer<void>().future,
    );
    await pumpVideo(
      tester,
      client,
      beforeShow: () => unawaited(
        harness.container
            .read(youTubeAudioDownloadProvider('video-1').notifier)
            .start(),
      ),
    );

    expect(client.audioRequested, [_videoId]);
    expect(find.text(es.youtubeAudioDownloading(33)), findsOneWidget);
  });

  testWidgets('un video que ya tiene su audio no lo vuelve a bajar: se '
      'escucha directo', (tester) async {
    final client = FakeYouTubeClient();
    await pumpVideo(tester, client, originalFilePath: 'src-1.m4a');

    expect(client.audioRequested, isEmpty);
    expect(find.text(es.youtubeAudioDownloaded), findsOneWidget);
    expect(find.byType(MediaPlayerView), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
