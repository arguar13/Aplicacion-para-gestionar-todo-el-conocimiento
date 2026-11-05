import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_progress.dart';
import 'package:sinapsis/features/creations/podcast/podcast_kind.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_listening.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_speech_track_player.dart';
import '../../../../support/processed_rows.dart';
import '../../../narration/data/audio/speech_audio_fakes.dart';
import '../../presentation/repasar_harness.dart';

/// F47, paso 6: el podcast guardado en «Lo creado» —su fila, «Hecho con IA»,
/// el botón de escuchar con su estado y el guion como transcripción, con
/// cada cita tocable que lleva al pasaje—, en la app de verdad con su router.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;

  const sourceText =
      'Capítulo 14. Y el mar se abrió ante ellos, y los hijos de Israel '
      'entraron por en medio del mar, en seco.';
  const quote = 'el mar se abrió ante ellos';

  const podcast = Podcast(
    title: 'El mar abierto',
    format: PodcastFormat.conversation,
    length: PodcastLength.short,
    requestedWords: 450,
    targetWords: 450,
    segments: [
      PodcastSegment(
        speaker: PodcastSpeaker.a,
        text: '¿Qué pasó cuando llegaron al mar?',
        kind: PodcastSegmentKind.link,
        pauseAfter: kPodcastTurnPause,
      ),
      PodcastSegment(
        speaker: PodcastSpeaker.b,
        text: 'El mar se abrió y el pueblo cruzó en seco.',
        kind: PodcastSegmentKind.data,
        pauseAfter: kPodcastBreath,
        citations: [
          PodcastCitation(
            quote: quote,
            documentId: 'p-1',
            documentTitle: 'Éxodo — Comentario',
          ),
        ],
      ),
      PodcastSegment(
        speaker: PodcastSpeaker.b,
        text: 'Lo cuenta el capítulo catorce.',
        kind: PodcastSegmentKind.data,
        citations: [
          PodcastCitation(
            quote: 'una frase que la fuente ya no tiene',
            documentId: 'p-1',
            documentTitle: 'Éxodo — Comentario',
          ),
        ],
      ),
    ],
  );

  late FakeSpeechTrackPlayer track;
  late FakeVoiceRenderer device;

  /// Dónde está, en el teléfono, cada audio de la bóveda: el almacén de
  /// mentira no tiene disco.
  late Map<String, String> onDisk;
  late bool renderers;

  Future<void> create() async {
    track = FakeSpeechTrackPlayer();
    device = FakeVoiceRenderer(prefix: 'device:');
    harness = await RepasarHarness.create(
      specs: [podcastKindSpec()],
      overrides: [
        speechTrackPlayerProvider.overrideWithValue(track),
        speechVoiceRenderersProvider.overrideWith(
          (ref) => renderers ? [device] : const [],
        ),
        podcastAudioPathProvider.overrideWith(
          (ref, reference) async => onDisk[reference],
        ),
      ],
    );
  }

  setUp(() async {
    onDisk = {};
    renderers = true;
    await create();
  });

  /// La fuente src-1 con [sourceText], para que la cita tenga a dónde ir.
  Future<void> saveSource() async {
    final now = DateTime(2026, 10, 30);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'src-1',
            title: 'Éxodo',
            source: Source(
              id: 'src-1',
              kind: SourceKind.webPage,
              capturedAt: now,
              url: 'https://e.org/exodo',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-src-1',
                itemId: 'src-1',
                kind: RenditionKind.markdown,
                content: sourceText,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
  }

  /// Un podcast listo sobre p-1, escrito por «Gemini»; con [sourceItemId],
  /// la fuente que guardó [saveSource].
  Future<StudyCreation> ready({
    Podcast content = podcast,
    String? raw,
    String? sourceItemId,
  }) async {
    await insertProcessedRows(
      harness.library.database,
      id: 'p-1',
      title: 'Éxodo — Comentario',
      sourceItemId: sourceItemId,
      parts: const {
        ProcessedSection.text: [sourceText],
      },
    );
    final queued = await harness.creation(
      StudyCreationKind.podcast,
      scope: const CreationScope.document('p-1'),
      sources: const ['p-1'],
      status: CreationStatus.generating,
    );
    await harness.creations.complete(
      queued.id,
      title: content.title,
      content: raw ?? PodcastJson.encodeString(content),
    );
    return queued;
  }

  Future<void> open(
    WidgetTester tester,
    StudyCreation creation, {
    Size size = const Size(420, 900),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) => harness.openRepasar(
    tester,
    size: size,
    theme: theme,
    textScale: textScale,
    location: '/creations/${creation.id}',
  );

  /// El audio de [content] con las voces de fábrica, en [reference].
  PodcastAudio audioOf(
    Podcast content, {
    String reference = 'originales/x/audio/podcast-ab.m4a',
    String? fingerprint,
  }) => PodcastAudio(
    reference: reference,
    mimeType: 'audio/mp4',
    fingerprint:
        fingerprint ??
        podcastAudioFingerprint(
          podcastSpeechPieces(
            content,
            PodcastCast.of(const {}, content.format),
            'es',
          ),
        ),
    duration: const Duration(seconds: 9),
    starts: const [Duration.zero, Duration(seconds: 3), Duration(seconds: 6)],
  );

  FilledButton listenButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('podcast-listen')));

  testWidgets('arriba, de qué es y «Hecho con IA» con su modelo; sin audio, '
      'el botón de escuchar apagado, que dice por qué, y «Generar el '
      'audio»', (tester) async {
    final creation = await ready();
    await open(tester, creation);

    expect(find.text('El mar abierto'), findsWidgets);
    expect(
      find.text('${es.f47P6FormatConversation} · ~1 min · 2 voces'),
      findsOneWidget,
    );
    expect(find.text(es.f47P6MadeWithAiModel('Gemini')), findsOneWidget);
    expect(listenButton(tester).onPressed, isNull);
    expect(find.text(es.f47P6bAudioNone), findsOneWidget);
    expect(find.text(es.f47P6bGenerateAudio), findsOneWidget);
    expect(find.text(es.f47P6Transcript), findsOneWidget);
  });

  group('el audio (F47, paso 6b)', () {
    testWidgets('con el audio de este guion en el teléfono, «Escuchar» lo '
        'abre en el reproductor anclado; después pausa y sigue', (
      tester,
    ) async {
      final audio = audioOf(podcast);
      onDisk[audio.reference] = '/telefono/podcast.m4a';
      final creation = await ready(content: podcast.withAudio(audio));
      await open(tester, creation);

      expect(find.text(es.f47P6bAudioReady('0:09')), findsOneWidget);
      expect(find.text(es.f47P6bGenerateAudio), findsNothing);
      await tester.tap(find.byKey(const Key('podcast-listen')));
      await tester.pumpAndSettle();

      expect(track.opened, '/telefono/podcast.m4a');
      final reading = harness.container.read(readAloudControllerProvider);
      expect(reading.document!.id, podcastReadableId(creation.id));
      expect(reading.recording!.starts, audio.starts);
      // La tarjeta y «Seguir escuchando» vuelven a este visor.
      expect(reading.document!.location, '/creations/${creation.id}');
      expect(reading.document!.segments.map((s) => s.spoken), [
        for (final segment in podcast.segments) segment.text,
      ]);
      expect(find.text(es.f47P6bPause), findsOneWidget);

      await tester.tap(find.byKey(const Key('podcast-listen')));
      await tester.pumpAndSettle();
      expect(track.playing, isFalse);
      expect(find.text(es.f47P6bResume), findsOneWidget);

      await tester.tap(find.byKey(const Key('podcast-listen')));
      await tester.pumpAndSettle();
      expect(track.playing, isTrue);
    });

    testWidgets('la transcripción sigue lo que suena: el tramo, resaltado', (
      tester,
    ) async {
      final audio = audioOf(podcast);
      onDisk[audio.reference] = '/telefono/podcast.m4a';
      final creation = await ready(content: podcast.withAudio(audio));
      await open(tester, creation);
      await tester.tap(find.byKey(const Key('podcast-listen')));
      await tester.pumpAndSettle();

      Finder speaking(int index) => find.descendant(
        of: find.byKey(ValueKey('podcast-segment-$index')),
        matching: find.byKey(const Key('podcast-segment-speaking')),
      );
      expect(speaking(0), findsOneWidget);
      expect(speaking(1), findsNothing);

      track.advance(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(speaking(0), findsNothing);
      expect(speaking(1), findsOneWidget);
    });

    testWidgets('un audio de otra versión del guion no se finge: se dice, '
        'no se escucha, y se ofrece generarlo de nuevo', (tester) async {
      final audio = audioOf(podcast, fingerprint: 'de-otro-guion');
      onDisk[audio.reference] = '/telefono/podcast.m4a';
      final creation = await ready(content: podcast.withAudio(audio));
      await open(tester, creation);

      expect(listenButton(tester).onPressed, isNull);
      expect(find.text(es.f47P6bAudioStale), findsOneWidget);
      expect(find.text(es.f47P6bRegenerateAudio), findsOneWidget);
    });

    testWidgets('si el archivo no está en el teléfono, se dice y se ofrece '
        'generarlo', (tester) async {
      final creation = await ready(
        content: podcast.withAudio(audioOf(podcast)),
      );
      await open(tester, creation);

      expect(listenButton(tester).onPressed, isNull);
      expect(find.text(es.f47P6bAudioMissingFile), findsOneWidget);
      expect(find.text(es.f47P6bGenerateAudio), findsOneWidget);
    });

    for (final (name, issue, text) in [
      (
        'la voz que falta, con su nombre',
        const PodcastAudioIssue(
          PodcastAudioProblem.voiceMissing,
          voiceId: 'offline:vits-piper-es_AR-daniela-high#0',
        ),
        (AppLocalizationsEs l) => l.f47P6bAudioVoiceMissing('Daniela'),
      ),
      (
        'una voz que falta, sin saber cuál',
        const PodcastAudioIssue(PodcastAudioProblem.voiceMissing),
        (AppLocalizationsEs l) => l.f47P6bAudioVoiceMissingAny,
      ),
      (
        'el motor',
        const PodcastAudioIssue(PodcastAudioProblem.engine),
        (AppLocalizationsEs l) => l.f47P6bAudioEngine,
      ),
      (
        'el disco',
        const PodcastAudioIssue(PodcastAudioProblem.file),
        (AppLocalizationsEs l) => l.f47P6bAudioFile,
      ),
    ]) {
      testWidgets('si no se pudo generar, dice por qué: $name', (tester) async {
        final creation = await ready(content: podcast.withAudioIssue(issue));
        await open(tester, creation);
        expect(find.text(text(es)), findsOneWidget);
        expect(find.text(es.f47P6bGenerateAudio), findsOneWidget);
        expect(
          find.byKey(const Key('podcast-audio-download')),
          issue.voiceId == null ? findsNothing : findsOneWidget,
        );
      });
    }

    testWidgets('donde nadie sabe hacer las voces, solo se dice', (
      tester,
    ) async {
      renderers = false;
      await create();
      final creation = await ready();
      await open(tester, creation);
      expect(find.text(es.f47P6bNoAudioHere), findsOneWidget);
      expect(find.text(es.f47P6bGenerateAudio), findsNothing);
    });

    testWidgets('«Generar el audio» deja el guion como lo que falta y la '
        'vuelve a la cola con «ahora», conservando el título', (tester) async {
      final creation = await ready();
      await open(tester, creation);
      await tester.tap(find.text(es.f47P6bGenerateAudio));
      await tester.pumpAndSettle();

      expect(harness.queue.calls.last.action, 'retry');
      expect(harness.queue.calls.last.detail, isTrue);
      final saved = PodcastProgress.decode(
        (await harness.creations.checkpoint(
          creation.id,
        )).getRight().toNullable(),
      );
      expect(saved, isA<PodcastVoiceProgress>());
      final voice = saved! as PodcastVoiceProgress;
      expect(voice.keepTitle, isTrue);
      expect(voice.podcast, podcast);
      expect(find.text(es.f47P6bAudioQueued), findsOneWidget);
    });

    testWidgets('con una voz que cobra, antes se dice el costo; sin aceptar, '
        'no se pide', (tester) async {
      device.prices['device:es:'] = const SpeechAudioPrice(
        per1000Characters: 1,
        currency: 'USD',
      );
      final creation = await ready();
      await open(tester, creation);
      await tester.tap(find.text(es.f47P6bGenerateAudio));
      await tester.pumpAndSettle();

      final characters = podcast.segments.fold(0, (n, s) => n + s.text.length);
      expect(find.textContaining('$characters'), findsOneWidget);
      await tester.tap(find.byKey(const Key('speech-audio-cost-cancel')));
      await tester.pumpAndSettle();
      expect(harness.queue.calls.where((c) => c.action == 'retry'), isEmpty);

      await tester.tap(find.text(es.f47P6bGenerateAudio));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speech-audio-cost-go')));
      await tester.pumpAndSettle();
      expect(harness.queue.calls.last.action, 'retry');
    });
  });

  testWidgets('la transcripción: cada tramo, y quién habla cuando cambia', (
    tester,
  ) async {
    final creation = await ready();
    await open(tester, creation);

    for (final segment in podcast.segments) {
      expect(find.text(segment.text), findsOneWidget);
    }
    // La Voz 2 dice dos tramos seguidos: su nombre va una sola vez.
    expect(find.text(es.f47P6SpeakerA), findsOneWidget);
    expect(find.text(es.f47P6SpeakerB), findsOneWidget);
    expect(find.byKey(const ValueKey('podcast-citation-1-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('podcast-citation-0-0')), findsNothing);
  });

  testWidgets('tocar una cita abre la lectura de la fuente parada en el '
      'pasaje', (tester) async {
    await saveSource();
    final creation = await ready(sourceItemId: 'src-1');
    await open(tester, creation);

    await tester.tap(find.byKey(const ValueKey('podcast-citation-1-0')));
    await tester.pumpAndSettle();

    final start = sourceText.indexOf('el mar se abrió ante ellos');
    final reading = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
    expect(reading.itemId, 'src-1');
    expect(reading.jump, (start: start, end: start + quote.length));
  });

  testWidgets('una cita que ya no está en la fuente abre el documento y lo '
      'dice', (tester) async {
    await saveSource();
    final creation = await ready(sourceItemId: 'src-1');
    await open(tester, creation);

    final citation = find.byKey(const ValueKey('podcast-citation-2-0'));
    await tester.ensureVisible(citation);
    await tester.pumpAndSettle();
    await tester.tap(citation);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ProcessedDocumentScreen>(find.byType(ProcessedDocumentScreen))
          .documentId,
      'p-1',
    );
    expect(find.text(es.f43MindPassageMissing), findsOneWidget);
  });

  testWidgets('lo que quitó la comprobación se cuenta, y abierto se ve '
      'tachado con su porqué; si el material no daba, también se dice', (
    tester,
  ) async {
    const checked = Podcast(
      title: 'Corto',
      format: PodcastFormat.brief,
      length: PodcastLength.long,
      requestedWords: 2250,
      targetWords: 300,
      segments: [
        PodcastSegment(
          speaker: PodcastSpeaker.a,
          text: 'El mar se abrió.',
          kind: PodcastSegmentKind.data,
          citations: [PodcastCitation(quote: quote, documentId: 'p-1')],
        ),
      ],
      discarded: [
        PodcastDiscard(
          reason: PodcastDiscardReason.numberNotInMaterial,
          text: 'Cruzaron 600.000 personas.',
        ),
        PodcastDiscard(
          reason: PodcastDiscardReason.noCitation,
          text: 'Fue el mayor milagro.',
        ),
      ],
    );
    final creation = await ready(content: checked);
    await open(tester, creation);

    expect(find.text(es.f47P6Shortened(2, 15)), findsOneWidget);
    expect(find.text(es.f47P6Discarded(2)), findsOneWidget);
    expect(find.text('Cruzaron 600.000 personas.'), findsNothing);
    // Una sola voz: la transcripción no nombra a nadie.
    expect(find.text(es.f47P6SpeakerA), findsNothing);

    await tester.tap(find.text(es.f47P6Discarded(2)));
    await tester.pumpAndSettle();
    final struck = tester.widget<Text>(find.text('Cruzaron 600.000 personas.'));
    expect(struck.style?.decoration, TextDecoration.lineThrough);
    expect(find.text(es.f47P6DiscardNumber), findsOneWidget);
    expect(find.text(es.f47P6DiscardNoCitation), findsOneWidget);
  });

  testWidgets('lo guardado que no se entiende lo dice, sin romperse', (
    tester,
  ) async {
    final creation = await ready(raw: '{"segments": []}');
    await open(tester, creation);

    expect(find.text(es.f47P6Unreadable), findsOneWidget);
  });

  testWidgets('en «Lo creado», su fila con su nombre; tocarla lo abre', (
    tester,
  ) async {
    final creation = await ready();
    harness.container.read(repasarScopeProvider.notifier).state =
        const CreationScope.document('p-1');
    await harness.openRepasar(tester, size: const Size(420, 2400));
    final row = find.byKey(ValueKey('creation-tile-${creation.id}'));
    await tester.scrollUntilVisible(
      row,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('review-entry')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    // La fila dice de qué tipo es y el título que le puso la IA.
    expect(
      find.descendant(of: row, matching: find.textContaining('El mar abierto')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining(es.f47P6KindPodcast),
      ),
      findsWidgets,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('podcast-viewer')), findsOneWidget);
  });

  for (final theme in [AppThemeChoice.light, AppThemeChoice.dark]) {
    testWidgets('a 360 dp con la letra al doble, en ${theme.name}, sin '
        'desbordes y con el lector de pantalla', (tester) async {
      final handle = tester.ensureSemantics();
      final creation = await ready();
      await open(
        tester,
        creation,
        size: const Size(360, 780),
        theme: theme,
        textScale: 2,
      );
      final citation = find.byKey(const ValueKey('podcast-citation-1-0'));
      // La lista se arma de a lo que se ve: se baja hasta la cita.
      await tester.scrollUntilVisible(
        citation,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('podcast-viewer')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getRect(citation).right, lessThanOrEqualTo(360));
      // El aviso del audio y su botón, sin cortarse.
      for (final key in ['podcast-audio-note', 'podcast-audio-generate']) {
        expect(
          tester.getRect(find.byKey(Key(key))).right,
          lessThanOrEqualTo(360),
          reason: key,
        );
      }
      expect(find.bySemanticsLabel(RegExp(es.f47P6bAudioNone)), findsOneWidget);
      // Cada tramo dice quién habla; cada cita, de dónde es y qué hace.
      expect(
        find.bySemanticsLabel(
          '${es.f47P6SpeakerB}: El mar se abrió y el pueblo cruzó en seco.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(citation),
        isSemantics(
          label: es.f47P6CitationSemantics('Éxodo — Comentario', quote),
          hint: es.f47P6CitationHint,
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  }
}
