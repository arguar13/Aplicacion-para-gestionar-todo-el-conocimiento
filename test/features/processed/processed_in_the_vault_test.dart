import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/data/services/chunk_passage_retriever.dart';
import 'package:sinapsis/features/content_trash/data/repositories/content_trash_repository_impl.dart';
import 'package:sinapsis/features/health/data/repositories/health_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/transform/data/repositories/text_anchor_relocator_impl.dart';

import '../../support/in_memory_file_store.dart';
import 'processed_harness.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Un documento procesado es un elemento más de la bóveda (F41, decisión A):
/// fuera de la Biblioteca, dentro de la búsqueda y el chat, con su papelera y
/// sus anclas cuando el texto de la fuente cambia o se suelta.
void main() {
  const text =
      'Los acueductos llevaban agua a Roma. '
      'El Senado discutía las leyes del foro.';
  late ProcessedHarness h;
  final docId = processedDocumentIdFor('roma');

  setUp(() async {
    h = await ProcessedHarness.create();
    await h.vault.saveSource(
      'roma',
      title: 'Roma antigua',
      text: text,
      originalName: 'roma.pdf',
    );
    await h.addSentence('m1', 'roma', text, start: 0, end: 36);
    final result = await h.process('roma', {
      ProcessedSection.text: SectionEdit.update(),
      ProcessedSection.summary: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
      ProcessedSection.notes: SectionEdit.add(
        const SectionInput.drafts([
          ProcessedDraft.written('Los gladiadores no aparecen.'),
        ]),
      ),
    });
    expect(result.isRight(), isTrue);
  });
  tearDown(() => h.close());

  Future<ProcessedPart> textPage() async => (await h.repository.partsOf(
    docId,
    sections: {ProcessedSection.text},
  )).getRight().toNullable()!.single;

  group('fuera de la Biblioteca', () {
    test('ni en la lista, ni en la cuenta, ni en la búsqueda', () async {
      await h.vault.saveNote('nota', title: 'Una nota');

      final items = await h.vault.library.watch(const LibraryQuery()).first;
      expect(items.map((i) => i.id), unorderedEquals(['roma', 'nota']));
      expect(await h.vault.library.watchCount(const LibraryQuery()).first, 2);
      final hits = (await h.vault.library.search(
        const LibraryQuery(searchText: 'gladiadores', limit: 20),
      )).getRight().toNullable()!;
      expect(hits, isEmpty);
      final byTitle = (await h.vault.library.search(
        const LibraryQuery(
          searchText: 'roma antigua',
          sortBy: LibrarySort.relevance,
          limit: 20,
        ),
      )).getRight().toNullable()!;
      expect(byTitle.map((hit) => hit.item.id), ['roma']);
    });

    test('pero en la papelera sí, para poder recuperarlo', () async {
      await h.vault.writer.trash([docId]);

      final trash = await h.vault.library.watchTrash().first;
      expect(trash.map((t) => t.id), [docId]);
    });
  });

  group('en el chat', () {
    ChunkPassageRetriever retriever() => ChunkPassageRetriever(database: h.db);

    test('sus notas y su resumen se leen; las páginas copiadas tal cual de '
        'una fuente a la vista, no: ya las da la fuente', () async {
      final notes = await retriever().retrieve('gladiadores');
      expect(notes.single.itemId, docId);
      expect(notes.single.excerpt, contains('gladiadores'));
      expect(notes.single.sourceCharStart, isNull);

      final senate = await retriever().retrieve('senado');
      expect(senate.map((s) => s.itemId), ['roma']);
    });

    test(
      'una página editada, o de una fuente que ya no está a la vista, sí',
      () async {
        final page = await textPage();
        await h.repository.editPart(page.id, 'El Senado y el pueblo romano.');

        final edited = await retriever().retrieve('pueblo');
        expect(edited.map((s) => s.itemId), [docId]);

        await h.repository.restorePart(page);
        await h.vault.writer.trash(['roma']);
        final orphan = await retriever().retrieve('senado');
        expect(orphan.map((s) => s.itemId), [docId]);
      },
    );

    test('acotado a lo procesado, lee también sus páginas', () async {
      final scoped = await retriever().retrieve('senado', scopeIds: {docId});

      expect(scoped.single.itemId, docId);
      expect(scoped.single.excerpt, contains('Senado'));
    });

    test('acotado a otra cosa, lo procesado no entra', () async {
      final scoped = await retriever().retrieve(
        'gladiadores',
        scopeIds: {'roma'},
      );

      expect(scoped, isEmpty);
    });

    test('lo de la papelera no se lee', () async {
      await h.vault.writer.trash([docId]);

      expect(await retriever().retrieve('gladiadores'), isEmpty);
      expect(await retriever().retrieve('senado', scopeIds: {docId}), isEmpty);
    });
  });

  group('cuando el texto de la fuente se suelta y vuelve', () {
    test('la parte se queda con su texto y pierde el enlace; recuperar el '
        'texto se lo devuelve', () async {
      final trash = ContentTrashRepositoryImpl(
        database: h.db,
        files: InMemoryFileStore(),
        telemetry: _SilentTelemetry(),
        clock: () => h.vault.now,
      );
      final before = await textPage();

      final trashed = (await trash.keepOnlyFile(
        'roma',
      )).getRight().toNullable()!;

      final loose = await textPage();
      expect(loose.content, before.content);
      expect(loose.anchor, isNull);
      expect((loose.sourceStart, loose.sourceEnd), (0, text.length));
      final row = await h.db.select(h.db.trashedContents).getSingle();
      expect(
        decodeTrashedProcessedParts(row.processedParts),
        unorderedEquals([
          before.id,
          // La oración del resumen también la anclaba.
          ...(await h.repository.partsOf(
            docId,
            sections: {ProcessedSection.summary},
          )).getRight().toNullable()!.map((p) => p.id),
        ]),
      );

      await trash.restore(trashed.single.id);

      expect(await textPage(), before);
    });

    test(
      'recuperar el texto no pisa un ancla que se rehízo mientras tanto',
      () async {
        final trash = ContentTrashRepositoryImpl(
          database: h.db,
          files: InMemoryFileStore(),
          telemetry: _SilentTelemetry(),
          clock: () => h.vault.now,
        );
        final trashed = (await trash.keepOnlyFile(
          'roma',
        )).getRight().toNullable()!;
        final page = await textPage();
        await h.vault.addRendition('roma', 'nueva', text);
        await (h.db.update(
          h.db.processedParts,
        )..where((p) => p.id.equals(page.id))).write(
          const ProcessedPartsCompanion(sourceRenditionId: Value('nueva')),
        );

        await trash.restore(trashed.single.id);

        expect((await textPage()).sourceRenditionId, 'nueva');
      },
    );

    test('lo guardado de las partes va y vuelve tal cual', () {
      expect(encodeTrashedProcessedParts(const []), isNull);
      expect(decodeTrashedProcessedParts(null), isEmpty);
      expect(
        decodeTrashedProcessedParts(encodeTrashedProcessedParts(['a', 'b'])),
        ['a', 'b'],
      );
    });
  });

  group('cuando el texto de la fuente se vuelve a extraer', () {
    test('el ancla se reubica por el pasaje; si ya no está, la parte se '
        'queda sin enlace', () async {
      final summary = (await h.repository.partsOf(
        docId,
        sections: {ProcessedSection.summary},
      )).getRight().toNullable()!.single;
      // Editada: se reubica por el pasaje que marcaba, no por lo que dice hoy.
      await h.repository.editPart(summary.id, 'Agua para Roma.');
      const moved = 'PRÓLOGO. Los acueductos llevaban agua a Roma. Nada más.';

      await h.db.transaction(
        () => TextAnchorRelocatorImpl(h.db).relocate(
          itemId: 'roma',
          renditionId: 'rend-roma',
          from: text,
          to: moved,
        ),
      );

      final relocated = (await h.repository.partsOf(
        docId,
        sections: {ProcessedSection.summary},
      )).getRight().toNullable()!.single;
      expect(relocated.anchor?.start, 9);
      expect(relocated.anchor?.end, 9 + summary.content.length);
      // La página del texto entero ya no está tal cual: sin enlace, con su
      // texto y dónde estaba.
      final page = await textPage();
      expect(page.anchor, isNull);
      expect(page.content, text);
      expect((page.sourceStart, page.sourceEnd), (0, text.length));
    });
  });

  test(
    'un procesado no es una nota que crezca: no cuenta en la salud',
    () async {
      await h.vault.saveNote('nota');

      final composition = await HealthRepositoryImpl(
        database: h.db,
        telemetry: _SilentTelemetry(),
      ).watchNoteComposition().first;

      expect(composition.kindCount(NoteKind.living), 1);
      expect(composition.kindCount(NoteKind.processed), 0);
      expect(composition.maturityCount(NoteMaturity.seed), 1);
    },
  );

  group('su tipo de nota', () {
    test('no cambia, ni ninguna otra nota pasa a serlo', () async {
      await h.vault.saveNote('nota');

      expect(await h.vault.writer.setNoteKind(docId, NoteKind.living), isFalse);
      expect(
        await h.vault.writer.setNoteKind('nota', NoteKind.processed),
        isFalse,
      );
      expect(await h.vault.writer.setNoteKind('nota', NoteKind.map), isTrue);
      final kinds = {
        for (final row in await h.db.select(h.db.knowledgeNotes).get())
          row.itemId: row.noteKind,
      };
      expect(kinds, {docId: NoteKind.processed, 'nota': NoteKind.map});
    });

    test('tocar su contenido sube su versión y su fecha', () async {
      final before = await (h.db.select(
        h.db.knowledgeEntries,
      )..where((e) => e.id.equals(docId))).getSingle();
      h.vault.at(9);

      expect(await h.vault.writer.markContentChanged(docId), isTrue);

      final after = await (h.db.select(
        h.db.knowledgeEntries,
      )..where((e) => e.id.equals(docId))).getSingle();
      expect(after.rev, before.rev + 1);
      expect(after.updatedAt, h.vault.now);
      expect(await h.vault.writer.markContentChanged('no-existe'), isFalse);
    });
  });

  test(
    'las marcas de estudio de la fuente siguen siendo de la fuente',
    () async {
      final marks = await h.db.select(h.db.studyMarks).get();

      expect(marks.single.kind, StudyMarkKind.summary);
      expect(marks.single.renditionId, 'rend-roma');
    },
  );
}
