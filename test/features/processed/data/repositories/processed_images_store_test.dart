import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_images_store.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_images_planner.dart';

import '../../../../support/fake_id_generator.dart';
import '../../processed_harness.dart';

void main() {
  late ProcessedHarness h;
  late String documentId;
  final ids = FakeIdGenerator(prefix: 'papelera');

  setUp(() async {
    h = await ProcessedHarness.create();
    await h.vault.saveSource('f', text: 'Un texto.');
    final outcome = await h.process('f', {
      ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    });
    documentId = outcome.getRight().toNullable()!.documentId;
  });

  tearDown(() => h.close());

  AppDatabase db() => h.db;

  SourceImage source(String name, {int size = 10}) => SourceImage(
    path: 'originales/f/contenido/$name',
    origin: SourceImageOrigin.content,
    sizeBytes: size,
    title: 'Foto $name',
    mimeType: 'image/jpeg',
  );

  StagedImage staged(SourceImage source) => StagedImage(
    source: source,
    relativePath:
        'originales/$documentId/$kProcessedImagesFolder/'
        '${source.path.split('/').last}',
    sizeBytes: source.sizeBytes,
  );

  /// Guarda [plan] en una transacción, como el repositorio.
  Future<ProcessedImagesUndo> apply(ImagesPlan plan) => db().transaction(
    () => applyProcessedImagesPlan(
      db(),
      documentId: documentId,
      plan: plan,
      staged: {for (final s in plan.fresh) s.path: staged(s)},
      ids: ids,
      at: h.vault.now,
    ),
  );

  Future<List<String>> gallery() async => [
    for (final image in await processedImagesOf(db(), documentId))
      '${image.position}:${image.sourceFilePath.split('/').last}',
  ];

  test('las imágenes nuevas entran como formas de imagen del procesado, con '
      'su archivo, su nombre y su peso, y sin ser «Contenido»', () async {
    final a = source('a.jpg', size: 30);
    await apply(
      planImagesChange(
        existing: const [],
        change: ProcessedChange.add,
        chosen: [a, source('b.jpg')],
      ),
    );

    expect(await gallery(), ['0:a.jpg', '1:b.jpg']);
    final rendition =
        await (db().select(db().renditions)..where(
              (r) =>
                  r.id.equals(processedImageRenditionIdFor(documentId, a.path)),
            ))
            .getSingle();
    expect(rendition.itemId, documentId);
    expect(rendition.kind, RenditionKind.image);
    expect(rendition.relativePath, staged(a).relativePath);
    expect(rendition.sizeBytes, 30);
    expect(rendition.title, 'Foto a.jpg');
    expect(rendition.mimeType, 'image/jpeg');
    expect(rendition.position, isNull);
    expect(rendition.isPrimary, isFalse);
  });

  test('la misma imagen de la fuente no entra dos veces en el mismo '
      'documento: lo garantiza la base', () async {
    await apply(
      planImagesChange(
        existing: const [],
        change: ProcessedChange.add,
        chosen: [source('a.jpg')],
      ),
    );
    final image = (await processedImagesOf(db(), documentId)).single;

    await expectLater(
      db()
          .into(db().processedImages)
          .insert(
            ProcessedImagesCompanion.insert(
              renditionId: 'otra',
              documentId: documentId,
              position: 1,
              sourceFilePath: image.sourceFilePath,
              sourceFileSize: 1,
              copiedAt: h.vault.now,
            ),
          ),
      throwsA(anything),
    );
  });

  test('reemplazar manda lo que sale a la papelera del contenido, con lo '
      'que hace falta para volver, y no borra ningún archivo', () async {
    await apply(
      planImagesChange(
        existing: const [],
        change: ProcessedChange.add,
        chosen: [source('a.jpg'), source('b.jpg')],
      ),
    );
    final existing = await processedImagesOf(db(), documentId);

    final undo = await apply(
      planImagesChange(
        existing: existing,
        change: ProcessedChange.replace,
        chosen: [source('c.jpg'), source('b.jpg')],
      ),
    );

    expect(await gallery(), ['0:c.jpg', '1:b.jpg']);
    final trash = await db().select(db().trashedContents).get();
    expect(trash, hasLength(1));
    expect(trash.single.id, undo.trashed.single);
    expect(trash.single.kind, TrashedContentKind.file);
    expect(trash.single.itemId, documentId);
    expect(trash.single.relativePath, existing.first.relativePath);
    expect(trash.single.renditionKind, RenditionKind.image);
    expect(trash.single.processedImage, isNotNull);
  });

  test('deshacer deja la galería como estaba: lo nuevo sale, lo que se fue '
      'vuelve y cada una a su lugar, y dice qué archivos borrar', () async {
    await apply(
      planImagesChange(
        existing: const [],
        change: ProcessedChange.add,
        chosen: [source('a.jpg'), source('b.jpg')],
      ),
    );
    final before = await processedImagesOf(db(), documentId);
    final undo = await apply(
      planImagesChange(
        existing: before,
        change: ProcessedChange.replace,
        chosen: [source('c.jpg'), source('b.jpg')],
      ),
    );

    final files = await db().transaction(() => undoProcessedImages(db(), undo));

    expect(await processedImagesOf(db(), documentId), before);
    expect(files, [staged(source('c.jpg')).relativePath]);
    expect(await db().select(db().trashedContents).get(), isEmpty);
  });

  test('quitar una y recuperarla la devuelve a su lugar, corriendo las '
      'demás', () async {
    await apply(
      planImagesChange(
        existing: const [],
        change: ProcessedChange.add,
        chosen: [source('a.jpg'), source('b.jpg'), source('c.jpg')],
      ),
    );
    final before = await processedImagesOf(db(), documentId);
    final b = before[1];

    final trashedId = await db().transaction(() async {
      final id = await trashProcessedImage(
        db(),
        renditionId: b.renditionId,
        ids: ids,
        at: h.vault.now,
      );
      await shiftProcessedImages(db(), b, by: -1);
      return id;
    });
    expect(await gallery(), ['0:a.jpg', '1:c.jpg']);

    final row = await (db().select(
      db().trashedContents,
    )..where((t) => t.id.equals(trashedId))).getSingle();
    final restored = await db().transaction(
      () => restoreTrashedProcessedImage(db(), row),
    );

    expect(restored, b);
    expect(await processedImagesOf(db(), documentId), before);
    expect(await db().select(db().trashedContents).get(), isEmpty);
  });

  test('no se recupera lo que el documento ya volvió a tener', () async {
    await apply(
      planImagesChange(
        existing: const [],
        change: ProcessedChange.add,
        chosen: [source('a.jpg')],
      ),
    );
    final a = (await processedImagesOf(db(), documentId)).single;
    final trashedId = await db().transaction(
      () => trashProcessedImage(
        db(),
        renditionId: a.renditionId,
        ids: ids,
        at: h.vault.now,
      ),
    );
    // Se volvió a triar con la misma imagen: tiene otra copia.
    await apply(
      planImagesChange(
        existing: const [],
        change: ProcessedChange.add,
        chosen: [source('a.jpg')],
      ),
    );
    final row = await (db().select(
      db().trashedContents,
    )..where((t) => t.id.equals(trashedId))).getSingle();

    expect(
      await db().transaction(() => restoreTrashedProcessedImage(db(), row)),
      isNull,
    );
    expect(await gallery(), ['0:a.jpg']);
  });

  test('los tramos de la galería', () async {
    await apply(
      planImagesChange(
        existing: const [],
        change: ProcessedChange.add,
        chosen: [for (var i = 0; i < 5; i++) source('f$i.jpg')],
      ),
    );

    final page = await processedImagesOf(db(), documentId, offset: 2, limit: 2);
    expect([for (final i in page) i.position], [2, 3]);
  });

  test('borrar la forma se lleva la fila de la imagen; borrar el documento, '
      'todo', () async {
    await apply(
      planImagesChange(
        existing: const [],
        change: ProcessedChange.add,
        chosen: [source('a.jpg'), source('b.jpg')],
      ),
    );
    final first = (await processedImagesOf(db(), documentId)).first;
    await (db().delete(
      db().renditions,
    )..where((r) => r.id.equals(first.renditionId))).go();
    expect(await gallery(), ['1:b.jpg']);

    await h.vault.writer.trash([documentId]);
    await h.vault.writer.purge(documentId);
    expect(await db().select(db().processedImages).get(), isEmpty);
  });
}
