import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/features/blocks/presentation/screens/block_editor_screen.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/transcript_follow_screen.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_more.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue_state.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../../support/fake_ai_organize_queue.dart';
import '../../../../support/library_harness.dart';

/// El motor nativo, falso: un video de un minuto que se abre sin más. Hace
/// falta para el audio de un video, en la parte de arriba del panel.
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
          size: const Size(1080, 1920),
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

const _id = 'f26-fuente';
final _now = DateTime(2026, 10, 2, 10);

/// Un elemento de [kind] con [texts] como formas de texto —la primera, la
/// principal—.
KnowledgeItem _source(
  SourceKind kind, {
  String? file,
  String? url,
  ProcessingState state = ProcessingState.ready,
  List<String> texts = const [],
  RenditionKind textKind = RenditionKind.plainText,
}) => KnowledgeItem(
  id: _id,
  title: 'Una fuente',
  source: Source(
    id: _id,
    kind: kind,
    capturedAt: _now,
    originalFilePath: file,
    url: url,
  ),
  processingState: state,
  createdAt: _now,
  updatedAt: _now,
  renditions: [
    for (final (index, content) in texts.indexed)
      Rendition.text(
        id: '$_id-texto-$index',
        itemId: _id,
        kind: textKind,
        content: content,
        isPrimary: index == 0,
        createdAt: _now,
      ),
  ],
);

/// El panel de la fuente (F26): qué partes muestra según la fuente, qué
/// ofrece "Más" de una nota, cómo cuenta lo que está pasando, qué hacen los
/// mosaicos de una nota y que entra sin desbordarse en un teléfono. Una
/// fuente no lleva mosaicos (F45, paso 3): lo de su «Más» se prueba en
/// Procesado, en `source_text_button_test.dart`.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  // La letra de verdad de la app: la de las pruebas dibuja cada letra como
  // un cuadrado de 1 em, y con ella "Resumir" mediría casi el doble que en
  // un teléfono. Para saber si los nombres de los mosaicos entran hay que
  // medirlos con Inter.
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    await inter.load();
  });

  setUp(() => VideoPlayerPlatform.instance = _FakePlayer());

  /// Guarda [item] y muestra su panel solo, con el mismo aire a los costados
  /// que en el detalle, siguiendo al elemento en la base.
  Future<void> pumpPanel(
    WidgetTester tester,
    KnowledgeItem item, {
    double width = 412,
    double height = 1000,
    ThemeData? theme,
    bool chatModelReady = false,
    String? summarizeResponse,
    List<Override> extraOverrides = const [],
    Future<void> Function()? beforeShow,
    double gapAbove = 0,
    double textScale = 1,
  }) async {
    harness = await LibraryHarness.create(
      chatModelReady: chatModelReady,
      summarizeResponse: summarizeResponse,
      extraOverrides: extraOverrides,
    );
    await harness.container.read(libraryRepositoryProvider).save(item);
    await beforeShow?.call();

    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.wrap(
        MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Theme(
            data: theme ?? AppTheme.lightTheme,
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Consumer(
                  builder: (context, ref, _) {
                    final current = ref
                        .watch(libraryItemProvider(item.id))
                        .valueOrNull;
                    return current == null
                        ? const SizedBox.shrink()
                        : SourcePanel(item: current, gapAbove: gapAbove);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SourcePanelTile tile(WidgetTester tester, String key) =>
      tester.widget<SourcePanelTile>(find.byKey(Key(key)));

  bool enabled(WidgetTester tester, String key) =>
      tile(tester, key).onTap != null;

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('source-panel-more')));
    await tester.pumpAndSettle();
  }

  Future<void> fail(ProcessingFailureReason reason) => harness.container
      .read(processingStateRepositoryProvider)
      .fail(_id, reason);

  final panel = find.byType(SourcePanel);

  group('las partes, según la fuente', () {
    for (final (kind, file) in [
      (SourceKind.webPage, null),
      (SourceKind.document, 'originales/f26/libro.pdf'),
    ]) {
      testWidgets('${kind.name} lista, con su texto: sin Leer · Copiar · Más '
          'ni nada que contar, el panel no se dibuja (F45, paso 3)', (
        tester,
      ) async {
        await pumpPanel(
          tester,
          _source(
            kind,
            file: file,
            url: 'https://ejemplo.org/nota',
            texts: ['[0:00] Un artículo.'],
          ),
        );

        expect(find.byType(SourcePanelTile), findsNothing);
        expect(find.byType(SourcePanelStatus), findsNothing);
        expect(find.byType(SourcePanelAudio), findsNothing);
        expect(find.byKey(const Key('source-panel')), findsNothing);
        // Ni el aire de arriba: vacío, no deja un hueco.
        expect(tester.getSize(panel).height, 0);
      });
    }

    testWidgets('una nota propia con texto: los cuatro mosaicos, con '
        '«Resumir», y «Más» ofrece que la organice la IA y buscarle fechas', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        _source(SourceKind.manualNote, texts: ['Nació en 1809.']),
      );

      expect(find.byType(SourcePanelTile), findsNWidgets(4));
      expect(enabled(tester, 'source-panel-summarize'), isTrue);

      await openMore(tester);

      expect(
        find.byKey(const Key('source-more-organizeWithAi')),
        findsOneWidget,
      );
      expect(find.text(es.sourcePanelOrganizeWithAi), findsOneWidget);
      expect(find.text(es.sourcePanelOrganizeWithAiHint), findsOneWidget);
      expect(
        find.byKey(const Key('source-more-findDatesWithAi')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('source-more-reextract')), findsNothing);
    });

    testWidgets('una página web que no se pudo traer: el motivo, con su '
        '«Reintentar», y nada más', (tester) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.webPage,
          url: 'https://ejemplo.org/nota',
          state: ProcessingState.failed,
        ),
        beforeShow: () => fail(ProcessingFailureReason.network),
        gapAbove: 12,
      );

      expect(find.text(es.failureNetwork), findsOneWidget);
      expect(find.byType(SourcePanelTile), findsNothing);
      expect(
        find.descendant(of: panel, matching: find.byType(Divider)),
        findsNothing,
      );
      // Con algo que contar, va con su aire debajo del original.
      expect(
        tester.getTopLeft(find.byKey(const Key('source-panel'))).dy -
            tester.getTopLeft(panel).dy,
        12,
      );
    });

    testWidgets('una nota de bloques: Leer · Resumir · Copiar · Editar, y '
        '"Editar" abre el editor', (tester) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.manualNote,
          textKind: RenditionKind.blocks,
          texts: [
            encodeContentBlocks(const [
              ContentBlock.heading(text: 'Un título'),
              ContentBlock.paragraph(text: 'Un párrafo.'),
            ]),
          ],
        ),
      );

      expect(find.byKey(const Key('source-panel-more')), findsNothing);
      expect(find.text(es.blocksEditAction), findsOneWidget);
      // La lectura para destilar trabaja sobre el texto de una fuente.
      expect(enabled(tester, 'source-panel-read'), isFalse);
      expect(find.byTooltip(es.sourcePanelReadNeedsSource), findsOneWidget);
      expect(enabled(tester, 'source-panel-copy'), isTrue);

      await tester.tap(find.byKey(const Key('source-panel-edit')));
      await tester.pumpAndSettle();

      expect(find.byType(BlockEditorScreen), findsOneWidget);
    });

    testWidgets('un video: el audio con su encabezado y los controles '
        'compactos, y la transcripción que lo sigue; sin mosaicos', (
      tester,
    ) async {
      const path = '/boveda/archivos/reel.mp4';
      await pumpPanel(
        tester,
        _source(
          SourceKind.video,
          file: 'originales/f26/reel.mp4',
          texts: ['[0:00] lo que se dice'],
        ),
        extraOverrides: [
          resolvedFileViewerProvider.overrideWith(
            (ref, item) async =>
                const MediaResolvedViewer(path: path, isVideo: true),
          ),
        ],
      );

      expect(find.text(es.sourcePanelAudioTitle), findsOneWidget);
      final player = tester.widget<MediaPlayerView>(
        find.byKey(const Key('video-audio-player')),
      );
      expect(player.compact, isTrue);
      expect(player.path, path);
      for (final key in [
        'media-replay',
        'media-play',
        'media-forward',
        'media-speed',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byType(SourcePanelTile), findsNothing);
      expect(
        tester.getBottomLeft(find.byType(SourcePanelAudio)).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('source-panel-transcript')))
              .dy,
        ),
      );
      expect(
        find.descendant(of: panel, matching: find.byType(Divider)),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('lo que está pasando', () {
    testWidgets('sin texto todavía: lo dice', (tester) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.webPage,
          url: 'https://ejemplo.org/nota',
          state: ProcessingState.pending,
        ),
      );

      expect(find.text(es.detailNoContentYet), findsOneWidget);
      expect(find.byType(SourcePanelTile), findsNothing);
      expect(find.text(es.detailRetry), findsNothing);
    });

    testWidgets('mientras avanza, la barra dice cuánto va', (tester) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.document,
          file: 'originales/f26/libro.pdf',
          state: ProcessingState.processing,
        ),
        beforeShow: () async => harness.queue.showProgress({
          _id: const ProcessingProgress(
            lane: ProcessingLane.long,
            done: 3,
            total: 10,
          ),
        }),
      );

      expect(find.text(es.detailNoContentYetFile), findsOneWidget);
      expect(find.text(es.processingRecognizingPages(3, 10)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('si falló, el motivo y un único "Reintentar" tonal, que lo '
        'devuelve a la cola', (tester) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.webPage,
          url: 'https://ejemplo.org/sin-red',
          state: ProcessingState.failed,
        ),
        beforeShow: () => fail(ProcessingFailureReason.network),
      );

      expect(find.text(es.failureNetwork), findsOneWidget);
      final retry = find.widgetWithText(FilledButton, es.detailRetry);
      expect(retry, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.byType(TextButton)),
        findsNothing,
      );

      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, [_id]);
    });

    testWidgets('si falta el modelo de transcripción, ofrece descargarlo, '
        'no reintentar', (tester) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.audio,
          file: 'originales/f26/clase.m4a',
          state: ProcessingState.failed,
        ),
        beforeShow: () =>
            fail(ProcessingFailureReason.transcriptionModelMissing),
      );

      expect(find.text(es.failureTranscriptionModelMissing), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, es.failureTranscriptionModelAction),
        findsOneWidget,
      );
      expect(find.text(es.detailRetry), findsNothing);
    });

    testWidgets('volviendo a extraer: lo dice', (tester) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.audio,
          file: 'originales/f26/clase.m4a',
          state: ProcessingState.pending,
          texts: ['[0:00] el texto de antes'],
        ),
      );

      expect(find.byKey(const Key('reextracting-text')), findsOneWidget);
      expect(find.text(es.detailReextractInProgress), findsOneWidget);
    });

    testWidgets('si volver a extraer falló sin un motivo conocido, dice que '
        'el texto de antes sigue guardado, y ofrece reintentar', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.audio,
          file: 'originales/f26/clase.m4a',
          state: ProcessingState.failed,
          texts: ['el texto de antes'],
        ),
      );

      expect(find.text(es.sourcePanelReextractFailed), findsOneWidget);
      expect(find.text(es.detailRetry), findsOneWidget);
    });
  });

  group('los mosaicos', () {
    testWidgets('"Copiar" copia el texto entero, con una vibración corta', (
      tester,
    ) async {
      String? copied;
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpPanel(
        tester,
        _source(SourceKind.manualNote, texts: ['Todo el artículo.']),
      );

      await tester.tap(find.byKey(const Key('source-panel-copy')));
      await tester.pumpAndSettle();

      expect(copied, 'Todo el artículo.');
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(find.text(es.detailContentCopied), findsOneWidget);
    });

    testWidgets('"Copiar" en una nota de bloques copia su texto, no el JSON '
        'con que se guarda', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpPanel(
        tester,
        _source(
          SourceKind.manualNote,
          textKind: RenditionKind.blocks,
          texts: [
            encodeContentBlocks(const [
              ContentBlock.heading(text: 'Un título'),
              ContentBlock.paragraph(text: 'Un párrafo.'),
            ]),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('source-panel-copy')));
      await tester.pumpAndSettle();

      expect(copied, 'Un título\n\nUn párrafo.');
    });

    testWidgets('"Resumir" de una nota muestra el resumen en su diálogo', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        _source(SourceKind.manualNote, texts: ['Un artículo largo.']),
        chatModelReady: true,
        summarizeResponse: 'La idea en dos líneas.',
      );

      await tester.tap(find.byKey(const Key('source-panel-summarize')));
      await tester.pumpAndSettle();

      expect(find.text(es.summarizeDialogTitle), findsOneWidget);
      expect(find.text('La idea en dos líneas.'), findsOneWidget);
      expect(harness.summarizationService.summarized, ['Un artículo largo.']);
      expect(tile(tester, 'source-panel-summarize').busy, isFalse);
    });

    testWidgets('"Leer" de una nota abre la lectura para destilar', (
      tester,
    ) async {
      harness = await LibraryHarness.create();
      await harness.container
          .read(libraryRepositoryProvider)
          .save(
            _source(SourceKind.manualNote, texts: ['Para leer con calma.']),
          );
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.pushTo(RoutePaths.itemDetail(_id));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('source-panel-read')));
      await tester.pumpAndSettle();

      expect(find.byType(ReadingScreen), findsOneWidget);
    });
  });

  group('organizar con la IA (F27)', () {
    late FakeAiOrganizeQueue queue;

    Future<void> pumpWithQueue(
      WidgetTester tester, {
      required bool modelsReady,
    }) async {
      queue = FakeAiOrganizeQueue();
      // Una nota propia: una fuente se organiza en su documento procesado
      // (F41, decisión K).
      await pumpPanel(
        tester,
        _source(SourceKind.manualNote, texts: ['Un artículo.']),
        chatModelReady: modelsReady,
        extraOverrides: [aiOrganizeQueueProvider.overrideWithValue(queue)],
        beforeShow: () async =>
            harness.embeddingModelManager.ready = modelsReady,
      );
    }

    Future<void> organize(WidgetTester tester) async {
      await openMore(tester);
      await tester.tap(find.byKey(const Key('source-more-organizeWithAi')));
      await tester.pumpAndSettle();
    }

    testWidgets('se lo pide a la cola y avisa que lo organiza en un momento', (
      tester,
    ) async {
      await pumpWithQueue(tester, modelsReady: true);
      await organize(tester);

      expect(queue.organizeNowCalls, [_id]);
      expect(find.text(es.aiOrganizeNowQueued), findsOneWidget);
      // La hoja se cerró antes de pedirlo.
      expect(find.text(es.sourcePanelMoreTitle), findsNothing);
    });

    testWidgets('si falta un modelo, lo pide igual y dice que espera', (
      tester,
    ) async {
      await pumpWithQueue(tester, modelsReady: false);
      await organize(tester);

      expect(queue.organizeNowCalls, [_id]);
      expect(find.text(es.aiOrganizeNowNeedsModel), findsOneWidget);
    });

    testWidgets('con la IA en pausa, lo pide igual y dice cuándo sigue', (
      tester,
    ) async {
      await pumpWithQueue(tester, modelsReady: true);
      await harness.container
          .read(aiOrganizeSettingsProvider.notifier)
          .set(AiOrganizeToggle.enabled, on: false);
      await organize(tester);

      expect(queue.organizeNowCalls, [_id]);
      expect(find.text(es.aiOrganizeNowPaused), findsOneWidget);
    });

    group('con la IA en la nube (F32)', () {
      late List<bool> asked;

      Future<void> pumpWithCloud(
        WidgetTester tester,
        LanguageModelStatus status,
      ) async {
        queue = FakeAiOrganizeQueue();
        asked = [];
        await pumpPanel(
          tester,
          _source(SourceKind.manualNote, texts: ['Un artículo.']),
          extraOverrides: [
            aiOrganizeQueueProvider.overrideWithValue(queue),
            languageModelStatusCheckProvider.overrideWithValue(({
              bool background = false,
            }) async {
              asked.add(background);
              return status;
            }),
          ],
          beforeShow: () async => harness.embeddingModelManager.ready = true,
        );
      }

      testWidgets('lista, avisa que lo organiza y pregunta por la de fondo', (
        tester,
      ) async {
        await pumpWithCloud(
          tester,
          const LanguageModelReady(provider: AiProvider.gemini),
        );
        await organize(tester);

        expect(queue.organizeNowCalls, [_id]);
        expect(find.text(es.aiOrganizeNowQueued), findsOneWidget);
        // Lo hace la IA de fondo: con su tope del día, no con el de la
        // persona.
        expect(asked, [true]);
      });

      testWidgets('sin clave, lo pide igual y dice que falta la clave', (
        tester,
      ) async {
        await pumpWithCloud(
          tester,
          const LanguageModelNeedsAccount(provider: AiProvider.gemini),
        );
        await organize(tester);

        expect(queue.organizeNowCalls, [_id]);
        expect(find.text(es.aiOrganizeNowNeedsKey), findsOneWidget);
        expect(find.text(es.aiOrganizeNowNeedsModel), findsNothing);
      });

      for (final (name, status) in [
        (
          'sin cuota',
          LanguageModelOutOfQuota(
            provider: AiProvider.gemini,
            accounts: 2,
            resetsAt: DateTime(2026, 10, 17, 4),
          ),
        ),
        (
          'en el tope del día de la IA de fondo',
          LanguageModelBackgroundCapReached(
            provider: AiProvider.gemini,
            cap: 200,
            resetsAt: DateTime(2026, 10, 17, 4),
          ),
        ),
      ]) {
        testWidgets('$name, lo pide igual y dice que espera la cuota', (
          tester,
        ) async {
          await pumpWithCloud(tester, status);
          await organize(tester);

          expect(queue.organizeNowCalls, [_id]);
          expect(find.text(es.aiOrganizeNowWaits), findsOneWidget);
        });
      }

      testWidgets('lista pero sin el modelo de búsqueda, dice que falta '
          'bajarlo', (tester) async {
        await pumpWithCloud(
          tester,
          const LanguageModelReady(provider: AiProvider.gemini),
        );
        harness.embeddingModelManager.ready = false;
        await organize(tester);

        expect(find.text(es.aiOrganizeNowNeedsModel), findsOneWidget);
      });
    });
  });

  group('buscar fechas con IA (F40)', () {
    late FakeAiOrganizeQueue queue;
    late List<bool> asked;

    Future<void> pumpWith(
      WidgetTester tester, {
      List<String> texts = const ['Nació en 1809.'],
      ProcessingState state = ProcessingState.ready,
      bool modelsReady = true,
      LanguageModelStatus? cloud,
    }) async {
      queue = FakeAiOrganizeQueue();
      asked = [];
      await pumpPanel(
        tester,
        _source(SourceKind.manualNote, texts: texts, state: state),
        chatModelReady: modelsReady,
        extraOverrides: [
          aiOrganizeQueueProvider.overrideWithValue(queue),
          if (cloud != null)
            languageModelStatusCheckProvider.overrideWithValue(({
              bool background = false,
            }) async {
              asked.add(background);
              return cloud;
            }),
        ],
        beforeShow: () async =>
            harness.embeddingModelManager.ready = modelsReady,
      );
    }

    Future<void> findDates(WidgetTester tester) async {
      await openMore(tester);
      await tester.tap(find.byKey(const Key('source-more-findDatesWithAi')));
      await tester.pumpAndSettle();
    }

    testWidgets('«Más» la ofrece con lo que hace, justo después de organizar', (
      tester,
    ) async {
      await pumpWith(tester);
      await openMore(tester);

      expect(
        find.byKey(const Key('source-more-findDatesWithAi')),
        findsOneWidget,
      );
      expect(find.text(es.sourcePanelFindDates), findsOneWidget);
      expect(find.text(es.sourcePanelFindDatesHint), findsOneWidget);
      // Las dos cosas de la IA llevan su ✨; lo demás de la hoja, no.
      expect(
        find.descendant(
          of: find.byKey(const Key('source-more-findDatesWithAi')),
          matching: find.byType(AiSparkCircle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('source-more-organizeWithAi')),
          matching: find.byType(AiSparkCircle),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const Key('source-more-organizeWithAi')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('source-more-findDatesWithAi')))
              .dy,
        ),
      );
    });

    testWidgets('le pide a la cola solo las fechas de ese elemento y avisa '
        'que las busca en un rato', (tester) async {
      await pumpWith(tester);
      await findDates(tester);

      expect(queue.dateRequests, [
        [_id],
      ]);
      // No pidió organizarlo entero.
      expect(queue.organizeNowCalls, isEmpty);
      expect(find.text(es.datesAskQueued(1)), findsOneWidget);
      // La hoja se cerró antes de pedirlo.
      expect(find.text(es.sourcePanelMoreTitle), findsNothing);
    });

    testWidgets('sin texto no se ofrece: no hay fechas que buscar', (
      tester,
    ) async {
      await pumpWith(tester, texts: const []);
      await openMore(tester);

      expect(
        find.byKey(const Key('source-more-organizeWithAi')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('source-more-findDatesWithAi')),
        findsNothing,
      );
    });

    testWidgets('con un texto en blanco tampoco', (tester) async {
      await pumpWith(tester, texts: const ['  \n  ']);
      await openMore(tester);

      expect(
        find.byKey(const Key('source-more-findDatesWithAi')),
        findsNothing,
      );
    });

    testWidgets('con el texto en cualquiera de sus formas se ofrece', (
      tester,
    ) async {
      await pumpWith(tester, texts: const ['', 'Nació en 1809.']);
      await openMore(tester);

      expect(
        find.byKey(const Key('source-more-findDatesWithAi')),
        findsOneWidget,
      );
    });

    test('mientras se procesa o si falló, no se ofrece: el texto va a '
        'cambiar', () {
      for (final state in [
        ProcessingState.pending,
        ProcessingState.processing,
        ProcessingState.failed,
      ]) {
        final item = _source(
          SourceKind.manualNote,
          texts: const ['Nació en 1809.'],
          state: state,
        );
        expect(
          sourceMoreActionsFor(item),
          isNot(contains(SourceMoreAction.findDatesWithAi)),
          reason: state.name,
        );
      }
    });

    testWidgets('si falta un modelo, lo pide igual y dice que espera', (
      tester,
    ) async {
      await pumpWith(tester, modelsReady: false);
      await findDates(tester);

      expect(queue.dateRequests, hasLength(1));
      expect(find.text(es.datesAskNeedsModel(1)), findsOneWidget);
    });

    testWidgets('con la IA en pausa, lo pide igual y dice cuándo sigue', (
      tester,
    ) async {
      await pumpWith(tester);
      await harness.container
          .read(aiOrganizeSettingsProvider.notifier)
          .set(AiOrganizeToggle.enabled, on: false);
      await findDates(tester);

      expect(queue.dateRequests, hasLength(1));
      expect(find.text(es.datesAskPaused(1)), findsOneWidget);
    });

    testWidgets('no necesita el modelo de búsqueda: con el de lenguaje '
        'listo, alcanza', (tester) async {
      await pumpWith(tester);
      harness.embeddingModelManager.ready = false;
      await findDates(tester);

      expect(find.text(es.datesAskQueued(1)), findsOneWidget);
      expect(find.text(es.datesAskNeedsModel(1)), findsNothing);
    });

    group('con la IA en la nube (F32)', () {
      testWidgets('lista: avisa y pregunta por la de fondo', (tester) async {
        await pumpWith(
          tester,
          cloud: const LanguageModelReady(provider: AiProvider.gemini),
        );
        await findDates(tester);

        expect(find.text(es.datesAskQueued(1)), findsOneWidget);
        expect(asked, [true]);
      });

      testWidgets('sin clave, lo pide igual y dice que falta la clave', (
        tester,
      ) async {
        await pumpWith(
          tester,
          cloud: const LanguageModelNeedsAccount(provider: AiProvider.gemini),
        );
        await findDates(tester);

        expect(queue.dateRequests, hasLength(1));
        expect(find.text(es.datesAskNeedsKey(1)), findsOneWidget);
      });

      testWidgets('sin cuota, lo pide igual y dice que espera', (tester) async {
        await pumpWith(
          tester,
          cloud: LanguageModelOutOfQuota(
            provider: AiProvider.gemini,
            accounts: 1,
            resetsAt: DateTime(2026, 10, 17, 4),
          ),
        );
        await findDates(tester);

        expect(queue.dateRequests, hasLength(1));
        expect(find.text(es.datesAskWaits(1)), findsOneWidget);
      });
    });
  });

  group('en un teléfono', () {
    for (final width in [360.0, 412.0]) {
      for (final (name, theme) in [
        ('claro', AppTheme.lightTheme),
        ('oscuro', AppTheme.darkTheme),
      ]) {
        testWidgets('a $width px, tema $name: el audio y el fallo de una '
            'fuente entran sin desbordarse', (tester) async {
          await pumpPanel(
            tester,
            _source(
              SourceKind.video,
              file: 'originales/f26/reel.mp4',
              state: ProcessingState.failed,
              texts: ['[0:00] lo que se dice'],
            ),
            width: width,
            theme: theme,
            extraOverrides: [
              resolvedFileViewerProvider.overrideWith(
                (ref, item) async => const MediaResolvedViewer(
                  path: '/boveda/archivos/reel.mp4',
                  isVideo: true,
                ),
              ),
            ],
            beforeShow: () => fail(ProcessingFailureReason.network),
          );

          expect(tester.takeException(), isNull);
          expect(tester.getSize(panel).width, width - 48);
          // Las dos partes: el audio y el fallo. Los mosaicos, en una nota.
          expect(find.byType(SourcePanelAudio), findsOneWidget);
          expect(find.text(es.failureNetwork), findsOneWidget);
          expect(find.byType(SourcePanelTile), findsNothing);
          // Los controles del audio, sin pisarse: la velocidad a la derecha
          // del botón de avanzar.
          expect(
            tester.getTopLeft(find.byKey(const Key('media-speed'))).dx,
            greaterThanOrEqualTo(
              tester.getTopRight(find.byKey(const Key('media-forward'))).dx,
            ),
          );

          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  });

  for (final (name, theme) in [
    ('claro', AppTheme.lightTheme),
    ('oscuro', AppTheme.darkTheme),
  ]) {
    testWidgets('a 360 px con la letra al doble, tema $name: lo que cuenta '
        'el panel de una fuente entra, con su «Reintentar», y el lector de '
        'pantalla lo dice', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPanel(
        tester,
        _source(
          SourceKind.webPage,
          url: 'https://ejemplo.org/sin-red',
          state: ProcessingState.failed,
        ),
        beforeShow: () => fail(ProcessingFailureReason.network),
        width: 360,
        theme: theme,
        textScale: 2,
        gapAbove: 12,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SourcePanelTile), findsNothing);
      expect(find.bySemanticsLabel(es.failureNetwork), findsOneWidget);
      expect(
        tester.getSemantics(find.text(es.detailRetry)),
        isSemantics(label: es.detailRetry, isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets('a 360 px, tema $name: los cuatro mosaicos de una nota '
        'entran en un renglón, del mismo ancho, con «Resumir» entero', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        _source(SourceKind.manualNote, texts: ['Una idea.']),
        width: 360,
        theme: theme,
      );

      expect(tester.takeException(), isNull);
      final tiles = find.byType(SourcePanelTile);
      expect(tiles, findsNWidgets(4));
      final rects = [for (var i = 0; i < 4; i++) tester.getRect(tiles.at(i))];
      for (final rect in rects) {
        expect(rect.top, rects.first.top);
        expect(rect.width, closeTo(rects.first.width, 0.01));
      }
      for (final label in [
        es.sourcePanelRead,
        es.sourcePanelSummarize,
        es.sourcePanelCopy,
        es.sourcePanelMore,
      ]) {
        final text = find.text(label);
        expect(
          tester.getSize(text).width,
          lessThanOrEqualTo(rects.first.width),
        );
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
          reason: label,
        );
      }
    });
  }

  group('la transcripción que sigue al audio (F23; F45, paso 3)', () {
    final line = find.byKey(const Key('source-panel-transcript'));
    final playback = itemPlaybackPathProvider.overrideWith(
      (ref, item) async => '/boveda/archivos/clase.m4a',
    );

    testWidgets('con su audio y su transcripción, la franja la ofrece y '
        '«Ver la transcripción» la abre en su pantalla', (tester) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.audio,
          file: 'originales/f26/clase.m4a',
          texts: ['[0:00] hola a todos'],
        ),
        extraOverrides: [playback],
      );

      expect(line, findsOneWidget);
      expect(find.text(es.f45S3TranscriptLine), findsOneWidget);
      expect(find.byType(SourcePanelTile), findsNothing);

      await tester.tap(find.text(es.f45S3TranscriptOpen));
      await tester.pumpAndSettle();

      expect(find.byType(TranscriptFollowScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin un audio que suene, no', (tester) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.audio,
          file: 'originales/f26/clase.m4a',
          texts: ['[0:00] hola a todos'],
        ),
        extraOverrides: [
          itemPlaybackPathProvider.overrideWith((ref, item) async => null),
        ],
      );

      expect(line, findsNothing);
    });

    testWidgets(
      'mientras se vuelve a extraer, tampoco: el texto va a cambiar',
      (tester) async {
        await pumpPanel(
          tester,
          _source(
            SourceKind.audio,
            file: 'originales/f26/clase.m4a',
            state: ProcessingState.pending,
            texts: ['[0:00] el texto de antes'],
          ),
          extraOverrides: [playback],
        );

        expect(line, findsNothing);
        expect(find.byKey(const Key('reextracting-text')), findsOneWidget);
      },
    );

    testWidgets('en un documento, nunca: no tiene audio que seguir', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        _source(
          SourceKind.document,
          file: 'originales/f26/libro.pdf',
          texts: ['Un libro.'],
        ),
        extraOverrides: [playback],
      );

      expect(line, findsNothing);
    });
  });
}
