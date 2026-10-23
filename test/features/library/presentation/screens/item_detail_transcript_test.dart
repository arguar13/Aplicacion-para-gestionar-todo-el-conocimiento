import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/timed_word.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/widgets/playback_synced_text.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../../support/library_harness.dart';

/// El motor nativo, falso: un audio de [duration] que dice dónde va.
class _FakePlayer extends VideoPlayerPlatform {
  _FakePlayer(this.duration);

  final Duration duration;
  Duration position = Duration.zero;

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

/// El detalle de un audio con su transcripción plegada en la tarjeta de
/// estudiar (F39): «Volver al audio» la despliega y muestra lo que suena.
void main() {
  final now = DateTime(2026, 10, 23);
  late _FakePlayer player;

  setUp(() {
    player = _FakePlayer(const Duration(minutes: 3));
    VideoPlayerPlatform.instance = player;
  });

  testWidgets('con la transcripción plegada, «Volver al audio» la despliega '
      'y lleva a la palabra que suena', (tester) async {
    final harness = await LibraryHarness.create(
      extraOverrides: [
        resolvedFileViewerProvider.overrideWith(
          (ref, item) async =>
              const MediaResolvedViewer(path: _path, isVideo: false),
        ),
      ],
    );
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'item-1',
            title: 'Clase grabada',
            source: Source(
              id: 'src-1',
              kind: SourceKind.audio,
              capturedAt: now,
              originalFilePath: 'originales/src-1/clase.opus',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'r1',
                itemId: 'item-1',
                kind: RenditionKind.plainText,
                content: 'Hola a todos. Bienvenidos al curso.',
                isPrimary: true,
                createdAt: now,
                wordTimings: const [
                  TimedWord('Hola', 0),
                  TimedWord('a', 400),
                  TimedWord('todos.', 700),
                  TimedWord('Bienvenidos', 1200),
                  TimedWord('al', 2000),
                  TimedWord('curso.', 2300),
                ],
              ),
            ],
          ),
        );
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(const ItemDetailScreen(itemId: 'item-1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('media-play')));
    await tester.pumpAndSettle();
    player.position = const Duration(milliseconds: 1300);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    // Bajar leyendo: el reproductor sale de la pantalla.
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ItemDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.textContaining('Bienvenidos'), findsNothing);

    await tester.tap(find.byKey(const Key('mini-player-back')));
    await tester.pumpAndSettle();

    final transcript = find.descendant(
      of: find.byType(PlaybackSyncedText),
      matching: find.byType(SelectableText),
    );
    expect(transcript, findsOneWidget);
    final playing = <String>[];
    tester.widget<SelectableText>(transcript).textSpan!.visitChildren((span) {
      if (span is TextSpan &&
          span.style?.backgroundColor == RenderedMarkdown.playingColor) {
        playing.add(span.text ?? '');
      }
      return true;
    });
    expect(playing, ['Bienvenidos']);

    // Al salir del detalle, el audio se suelta: no sigue sonando.
    await tester.pumpWidget(harness.wrap(const SizedBox()));
    await tester.pump();
    // Soltarlo termina de a poco: el reproductor deja de preguntar dónde
    // va recién en su próximo aviso.
    await tester.pump(const Duration(seconds: 1));
    expect(harness.container.exists(playbackSessionProvider(_path)), isFalse);

    await tester.pumpWidget(const SizedBox());
  });
}
