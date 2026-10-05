import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/timed_word.dart';
import 'package:sinapsis/features/transform/data/transformers/social_post_transformer.dart';
import 'package:sinapsis/features/transform/domain/clients/social_post_client.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_checkpoints.dart';
import 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';

import '../../../../support/attachment_test_doubles.dart';
import '../../../../support/fake_audio_transcriber.dart';
import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/silent_logger.dart';
import '../../../../support/transform_test_doubles.dart';

void main() {
  final now = DateTime(2026, 9, 14, 10);
  late FakeIdGenerator ids;
  late InMemoryFileStore files;

  setUp(() {
    ids = FakeIdGenerator();
    files = InMemoryFileStore();
  });

  KnowledgeItem postItem({
    String url = 'https://www.tiktok.com/@alguien/video/123',
    List<Rendition> renditions = const [],
    SourceKind kind = SourceKind.socialPost,
  }) => KnowledgeItem(
    id: 'item-1',
    title: 'tiktok.com',
    source: Source(id: 'src-1', kind: kind, capturedAt: now, url: url),
    processingState: ProcessingState.pending,
    createdAt: now,
    updatedAt: now,
    renditions: renditions,
  );

  SocialPostTransformer build({
    FakeSocialPostClient? client,
    FakeResourceFetcher? fetcher,
    FakeAudioTranscriber? transcriber,
    ProcessingCheckpoints? checkpoints,
  }) => SocialPostTransformer(
    client: client ?? FakeSocialPostClient(),
    fetcher: fetcher ?? FakeResourceFetcher(),
    files: files,
    ids: ids,
    clock: () => now,
    logger: const SilentLogger(),
    transcriber: transcriber,
    checkpoints: checkpoints,
  );

  group('a qué se aplica', () {
    test('a una publicación social sin contenido todavía', () {
      expect(build().canTransform(postItem()), isTrue);
    });

    test('NO a algo que no es una publicación social', () {
      expect(build().canTransform(postItem(kind: SourceKind.webPage)), isFalse);
    });

    test('NO a una que ya tiene contenido', () {
      final withContent = postItem(
        renditions: [
          Rendition.text(
            id: 'r1',
            itemId: 'item-1',
            kind: RenditionKind.plainText,
            content: 'ya estaba',
            isPrimary: true,
            createdAt: now,
          ),
        ],
      );

      expect(build().canTransform(withContent), isFalse);
    });
  });

  group('lo que trae', () {
    test('guarda el texto de la publicación', () async {
      final client = FakeSocialPostClient(
        data: const SocialPostData(caption: 'Un texto interesante'),
      );

      final result = await build(client: client).transform(postItem());

      expect(result.renditions.single.searchableText, 'Un texto interesante');
    });

    test('completa el autor cuando lo trae', () async {
      final client = FakeSocialPostClient(
        data: const SocialPostData(
          caption: 'Algo',
          authorName: 'alguien.oficial',
        ),
      );

      final result = await build(client: client).transform(postItem());

      expect(result.source.authorName, 'alguien.oficial');
      expect(result.subtitle, 'alguien.oficial');
    });

    test('baja el video y lo guarda cuando hay una dirección', () async {
      final videoUrl = Uri.parse('https://v16.tiktokcdn.com/video.mp4');
      final client = FakeSocialPostClient(
        data: SocialPostData(caption: 'Algo', videoUrl: videoUrl),
      );
      final fetcher = FakeResourceFetcher(
        byUrl: {
          videoUrl.toString(): Uint8List.fromList([1, 2, 3]),
        },
      );

      final result = await build(
        client: client,
        fetcher: fetcher,
      ).transform(postItem());

      expect(result.source.originalFilePath, isNotNull);
      expect(await files.exists(result.source.originalFilePath!), isTrue);
    });

    test('si el video no se pudo bajar, el texto se guarda igual', () async {
      final videoUrl = Uri.parse('https://v16.tiktokcdn.com/video.mp4');
      final client = FakeSocialPostClient(
        data: SocialPostData(caption: 'Algo', videoUrl: videoUrl),
      );
      // Sin nada en `byUrl`: simula un 404 o un CDN caído.
      final fetcher = FakeResourceFetcher();

      final result = await build(
        client: client,
        fetcher: fetcher,
      ).transform(postItem());

      expect(result.source.originalFilePath, isNull);
      expect(result.renditions, isNotEmpty);
    });

    test('sin texto pero con video, igual guarda el video', () async {
      final videoUrl = Uri.parse('https://v16.tiktokcdn.com/video.mp4');
      final client = FakeSocialPostClient(
        data: SocialPostData(videoUrl: videoUrl),
      );
      final fetcher = FakeResourceFetcher(
        byUrl: {
          videoUrl.toString(): Uint8List.fromList([1, 2, 3]),
        },
      );

      final result = await build(
        client: client,
        fetcher: fetcher,
      ).transform(postItem());

      expect(result.renditions, isEmpty);
      expect(result.source.originalFilePath, isNotNull);
    });

    test('ni texto, ni video, ni foto: falla, para poder reintentar', () async {
      final client = FakeSocialPostClient(data: const SocialPostData());

      await expectLater(
        build(client: client).transform(postItem()),
        throwsA(isA<SocialPostUnavailableException>()),
      );
    });

    test('sin video, baja la foto de portada y la guarda', () async {
      final imageUrl = Uri.parse('https://p16.tiktokcdn.com/portada.jpg');
      final client = FakeSocialPostClient(
        data: SocialPostData(caption: 'Algo', imageUrl: imageUrl),
      );
      final fetcher = FakeResourceFetcher(
        byUrl: {
          imageUrl.toString(): Uint8List.fromList([1, 2, 3]),
        },
      );

      final result = await build(
        client: client,
        fetcher: fetcher,
      ).transform(postItem());

      expect(result.source.originalFilePath, isNotNull);
      expect(await files.exists(result.source.originalFilePath!), isTrue);
    });

    test('con video Y foto, se queda con el video: es el contenido más '
        'completo', () async {
      final videoUrl = Uri.parse('https://v16.tiktokcdn.com/video.mp4');
      final imageUrl = Uri.parse('https://p16.tiktokcdn.com/portada.jpg');
      final client = FakeSocialPostClient(
        data: SocialPostData(
          caption: 'Algo',
          videoUrl: videoUrl,
          imageUrl: imageUrl,
        ),
      );
      final fetcher = FakeResourceFetcher(
        byUrl: {
          videoUrl.toString(): Uint8List.fromList([1, 2, 3]),
          imageUrl.toString(): Uint8List.fromList([4, 5, 6]),
        },
      );

      final result = await build(
        client: client,
        fetcher: fetcher,
      ).transform(postItem());

      expect(result.source.originalFilePath, endsWith('.mp4'));
      // La foto nunca se pidió: bajarla habría sido trabajo de más para
      // algo que no se iba a usar.
      expect(fetcher.requested, [videoUrl]);
    });

    test(
      'sin texto y sin video, pero con foto: no hace falta reintentar',
      () async {
        final imageUrl = Uri.parse('https://p16.tiktokcdn.com/portada.jpg');
        final client = FakeSocialPostClient(
          data: SocialPostData(imageUrl: imageUrl),
        );
        final fetcher = FakeResourceFetcher(
          byUrl: {
            imageUrl.toString(): Uint8List.fromList([1, 2, 3]),
          },
        );

        final result = await build(
          client: client,
          fetcher: fetcher,
        ).transform(postItem());

        expect(result.renditions, isEmpty);
        expect(result.source.originalFilePath, isNotNull);
      },
    );
  });

  group('el audio del video (F24)', () {
    final videoUrl = Uri.parse('https://v16.tiktokcdn.com/video.mp4');
    final imageUrl = Uri.parse('https://p16.tiktokcdn.com/portada.jpg');

    FakeResourceFetcher withVideo() => FakeResourceFetcher(
      byUrl: {
        videoUrl.toString(): Uint8List.fromList([1, 2, 3]),
      },
    );

    FakeSocialPostClient reel({String? caption = 'Mirá esto #ciencia'}) =>
        FakeSocialPostClient(
          data: SocialPostData(caption: caption, videoUrl: videoUrl),
        );

    test('transcribe el video bajado: lo dicho, con el momento de cada '
        'palabra, es el texto principal, y la descripción queda al '
        'lado', () async {
      final transcriber = FakeAudioTranscriber(
        text: 'Hola a todos',
        words: const [
          TimedWord('Hola', 0),
          TimedWord('a', 400),
          TimedWord('todos', 600),
        ],
      );

      final result = await build(
        client: reel(),
        fetcher: withVideo(),
        transcriber: transcriber,
      ).transform(postItem());

      final texts = result.renditions.whereType<TextRendition>().toList();
      expect(texts, hasLength(2));
      final spoken = texts.singleWhere((r) => r.isPrimary);
      expect(spoken.content, 'Hola a todos');
      expect(spoken.kind, RenditionKind.plainText);
      expect(spoken.wordTimings, transcriber.words);
      // La descripción no se pierde: sigue guardada, y buscable.
      final caption = texts.singleWhere((r) => !r.isPrimary);
      expect(caption.content, 'Mirá esto #ciencia');
      expect(result.searchableText, contains('#ciencia'));
      expect(result.source.originalFilePath, endsWith('.mp4'));
    });

    test('pide la ruta absoluta del video guardado, en el idioma de la '
        'publicación o en español si no se sabe', () async {
      final transcriber = FakeAudioTranscriber(text: 'algo');
      final transformer = build(
        client: reel(),
        fetcher: withVideo(),
        transcriber: transcriber,
      );

      final result = await transformer.transform(postItem());
      final english = postItem();
      await transformer.transform(
        english.copyWith(source: english.source.copyWith(language: 'en')),
      );

      expect(
        transcriber.requested.first,
        '/memoria/${result.source.originalFilePath}',
      );
      expect(transcriber.languages, ['es', 'en']);
      expect(result.source.language, 'es');
    });

    test('lo transcribe en el carril largo, retomando los tramos de este '
        'elemento (F21)', () async {
      final checkpoints = _MemoryCheckpoints();
      await checkpoints.save(
        'item-1',
        ProcessingCheckpointKind.transcriptWindow,
        position: 0,
        content: 'de antes',
      );
      final transcriber = FakeAudioTranscriber(text: 'algo');
      final context = _RecordingContext();

      await build(
        client: reel(),
        fetcher: withVideo(),
        transcriber: transcriber,
        checkpoints: checkpoints,
      ).transform(postItem(), context: context);

      expect(context.enteredLongLane, isTrue);
      final session = transcriber.sessions.single;
      expect(session.workKey, 'item-1');
      expect(identical(session.context, context), isTrue);
      expect(await session.transcribedSegments(), {0: 'de antes'});
      await session.saveSegment(1, 'nuevo');
      expect(
        await checkpoints.load(
          'item-1',
          ProcessingCheckpointKind.transcriptWindow,
        ),
        {0: 'de antes', 1: 'nuevo'},
      );
    });

    test('sin con qué transcribir, queda como antes: solo la '
        'descripción', () async {
      final context = _RecordingContext();

      final result = await build(
        client: reel(),
        fetcher: withVideo(),
      ).transform(postItem(), context: context);

      expect(
        result.renditions.whereType<TextRendition>().single,
        isA<TextRendition>()
            .having((r) => r.content, 'content', 'Mirá esto #ciencia')
            .having((r) => r.isPrimary, 'isPrimary', isTrue),
      );
      expect(result.source.language, isNull);
      // Sin nada largo que hacer, ni pasa al carril largo.
      expect(context.enteredLongLane, isFalse);
    });

    test('sin nada dicho —música sola, silencio—, no agrega texto y el '
        'elemento queda igual de listo', () async {
      final transcriber = FakeAudioTranscriber(text: '  ');

      final result = await build(
        client: reel(),
        fetcher: withVideo(),
        transcriber: transcriber,
      ).transform(postItem());

      expect(transcriber.requested, hasLength(1));
      final caption = result.renditions.whereType<TextRendition>().single;
      expect(caption.content, 'Mirá esto #ciencia');
      expect(caption.isPrimary, isTrue);
      expect(result.source.language, isNull);
    });

    test('sin nada dicho ni descripción: sin texto, pero con el '
        'video', () async {
      final result = await build(
        client: reel(caption: null),
        fetcher: withVideo(),
        transcriber: FakeAudioTranscriber(),
      ).transform(postItem());

      expect(result.renditions, isEmpty);
      expect(result.source.originalFilePath, endsWith('.mp4'));
    });

    test('lo dicho sin descripción: es el único texto, y el '
        'principal', () async {
      final result = await build(
        client: reel(caption: null),
        fetcher: withVideo(),
        transcriber: FakeAudioTranscriber(text: 'Hola'),
      ).transform(postItem());

      final spoken = result.renditions.whereType<TextRendition>().single;
      expect(spoken.content, 'Hola');
      expect(spoken.isPrimary, isTrue);
    });

    test('una publicación con foto y sin video no transcribe nada', () async {
      final transcriber = FakeAudioTranscriber(text: 'no');
      final context = _RecordingContext();

      final result = await build(
        client: FakeSocialPostClient(
          data: SocialPostData(caption: 'Algo', imageUrl: imageUrl),
        ),
        fetcher: FakeResourceFetcher(
          byUrl: {
            imageUrl.toString(): Uint8List.fromList([1, 2, 3]),
          },
        ),
        transcriber: transcriber,
      ).transform(postItem(), context: context);

      expect(transcriber.requested, isEmpty);
      expect(context.enteredLongLane, isFalse);
      expect(result.renditions.single.searchableText, 'Algo');
    });

    test('si el video no se pudo bajar, no hay nada que transcribir y el '
        'texto se guarda igual', () async {
      final transcriber = FakeAudioTranscriber(text: 'no');

      final result = await build(
        client: reel(),
        // Sin nada en `byUrl`: el CDN no lo dio.
        fetcher: FakeResourceFetcher(),
        transcriber: transcriber,
      ).transform(postItem());

      expect(transcriber.requested, isEmpty);
      expect(result.renditions.single.searchableText, 'Mirá esto #ciencia');
    });

    test('si la transcripción falla, el elemento falla para reintentar, y '
        'el video queda donde el reintento lo vuelve a bajar', () async {
      final transcriber = FakeAudioTranscriber()..error = Exception('corte');

      await expectLater(
        build(
          client: reel(),
          fetcher: withVideo(),
          transcriber: transcriber,
        ).transform(postItem()),
        throwsA(isA<Exception>()),
      );

      expect(files.deleted, isEmpty);
    });

    test('si se abandona porque el elemento se borró, se propaga y el video '
        'bajado no queda huérfano', () async {
      final signal = CancellationSignal()..cancel();
      final transcriber = FakeAudioTranscriber()
        ..error = const ProcessingCancelledException();

      await expectLater(
        build(
          client: reel(),
          fetcher: withVideo(),
          transcriber: transcriber,
        ).transform(postItem(), context: CancellableTransformContext(signal)),
        throwsA(isA<ProcessingCancelledException>()),
      );

      expect(files.deleted.single, endsWith('.mp4'));
    });
  });

  group('un carrusel (F30)', () {
    test(
      'la primera es la foto del elemento; las demás, al «Contenido»',
      () async {
        final attachments = FakeAttachmentRepository();
        final transformer = SocialPostTransformer(
          client: FakeSocialPostClient(
            data: SocialPostData(
              caption: 'Tres fotos',
              imageUrl: Uri.parse('https://cdn.org/1.jpg'),
              moreImages: [
                Uri.parse('https://cdn.org/2.jpg'),
                Uri.parse('https://cdn.org/3.jpg'),
              ],
            ),
          ),
          fetcher: FakeResourceFetcher(
            byUrl: {
              'https://cdn.org/1.jpg': Uint8List.fromList([1, 2]),
            },
          ),
          files: files,
          ids: ids,
          clock: () => now,
          logger: const SilentLogger(),
          attachments: attachments,
        );

        final result = await transformer.transform(postItem());

        expect(result.source.originalFilePath, isNotNull);
        expect(
          attachments.downloads.map((d) => (d.url.toString(), d.position)),
          [('https://cdn.org/2.jpg', 1), ('https://cdn.org/3.jpg', 2)],
        );
        expect(
          attachments.downloads.map((d) => d.kind),
          everyElement(RenditionKind.image),
        );
      },
    );

    test('sin «Contenido» (la web), solo la primera, como antes', () async {
      final result = await build(
        client: FakeSocialPostClient(
          data: SocialPostData(
            imageUrl: Uri.parse('https://cdn.org/1.jpg'),
            moreImages: [Uri.parse('https://cdn.org/2.jpg')],
          ),
        ),
        fetcher: FakeResourceFetcher(
          byUrl: {
            'https://cdn.org/1.jpg': Uint8List.fromList([1]),
          },
        ),
      ).transform(postItem());

      expect(result.source.originalFilePath, isNotNull);
    });
  });
}

/// El avance guardado, en memoria.
class _MemoryCheckpoints implements ProcessingCheckpoints {
  final _saved = <(String, ProcessingCheckpointKind), Map<int, String>>{};

  @override
  Future<Map<int, String>> load(
    String itemId,
    ProcessingCheckpointKind kind,
  ) async => {...?_saved[(itemId, kind)]};

  @override
  Future<void> save(
    String itemId,
    ProcessingCheckpointKind kind, {
    required int position,
    required String content,
  }) async => (_saved[(itemId, kind)] ??= {})[position] = content;
}

/// Una cola que anota si se pasó al carril largo.
class _RecordingContext implements TransformContext {
  bool enteredLongLane = false;

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;

  @override
  void throwIfCancelled() {}

  @override
  Future<void> enterLongLane() async => enteredLongLane = true;

  @override
  void reportProgress(int done, int total) {}
}
