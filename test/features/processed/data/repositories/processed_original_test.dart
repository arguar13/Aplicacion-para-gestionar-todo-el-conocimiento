import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Order;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/file_references.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/content_trash/data/repositories/content_trash_repository_impl.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

import '../../processed_harness.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// El repositorio de siempre, salvo que guardar falla: como si el disco se
/// llenara entre copiar el original y guardar.
class _FailingCommit implements ProcessedRepository {
  _FailingCommit(this._inner);

  final ProcessedRepository _inner;

  /// La copia que se llegó a hacer antes de guardar.
  StagedOriginal? staged;

  @override
  Future<Either<Failure, ProcessUndo>> commit(ProcessedCommit commit) async =>
      left(const Failure.unexpected(message: 'el disco se llenó'));

  @override
  Future<Either<Failure, StagedOriginal>> stageOriginal(
    String sourceItemId,
  ) async {
    final result = await _inner.stageOriginal(sourceItemId);
    staged = result.getRight().toNullable();
    return result;
  }

  @override
  Future<void> discardStagedOriginal(StagedOriginal staged) =>
      _inner.discardStagedOriginal(staged);

  @override
  Future<Either<Failure, ProcessedSourceMaterial>> materialOf(
    String sourceItemId, {
    bool countWords = true,
  }) => _inner.materialOf(sourceItemId, countWords: countWords);

  @override
  Future<Either<Failure, ProcessedDocumentStatus>> statusOf(
    String documentId,
  ) => _inner.statusOf(documentId);

  @override
  Future<Either<Failure, ProcessedOriginal?>> originalOf(String documentId) =>
      _inner.originalOf(documentId);

  @override
  Future<Either<Failure, ProcessedSourceText?>> sourceText(
    String sourceItemId, {
    String? renditionId,
  }) => _inner.sourceText(sourceItemId, renditionId: renditionId);

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Ids implements IdGenerator {
  var _n = 0;
  @override
  String next() => 'papelera-${_n++}';
}

/// La copia del original en un documento procesado (F41, decisión H): un
/// archivo propio, con su papelera, su deshacer y lo elegido marcado sobre él.
void main() {
  const text = 'El Senado de Roma. Cartago debe ser destruida. Fin.';
  const pdfBytes = '%PDF-1.4 un pdf de prueba';
  late ProcessedHarness h;
  final docId = processedDocumentIdFor('libro');

  /// Un documento con su PDF y su texto, como lo deja la captura.
  Future<void> saveDocument(
    String id, {
    String name = 'libro.pdf',
    String bytes = pdfBytes,
    SourceKind kind = SourceKind.document,
  }) async {
    final path = 'originales/$id/$name';
    await h.vault.writeOriginal(path, bytes);
    final at = h.vault.now;
    await h.vault.library.save(
      KnowledgeItem(
        id: id,
        title: 'El libro',
        source: Source(
          id: id,
          kind: kind,
          capturedAt: at,
          originalFilePath: path,
        ),
        processingState: ProcessingState.ready,
        createdAt: at,
        updatedAt: at,
        renditions: [
          Rendition.text(
            id: 'rend-$id',
            itemId: id,
            kind: RenditionKind.plainText,
            content: text,
            isPrimary: true,
            createdAt: at,
          ),
        ],
      ),
    );
  }

  setUp(() async {
    h = await ProcessedHarness.create();
    await saveDocument('libro');
  });
  tearDown(() => h.close());

  Future<ProcessOutcome> process(
    ProcessedChange change, {
    Map<ProcessedSection, SectionEdit> edits = const {},
  }) async {
    final result = await h.process(
      'libro',
      edits,
      original: OriginalEdit(change),
    );
    return result.getRight().toNullable() ??
        (throw StateError('falló: ${result.getLeft().toNullable()}'));
  }

  Future<ProcessedOriginal?> original() async =>
      (await h.repository.originalOf(docId)).getRight().toNullable();

  File fileOf(String relativePath) =>
      File(p.join(h.vault.docs.path, p.joinAll(p.posix.split(relativePath))));

  group('lo que ofrece la fuente', () {
    test(
      'un documento: su archivo, cuánto ocupa y en qué visor se abre',
      () async {
        final material = (await h.repository.materialOf(
          'libro',
        )).getRight().toNullable()!;

        expect(material.original?.relativePath, 'originales/libro/libro.pdf');
        expect(material.original?.sizeBytes, pdfBytes.length);
        expect(material.original?.kind, RenditionKind.pdf);
      },
    );

    test('un Word, un EPUB o un texto se abren en el lector; una página '
        'archivada, en el visor de páginas', () async {
      await saveDocument('word', name: 'notas.txt', bytes: 'texto plano');
      await saveDocument(
        'pagina',
        name: 'pagina.html',
        bytes: '<html></html>',
        kind: SourceKind.webPage,
      );

      Future<RenditionKind?> kindOf(String id) async =>
          (await h.repository.materialOf(
            id,
          )).getRight().toNullable()!.original?.kind;

      expect(await kindOf('word'), RenditionKind.document);
      expect(await kindOf('pagina'), RenditionKind.html);
    });

    test('un audio, una nota o un documento sin su archivo no ofrecen '
        'ninguno', () async {
      await saveDocument('audio', name: 'voz.m4a', kind: SourceKind.audio);
      await saveDocument('sinarchivo');
      await fileOf('originales/sinarchivo/libro.pdf').delete();

      for (final id in ['audio', 'sinarchivo']) {
        expect(
          (await h.repository.materialOf(id)).getRight().toNullable()!.original,
          isNull,
          reason: id,
        );
      }
      final result = await h.process(
        'audio',
        const {},
        original: const OriginalEdit(ProcessedChange.add),
      );
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await h.db.select(h.db.processedDocuments).get(), isEmpty);
    });
  });

  group('copiarlo', () {
    test(
      'agregar copia el archivo como una forma propia del procesado',
      () async {
        final outcome = await process(ProcessedChange.add);

        expect(outcome.created, isTrue);
        expect(outcome.original, OriginalOutcome.copied);
        final copy = (await original())!;
        expect(copy.renditionId, processedOriginalRenditionIdFor(docId));
        expect(copy.relativePath, 'originales/$docId/original/libro.pdf');
        expect(copy.kind, RenditionKind.pdf);
        expect(copy.sizeBytes, pdfBytes.length);
        expect(copy.sourceFilePath, 'originales/libro/libro.pdf');
        expect(fileOf(copy.relativePath).readAsStringSync(), pdfBytes);
        expect(await isFileReferenced(h.db, copy.relativePath), isTrue);
        final summary =
            (await h.repository.watchDocuments(const ProcessedQuery()).first)
                .single;
        expect(summary.hasOriginal, isTrue);
        expect(summary.isEmpty, isFalse);
        expect(
          await h.repository
              .watchDocuments(const ProcessedQuery(withOriginal: true))
              .first,
          hasLength(1),
        );
      },
    );

    test('agregar de nuevo no copia otra vez', () async {
      await process(ProcessedChange.add);

      final again = await process(ProcessedChange.add);

      expect(again.original, OriginalOutcome.untouched);
      expect(again.unchanged, isTrue);
      expect(
        Directory(
          p.join(h.vault.docs.path, 'originales', docId, 'original'),
        ).listSync(),
        hasLength(1),
      );
    });

    test('actualizar con el mismo archivo no copia; con otro, sí', () async {
      await process(ProcessedChange.add);
      expect(
        (await process(ProcessedChange.update)).original,
        OriginalOutcome.untouched,
      );

      // Se le adjunta otro archivo a la fuente: otra ruta.
      await h.vault.writeOriginal('originales/libro/libro-2.pdf', '%PDF-2.0');
      await h.vault.writer.setFieldFromText(
        'libro',
        'originalBlobPath',
        'originales/libro/libro-2.pdf',
      );
      final updated = await process(ProcessedChange.update);

      expect(updated.original, OriginalOutcome.copied);
      final copy = (await original())!;
      expect(copy.sourceFilePath, 'originales/libro/libro-2.pdf');
      expect(fileOf(copy.relativePath).readAsStringSync(), '%PDF-2.0');
      // La de antes, a la papelera del contenido del procesado.
      final trashed = await h.db.select(h.db.trashedContents).getSingle();
      expect(trashed.itemId, docId);
      expect(trashed.kind, TrashedContentKind.file);
      expect(trashed.relativePath, 'originales/$docId/original/libro.pdf');
    });

    test(
      'actualizar con el texto vuelto a extraer solo anota el texto',
      () async {
        await process(ProcessedChange.add);
        await (h.db.update(h.db.knowledgeSources)
              ..where((s) => s.itemId.equals('libro')))
            .write(const KnowledgeSourcesCompanion(contentHash: Value('otro')));

        final updated = await process(ProcessedChange.update);

        expect(updated.original, OriginalOutcome.refreshed);
        final row = await h.db.select(h.db.processedOriginals).getSingle();
        expect(row.textHash, 'otro');
        expect(await h.db.select(h.db.trashedContents).get(), isEmpty);
      },
    );

    test(
      'quitar la manda a la papelera del contenido, de donde vuelve',
      () async {
        await process(ProcessedChange.add);
        final path = (await original())!.relativePath;

        final removed = await process(ProcessedChange.remove);

        expect(removed.original, OriginalOutcome.removed);
        expect(await original(), isNull);
        expect(fileOf(path).existsSync(), isTrue);
        final trash = ContentTrashRepositoryImpl(
          database: h.db,
          files: h.files,
          telemetry: _SilentTelemetry(),
          clock: () => h.vault.now,
        );
        final trashed = (await trash.watchOf(docId).first).single;

        expect(
          (await trash.restore(trashed.id)).getRight().toNullable(),
          ContentRestoreOutcome.restored,
        );
        expect((await original())?.relativePath, path);
        expect(await h.db.select(h.db.trashedContents).get(), isEmpty);
      },
    );

    test('si guardar falla después de copiar, la copia se borra', () async {
      final repository = _FailingCommit(h.repository);

      final result = await ProcessSourceUseCase(repository)(
        'libro',
        const {},
        original: const OriginalEdit(ProcessedChange.add),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.staged, isNotNull);
      expect(fileOf(repository.staged!.relativePath).existsSync(), isFalse);
    });

    test('recuperar la de la papelera no pisa la que hay ahora', () async {
      await process(ProcessedChange.add);
      await process(ProcessedChange.remove);
      await process(ProcessedChange.add);
      final now = (await original())!;
      final trash = ContentTrashRepositoryImpl(
        database: h.db,
        files: h.files,
        telemetry: _SilentTelemetry(),
        clock: () => h.vault.now,
      );
      final trashed = (await trash.watchOf(docId).first).single;

      expect(
        (await trash.restore(trashed.id)).getRight().toNullable(),
        ContentRestoreOutcome.alreadyHasFile,
      );
      expect(await original(), now);
    });

    test('una copia que no llegó a guardarse se borra', () async {
      final staged = (await h.repository.stageOriginal(
        'libro',
      )).getRight().toNullable()!;
      await h.repository.discardStagedOriginal(staged);

      expect(fileOf(staged.relativePath).existsSync(), isFalse);
    });
  });

  group('la vista previa: qué pasaría, sin copiar nada', () {
    Future<(OriginalOutcome, int)> preview(ProcessedChange change) async {
      final result = await h.process.previewOriginal(
        'libro',
        OriginalEdit(change),
      );
      final preview = result.getRight().toNullable()!;
      return (preview.outcome, preview.sizeBytes);
    }

    test('sin copia: agregar copiaría lo que ocupa el archivo; quitar, '
        'nada', () async {
      expect(await preview(ProcessedChange.add), (
        OriginalOutcome.copied,
        pdfBytes.length,
      ));
      expect(await preview(ProcessedChange.remove), (
        OriginalOutcome.untouched,
        0,
      ));
      expect(await h.db.select(h.db.processedOriginals).get(), isEmpty);
      expect(await h.db.select(h.db.renditions).get(), hasLength(1));
    });

    test('con copia: agregar la deja, quitar la saca, actualizar con el mismo '
        'archivo solo anota el texto', () async {
      await process(ProcessedChange.add);

      expect(await preview(ProcessedChange.add), (
        OriginalOutcome.untouched,
        pdfBytes.length,
      ));
      expect(await preview(ProcessedChange.remove), (
        OriginalOutcome.removed,
        0,
      ));
      expect(await preview(ProcessedChange.update), (
        OriginalOutcome.refreshed,
        pdfBytes.length,
      ));
      expect(await preview(ProcessedChange.replace), (
        OriginalOutcome.copied,
        pdfBytes.length,
      ));
    });
  });

  group('deshacer', () {
    test('una copia que nació se va con su archivo', () async {
      final outcome = await process(ProcessedChange.add);
      final path = (await original())!.relativePath;

      await h.process.undo(outcome.undo);

      expect(await h.db.select(h.db.processedDocuments).get(), isEmpty);
      expect(fileOf(path).existsSync(), isFalse);
    });

    test('reemplazar se deshace: vuelve la copia de antes', () async {
      await process(
        ProcessedChange.add,
        edits: {ProcessedSection.text: SectionEdit.update()},
      );
      final before = (await original())!;
      final replaced = await process(ProcessedChange.replace);
      final newPath = (await original())!.relativePath;
      expect(newPath, isNot(before.relativePath));

      await h.process.undo(replaced.undo);

      final back = (await original())!;
      expect(back.relativePath, before.relativePath);
      expect(back.copiedAt, before.copiedAt);
      expect(fileOf(newPath).existsSync(), isFalse);
      expect(await h.db.select(h.db.trashedContents).get(), isEmpty);
    });

    test('quitar se deshace', () async {
      await process(
        ProcessedChange.add,
        edits: {ProcessedSection.text: SectionEdit.update()},
      );
      final removed = await process(ProcessedChange.remove);

      await h.process.undo(removed.undo);

      expect(await original(), isNotNull);
      expect(await h.db.select(h.db.trashedContents).get(), isEmpty);
    });
  });

  test(
    'soltar el archivo de la fuente no toca la copia, ni al revés',
    () async {
      await process(
        ProcessedChange.add,
        edits: {ProcessedSection.text: SectionEdit.update()},
      );
      final copy = (await original())!;
      final trash = ContentTrashRepositoryImpl(
        database: h.db,
        files: h.files,
        telemetry: _SilentTelemetry(),
        ids: _Ids(),
        clock: () => h.vault.now,
      );

      await trash.keepOnlyText('libro');
      expect(await original(), copy);
      expect(fileOf(copy.relativePath).existsSync(), isTrue);

      await process(ProcessedChange.remove);
      final source = await (h.db.select(
        h.db.knowledgeSources,
      )..where((s) => s.itemId.equals('libro'))).getSingle();
      expect(source.originalBlobPath, isNull, reason: 'lo soltó la persona');
      expect(fileOf('originales/libro/libro.pdf').existsSync(), isTrue);
    },
  );

  test(
    'borrar de verdad el procesado borra su copia, y no la de la fuente',
    () async {
      await process(
        ProcessedChange.add,
        edits: {ProcessedSection.text: SectionEdit.update()},
      );
      final copy = (await original())!;
      final library = LibraryRepositoryImpl(
        database: h.db,
        telemetry: _SilentTelemetry(),
        files: h.files,
        clock: () => h.vault.now,
      );

      await library.delete(docId);
      await library.purge([docId]);

      expect(fileOf(copy.relativePath).existsSync(), isFalse);
      expect(fileOf('originales/libro/libro.pdf').existsSync(), isTrue);
    },
  );

  group('lo elegido, marcado sobre la copia', () {
    setUp(() async {
      await h.addSentence('s1', 'libro', text, start: 0, end: 18);
      await h.addSentence(
        'k1',
        'libro',
        text,
        start: 3,
        end: 9,
        kind: StudyMarkKind.keyword,
      );
      await chunkAndPersistSource(h.db, itemId: 'libro', ids: _Ids());
    });

    test('el resumen, las palabras clave y los fragmentos, en las posiciones '
        'de la fuente', () async {
      await process(
        ProcessedChange.add,
        edits: {
          ProcessedSection.summary: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
          ProcessedSection.keywords: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
          ProcessedSection.fragments: SectionEdit.add(
            const SectionInput.drafts([
              ProcessedDraft.cut(
                ProcessedAnchor(renditionId: 'rend-libro', start: 19, end: 46),
              ),
            ]),
          ),
        },
      );

      final marks = (await h.repository.watchOriginalMarks(docId).first)!;

      expect(marks.sourceKey, 'rend-libro');
      expect(marks.study.marks.map((m) => (m.kind, m.start, m.end)), [
        (StudyMarkKind.summary, 0, 18),
        (StudyMarkKind.keyword, 3, 9),
      ]);
      expect(marks.fragments, const [ProcessedSpan(start: 19, end: 46)]);
    });

    test(
      'si el texto de la fuente ya no es el de la copia, no se pinta nada',
      () async {
        await process(
          ProcessedChange.add,
          edits: {
            ProcessedSection.summary: SectionEdit.add(
              const SectionInput.fromSource(),
            ),
          },
        );
        expect(await h.repository.watchOriginalMarks(docId).first, isNotNull);

        await (h.db.update(h.db.knowledgeSources)
              ..where((s) => s.itemId.equals('libro')))
            .write(const KnowledgeSourcesCompanion(contentHash: Value('otro')));

        expect(await h.repository.watchOriginalMarks(docId).first, isNull);
      },
    );

    test('lo editado ya no es la letra del original: no se pinta', () async {
      await process(
        ProcessedChange.add,
        edits: {
          ProcessedSection.summary: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
        },
      );
      final summary = (await h.repository.partsOf(
        docId,
        sections: {ProcessedSection.summary},
      )).getRight().toNullable()!.single;

      await h.repository.editPart(summary.id, 'Otra cosa.');

      final marks = (await h.repository.watchOriginalMarks(docId).first)!;
      expect(marks.study.marks, isEmpty);
    });

    test('sin copia, nada que pintar', () async {
      await h.process('libro', {ProcessedSection.text: SectionEdit.update()});

      expect(await h.repository.watchOriginalMarks(docId).first, isNull);
    });
  });
}
