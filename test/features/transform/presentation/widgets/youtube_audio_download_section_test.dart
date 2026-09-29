import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/youtube_embed_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/transform_test_doubles.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  /// Abre el detalle de un video de YouTube ya procesado —con su
  /// transcripción, sin audio—, con [client] como YouTube.
  Future<void> pumpVideo(WidgetTester tester, FakeYouTubeClient client) async {
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
              url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.wrap(const ItemDetailScreen(itemId: 'video-1')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no se baja solo: se ofrece, explicando para qué', (
    tester,
  ) async {
    final client = FakeYouTubeClient();
    await pumpVideo(tester, client);

    expect(find.text(es.youtubeAudioDownloadAction), findsOneWidget);
    expect(find.text(es.youtubeAudioDownloadHint), findsOneWidget);
    expect(client.audioRequested, isEmpty);
  });

  testWidgets('bajando muestra cuánto va, y cancelar lo corta sin dejar '
      'archivo', (tester) async {
    await pumpVideo(
      tester,
      // 6 bytes en partes de 2: tras la primera parte, un tercio.
      FakeYouTubeClient(audioPausedAfterFirstChunk: Completer<void>().future),
    );

    await tester.tap(find.text(es.youtubeAudioDownloadAction));
    await tester.pump();
    await tester.pump();

    expect(find.text(es.youtubeAudioDownloading(33)), findsOneWidget);

    await tester.tap(find.text(es.youtubeAudioCancel));
    await tester.pumpAndSettle();

    expect(find.text(es.youtubeAudioDownloadAction), findsOneWidget);
    expect(harness.files.paths, isEmpty);
  });

  testWidgets('al terminar, el audio queda guardado y se escucha ahí mismo, '
      'debajo del video', (tester) async {
    final resume = Completer<void>();
    await pumpVideo(
      tester,
      FakeYouTubeClient(audioPausedAfterFirstChunk: resume.future),
    );

    await tester.tap(find.text(es.youtubeAudioDownloadAction));
    await tester.pump();
    resume.complete();
    await tester.pumpAndSettle();

    expect(find.text(es.youtubeAudioDownloadAction), findsNothing);
    expect(find.text(es.youtubeAudioDownloaded), findsOneWidget);
    expect(find.byType(MediaPlayerView), findsOneWidget);
    // El video sigue siendo lo principal: su vista previa no se reemplaza.
    expect(find.byType(YoutubeEmbedView), findsOneWidget);
    expect(harness.files.paths, hasLength(1));
  });

  testWidgets('si no se puede, dice por qué y deja reintentar', (tester) async {
    await pumpVideo(
      tester,
      FakeYouTubeClient(audioError: const NetworkException(message: 'sin red')),
    );

    await tester.tap(find.text(es.youtubeAudioDownloadAction));
    await tester.pumpAndSettle();

    expect(find.text(es.failureNetwork), findsOneWidget);
    expect(find.text(es.youtubeAudioDownloadAction), findsOneWidget);
  });
}
