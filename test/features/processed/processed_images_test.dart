import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/content_trash/data/repositories/content_trash_repository_impl.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_images_store.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

import 'processed_harness.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// El repositorio de siempre, salvo que el guardado nunca llega: el documento
/// cambió mientras se copiaban las imágenes.
class _FailingCommit extends ProcessedRepositoryImpl {
  _FailingCommit(ProcessedHarness h)
    : super(database: h.db, telemetry: _SilentTelemetry(), files: h.files);

  @override
  Future<Either<Failure, ProcessUndo>> commit(ProcessedCommit commit) async =>
      left(const Failure.validation(message: 'Cambió mientras tanto.'));
}

/// Las imágenes en Procesado (F41, decisión L): elegidas una por una, cada una
/// una copia propia que viaja con el documento, y la fuente intacta.
void main() {
  late ProcessedHarness h;
  final docId = processedDocumentIdFor('post');
  late List<String> photos;

  /// Una publicación con su primera foto como archivo y dos más en su
  /// «Contenido» (F30), sin texto: una foto no tiene letras.
  Future<void> savePost() async {
    final own = await h.files.save(
      bytes: Uint8List(100),
      suggestedName: 'post.jpg',
      id: 'post',
    );
    final at = h.vault.now;
    await h.vault.writer.upsert(
      KnowledgeItem(
        id: 'post',
        title: 'Una publicación',
        source: Source(
          id: 'post',
          kind: SourceKind.socialPost,
          capturedAt: at,
          originalFilePath: own,
        ),
        processingState: ProcessingState.ready,
        createdAt: at,
        updatedAt: at,
      ),
    );
    photos = [own];
    for (final (index, name) in ['b.jpg', 'c.jpg'].indexed) {
      final path = await h.files.saveStream(
        bytes: Stream.value(List.filled(10 * (index + 1), 1)),
        suggestedName: name,
        id: 'post',
        folder: 'contenido',
      );
      await h.db
          .into(h.db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'foto-$name',
              itemId: 'post',
              kind: RenditionKind.image,
              relativePath: Value(path),
              isPrimary: false,
              createdAt: at,
              position: Value(index + 1),
              sizeBytes: Value(10 * (index + 1)),
              title: Value('Foto $name'),
            ),
          );
      photos.add(path);
    }
  }

  setUp(() async {
    h = await ProcessedHarness.create();
    await savePost();
  });
  tearDown(() => h.close());

  SectionEdit add(ImageChoice choice) =>
      SectionEdit.add(SectionInput.images(choice));

  Future<List<ProcessedImage>> gallery() async =>
      (await h.repository.imagesOf(docId)).getRight().toNullable()!;

  /// Las copias que hay en el disco, en la carpeta del procesado: las de sus
  /// imágenes, relativas al almacén.
  Future<List<String>> copies() async {
    final folder = Directory(
      p.join(h.vault.docs.path, 'originales', docId, kProcessedImagesFolder),
    );
    if (!folder.existsSync()) return const [];
    return [
      for (final entity in folder.listSync(recursive: true))
        if (entity is File)
          p.posix.joinAll(
            p.split(p.relative(entity.path, from: h.vault.docs.path)),
          ),
    ]..sort();
  }

  test('lo que ofrece la fuente: cuántas imágenes y cuánto pesan', () async {
    final material = (await h.repository.materialOf(
      'post',
    )).getRight().toNullable()!;

    expect(
      material.images,
      const SourceImagesSummary(count: 3, sizeBytes: 130),
    );
    expect(material.hasText, isFalse);
  });

  test('elegir algunas crea el documento con su copia propia de cada una, '
      'en el orden de la fuente, sin tocar la fuente', () async {
    final before = await h.sourceSnapshot('post');

    final outcome = (await h.process('post', {
      ProcessedSection.images: add(ImageChoice.only({photos[2], photos[0]})),
    })).getRight().toNullable()!;

    expect(outcome.created, isTrue);
    expect(outcome.sections[ProcessedSection.images]?.added, 2);
    final images = await gallery();
    expect([for (final i in images) i.sourceFilePath], [photos[0], photos[2]]);
    expect([for (final i in images) i.position], [0, 1]);
    expect(images[1].title, 'Foto c.jpg');
    expect(images[1].sizeBytes, 20);
    expect(await copies(), hasLength(2));
    for (final image in images) {
      expect(image.relativePath, startsWith('originales/$docId/imagenes/'));
      expect(image.relativePath, isNot(image.sourceFilePath));
      expect(await h.files.read(image.relativePath), isNotNull);
    }
    expect(await h.sourceSnapshot('post'), before);

    final summary = (await h.repository.watchDocument(docId).first)!;
    expect(summary.summary.partCounts, {ProcessedSection.images: 2});
    expect(summary.stats[ProcessedSection.images]?.parts, 2);
  });

  test('«Todas» lleva todo lo que ofrece la fuente, menos lo que se sacó de '
      'a una', () async {
    await h.process('post', {
      ProcessedSection.images: add(ImageChoice.all(except: {photos[1]})),
    });

    expect(
      [for (final i in await gallery()) i.sourceFilePath],
      [photos[0], photos[2]],
    );
  });

  test('la vista previa dice cuántas van y lo que va a ocupar, sin copiar '
      'nada', () async {
    final previews = (await h.process.preview('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
    })).getRight().toNullable()!;

    final preview = previews[ProcessedSection.images]!;
    expect(preview.parts, 3);
    expect(preview.words, 0);
    expect(preview.sizeBytes, 130);
    expect(preview.addedBytes, 130);
    expect(await copies(), isEmpty);
  });

  test('ninguna elegida no se pide', () async {
    final result = await h.process('post', {
      ProcessedSection.images: add(ImageChoice.none),
    });

    expect(result.getLeft().toNullable(), isA<Failure>());
    expect(await copies(), isEmpty);
  });

  test('una imagen que no es de la fuente no entra', () async {
    final result = await h.process('post', {
      ProcessedSection.images: add(const ImageChoice.only({'otra/foto.jpg'})),
    });

    expect(result.isLeft(), isTrue);
    expect(
      (await h.repository.statusOf(docId)).toNullable(),
      ProcessedDocumentStatus.absent,
    );
    expect(await copies(), isEmpty);
  });

  test('si una elegida ya no está en el teléfono, no se copia ninguna y no '
      'se guarda nada', () async {
    await h.files.delete(photos[2]);

    final result = await h.process('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
    });

    expect(result.isLeft(), isTrue);
    expect(await copies(), isEmpty);
    expect(await h.db.select(h.db.processedImages).get(), isEmpty);
  });

  test('si el guardado no llega, las copias hechas se borran', () async {
    final failing = ProcessSourceUseCase(_FailingCommit(h));

    final result = await failing('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
    });

    expect(result.isLeft(), isTrue);
    expect(await copies(), isEmpty);
  });

  test('deshacer saca las imágenes y borra sus copias del disco', () async {
    final outcome = (await h.process('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
    })).getRight().toNullable()!;
    expect(await copies(), hasLength(3));

    expect((await h.process.undo(outcome.undo)).isRight(), isTrue);

    expect(await copies(), isEmpty);
    expect(await h.db.select(h.db.processedImages).get(), isEmpty);
  });

  test('volver a triar: agregar no copia dos veces la misma; reemplazar deja '
      'lo elegido y lo demás va a la papelera del contenido; deshacer lo '
      'devuelve todo', () async {
    await h.process('post', {
      ProcessedSection.images: add(ImageChoice.only({photos[0], photos[1]})),
    });
    final first = await gallery();

    final again = (await h.process('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
    })).getRight().toNullable()!;
    expect(again.sections[ProcessedSection.images]?.added, 1);
    expect(again.sections[ProcessedSection.images]?.kept, 2);
    expect(await copies(), hasLength(3));

    final replaced = (await h.process('post', {
      ProcessedSection.images: SectionEdit.replace(
        SectionInput.images(ImageChoice.only({photos[1]})),
      ),
    })).getRight().toNullable()!;
    expect([for (final i in await gallery()) i.sourceFilePath], [photos[1]]);
    expect(replaced.sections[ProcessedSection.images]?.removed, 2);
    // Las que salieron no se borran: esperan en la papelera del contenido.
    expect(await copies(), hasLength(3));
    expect(await h.db.select(h.db.trashedContents).get(), hasLength(2));

    await h.process.undo(replaced.undo);
    await h.process.undo(again.undo);
    expect(await gallery(), first);
    expect(await h.db.select(h.db.trashedContents).get(), isEmpty);
    expect(await copies(), hasLength(2));
  });

  test('quitar la sección entera, con deshacer', () async {
    await h.process('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
      ProcessedSection.notes: SectionEdit.add(
        const SectionInput.drafts([ProcessedDraft.written('Una nota')]),
      ),
    });
    final before = await gallery();

    final removed = (await h.process('post', {
      ProcessedSection.images: SectionEdit.remove(),
    })).getRight().toNullable()!;
    expect(await gallery(), isEmpty);

    await h.process.undo(removed.undo);
    expect(await gallery(), before);
  });

  test('quitar una de la galería corre las demás, y «Deshacer» la devuelve '
      'a su lugar', () async {
    await h.process('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
    });
    final before = await gallery();

    final removal = (await h.repository.removeImage(
      before[1].renditionId,
    )).getRight().toNullable()!;
    expect([for (final i in await gallery()) i.position], [0, 1]);
    expect(
      [for (final i in await gallery()) i.renditionId],
      [before[0].renditionId, before[2].renditionId],
    );
    // La copia sigue en el disco, en la papelera del contenido.
    expect(await h.files.read(before[1].relativePath), isNotNull);

    expect((await h.repository.restoreImage(removal)).isRight(), isTrue);
    expect(await gallery(), before);
    expect(
      (await h.repository.restoreImage(removal)).isLeft(),
      isTrue,
      reason: 'ya volvió: no se puede devolver dos veces',
    );
  });

  test('la papelera del contenido recupera una imagen quitada en su '
      'galería, no como el archivo de la fuente', () async {
    await h.process('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
    });
    final before = await gallery();
    final removal = (await h.repository.removeImage(
      before[0].renditionId,
    )).getRight().toNullable()!;
    final trash = ContentTrashRepositoryImpl(
      database: h.db,
      files: h.files,
      telemetry: _SilentTelemetry(),
    );

    final restored = await trash.restore(removal.trashedId);

    expect(restored.getRight().toNullable(), ContentRestoreOutcome.restored);
    expect(await gallery(), before);
    final source = await (h.db.select(
      h.db.knowledgeSources,
    )..where((s) => s.itemId.equals('post'))).getSingle();
    expect(source.originalBlobPath, photos[0]);
  });

  test('las imágenes viajan con el documento a la papelera y vuelven; '
      'borrarlo de verdad borra sus copias, y la fuente queda', () async {
    await h.process('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
    });
    final library = LibraryRepositoryImpl(
      database: h.db,
      telemetry: _SilentTelemetry(),
      files: h.files,
      clock: () => h.vault.now,
    );

    await library.deleteMany([docId]);
    expect(await gallery(), hasLength(3));
    await library.restoreMany([docId]);
    expect(await gallery(), hasLength(3));

    await library.deleteMany([docId]);
    await library.purge([docId]);
    expect(await copies(), isEmpty);
    for (final photo in photos) {
      expect(await h.files.read(photo), isNotNull, reason: photo);
    }
  });

  test('soltar el archivo de la fuente no toca la copia', () async {
    await h.process('post', {
      ProcessedSection.images: add(ImageChoice.only({photos[0]})),
    });
    final trash = ContentTrashRepositoryImpl(
      database: h.db,
      files: h.files,
      telemetry: _SilentTelemetry(),
    );

    await trash.keepOnlyText('post');

    final image = (await gallery()).single;
    expect(await h.files.read(image.relativePath), isNotNull);
  });

  test('el filtro «qué partes tiene» encuentra las imágenes', () async {
    await h.process('post', {
      ProcessedSection.images: add(const ImageChoice.all()),
    });

    final withImages = await h.repository.matchingIds(
      const ProcessedQuery(sections: {ProcessedSection.images}),
    );
    final withNotes = await h.repository.matchingIds(
      const ProcessedQuery(sections: {ProcessedSection.notes}),
    );
    final either = await h.repository.matchingIds(
      const ProcessedQuery(
        sections: {ProcessedSection.notes, ProcessedSection.images},
      ),
    );

    expect(withImages.getRight().toNullable(), [docId]);
    expect(withNotes.getRight().toNullable(), isEmpty);
    expect(either.getRight().toNullable(), [docId]);
  });

  test('la copia vive en la carpeta de imágenes del procesado', () {
    expect(kProcessedImagesFolder, 'imagenes');
  });
}
