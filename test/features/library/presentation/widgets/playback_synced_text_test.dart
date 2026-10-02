import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/timed_word.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/playback_synced_text.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
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

TextRendition _transcript(
  String content, {
  List<TimedWord> wordTimings = const [],
}) => TextRendition(
  id: 'rend-1',
  itemId: 'item-1',
  kind: RenditionKind.plainText,
  content: content,
  isPrimary: true,
  createdAt: DateTime(2026, 10),
  wordTimings: wordTimings,
);

/// Una transcripción con el momento de cada palabra (F23). Las posiciones
/// en el texto: "Hola" 0–4, "a" 5–6, "todos," 7–13, "bienvenidos" 14–25,
/// "al" 26–28, "curso." 29–35.
final _timed = _transcript(
  'Hola a todos, bienvenidos al curso.',
  wordTimings: const [
    TimedWord('Hola', 0),
    TimedWord('a', 400),
    TimedWord('todos,', 700),
    TimedWord('bienvenidos', 1200),
    TimedWord('al', 2000),
    TimedWord('curso.', 2300),
  ],
);

/// La transcripción que sigue al audio: la palabra que suena, en amarillo;
/// tocar una palabra lleva el audio ahí.
void main() {
  late _FakePlayer player;

  setUp(() {
    player = _FakePlayer(const Duration(minutes: 3));
    VideoPlayerPlatform.instance = player;
  });

  /// El reproductor del detalle arriba —el que hace sonar el audio— y la
  /// transcripción abajo, como en el detalle de un audio.
  Future<void> pump(
    WidgetTester tester,
    TextRendition rendition, {
    PlaybackFollowLink? link,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          resolvedFileViewerProvider.overrideWith(
            (ref, item) async =>
                const MediaResolvedViewer(path: _path, isVideo: false),
          ),
          renditionHighlightsProvider.overrideWith(
            (ref, renditionId) => Stream.value(const <Highlight>[]),
          ),
          libraryItemProvider.overrideWith((ref, id) => Stream.value(_item)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(
                    height: 300,
                    child: MediaPlayerView(path: _path, isVideo: false),
                  ),
                  PlaybackSyncedText(
                    item: _item,
                    rendition: rendition,
                    markdown: false,
                    link: link,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Los pedazos del texto que se ven en amarillo, en orden.
  List<String> yellow(WidgetTester tester) {
    final span = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!;
    final found = <String>[];
    span.visitChildren((child) {
      if (child is TextSpan &&
          child.style?.backgroundColor == RenderedMarkdown.playingColor) {
        found.add(child.text ?? '');
      }
      return true;
    });
    return found;
  }

  /// Hace sonar el audio desde el reproductor del detalle.
  Future<void> play(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('media-play')));
    await tester.pumpAndSettle();
  }

  /// Deja que el audio llegue a [position]: `video_player` pregunta por la
  /// posición cada 100 ms mientras suena.
  Future<void> advanceTo(WidgetTester tester, Duration position) async {
    player.position = position;
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
  }

  /// Un toque sin arrastrar en la posición [offset] del texto —el mismo
  /// camino que recorre Flutter con un toque de verdad—.
  Future<void> tapAt(WidgetTester tester, int offset) async {
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection.collapsed(offset: offset),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pump();
  }

  testWidgets('antes de que el audio empiece es el texto de siempre: nada en '
      'amarillo, y "Volver al audio" no tiene qué mostrar', (tester) async {
    final link = PlaybackFollowLink();
    await pump(tester, _timed, link: link);

    expect(
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .toPlainText(),
      'Hola a todos, bienvenidos al curso.',
    );
    expect(yellow(tester), isEmpty);
    expect(link.revealPlaying, isNotNull);
    expect(link.revealPlaying!(), isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con los tiempos de cada palabra, se pinta en amarillo la '
      'palabra que suena, y va siguiendo al audio', (tester) async {
    final link = PlaybackFollowLink();
    await pump(tester, _timed, link: link);
    await play(tester);

    await advanceTo(tester, const Duration(milliseconds: 1300));
    expect(yellow(tester), ['bienvenidos']);

    await advanceTo(tester, const Duration(milliseconds: 2100));
    expect(yellow(tester), ['al']);

    // Ya sonando, "Volver al audio" sí tiene qué mostrar.
    expect(link.revealPlaying!(), isTrue);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin tiempos por palabra —una transcripción de antes—, se '
      'pinta el renglón entero de la marca que suena', (tester) async {
    await pump(
      tester,
      _transcript(
        '[0:00] Primer renglón del audio.\n'
        '[0:05] Segundo renglón, más largo.\n'
        '[0:12] Tercer renglón.',
      ),
    );
    await play(tester);

    await advanceTo(tester, const Duration(seconds: 1));
    expect(yellow(tester), ['Primer renglón del audio.']);

    // La marca "[0:05]" queda afuera: lo que se dice es el renglón.
    await advanceTo(tester, const Duration(seconds: 7));
    expect(yellow(tester), ['Segundo renglón, más largo.']);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tocar una palabra con el audio en marcha lleva el audio ahí; '
      'con el audio quieto, un toque es solo un toque', (tester) async {
    await pump(tester, _timed);

    // "curso." empieza en el 29: tocar en el medio de la palabra.
    await tapAt(tester, 31);
    expect(player.seeks, isEmpty);
    expect(yellow(tester), isEmpty);

    await play(tester);
    await advanceTo(tester, const Duration(milliseconds: 100));
    expect(yellow(tester), ['Hola']);

    await tapAt(tester, 31);
    expect(player.seeks, [const Duration(milliseconds: 2300)]);
    await advanceTo(tester, player.position);
    expect(yellow(tester), ['curso.']);

    // Entre dos palabras: va a la que sigue.
    await tapAt(tester, 13);
    expect(player.seeks.last, const Duration(milliseconds: 1200));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en pausa sigue en amarillo lo último que sonó', (tester) async {
    await pump(tester, _timed);
    await play(tester);
    await advanceTo(tester, const Duration(milliseconds: 1300));

    await tester.tap(find.byKey(const Key('media-play')));
    await tester.pumpAndSettle();
    expect(yellow(tester), ['bienvenidos']);

    await tester.pumpWidget(const SizedBox());
  });
}
