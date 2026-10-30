import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/transcript_follow_screen.dart';
import 'package:sinapsis/features/library/presentation/widgets/playback_synced_text.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/quiet_video_player.dart';

const _id = 'f45-clase';
final _now = DateTime(2026, 10, 30, 10);

KnowledgeItem _audio({
  String transcript = '[0:00] hola a todos\n[0:05] y chau',
}) => KnowledgeItem(
  id: _id,
  title: 'Una clase grabada',
  source: Source(
    id: _id,
    kind: SourceKind.audio,
    capturedAt: _now,
    originalFilePath: 'clase.opus',
  ),
  processingState: ProcessingState.ready,
  createdAt: _now,
  updatedAt: _now,
  renditions: [
    Rendition.text(
      id: '$_id-texto',
      itemId: _id,
      kind: RenditionKind.plainText,
      content: transcript,
      isPrimary: true,
      createdAt: _now,
    ),
  ],
);

/// La transcripción que sigue al audio (F23), en su pantalla (F45, paso 3):
/// el detalle de una fuente muestra solo su original, y esta es la forma de
/// escucharlo con su texto.
void main() {
  final es = AppLocalizationsEs();

  setUp(() => VideoPlayerPlatform.instance = QuietVideoPlayer());

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(800, 1200),
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    final harness = await LibraryHarness.create(
      extraOverrides: [
        itemPlaybackPathProvider.overrideWith(
          (ref, item) async => '/boveda/archivos/clase.opus',
        ),
      ],
    );
    await harness.container.read(libraryRepositoryProvider).save(_audio());
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: const TranscriptFollowScreen(itemId: _id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('arriba el audio, siempre a la vista, y abajo la transcripción '
      'que lo sigue', (tester) async {
    await pump(tester);

    final player = tester.widget<MediaPlayerView>(
      find.byKey(const Key('transcript-follow-player')),
    );
    expect(player.path, '/boveda/archivos/clase.opus');
    expect(player.audioOnly, isTrue);
    final text = tester.widget<PlaybackSyncedText>(
      find.byType(PlaybackSyncedText),
    );
    expect(text.rendition.id, '$_id-texto');
    expect(find.textContaining('hola a todos'), findsOneWidget);
    expect(
      tester
          .getBottomLeft(find.byKey(const Key('transcript-follow-player')))
          .dy,
      lessThan(tester.getTopLeft(find.byType(PlaybackSyncedText)).dy),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('«Ir a lo que suena» está en la barra, para el lector de '
      'pantalla también; sin nada sonando, no mueve nada', (tester) async {
    await pump(tester);

    final button = find.byKey(const Key('transcript-follow-now'));
    expect(find.byTooltip(es.f45S3TranscriptNow), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('a 360 dp con la letra al doble, en ${themeMode.name}: entra '
        'sin desbordarse', (tester) async {
      await pump(
        tester,
        size: const Size(360, 780),
        textScale: 2,
        themeMode: themeMode,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PlaybackSyncedText), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  }

  test('sigue la transcripción principal de un audio, un video o un YouTube; '
      'no la de un documento ni una vacía', () {
    expect(followedTranscriptOf(_audio())?.id, '$_id-texto');
    expect(followedTranscriptOf(_audio(transcript: '  ')), isNull);
    final document = _audio().copyWith(
      source: _audio().source.copyWith(kind: SourceKind.document),
    );
    expect(followedTranscriptOf(document), isNull);
  });
}
