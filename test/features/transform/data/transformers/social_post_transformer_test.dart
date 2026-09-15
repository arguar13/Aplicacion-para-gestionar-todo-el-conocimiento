import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/transform/data/transformers/social_post_transformer.dart';
import 'package:sinapsis/features/transform/domain/clients/social_post_client.dart';

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
  }) => SocialPostTransformer(
    client: client ?? FakeSocialPostClient(),
    fetcher: fetcher ?? FakeResourceFetcher(),
    files: files,
    ids: ids,
    clock: () => now,
    logger: const SilentLogger(),
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

    test('ni texto ni video: falla, para poder reintentar', () async {
      final client = FakeSocialPostClient(data: const SocialPostData());

      await expectLater(
        build(client: client).transform(postItem()),
        throwsA(isA<SocialPostUnavailableException>()),
      );
    });
  });
}
