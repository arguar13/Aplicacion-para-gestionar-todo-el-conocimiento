import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/attachments/data/repositories/attachment_repository_impl.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class _QuietTelemetry extends Mock implements TelemetryService {}

void main() {
  late AppDatabase db;
  late AttachmentRepositoryImpl attachments;
  late FakeIdGenerator ids;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    attachments = AttachmentRepositoryImpl(
      db,
      ids: ids,
      clock: () => DateTime(2026, 10, 4, 12, 0, ids.generated),
    );
    await db.customStatement('PRAGMA foreign_keys = ON');
    await insertItemRows(db, id: 'pagina', title: 'Roma');
  });

  tearDown(() => db.close());

  AttachmentCandidate candidate(String url, RenditionKind kind, int position) =>
      AttachmentCandidate(
        url: Uri.parse(url),
        kind: kind,
        position: position,
        title: 'cosa $position',
      );

  group('la lista de trabajo', () {
    test(
      'se anota en el orden de la página, y volver a anotar no repite',
      () async {
        await attachments.plan('pagina', [
          candidate('https://x.org/b.pdf', RenditionKind.pdf, 1),
          candidate('https://x.org/a.jpg', RenditionKind.image, 0),
        ]);
        await attachments.plan('pagina', [
          candidate('https://x.org/a.jpg', RenditionKind.image, 0),
          candidate('https://x.org/c.mp3', RenditionKind.audio, 2),
        ]);

        final downloads = await attachments.downloadsOf('pagina');
        expect(downloads.map((d) => d.url.toString()), [
          'https://x.org/a.jpg',
          'https://x.org/b.pdf',
          'https://x.org/c.mp3',
        ]);
        expect(
          downloads.map((d) => d.status),
          everyElement(AttachmentDownloadStatus.pending),
        );
        expect(downloads.first.title, 'cosa 0');
      },
    );

    test('«Bajar el resto» retoma lo de afuera, sin tope', () async {
      await attachments.plan('pagina', [
        candidate('https://x.org/a.mp4', RenditionKind.video, 0),
        candidate('https://x.org/b.mp4', RenditionKind.video, 1),
        candidate('https://x.org/c.pdf', RenditionKind.pdf, 2),
      ]);
      final [a, b, c] = await attachments.downloadsOf('pagina');
      await attachments.markDownload(
        a.id,
        status: AttachmentDownloadStatus.leftOut,
        expectedBytes: 900,
      );
      await attachments.markDownload(
        b.id,
        status: AttachmentDownloadStatus.noSpace,
      );
      await attachments.markDownload(
        c.id,
        status: AttachmentDownloadStatus.done,
      );

      expect(await attachments.hasWork('pagina'), isFalse);
      expect(await attachments.requestRest('pagina'), 2);

      final after = {
        for (final d in await attachments.downloadsOf('pagina')) d.id: d,
      };
      expect(after[a.id]!.status, AttachmentDownloadStatus.pending);
      expect(after[a.id]!.forced, isTrue);
      expect(after[a.id]!.expectedBytes, 900);
      expect(after[b.id]!.status, AttachmentDownloadStatus.pending);
      expect(after[b.id]!.forced, isFalse);
      expect(after[c.id]!.status, AttachmentDownloadStatus.done);
      expect(await attachments.hasWork('pagina'), isTrue);
    });
  });

  group('los archivos y su texto', () {
    test(
      'se suman en orden, con todo lo suyo; el texto se pide aparte',
      () async {
        final pdf = await attachments.addAttachment(
          itemId: 'pagina',
          kind: RenditionKind.pdf,
          relativePath: 'originales/s/contenido/informe.pdf',
          position: 3,
          title: 'Informe anual',
          originUrl: 'https://x.org/informe.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 1000,
        );
        await attachments.addAttachment(
          itemId: 'pagina',
          kind: RenditionKind.image,
          relativePath: 'originales/s/contenido/a.jpg',
          position: 0,
          sizeBytes: 50,
        );

        final list = await attachments.attachmentsOf('pagina');
        expect(list.map((a) => a.fileName), ['a.jpg', 'informe.pdf']);
        expect(list.last.displayName, 'Informe anual');
        expect(list.first.displayName, 'a.jpg');
        expect(list.last.textAttempted, isFalse);
        expect(await attachments.totalBytes('pagina'), 1050);
        expect(await attachments.hasWork('pagina'), isTrue);

        await attachments.saveText(pdf.id, 'Primera versión');
        await attachments.saveText(pdf.id, 'El texto del informe.');
        expect(await attachments.textOf(pdf.id), 'El texto del informe.');
        final withText = (await attachments.attachmentsOf('pagina')).last;
        expect(withText.textLength, 'El texto del informe.'.length);
        expect(withText.hasText, isTrue);

        // Una foto sin letras: se intentó y no tiene. No queda trabajo.
        await attachments.saveText(list.first.id, '');
        final photo = (await attachments.attachmentsOf('pagina')).first;
        expect(photo.textAttempted, isTrue);
        expect(photo.hasText, isFalse);
        expect(await attachments.hasWork('pagina'), isFalse);
      },
    );

    test('sacar un archivo se lleva su texto y devuelve su ruta', () async {
      final file = await attachments.addAttachment(
        itemId: 'pagina',
        kind: RenditionKind.audio,
        relativePath: 'originales/s/contenido/a.mp3',
        position: 0,
      );
      await attachments.saveText(file.id, 'lo dicho');

      expect(
        await attachments.removeAttachment(file.id),
        'originales/s/contenido/a.mp3',
      );
      expect(await attachments.textOf(file.id), isNull);
      expect(await attachments.attachmentsOf('pagina'), isEmpty);
      expect(await attachments.removeAttachment(file.id), isNull);
    });

    test('se ve en vivo', () async {
      final seen = attachments.watchAttachments('pagina');
      final expectation = expectLater(
        seen.map((list) => list.length),
        emitsThrough(1),
      );
      await attachments.addAttachment(
        itemId: 'pagina',
        kind: RenditionKind.image,
        relativePath: 'originales/s/contenido/a.jpg',
        position: 0,
      );
      await expectation;
    });
  });

  group('con la biblioteca', () {
    late LibraryRepositoryImpl library;
    late InMemoryFileStore files;

    setUp(() {
      files = InMemoryFileStore();
      library = LibraryRepositoryImpl(
        database: db,
        telemetry: _QuietTelemetry(),
        files: files,
      );
    });

    KnowledgeItem page() => KnowledgeItem(
      id: 'otra',
      title: 'Otra página',
      source: Source(
        id: 'src-otra',
        kind: SourceKind.webPage,
        url: 'https://x.org/otra',
        capturedAt: DateTime(2026, 10),
      ),
      processingState: ProcessingState.ready,
      createdAt: DateTime(2026, 10),
      updatedAt: DateTime(2026, 10),
      renditions: [
        Rendition.text(
          id: 'texto-otra',
          itemId: 'otra',
          kind: RenditionKind.markdown,
          content: 'El artículo.',
          isPrimary: true,
          createdAt: DateTime(2026, 10),
        ),
      ],
    );

    test(
      'el elemento no trae su «Contenido», y guardarlo no lo borra',
      () async {
        await library.save(page());
        final photo = await attachments.addAttachment(
          itemId: 'otra',
          kind: RenditionKind.image,
          relativePath: 'originales/src-otra/contenido/a.jpg',
          position: 0,
        );
        await attachments.saveText(photo.id, 'LEYENDA');

        final loaded = (await library.findById(
          'otra',
        )).getRight().toNullable()!;
        expect(loaded.renditions.map((r) => r.renditionId), ['texto-otra']);

        await library.save(loaded.copyWith(title: 'Renombrada'));
        expect(await attachments.attachmentsOf('otra'), hasLength(1));
        expect(await attachments.textOf(photo.id), 'LEYENDA');
      },
    );

    test(
      'borrar el elemento para siempre borra los archivos del disco',
      () async {
        await library.save(page());
        final path = await files.saveStream(
          bytes: Stream.value([1, 2, 3]),
          suggestedName: 'a.jpg',
          id: 'src-otra',
          folder: 'contenido',
        );
        await attachments.addAttachment(
          itemId: 'otra',
          kind: RenditionKind.image,
          relativePath: path,
          position: 0,
        );

        await library.delete('otra');
        await library.purge(['otra']);

        expect(files.deleted, contains(path));
        expect(await attachments.attachmentsOf('otra'), isEmpty);
      },
    );
  });
}
