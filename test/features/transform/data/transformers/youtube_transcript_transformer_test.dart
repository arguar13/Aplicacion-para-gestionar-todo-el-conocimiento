import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/transcript_timestamps.dart';
import 'package:sinapsis/features/transform/data/transformers/youtube_transcript_transformer.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/services/video_text_notices.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

import '../../../../support/fake_audio_transcriber.dart';
import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/transform_test_doubles.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);
  late FakeIdGenerator ids;

  setUp(() {
    ids = FakeIdGenerator();
  });

  KnowledgeItem videoItem({
    String url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    List<Rendition> renditions = const [],
    SourceKind kind = SourceKind.youtube,
    String? language,
  }) => KnowledgeItem(
    id: 'item-1',
    // El título provisional que puso la captura: el identificador del video,
    // porque sin red no se sabía cómo se llamaba.
    title: 'youtu.be/dQw4w9WgXcQ',
    source: Source(
      id: 'src-1',
      kind: kind,
      capturedAt: now,
      url: url,
      language: language,
    ),
    processingState: ProcessingState.pending,
    createdAt: now,
    updatedAt: now,
    renditions: renditions,
  );

  YouTubeTranscriptTransformer build(FakeYouTubeClient client) =>
      YouTubeTranscriptTransformer(client: client, ids: ids, clock: () => now);

  group('a qué se aplica', () {
    test('a un video de YouTube sin contenido todavía', () {
      expect(build(FakeYouTubeClient()).canTransform(videoItem()), isTrue);
    });

    test('NO a algo que no es de YouTube', () {
      expect(
        build(
          FakeYouTubeClient(),
        ).canTransform(videoItem(kind: SourceKind.webPage)),
        isFalse,
      );
    });

    test('NO a un video que ya tiene su transcripción', () {
      // Sin esta comprobación, cada pasada de la cola la bajaría de nuevo y
      // el elemento terminaría con la misma transcripción repetida.
      final withContent = videoItem(
        renditions: [
          Rendition.text(
            id: 'r1',
            itemId: 'item-1',
            kind: RenditionKind.markdown,
            content: 'ya estaba',
            isPrimary: true,
            createdAt: now,
          ),
        ],
      );

      expect(build(FakeYouTubeClient()).canTransform(withContent), isFalse);
    });

    test('NO a una dirección de YouTube que no apunta a un video', () {
      expect(
        build(
          FakeYouTubeClient(),
        ).canTransform(videoItem(url: 'https://www.youtube.com/@uncanal')),
        isFalse,
      );
    });
  });

  group('lo que trae', () {
    test('reemplaza el título provisional por el de verdad', () async {
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(
          title: 'La estructura de las revoluciones científicas',
          authorName: 'Canal de Filosofía',
          authorChannelUrl: 'https://www.youtube.com/channel/UC123',
        ),
      );

      final result = await build(client).transform(videoItem());

      expect(result.title, 'La estructura de las revoluciones científicas');
      expect(result.subtitle, 'Canal de Filosofía');
    });

    test('completa la procedencia con el autor y su canal', () async {
      final client = FakeYouTubeClient(
        data: YouTubeVideoData(
          title: 'Un video',
          authorName: 'Ana Ejemplo',
          authorChannelUrl: 'https://www.youtube.com/channel/UC123',
          publishedAt: DateTime(2019, 3, 15),
        ),
      );

      final result = await build(client).transform(videoItem());

      expect(result.source.authorName, 'Ana Ejemplo');
      expect(result.source.authorUrl, 'https://www.youtube.com/channel/UC123');
      expect(result.source.publishedAt, DateTime(2019, 3, 15));
      // Y no pierde el enlace al video.
      expect(result.source.url, contains('dQw4w9WgXcQ'));
    });

    test('guarda la transcripción con sus marcas de tiempo', () async {
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(
          title: 'Un video',
          transcript: [
            TranscriptLine(offset: Duration.zero, text: 'Primera frase'),
            TranscriptLine(
              offset: Duration(minutes: 1, seconds: 5),
              text: 'Segunda frase',
            ),
          ],
        ),
      );

      final result = await build(client).transform(videoItem());
      final content = result.renditions.single.searchableText!;

      expect(content, contains('[0:00] Primera frase'));
      expect(content, contains('[1:05] Segunda frase'));
      // Lo dicho, tal cual: no es Markdown (F22).
      expect(result.renditions.single.kind, RenditionKind.plainText);
    });

    test('le pide al cliente el identificador correcto del video', () async {
      final client = FakeYouTubeClient();

      await build(
        client,
      ).transform(videoItem(url: 'https://youtu.be/abcdefghijk'));

      expect(client.requested, ['abcdefghijk']);
    });

    test('guarda en qué idioma están los subtítulos, y sin un idioma '
        'elegido no le pide ninguno: manda el que se habla (F22)', () async {
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(
          title: 'A talk',
          transcript: [TranscriptLine(offset: Duration.zero, text: 'Hello')],
          transcriptLanguage: 'en',
        ),
      );

      final result = await build(client).transform(videoItem());

      expect(result.source.language, 'en');
      expect(client.languagesRequested.single, isEmpty);
    });

    test('el idioma que eligió el usuario se le pide primero', () async {
      final client = FakeYouTubeClient();

      await build(client).transform(videoItem(language: 'pt'));

      expect(client.languagesRequested.single, ['pt']);
    });
  });

  group('videos sin subtítulos', () {
    test('se transcribe su audio, en el idioma del video, y no queda '
        'ningún archivo temporal (F22)', () async {
      final temp = Directory.systemTemp.createTempSync('yt_audio');
      addTearDown(() => temp.deleteSync(recursive: true));
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(
          title: 'Una prédica sin subtítulos',
          description: 'La descripción, que ya no es lo único.',
        ),
      );
      final transcriber = FakeAudioTranscriber(
        text: '[0:00] Lo que se dijo\n[0:14] palabra por palabra',
      );

      final result = await YouTubeTranscriptTransformer(
        client: client,
        ids: ids,
        clock: () => now,
        transcriber: transcriber,
        temporaryDirectory: () async => temp,
      ).transform(videoItem(language: 'en'));

      expect(client.audioRequested, ['dQw4w9WgXcQ']);
      expect(transcriber.requested.single, startsWith(temp.path));
      expect(transcriber.languages, ['en']);
      expect(
        result.renditions.single.searchableText,
        '[0:00] Lo que se dijo\n[0:14] palabra por palabra',
      );
      expect(result.renditions.single.kind, RenditionKind.plainText);
      expect(temp.listSync(), isEmpty);
    });

    group('en qué idioma se transcribe el audio', () {
      Future<List<String>> transcribedLanguages({
        String? spoken,
        String? chosen,
      }) async {
        final temp = Directory.systemTemp.createTempSync('yt_audio');
        addTearDown(() => temp.deleteSync(recursive: true));
        final transcriber = FakeAudioTranscriber(text: '[0:00] Hola');

        await YouTubeTranscriptTransformer(
          client: FakeYouTubeClient(
            // Sin subtítulos de fiar: aunque el video tenga en árabe, el
            // cliente no los baja (F22).
            data: YouTubeVideoData(title: 'Un video', spokenLanguage: spoken),
          ),
          ids: ids,
          clock: () => now,
          transcriber: transcriber,
          temporaryDirectory: () async => temp,
        ).transform(videoItem(language: chosen));
        return transcriber.languages;
      }

      test('el que se sabe que se habla en el video', () async {
        expect(await transcribedLanguages(spoken: 'en'), ['en']);
      });

      test('el que eligió el usuario pasa adelante', () async {
        expect(await transcribedLanguages(spoken: 'en', chosen: 'pt'), ['pt']);
      });

      test('sin saber qué se habla, el de quien usa la app', () async {
        expect(await transcribedLanguages(), ['es']);
      });

      test('y el idioma queda guardado: el transcrito, no el de unos '
          'subtítulos que no se bajaron', () async {
        final temp = Directory.systemTemp.createTempSync('yt_audio');
        addTearDown(() => temp.deleteSync(recursive: true));

        final result = await YouTubeTranscriptTransformer(
          client: FakeYouTubeClient(
            data: const YouTubeVideoData(
              title: 'A talk about the universe',
              spokenLanguage: 'en',
            ),
          ),
          ids: ids,
          clock: () => now,
          transcriber: FakeAudioTranscriber(text: '[0:00] Hola'),
          temporaryDirectory: () async => temp,
        ).transform(videoItem());

        expect(result.source.language, 'en');
      });
    });

    test('el audio bajado para transcribir queda como el audio del video, '
        'para escucharlo debajo de su vista previa sin bajarlo de nuevo '
        '(F24)', () async {
      final temp = Directory.systemTemp.createTempSync('yt_audio');
      addTearDown(() => temp.deleteSync(recursive: true));
      final files = InMemoryFileStore();
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(title: 'Una prédica sin subtítulos'),
      );

      final result = await YouTubeTranscriptTransformer(
        client: client,
        ids: ids,
        clock: () => now,
        transcriber: FakeAudioTranscriber(text: '[0:00] Lo que se dijo'),
        temporaryDirectory: () async => temp,
        files: files,
      ).transform(videoItem());

      expect(result.source.originalFilePath, isNotNull);
      expect(files.paths, [result.source.originalFilePath]);
      expect(client.audioRequested, hasLength(1));
      // Y ningún temporal queda tirado.
      expect(temp.listSync(), isEmpty);
    });

    test('aunque no se haya dicho nada —solo música—, el audio se conserva: '
        'es lo que se escucha (F24)', () async {
      final temp = Directory.systemTemp.createTempSync('yt_audio');
      addTearDown(() => temp.deleteSync(recursive: true));
      final files = InMemoryFileStore();

      final result = await YouTubeTranscriptTransformer(
        client: FakeYouTubeClient(
          data: const YouTubeVideoData(title: 'Solo música'),
        ),
        ids: ids,
        clock: () => now,
        transcriber: FakeAudioTranscriber(),
        temporaryDirectory: () async => temp,
        files: files,
      ).transform(videoItem());

      expect(result.source.originalFilePath, isNotNull);
      expect(files.paths, hasLength(1));
    });

    test('con subtítulos, el audio no se baja', () async {
      final temp = Directory.systemTemp.createTempSync('yt_audio');
      addTearDown(() => temp.deleteSync(recursive: true));
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(
          title: 'Con subtítulos',
          transcript: [TranscriptLine(offset: Duration.zero, text: 'Hola')],
        ),
      );
      final transcriber = FakeAudioTranscriber(text: 'no');

      await YouTubeTranscriptTransformer(
        client: client,
        ids: ids,
        clock: () => now,
        transcriber: transcriber,
        temporaryDirectory: () async => temp,
      ).transform(videoItem());

      expect(client.audioRequested, isEmpty);
      expect(transcriber.requested, isEmpty);
    });

    test('si la transcripción falla, el audio bajado queda para retomar sin '
        'volver a bajarlo', () async {
      final temp = Directory.systemTemp.createTempSync('yt_audio');
      addTearDown(() => temp.deleteSync(recursive: true));
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(title: 'Sin subtítulos'),
      );
      final transcriber = FakeAudioTranscriber()..error = Exception('corte');
      final transformer = YouTubeTranscriptTransformer(
        client: client,
        ids: ids,
        clock: () => now,
        transcriber: transcriber,
        temporaryDirectory: () async => temp,
      );

      await expectLater(
        transformer.transform(videoItem()),
        throwsA(isA<Exception>()),
      );
      transcriber
        ..error = null
        ..text = 'Retomado';
      final result = await transformer.transform(videoItem());

      expect(client.audioRequested, hasLength(1));
      expect(result.renditions.single.searchableText, 'Retomado');
      expect(temp.listSync(), isEmpty);
    });

    test('sin con qué transcribir, guarda la descripción en vez de dejar el '
        'elemento vacío', () async {
      // Sin transcriptor —en la web, o acá—: la descripción es contenido
      // real y buscable.
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(
          title: 'Un video casero',
          description: 'En este video explico cómo funciona el experimento.',
        ),
      );

      final result = await build(client).transform(videoItem());

      expect(result.renditions, hasLength(1));
      expect(
        result.renditions.single.searchableText,
        contains('el experimento'),
      );
    });

    test('sin subtítulos ni descripción, queda sin contenido pero con el '
        'título y el autor ya corregidos', () async {
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(
          title: 'Un video mudo',
          authorName: 'Alguien',
        ),
      );

      final result = await build(client).transform(videoItem());

      expect(result.renditions, isEmpty);
      expect(result.title, 'Un video mudo');
      expect(result.source.authorName, 'Alguien');
    });
  });

  group('la red de seguridad del idioma (F45, paso 4)', () {
    const title =
        'Las reliquias de San Francisco de Asís que han fascinado al mundo';
    const arabic = [
      TranscriptLine(
        offset: Duration.zero,
        text: 'بقايا القديس فرنسيس الأسيزي التي أذهلت العالم',
      ),
      TranscriptLine(
        offset: Duration(seconds: 7),
        text: 'في هذا الفيديو نتحدث عن تاريخ هذه الآثار المقدسة',
      ),
    ];

    Future<
      ({
        KnowledgeItem result,
        FakeAudioTranscriber transcriber,
        List<ForeignCaptionsNotice> notices,
        FakeYouTubeClient client,
      })
    >
    run(
      YouTubeVideoData data, {
      String? chosen,
      bool transcribes = true,
    }) async {
      final temp = Directory.systemTemp.createTempSync('yt_audio');
      addTearDown(() => temp.deleteSync(recursive: true));
      final client = FakeYouTubeClient(data: data);
      final transcriber = FakeAudioTranscriber(
        text: '[0:00] Las reliquias del santo',
      );
      final notices = <ForeignCaptionsNotice>[];
      final result = await YouTubeTranscriptTransformer(
        client: client,
        ids: ids,
        clock: () => now,
        transcriber: transcribes ? transcriber : null,
        temporaryDirectory: transcribes ? () async => temp : null,
        notify: notices.add,
      ).transform(videoItem(language: chosen));
      return (
        result: result,
        transcriber: transcriber,
        notices: notices,
        client: client,
      );
    }

    test('subtítulos en árabe de un video en español: no se guardan, se '
        'transcribe el audio en español y el aviso lo dice', () async {
      final outcome = await run(
        const YouTubeVideoData(
          title: title,
          transcript: arabic,
          transcriptLanguage: 'es',
          spokenLanguage: 'es',
        ),
      );

      expect(
        outcome.result.renditions.single.searchableText,
        '[0:00] Las reliquias del santo',
      );
      expect(outcome.transcriber.languages, ['es']);
      expect(outcome.result.source.language, 'es');
      expect(outcome.notices, [
        const ForeignCaptionsNotice(
          itemId: 'item-1',
          title: title,
          foundLanguage: 'ar',
          audioLanguage: 'es',
        ),
      ]);
    });

    test(
      'un «ar» que guardó una versión anterior se pide, pero no manda: '
      'el audio se transcribe en el idioma del título, no en árabe',
      () async {
        final outcome = await run(
          const YouTubeVideoData(
            title: title,
            transcript: arabic,
            transcriptLanguage: 'ar',
            spokenLanguage: 'ar',
            description:
                'En este video les contamos la historia de las reliquias del '
                'santo. Es una de las más visitadas del mundo, con miles de '
                'peregrinos por año.',
          ),
          chosen: 'ar',
        );

        expect(outcome.client.languagesRequested.single, ['ar']);
        expect(outcome.transcriber.languages, ['es']);
        expect(outcome.result.source.language, 'es');
        expect(outcome.notices.single.audioLanguage, 'es');
      },
    );

    test(
      'inglés con subtítulos en inglés: se guardan, sin aviso ni audio',
      () async {
        final outcome = await run(
          const YouTubeVideoData(
            title: 'The relics of Saint Francis of Assisi',
            transcript: [
              TranscriptLine(
                offset: Duration.zero,
                text:
                    'In this video we talk about the history of the relics and '
                    'how they have been kept for eight hundred years.',
              ),
            ],
            transcriptLanguage: 'en',
            spokenLanguage: 'en',
          ),
        );

        expect(
          outcome.result.renditions.single.searchableText,
          startsWith('[0:00]'),
        );
        expect(outcome.transcriber.languages, isEmpty);
        expect(outcome.client.audioRequested, isEmpty);
        expect(outcome.notices, isEmpty);
        expect(outcome.result.source.language, 'en');
      },
    );

    test('sin con qué transcribir, tampoco se guarda el árabe: queda la '
        'descripción, y el aviso no promete el audio', () async {
      final outcome = await run(
        const YouTubeVideoData(
          title: title,
          transcript: arabic,
          spokenLanguage: 'es',
          description: 'La historia de las reliquias del santo.',
        ),
        transcribes: false,
      );

      expect(
        outcome.result.renditions.single.searchableText,
        'La historia de las reliquias del santo.',
      );
      expect(outcome.notices.single.transcribing, isFalse);
    });
  });

  group('el audio', () {
    test('NO se baja al procesar: el video queda listo con la '
        'transcripción', () async {
      // Antes el video no quedaba listo hasta bajar el audio entero —cientos
      // de MB en uno de cuatro horas—. Ahora se baja solo a pedido (F21).
      final client = FakeYouTubeClient(
        data: const YouTubeVideoData(
          title: 'Un video',
          transcript: [
            TranscriptLine(offset: Duration.zero, text: 'Primera frase'),
          ],
        ),
      );

      final result = await build(client).transform(videoItem());

      expect(client.audioRequested, isEmpty);
      expect(result.source.originalFilePath, isNull);
      expect(result.renditions, isNotEmpty);
    });

    test('es trabajo corto: tiene tope de tiempo', () {
      expect(build(FakeYouTubeClient()).timeLimit, kShortTransformTimeLimit);
    });
  });

  group('formato de la transcripción', () {
    test('menos de una hora se escribe sin la hora', () {
      // Un "0:02:07" obliga a leer un cero que no aporta nada, y la mayoría
      // de los videos duran minutos.
      expect(formatTimestamp(const Duration(seconds: 7)), '0:07');
      expect(formatTimestamp(const Duration(minutes: 2, seconds: 7)), '2:07');
      expect(
        formatTimestamp(const Duration(minutes: 59, seconds: 59)),
        '59:59',
      );
    });

    test('a partir de una hora sí aparece', () {
      expect(
        formatTimestamp(const Duration(hours: 1, minutes: 2, seconds: 7)),
        '1:02:07',
      );
      expect(formatTimestamp(const Duration(hours: 2)), '2:00:00');
    });

    test('una línea por frase, cada una con su momento', () {
      final text = formatTranscript(const [
        TranscriptLine(offset: Duration(seconds: 3), text: 'Hola'),
        TranscriptLine(offset: Duration(seconds: 9), text: 'Chau'),
      ]);

      expect(text, '[0:03] Hola\n[0:09] Chau');
    });
  });
}
