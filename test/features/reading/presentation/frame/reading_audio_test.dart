import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/narration/data/audio/document_audio_store.dart';
import 'package:sinapsis/features/narration/data/audio/speech_audio_renderer.dart';
import 'package:sinapsis/features/narration/domain/audio/document_audio.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/presentation/providers/document_audio_downloads.dart';
import 'package:sinapsis/features/narration/presentation/providers/document_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/narration/presentation/voices/speech_audio_approval.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_audio.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/disk_path_file_store.dart';
import '../../../../support/fake_speech_track_player.dart';
import '../../../../support/fake_text_to_speech_service.dart';
import '../../../narration/data/audio/speech_audio_fakes.dart';

/// Las descargas, sin generar nada: lo que se pide queda anotado, y la
/// prueba dice cuándo termina y cómo.
class _FakeDownloads extends DocumentAudioDownloads {
  final requested = <String>[];
  final cancelled = <String>[];
  Completer<DocumentAudio?>? pending;

  @override
  Future<DocumentAudio?> download(
    ReadableDocument document,
    DocumentAudioPlan plan,
  ) {
    requested.add(document.id);
    put(
      DocumentAudioJob(
        document: document,
        phase: DocumentAudioJobPhase.running,
        done: 1,
        total: 4,
      ),
    );
    return (pending = Completer()).future;
  }

  @override
  void cancel(String documentId) => cancelled.add(documentId);

  void put(DocumentAudioJob job) => state = {...state, job.document.id: job};

  void clear() => state = const {};
}

/// F47, paso 5: el audio de lo que se lee en ⋮ del marco —descargar, cómo
/// va, escucharlo, exportarlo y borrarlo— y la barra de la descarga.
void main() {
  final es = AppLocalizationsEs();
  const text = 'Uno dos tres.\nCuatro cinco.';
  final document = ReadableDocument(
    id: 'marco:1',
    title: 'Roma',
    segments: buildReadableSegments(text, sourceKey: 'texto:1'),
  );

  late DiskPathFileStore files;
  late _FakeDownloads downloads;
  late FakeVoiceRenderer voices;
  late List<String> shared;
  late ProviderContainer container;
  bool? approve;

  Future<void> pump(
    WidgetTester tester, {
    ReadableDocument? offered,
    bool supported = true,
    bool resumable = false,
    Size size = const Size(420, 900),
    double textScale = 1,
    AppThemeChoice theme = AppThemeChoice.light,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ReadingFrame(
            info: const ReadingDocumentInfo(
              title: 'Roma',
              kindLabel: 'Texto',
              kindIcon: Icons.notes_outlined,
            ),
            body: ReadableRegion(
              document: offered ?? document,
              child: const Text('Uno dos tres.'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          textToSpeechServiceProvider.overrideWithValue(
            FakeTextToSpeechService(),
          ),
          speechTrackPlayerProvider.overrideWithValue(FakeSpeechTrackPlayer()),
          narrationClockProvider.overrideWithValue(() => Duration.zero),
          documentAudioSupportedProvider.overrideWithValue(supported),
          fileStoreProvider.overrideWithValue(files),
          speechFallbackLocaleProvider.overrideWithValue('es-AR'),
          speechAudioRendererProvider.overrideWithValue(
            SpeechAudioRenderer(
              voices: () => [voices],
              workRoot: () async => Directory('sin-trabajo'),
              encoder: FakeEncoder(),
            ),
          ),
          documentAudioDownloadsProvider.overrideWith(() => downloads),
          documentAudioResumableProvider.overrideWith((ref, _) => resumable),
          audioFileSharerProvider.overrideWithValue(({
            required path,
            required fileName,
            required mimeType,
            required title,
            origin,
          }) async {
            shared.add('$path $fileName $mimeType $title');
          }),
          speechAudioApprovalProvider.overrideWithValue((_, cost) async {
            shared.add('costo ${cost.characters}');
            return approve ?? false;
          }),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: theme.theme,
          darkTheme: theme.darkTheme,
          themeMode: theme.mode,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: ReadAloudOverlay(router: router, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
  }

  setUp(() {
    files = DiskPathFileStore();
    downloads = _FakeDownloads();
    voices = FakeVoiceRenderer(prefix: 'device:');
    shared = [];
    approve = null;
  });

  /// Guarda en la bóveda un audio de [of] —lo que se descargaría hoy—.
  Future<DocumentAudio> saveAudio(
    WidgetTester tester, {
    ReadableDocument? of,
    String id = 'marco:1',
  }) async {
    final source = of ?? document;
    final plan = container
        .read(documentAudioDownloadsProvider.notifier)
        .planOf(source);
    final audio = await DocumentAudioStore(files).save(
      documentId: id,
      title: 'Roma',
      plan: plan,
      result: SpeechAudioResult(
        path: 'trabajo/audio.m4a',
        mimeType: 'audio/mp4',
        duration: const Duration(seconds: 4),
        starts: [for (var i = 0; i < plan.pieces.length; i++) Duration.zero],
      ),
      bytes: Stream.value(const [1, 2, 3]),
      now: DateTime.utc(2026, 11, 5),
    );
    container.invalidate(documentAudioProvider(id));
    await tester.pumpAndSettle();
    return audio;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> openMore(WidgetTester tester) =>
      tapKey(tester, 'reading-frame-more');

  ListTile tile(WidgetTester tester, String key) =>
      tester.widget<ListTile>(find.byKey(Key(key)));

  String? titleOf(WidgetTester tester, String key) =>
      (tile(tester, key).title! as Text).data;

  String? detailOf(WidgetTester tester, String key) =>
      (tile(tester, key).subtitle as Text?)?.data;

  String? snack(WidgetTester tester) {
    final bar = find.byType(SnackBar);
    if (bar.evaluate().isEmpty) return null;
    return tester
        .widgetList<Text>(find.descendant(of: bar, matching: find.byType(Text)))
        .first
        .data;
  }

  group('⋮', () {
    testWidgets('sin audio: «Descargar audio» arriba de todo, con la voz y lo '
        'que va a durar; «Exportar audio» apagado y nada para borrar', (
      tester,
    ) async {
      await pump(tester);
      await openMore(tester);

      expect(titleOf(tester, 'reading-more-audio-download'), es.f47P5Download);
      expect(
        detailOf(tester, 'reading-more-audio-download'),
        es.f47P5DownloadDetail(es.f47P5PhoneVoice, es.f47P5AboutMinutes(1)),
      );
      // Arriba de todo: antes que «Añadir a la cola».
      expect(
        tester
            .getTopLeft(find.byKey(const Key('reading-more-audio-download')))
            .dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('reading-more-enqueue'))).dy,
        ),
      );
      expect(tile(tester, 'reading-more-audio-export').enabled, isFalse);
      expect(detailOf(tester, 'reading-more-audio-export'), es.f47P5ExportNone);
      expect(find.byKey(const Key('reading-more-audio-delete')), findsNothing);
    });

    testWidgets('descargar: lo pide, dice que empezó, la barra dice cuánto va '
        'y al terminar ofrece escucharlo, que suena desde el audio', (
      tester,
    ) async {
      await pump(tester);
      await openMore(tester);
      await tapKey(tester, 'reading-more-audio-download');

      expect(downloads.requested, ['marco:1']);
      expect(snack(tester), es.f47P5Started('Roma'));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('reading-audio-bar-text')))
            .data,
        es.f47P5Downloading(25),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('reading-audio-bar-progress')),
            )
            .value,
        0.25,
      );
      // Mientras, ⋮ lo dice y tocarlo lo cancela.
      await openMore(tester);
      expect(
        titleOf(tester, 'reading-more-audio-download'),
        es.f47P5Downloading(25),
      );
      expect(
        detailOf(tester, 'reading-more-audio-download'),
        es.f47P5CancelDetail,
      );
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      final audio = await saveAudio(tester);
      downloads
        ..clear()
        ..pending!.complete(audio);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-audio-bar')), findsNothing);
      expect(snack(tester), es.f47P5Done('Roma'));

      await tester.tap(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(es.f47P5Listen),
        ),
      );
      await tester.pumpAndSettle();
      final reading = container.read(readAloudControllerProvider);
      expect(reading.document?.id, 'marco:1');
      expect(reading.recording?.path, '/disco/${audio.reference}');
    });

    testWidgets('con el audio de este texto: «Audio descargado», que lo hace '
        'sonar; «Exportar audio» lo pasa con la hoja de compartir', (
      tester,
    ) async {
      await pump(tester);
      final audio = await saveAudio(tester);
      await openMore(tester);

      expect(
        titleOf(tester, 'reading-more-audio-download'),
        es.f47P5Ready('0:04'),
      );
      expect(
        detailOf(tester, 'reading-more-audio-download'),
        es.f47P5ReadyDetail(es.f47P5PhoneVoice),
      );
      expect(
        detailOf(tester, 'reading-more-audio-export'),
        es.f47P5ExportDetail('M4A'),
      );
      await tapKey(tester, 'reading-more-audio-export');
      expect(shared, ['/disco/${audio.reference} Roma.m4a audio/mp4 Roma']);

      // Aunque suene otra cosa, lo hace sonar ya: no lo pone en la cola.
      await container
          .read(readAloudControllerProvider.notifier)
          .open(
            ReadableDocument(
              id: 'otro',
              title: 'Otro',
              segments: buildReadableSegments('Otra cosa.', sourceKey: 'o'),
            ),
          );
      await tester.pumpAndSettle();
      await openMore(tester);
      await tapKey(tester, 'reading-more-audio-download');
      final reading = container.read(readAloudControllerProvider);
      expect(reading.document?.id, 'marco:1');
      expect(reading.recording?.path, '/disco/${audio.reference}');
    });

    testWidgets('borrar el audio pregunta, deja de sonar si sonaba y se '
        'lleva solo el audio', (tester) async {
      await pump(tester);
      await saveAudio(tester);
      await container.read(readAloudControllerProvider.notifier).open(document);
      await tester.pumpAndSettle();
      expect(container.read(readAloudControllerProvider).recording, isNotNull);

      await openMore(tester);
      final delete = tile(tester, 'reading-more-audio-delete');
      expect((delete.title! as Text).style?.color, isNotNull);
      await tapKey(tester, 'reading-more-audio-delete');
      expect(find.byKey(const Key('document-audio-delete')), findsOneWidget);
      await tapKey(tester, 'document-audio-delete-cancel');
      expect(files.paths, hasLength(2));

      await openMore(tester);
      await tapKey(tester, 'reading-more-audio-delete');
      await tapKey(tester, 'document-audio-delete-go');
      expect(files.paths, isEmpty);
      expect(container.read(readAloudControllerProvider).document, isNull);
      expect(snack(tester), es.f47P5Deleted);

      await openMore(tester);
      expect(titleOf(tester, 'reading-more-audio-download'), es.f47P5Download);
      expect(find.byKey(const Key('reading-more-audio-delete')), findsNothing);
    });

    testWidgets('con un audio de otro texto: quedó viejo, «Generar de nuevo '
        'el audio», sin exportarlo pero con borrarlo', (tester) async {
      await pump(tester);
      await saveAudio(
        tester,
        of: ReadableDocument(
          id: 'marco:1',
          title: 'Roma',
          segments: buildReadableSegments(
            'Otro texto.\nDe antes.',
            sourceKey: 'texto:1',
          ),
        ),
      );
      await openMore(tester);

      expect(titleOf(tester, 'reading-more-audio-download'), es.f47P5Stale);
      expect(
        detailOf(tester, 'reading-more-audio-download'),
        es.f47P5StaleDetail,
      );
      expect(tile(tester, 'reading-more-audio-export').enabled, isFalse);
      expect(
        detailOf(tester, 'reading-more-audio-export'),
        es.f47P5ExportStale,
      );
      expect(
        find.byKey(const Key('reading-more-audio-delete')),
        findsOneWidget,
      );

      await tapKey(tester, 'reading-more-audio-download');
      expect(downloads.requested, ['marco:1']);
    });

    testWidgets('con algo hecho de antes, «Seguir descargando el audio»', (
      tester,
    ) async {
      await pump(tester, resumable: true);
      await openMore(tester);
      expect(
        titleOf(tester, 'reading-more-audio-download'),
        es.f47P5DownloadResume,
      );
      expect(
        detailOf(tester, 'reading-more-audio-download'),
        es.f47P5DownloadResumeDetail(
          es.f47P5PhoneVoice,
          es.f47P5AboutMinutes(1),
        ),
      );
    });

    testWidgets('con una voz que cobra, antes se pregunta: con un «no» no se '
        'pide nada', (tester) async {
      voices.prices['device:es-AR:'] = const SpeechAudioPrice(
        per1000Characters: 0.3,
        currency: 'USD',
      );
      await pump(tester);
      await openMore(tester);
      await tapKey(tester, 'reading-more-audio-download');
      expect(shared, ['costo ${'Uno dos tres.Cuatro cinco.'.length}']);
      expect(downloads.requested, isEmpty);

      approve = true;
      await openMore(tester);
      await tapKey(tester, 'reading-more-audio-download');
      expect(downloads.requested, ['marco:1']);
    });

    testWidgets('donde no se descargan audios, o lo que se lee ya suena en '
        'su propio audio, no se ofrece', (tester) async {
      await pump(tester, supported: false);
      await openMore(tester);
      expect(
        find.byKey(const Key('reading-more-audio-download')),
        findsNothing,
      );
      expect(find.byKey(const Key('reading-more-audio-export')), findsNothing);
      expect(find.byKey(const Key('reading-more-enqueue')), findsOneWidget);

      await pump(tester, offered: document.withOwnAudio());
      await openMore(tester);
      expect(
        find.byKey(const Key('reading-more-audio-download')),
        findsNothing,
      );

      await pump(
        tester,
        offered: document.withRecording(
          const RecordedSpeech(
            path: 'p.m4a',
            duration: Duration.zero,
            starts: [],
          ),
        ),
      );
      await openMore(tester);
      expect(
        find.byKey(const Key('reading-more-audio-download')),
        findsNothing,
      );
    });
  });

  group('la barra', () {
    testWidgets('en curso: «Cancelar» corta y lo dice', (tester) async {
      await pump(tester);
      downloads.put(
        DocumentAudioJob(
          document: document,
          phase: DocumentAudioJobPhase.running,
          done: 2,
          total: 4,
        ),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'reading-audio-bar-cancel');
      expect(downloads.cancelled, ['marco:1']);
      expect(snack(tester), es.f47P5Cancelled);
    });

    testWidgets('en espera, lo dice', (tester) async {
      await pump(tester);
      downloads.put(
        DocumentAudioJob(
          document: document,
          phase: DocumentAudioJobPhase.waiting,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(es.f47P5Waiting), findsOneWidget);
      expect(find.text(es.f47P5WaitingDetail), findsOneWidget);
    });

    testWidgets('si faltó una voz sin conexión, la nombra y ofrece bajarla; '
        '«Reintentar» la vuelve a pedir y ✕ la saca', (tester) async {
      final voice = OfflineVoiceCatalog.voices.first;
      await pump(tester);
      downloads.put(
        DocumentAudioJob(
          document: document,
          phase: DocumentAudioJobPhase.failed,
          failure: SpeechAudioException(
            SpeechAudioFailure.voiceMissing,
            voiceId: SpeechVoiceIds.offline(voice.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('reading-audio-bar-text')))
            .data,
        es.f47P5FailVoice(voice.name),
      );
      expect(find.byKey(const Key('reading-audio-bar-voice')), findsOneWidget);
      await openMore(tester);
      expect(titleOf(tester, 'reading-more-audio-download'), es.f47P5Failed);
      expect(
        detailOf(tester, 'reading-more-audio-download'),
        es.f47P5FailVoice(voice.name),
      );
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      await tapKey(tester, 'reading-audio-bar-dismiss');
      expect(find.byKey(const Key('reading-audio-bar')), findsNothing);

      downloads.put(
        DocumentAudioJob(
          document: document,
          phase: DocumentAudioJobPhase.failed,
          failure: const SpeechAudioException(SpeechAudioFailure.file),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(es.f47P5FailFile), findsOneWidget);
      await tapKey(tester, 'reading-audio-bar-retry');
      expect(downloads.requested, ['marco:1']);
    });

    testWidgets('los porqués, en una línea', (tester) async {
      await pump(tester);
      final l10n = es;
      expect(
        documentAudioFailureText(
          l10n,
          const SpeechAudioException(SpeechAudioFailure.engine),
          const [],
        ),
        es.f47P5FailEngine,
      );
      expect(
        documentAudioFailureText(
          l10n,
          const SpeechAudioException(
            SpeechAudioFailure.voiceMissing,
            voiceId: 'device:es-AR:',
          ),
          const [],
        ),
        es.f47P5FailVoiceAny,
      );
      expect(
        documentAudioFailureText(
          l10n,
          const SpeechAudioException(
            SpeechAudioFailure.voiceMissing,
            voiceId: 'device:es-AR:Marisa',
          ),
          const [],
        ),
        es.f47P5FailVoice('Marisa'),
      );
    });
  });

  group('cómo se ve', () {
    for (final theme in [AppThemeChoice.light, AppThemeChoice.dark]) {
      testWidgets('en 360 dp con la letra al doble, en ${theme.name}: ⋮ y la '
          'barra sin desbordes, y el lector de pantalla dice cada botón', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pump(
          tester,
          size: const Size(360, 780),
          textScale: 2,
          theme: theme,
        );
        await saveAudio(tester);
        await openMore(tester);
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel(RegExp(es.f47P5Export)), findsOneWidget);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();

        downloads.put(
          DocumentAudioJob(
            document: document,
            phase: DocumentAudioJobPhase.running,
            done: 1,
            total: 3,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSemantics(
            find.byKey(const Key('reading-audio-bar-cancel')),
          ),
          matchesSemantics(
            label: es.f47P5Cancel,
            isButton: true,
            hasTapAction: true,
            isEnabled: true,
            hasEnabledState: true,
            isFocusable: true,
            hasFocusAction: true,
          ),
        );

        downloads.put(
          DocumentAudioJob(
            document: document,
            phase: DocumentAudioJobPhase.failed,
            failure: const SpeechAudioException(SpeechAudioFailure.engine),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip(es.f47P5Dismiss), findsOneWidget);
        semantics.dispose();
      });
    }
  });
}
