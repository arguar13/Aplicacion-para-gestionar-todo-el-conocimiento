import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';

import '../../../processed/processed_harness.dart';

/// La unión de bóvedas con las imágenes de los procesados (F41, decisión L):
/// cada copia viaja con su archivo, no se repite, y lo que se quitó acá no
/// vuelve.
void main() {
  late ProcessedHarness tel;
  late ProcessedHarness pc;
  final docId = processedDocumentIdFor('pagina');
  final photos = [
    for (var i = 0; i < 3; i++) 'originales/pagina/contenido/foto-$i.jpg',
  ];

  /// La página con sus tres fotos, en [h] —las dos bóvedas la tienen, como la
  /// tendría una que ya se unió antes—.
  Future<void> savePage(ProcessedHarness h) async {
    await h.vault.saveSource('pagina', title: 'Una página');
    for (final (index, path) in photos.indexed) {
      await h.vault.writeOriginal(path, 'foto $index');
      await h.db
          .into(h.db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'foto-$index',
              itemId: 'pagina',
              kind: RenditionKind.image,
              relativePath: Value(path),
              isPrimary: false,
              createdAt: h.vault.now,
              position: Value(index),
              sizeBytes: const Value(6),
            ),
          );
    }
  }

  setUp(() async {
    tel = await ProcessedHarness.create();
    pc = await ProcessedHarness.create(deviceId: 'pc');
    await savePage(tel);
    await savePage(pc);
  });
  tearDown(() async {
    await tel.close();
    await pc.close();
  });

  Future<void> choose(ProcessedHarness h, ImageChoice choice) async {
    final result = await h.process('pagina', {
      ProcessedSection.images: SectionEdit.add(SectionInput.images(choice)),
    });
    expect(result.isRight(), isTrue, reason: '$result');
  }

  Future<List<ProcessedImage>> gallery(ProcessedHarness h) async =>
      (await h.repository.imagesOf(docId)).getRight().toNullable()!;

  test('las imágenes de un procesado viajan con sus archivos, en su lugar, '
      'y una segunda vez no traen otras', () async {
    await choose(tel, const ImageChoice.all());
    final there = await gallery(tel);

    final merged = await pc.vault.mergeFrom(tel.vault);

    expect(merged.processedImagesAdded, 3);
    final here = await gallery(pc);
    expect(
      [for (final i in here) (i.renditionId, i.position, i.relativePath)],
      [for (final i in there) (i.renditionId, i.position, i.relativePath)],
    );
    for (final image in here) {
      expect(pc.vault.hasOriginal(image.relativePath), isTrue);
      expect(
        pc.vault.readOriginal(image.relativePath),
        tel.vault.readOriginal(image.relativePath),
      );
    }

    final again = await pc.vault.mergeFrom(tel.vault);
    expect(again.processedImagesAdded, 0);
  });

  test('dos dispositivos que eligieron cada uno lo suyo quedan con todas, '
      'sin repetir la que eligieron los dos', () async {
    await choose(tel, ImageChoice.only({photos[0], photos[1]}));
    await choose(pc, ImageChoice.only({photos[1], photos[2]}));

    final merged = await pc.vault.mergeFrom(tel.vault);

    expect(merged.processedImagesAdded, 1);
    final here = await gallery(pc);
    expect(
      [for (final i in here) i.sourceFilePath],
      [photos[1], photos[2], photos[0]],
    );
    expect([for (final i in here) i.position], [0, 1, 2]);
  });

  test('la que se quitó acá no vuelve con la unión', () async {
    await choose(tel, const ImageChoice.all());
    await pc.vault.mergeFrom(tel.vault);
    final removed = (await gallery(pc)).first;
    expect(
      (await pc.repository.removeImage(removed.renditionId)).isRight(),
      isTrue,
    );

    final merged = await pc.vault.mergeFrom(tel.vault);

    expect(merged.processedImagesAdded, 0);
    expect([
      for (final i in await gallery(pc)) i.renditionId,
    ], isNot(contains(removed.renditionId)));
    expect(await gallery(pc), hasLength(2));
  });

  test('la copia de la bóveda lleva los archivos de las imágenes', () async {
    await choose(tel, ImageChoice.only({photos[2]}));
    final image = (await gallery(tel)).single;

    final zip = ZipDecoder().decodeBytes(await tel.vault.zip());

    expect([
      for (final file in zip.files) file.name,
    ], contains(image.relativePath));
  });
}
