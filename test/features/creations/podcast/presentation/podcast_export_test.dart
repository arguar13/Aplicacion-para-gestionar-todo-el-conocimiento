import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/podcast_kind.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_export.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/in_memory_file_store.dart';

const _podcast = Podcast(
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
      text: ' El mar se abrió y el pueblo cruzó en seco. ',
      kind: PodcastSegmentKind.data,
      citations: [
        PodcastCitation(
          quote: 'el mar se abrió ante ellos',
          documentId: 'p-1',
          documentTitle: 'Éxodo — Comentario',
        ),
        PodcastCitation(quote: 'en medio del mar, en seco'),
      ],
    ),
  ],
);

/// F47, paso 5: exportar un podcast —su audio, o su guion como texto—, lo
/// que pasan «Compartir» y «Descargar» de su menú.
void main() {
  final es = AppLocalizationsEs();

  test('el podcast exporta: su tipo tiene con qué', () {
    expect(podcastKindSpec().exporter, isNotNull);
  });

  test('el guion como texto: el título, «Hecho con IA», quién dice cada '
      'cosa y sus citas, con su documento si se sabe', () {
    final text = podcastScriptText(
      _podcast,
      title: 'El mar abierto',
      madeWith: es.f47P6MadeWithAiModel('Gemma'),
      roleOf: (speaker) => speaker == PodcastSpeaker.a ? 'Conduce' : 'Explica',
      quote: es.f47P5ScriptQuote,
      quoteFrom: es.f47P5ScriptQuoteFrom,
    );
    expect(
      text,
      'El mar abierto\n'
      'Hecho con IA · Gemma\n'
      '\n'
      'Conduce: ¿Qué pasó cuando llegaron al mar?\n'
      '\n'
      'Explica: El mar se abrió y el pueblo cruzó en seco.\n'
      '    «el mar se abrió ante ellos» — Éxodo — Comentario\n'
      '    «en medio del mar, en seco»\n',
    );
  });

  group('exportar', () {
    late InMemoryFileStore files;
    CreationExportFile? exported;
    var finished = false;

    StudyCreation creation(Podcast podcast, {String? model = 'Gemma'}) =>
        StudyCreation(
          id: 'c1',
          kind: StudyCreationKind.podcast,
          title: 'El mar abierto',
          scope: const CreationScope.allProcessed(),
          languageCode: 'es',
          status: CreationStatus.ready,
          content: PodcastJson.encodeString(podcast),
          modelName: model,
          createdAt: DateTime(2026, 11, 5),
          updatedAt: DateTime(2026, 11, 5),
        );

    PodcastAudio audioOf({String? fingerprint}) => PodcastAudio(
      reference: 'originales/c1/audio/podcast.m4a',
      mimeType: 'audio/mp4',
      fingerprint:
          fingerprint ??
          podcastAudioFingerprint(
            podcastSpeechPieces(
              _podcast,
              PodcastCast.of(const {}, _podcast.format),
              'es',
            ),
          ),
      duration: const Duration(minutes: 3, seconds: 5),
      starts: const [Duration.zero, Duration(seconds: 4)],
    );

    Future<void> run(WidgetTester tester, StudyCreation creation) async {
      exported = null;
      finished = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [fileStoreProvider.overrideWithValue(files)],
          child: MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  exported = await exportPodcast(context, ref, creation);
                  finished = true;
                },
                child: const Text('Exportar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Exportar'));
      await tester.pumpAndSettle();
    }

    setUp(() async {
      files = InMemoryFileStore();
      await files.saveStream(
        bytes: Stream.value(const [7, 7, 7]),
        suggestedName: 'podcast.m4a',
        id: 'c1',
        folder: 'audio',
      );
    });

    testWidgets('sin audio, el guion, sin preguntar', (tester) async {
      await run(tester, creation(_podcast));

      expect(find.byType(BottomSheet), findsNothing);
      expect(finished, isTrue);
      expect(exported!.fileName, 'El mar abierto.txt');
      expect(exported!.mimeType, 'text/plain');
      final text = utf8.decode(exported!.bytes);
      expect(text, startsWith('El mar abierto\nHecho con IA · Gemma\n'));
      expect(text, contains('«el mar se abrió ante ellos» — Éxodo'));
    });

    testWidgets('con el audio de este guion, pregunta: el audio, tal cual '
        'se generó, o el guion', (tester) async {
      final ready = creation(_podcast.withAudio(audioOf()), model: null);
      await run(tester, ready);

      expect(find.text(es.f47P5PodcastExportTitle), findsOneWidget);
      expect(
        find.text(es.f47P5PodcastExportAudioHint('M4A', '3:05')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('study-export-PodcastExportChoice.audio')),
      );
      await tester.pumpAndSettle();
      expect(exported!.fileName, 'El mar abierto.m4a');
      expect(exported!.mimeType, 'audio/mp4');
      expect(exported!.bytes, [7, 7, 7]);

      await run(tester, ready);
      await tester.tap(
        find.byKey(const Key('study-export-PodcastExportChoice.script')),
      );
      await tester.pumpAndSettle();
      expect(exported!.fileName, 'El mar abierto.txt');
      expect(
        utf8.decode(exported!.bytes),
        startsWith('El mar abierto\n${es.f47P6MadeWithAi}\n'),
      );

      // Cerrar la pregunta no exporta nada.
      await run(tester, ready);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(exported, isNull);
    });

    testWidgets('con un audio de otra versión del guion, o que no está en el '
        'teléfono, el guion: un audio viejo no pasa por el de ahora', (
      tester,
    ) async {
      await run(
        tester,
        creation(_podcast.withAudio(audioOf(fingerprint: 'otra'))),
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(exported!.fileName, 'El mar abierto.txt');

      await files.delete('originales/c1/audio/podcast.m4a');
      await run(tester, creation(_podcast.withAudio(audioOf())));
      expect(find.byType(BottomSheet), findsNothing);
      expect(exported!.fileName, 'El mar abierto.txt');
    });
  });
}
