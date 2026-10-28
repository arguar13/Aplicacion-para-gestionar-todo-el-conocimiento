import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/processed/data/repositories/source_images_reader.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/test_vault.dart';

void main() {
  late TestVault vault;
  late InMemoryFileStore files;
  late SourceImagesReader reader;

  setUp(() async {
    vault = await TestVault.create(deviceId: 'tel');
    files = InMemoryFileStore();
    reader = SourceImagesReader(vault.db, files);
  });

  tearDown(() => vault.db.close());

  /// Una fuente de [kind] con [blob] como su archivo, guardado con
  /// [blobBytes] bytes.
  Future<String?> saveSource(
    String id, {
    required SourceKind kind,
    String? blobName,
    int blobBytes = 10,
  }) async {
    final blob = blobName == null
        ? null
        : await files.save(
            bytes: Uint8List(blobBytes),
            suggestedName: blobName,
            id: id,
          );
    final at = vault.now;
    await vault.writer.upsert(
      KnowledgeItem(
        id: id,
        title: 'Fuente $id',
        source: Source(
          id: id,
          kind: kind,
          capturedAt: at,
          originalFilePath: blob,
        ),
        processingState: ProcessingState.ready,
        createdAt: at,
        updatedAt: at,
      ),
    );
    return blob;
  }

  /// Una foto del «Contenido» de [itemId] (F30), en [position].
  Future<String> addPhoto(
    String itemId,
    String name, {
    required int position,
    int? size = 100,
    String? title,
    String? mime,
    RenditionKind kind = RenditionKind.image,
  }) async {
    final path = 'originales/$itemId/contenido/$name';
    await vault.db
        .into(vault.db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'foto-$itemId-$name',
            itemId: itemId,
            kind: kind,
            relativePath: Value(path),
            isPrimary: false,
            createdAt: vault.now,
            position: Value(position),
            sizeBytes: Value(size),
            title: Value(title),
            mimeType: Value(mime),
          ),
        );
    return path;
  }

  group('SourceImagesReader (F41, decisión L)', () {
    test('una imagen guardada ofrece su archivo, con lo que pesa', () async {
      final blob = await saveSource(
        'img',
        kind: SourceKind.image,
        blobName: 'captura.png',
        blobBytes: 42,
      );

      expect(await reader.list('img'), [
        SourceImage(
          path: blob!,
          origin: SourceImageOrigin.original,
          sizeBytes: 42,
        ),
      ]);
      expect(
        await reader.summary('img'),
        const SourceImagesSummary(count: 1, sizeBytes: 42),
      );
    });

    test('una publicación ofrece su primera foto y después las del carrusel, '
        'en su orden', () async {
      final first = await saveSource(
        'post',
        kind: SourceKind.socialPost,
        blobName: 'post.jpg',
      );
      final third = await addPhoto('post', 'c.jpg', position: 2);
      final second = await addPhoto(
        'post',
        'b.jpg',
        position: 1,
        title: '  Atardecer  ',
        mime: 'image/jpeg',
      );

      final images = await reader.list('post');
      expect([for (final i in images) i.path], [first, second, third]);
      expect(images[0].origin, SourceImageOrigin.original);
      expect(images[1].origin, SourceImageOrigin.content);
      expect(images[1].title, 'Atardecer');
      expect(images[1].mimeType, 'image/jpeg');
      expect(
        await reader.summary('post'),
        const SourceImagesSummary(count: 3, sizeBytes: 210),
      );
    });

    test('una publicación con video no ofrece el video como imagen', () async {
      await saveSource('video', kind: SourceKind.socialPost, blobName: 'v.mp4');

      expect(await reader.list('video'), isEmpty);
      expect(await reader.summary('video'), SourceImagesSummary.none);
    });

    test('una página guardada ofrece las fotos de su «Contenido», no la '
        'página archivada ni los demás archivos', () async {
      await saveSource(
        'web',
        kind: SourceKind.webPage,
        blobName: 'pagina.html',
      );
      final photo = await addPhoto('web', 'foto.jpg', position: 0);
      await addPhoto('web', 'apunte.pdf', position: 1, kind: RenditionKind.pdf);
      await addPhoto('web', 'logo.svg', position: 2);
      await addPhoto('web', 'icono', position: 3, mime: 'image/svg+xml');

      final images = await reader.list('web');
      expect([for (final i in images) i.path], [photo]);
      expect((await reader.summary('web')).count, 1);
    });

    test('lo que la base no sabe cuánto pesa se mide en el disco', () async {
      await saveSource('web', kind: SourceKind.webPage);
      final path = await addPhoto('web', 'vieja.jpg', position: 0, size: null);
      await files.saveStream(
        bytes: Stream.value(List.filled(7, 0)),
        suggestedName: 'vieja.jpg',
        id: 'web',
        folder: 'contenido',
      );

      expect((await reader.list('web')).single.sizeBytes, 7);
      expect(
        await reader.summary('web'),
        const SourceImagesSummary(count: 1, sizeBytes: 7),
      );
      expect(path, 'originales/web/contenido/vieja.jpg');
    });

    test('el archivo de la fuente que ya no está en el teléfono no se '
        'ofrece', () async {
      final blob = await saveSource(
        'img',
        kind: SourceKind.image,
        blobName: 'captura.png',
      );
      await files.delete(blob!);

      expect(await reader.list('img'), isEmpty);
    });

    test('se pide de a tramos: el primero empieza por el archivo de la '
        'fuente, los demás siguen con el «Contenido»', () async {
      final own = await saveSource(
        'post',
        kind: SourceKind.socialPost,
        blobName: 'post.jpg',
      );
      final photos = [
        for (var i = 0; i < 5; i++)
          await addPhoto('post', 'f$i.jpg', position: i + 1),
      ];
      final all = [own!, ...photos];

      Future<List<String>> page(int offset, int limit) async => [
        for (final image in await reader.list(
          'post',
          offset: offset,
          limit: limit,
        ))
          image.path,
      ];

      expect(await page(0, 2), all.sublist(0, 2));
      expect(await page(2, 2), all.sublist(2, 4));
      expect(await page(4, 2), all.sublist(4, 6));
      expect(await page(6, 2), isEmpty);
      expect(await page(0, 0), isEmpty);
      expect(await page(0, 1), [own]);
      expect(await page(1, 1), [photos.first]);
    });

    test('sin archivo propio, los tramos son los del «Contenido»', () async {
      await saveSource('web', kind: SourceKind.webPage);
      final photos = [
        for (var i = 0; i < 3; i++)
          await addPhoto('web', 'f$i.jpg', position: i),
      ];

      final second = await reader.list('web', offset: 1, limit: 1);
      expect([for (final i in second) i.path], [photos[1]]);
    });

    test('una forma que apunta al archivo de la fuente —datos de antes o '
        'traídos por una unión— no lo ofrece dos veces', () async {
      final blob = await saveSource(
        'img',
        kind: SourceKind.image,
        blobName: 'captura.png',
      );
      await vault.db
          .into(vault.db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'misma',
              itemId: 'img',
              kind: RenditionKind.image,
              relativePath: Value(blob),
              isPrimary: false,
              createdAt: vault.now,
              sizeBytes: const Value(10),
            ),
          );

      expect([for (final i in await reader.list('img')) i.path], [blob]);
      expect((await reader.summary('img')).count, 1);
    });

    test('lo que no es una fuente no ofrece nada', () async {
      expect(await reader.list('nada'), isEmpty);
      expect(await reader.summary('nada'), SourceImagesSummary.none);
    });
  });
}
