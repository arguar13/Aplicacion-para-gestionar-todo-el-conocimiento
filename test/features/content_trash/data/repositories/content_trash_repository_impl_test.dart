import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/content_trash/data/repositories/content_trash_repository_impl.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// La papelera del contenido (F30, decisión 68) contra SQLite real, en
/// memoria: soltar el archivo o el texto de un libro, recuperarlo, y que a
/// los 30 días se borre de verdad —y no antes—.
void main() {
  late AppDatabase db;
  late InMemoryFileStore files;
  late LibraryRepositoryImpl library;
  late ContentTrashRepositoryImpl trash;
  var clockNow = DateTime(2026, 10, 5, 10);
  final captured = DateTime(2026, 10, 1, 9);

  setUp(() {
    clockNow = DateTime(2026, 10, 5, 10);
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    files = InMemoryFileStore();
    final telemetry = MockTelemetryService();
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: telemetry,
      files: files,
    );
    trash = ContentTrashRepositoryImpl(
      database: db,
      files: files,
      telemetry: telemetry,
      clock: () => clockNow,
    );
  });

  tearDown(() => db.close());

  const text = 'Roma no se hizo en un día. Tardó siglos en hacerse imperio.';

  /// Un libro guardado con su archivo y su texto, como lo deja la cola.
  Future<String> saveBook(String id, {String? text = text}) async {
    final path = await files.save(
      bytes: Uint8List.fromList(List.filled(2048, 7)),
      suggestedName: '$id.pdf',
      id: id,
    );
    final saved = await library.save(
      KnowledgeItem(
        id: id,
        title: 'Historia de Roma',
        source: Source(
          id: id,
          kind: SourceKind.document,
          capturedAt: captured,
          originalFilePath: path,
        ),
        processingState: ProcessingState.ready,
        createdAt: captured,
        updatedAt: captured,
        renditions: [
          if (text != null)
            Rendition.text(
              id: '$id-texto',
              itemId: id,
              kind: RenditionKind.plainText,
              content: text,
              isPrimary: true,
              createdAt: captured,
            ),
        ],
      ),
    );
    expect(saved.isRight(), isTrue);
    return id;
  }

  Future<KnowledgeSourceRow> sourceOf(String id) => (db.select(
    db.knowledgeSources,
  )..where((s) => s.itemId.equals(id))).getSingle();

  Future<List<RenditionRow>> renditionsOf(String id) =>
      (db.select(db.renditions)..where((r) => r.itemId.equals(id))).get();

  Future<int> chunksOf(String id) async => (await (db.select(
    db.chunks,
  )..where((c) => c.itemId.equals(id))).get()).length;

  Future<void> highlight(String renditionId) => db
      .into(db.highlights)
      .insert(
        HighlightsCompanion.insert(
          id: 'subrayado',
          renditionId: renditionId,
          startOffset: 0,
          endOffset: 4,
          excerpt: 'Roma',
          note: const Value('La ciudad'),
          createdAt: captured,
        ),
      );

  group('solo el texto: el archivo a la papelera', () {
    test('la fuente deja de apuntarle, pero el archivo sigue en el disco y '
        'el texto queda', () async {
      final id = await saveBook('libro');
      final path = (await sourceOf(id)).originalBlobPath!;

      final result = await trash.keepOnlyText(id);

      final trashed = result.getOrElse((f) => fail('$f')).single;
      expect(trashed.kind, TrashedContentKind.file);
      expect(trashed.sizeBytes, 2048);
      expect(trashed.expiresAt, clockNow.add(const Duration(days: 30)));
      expect((await sourceOf(id)).originalBlobPath, isNull);
      expect(files.paths, contains(path));
      expect(files.deleted, isEmpty);
      expect((await renditionsOf(id)).single.content, text);
      // Es un campo con linaje: una fusión tiene que saber que acá se soltó.
      final version =
          await (db.select(db.fieldVersions)..where(
                (f) =>
                    f.itemId.equals(id) &
                    f.fieldName.equals(EntryField.originalBlobPath),
              ))
              .getSingle();
      expect(version.deviceId, 'telefono');
    });

    test(
      'sin texto no se suelta el archivo: el elemento quedaría vacío',
      () async {
        final id = await saveBook('sin-texto', text: null);

        final result = await trash.keepOnlyText(id);

        expect(result.isLeft(), isTrue);
        expect((await sourceOf(id)).originalBlobPath, isNotNull);
        expect(await db.select(db.trashedContents).get(), isEmpty);
      },
    );

    test('recuperar el archivo vuelve a apuntarle', () async {
      final id = await saveBook('libro');
      final path = (await sourceOf(id)).originalBlobPath!;
      final trashed = (await trash.keepOnlyText(
        id,
      )).getOrElse((f) => fail('$f'));

      final outcome = await trash.restore(trashed.single.id);

      expect(
        outcome.getOrElse((f) => fail('$f')),
        ContentRestoreOutcome.restored,
      );
      expect((await sourceOf(id)).originalBlobPath, path);
      expect(await db.select(db.trashedContents).get(), isEmpty);
    });

    test('si el archivo ya no estaba, lo dice y sale de la papelera', () async {
      final id = await saveBook('libro');
      final path = (await sourceOf(id)).originalBlobPath!;
      final trashed = (await trash.keepOnlyText(
        id,
      )).getOrElse((f) => fail('$f'));
      await files.delete(path);

      final outcome = await trash.restore(trashed.single.id);

      expect(
        outcome.getOrElse((f) => fail('$f')),
        ContentRestoreOutcome.fileMissing,
      );
      expect((await sourceOf(id)).originalBlobPath, isNull);
      expect(await db.select(db.trashedContents).get(), isEmpty);
    });

    test('si el elemento ya tiene otro archivo, no lo pisa y el viejo sigue '
        'en la papelera', () async {
      final id = await saveBook('libro');
      final trashed = (await trash.keepOnlyText(
        id,
      )).getOrElse((f) => fail('$f'));
      final current = (await library.findById(
        id,
      )).getOrElse((f) => fail('$f'))!;
      await library.save(
        current.copyWith(
          source: current.source.copyWith(
            originalFilePath: 'originales/libro/otro.pdf',
          ),
        ),
      );

      final outcome = await trash.restore(trashed.single.id);

      expect(
        outcome.getOrElse((f) => fail('$f')),
        ContentRestoreOutcome.alreadyHasFile,
      );
      expect(
        (await sourceOf(id)).originalBlobPath,
        'originales/libro/otro.pdf',
      );
      expect(await db.select(db.trashedContents).get(), hasLength(1));
    });
  });

  group('solo el libro: el texto a la papelera', () {
    test('se va el texto con sus subrayados y sus chunks, queda el archivo y '
        'la marca', () async {
      final id = await saveBook('libro');
      await highlight('libro-texto');
      expect(await chunksOf(id), greaterThan(0));

      final result = await trash.keepOnlyFile(id);

      final trashed = result.getOrElse((f) => fail('$f')).single;
      expect(trashed.kind, TrashedContentKind.text);
      expect(trashed.textLength, text.length);
      expect(await renditionsOf(id), isEmpty);
      expect(await db.select(db.highlights).get(), isEmpty);
      expect(await chunksOf(id), 0);
      final source = await sourceOf(id);
      expect(source.onlyFile, isTrue);
      expect(source.originalBlobPath, isNotNull);
      // El elemento, leído de la Biblioteca, lo sabe.
      final item = (await library.findById(id)).getOrElse((f) => fail('$f'))!;
      expect(item.source.onlyFile, isTrue);
      expect(item.renditions, isEmpty);
    });

    test('recuperar el texto lo devuelve igual —el mismo identificador, sus '
        'subrayados, sus chunks— y saca la marca', () async {
      final id = await saveBook('libro');
      await highlight('libro-texto');
      final trashed = (await trash.keepOnlyFile(
        id,
      )).getOrElse((f) => fail('$f'));

      final outcome = await trash.restore(trashed.single.id);

      expect(
        outcome.getOrElse((f) => fail('$f')),
        ContentRestoreOutcome.restored,
      );
      final rendition = (await renditionsOf(id)).single;
      expect(rendition.id, 'libro-texto');
      expect(rendition.content, text);
      expect(rendition.isPrimary, isTrue);
      expect(rendition.createdAt, captured);
      final restored = (await db.select(db.highlights).get()).single;
      expect(restored.id, 'subrayado');
      expect(restored.renditionId, 'libro-texto');
      expect(restored.note, 'La ciudad');
      expect(await chunksOf(id), greaterThan(0));
      expect((await sourceOf(id)).onlyFile, isFalse);
      expect(await db.select(db.trashedContents).get(), isEmpty);
    });

    test('si el elemento ya volvió a tener texto, el recuperado entra al lado, '
        'sin sacarle el lugar al principal', () async {
      final id = await saveBook('libro');
      final trashed = (await trash.keepOnlyFile(
        id,
      )).getOrElse((f) => fail('$f'));
      final current = (await library.findById(
        id,
      )).getOrElse((f) => fail('$f'))!;
      await library.save(
        current.copyWith(
          renditions: [
            Rendition.text(
              id: 'extraido-de-nuevo',
              itemId: id,
              kind: RenditionKind.plainText,
              content: 'El texto, extraído otra vez.',
              isPrimary: true,
              createdAt: clockNow,
            ),
          ],
        ),
      );

      await trash.restore(trashed.single.id);

      final renditions = {
        for (final r in await renditionsOf(id)) r.id: r.isPrimary,
      };
      expect(renditions, {'extraido-de-nuevo': true, 'libro-texto': false});
    });
  });

  group('guardar el elemento y la marca', () {
    test('guardarlo sin texto no la saca; con texto, sí', () async {
      final id = await saveBook('libro');
      await trash.keepOnlyFile(id);
      final bare = (await library.findById(id)).getOrElse((f) => fail('$f'))!;

      await library.save(bare.copyWith(title: 'Otro título'));
      expect((await sourceOf(id)).onlyFile, isTrue);

      await library.save(
        bare.copyWith(
          renditions: [
            Rendition.text(
              id: 'nuevo',
              itemId: id,
              kind: RenditionKind.plainText,
              content: 'Un texto nuevo.',
              isPrimary: true,
              createdAt: clockNow,
            ),
          ],
        ),
      );
      expect((await sourceOf(id)).onlyFile, isFalse);
    });
  });

  group('el barrido', () {
    test(
      'antes de los 30 días no borra nada; a los 30, la fila y el archivo',
      () async {
        final id = await saveBook('libro');
        final path = (await sourceOf(id)).originalBlobPath!;
        await trash.keepOnlyText(id);

        clockNow = clockNow.add(const Duration(days: 29, hours: 23));
        expect((await trash.purgeExpired()).getOrElse((f) => fail('$f')), 0);
        expect(files.paths, contains(path));
        expect(await db.select(db.trashedContents).get(), hasLength(1));

        clockNow = clockNow.add(const Duration(hours: 1));
        expect((await trash.purgeExpired()).getOrElse((f) => fail('$f')), 1);
        expect(files.deleted, [path]);
        expect(await db.select(db.trashedContents).get(), isEmpty);
        // El elemento sigue, con su texto.
        expect((await renditionsOf(id)).single.content, text);
      },
    );

    test('un texto vencido se borra de la base; el libro queda', () async {
      final id = await saveBook('libro');
      final path = (await sourceOf(id)).originalBlobPath!;
      await trash.keepOnlyFile(id);

      clockNow = clockNow.add(const Duration(days: 31));
      expect((await trash.purgeExpired()).getOrElse((f) => fail('$f')), 1);

      expect(await db.select(db.trashedContents).get(), isEmpty);
      expect(files.deleted, isEmpty);
      expect((await sourceOf(id)).originalBlobPath, path);
      expect((await sourceOf(id)).onlyFile, isTrue);
    });

    test('un archivo vencido que otro elemento todavía usa no se borra del '
        'disco', () async {
      final id = await saveBook('libro');
      final path = (await sourceOf(id)).originalBlobPath!;
      // El mismo PDF, capturado dos veces.
      final other = await library.save(
        KnowledgeItem(
          id: 'copia',
          title: 'Historia de Roma (otra vez)',
          source: Source(
            id: 'copia',
            kind: SourceKind.document,
            capturedAt: captured,
            originalFilePath: path,
          ),
          processingState: ProcessingState.ready,
          createdAt: captured,
          updatedAt: captured,
        ),
      );
      expect(other.isRight(), isTrue);
      await trash.keepOnlyText(id);

      clockNow = clockNow.add(const Duration(days: 30));
      expect((await trash.purgeExpired()).getOrElse((f) => fail('$f')), 1);

      expect(files.deleted, isEmpty);
      expect(files.paths, contains(path));
    });

    test('lo que ya no está no se puede recuperar', () async {
      final id = await saveBook('libro');
      final trashed = (await trash.keepOnlyText(
        id,
      )).getOrElse((f) => fail('$f'));
      clockNow = clockNow.add(const Duration(days: 30));
      await trash.purgeExpired();

      final outcome = await trash.restore(trashed.single.id);

      expect(outcome.getOrElse((f) => fail('$f')), ContentRestoreOutcome.gone);
    });
  });

  group('borrar el elemento para siempre', () {
    test(
      'se lleva también lo que tenía en la papelera del contenido',
      () async {
        final id = await saveBook('libro');
        final path = (await sourceOf(id)).originalBlobPath!;
        await trash.keepOnlyText(id);

        await library.delete(id);
        await library.purge([id]);

        expect(files.deleted, [path]);
        expect(await db.select(db.trashedContents).get(), isEmpty);
      },
    );
  });

  test(
    'watchOf cuenta lo que hay, y deja de contarlo al recuperarlo',
    () async {
      final id = await saveBook('libro');
      final trashed = (await trash.keepOnlyText(
        id,
      )).getOrElse((f) => fail('$f'));

      expect(await trash.watchOf(id).first, trashed);
      await trash.restore(trashed.single.id);
      expect(await trash.watchOf(id).first, isEmpty);
    },
  );
}
