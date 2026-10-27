import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Order;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../processed_harness.dart';

/// Procesar una fuente (F41, paso 1): el caso de uso contra el repositorio y
/// SQLite reales.
void main() {
  const text =
      'La república romana cayó. César cruzó el Rubicón. '
      'El Senado lo declaró enemigo.\n\nAugusto fundó el imperio. '
      'Su paz duró dos siglos.';
  ({int start, int end}) at(String sentence) {
    final start = text.indexOf(sentence);
    return (start: start, end: start + sentence.length);
  }

  late ProcessedHarness h;
  final docId = processedDocumentIdFor('libro');

  setUp(() async {
    h = await ProcessedHarness.create();
    await h.vault.saveSource('libro', title: 'Roma', text: text);
  });
  tearDown(() => h.close());

  Future<void> sentence(
    String id,
    String s, {
    StudyMarkKind kind = StudyMarkKind.summary,
  }) {
    final r = at(s);
    return h.addSentence(
      id,
      'libro',
      text,
      start: r.start,
      end: r.end,
      kind: kind,
    );
  }

  Future<List<ProcessedPart>> parts([ProcessedSection? section]) async =>
      (await h.repository.partsOf(
        docId,
        sections: section == null ? null : {section},
      )).getRight().toNullable()!;

  ProcessOutcome ok(Either<Failure, ProcessOutcome> result) =>
      result.getRight().toNullable() ??
      (throw StateError('falló: ${result.getLeft().toNullable()}'));

  ProcessedAnchor anchorOf(String s) {
    final r = at(s);
    return ProcessedAnchor(
      renditionId: 'rend-libro',
      start: r.start,
      end: r.end,
    );
  }

  group('procesar por primera vez', () {
    test('«pasar todo sin modificar» guarda el texto entero, con su enlace, '
        'como un elemento nuevo de la bóveda', () async {
      final outcome = ok(await h.process.passUnchanged('libro'));

      expect(outcome.documentId, docId);
      expect(outcome.created, isTrue);
      final text0 = await parts(ProcessedSection.text);
      expect(text0, hasLength(1));
      expect(text0.single.content, text);
      expect(text0.single.origin, ProcessedPartOrigin.copied);
      expect(text0.single.edited, isFalse);
      expect(
        text0.single.anchor,
        const ProcessedAnchor(
          renditionId: 'rend-libro',
          start: 0,
          end: text.length,
        ),
      );
      // Ni resumen, ni síntesis, ni notas.
      expect((await parts()).map((p) => p.section).toSet(), {
        ProcessedSection.text,
      });

      final item = await (h.db.select(
        h.db.knowledgeEntries,
      )..where((e) => e.id.equals(docId))).getSingle();
      expect(item.kind, ItemKind.note);
      expect(item.title, 'Roma');
      final note = await (h.db.select(
        h.db.knowledgeNotes,
      )..where((n) => n.itemId.equals(docId))).getSingle();
      expect(note.noteKind, NoteKind.processed);
      final link = await h.db.select(h.db.processedDocuments).getSingle();
      expect(link.itemId, docId);
      expect(link.sourceItemId, 'libro');
      expect(link.sourceKind, SourceKind.webPage);
      // Solo texto: el procesado no tiene formas, ni archivo, ni ficha.
      expect(await h.vault.renditionsOf(docId), isEmpty);
      expect(
        await (h.db.select(
          h.db.knowledgeSources,
        )..where((s) => s.itemId.equals(docId))).get(),
        isEmpty,
      );
    });

    test('un texto largo se guarda por páginas que, juntas, son el texto '
        'entero', () async {
      final long = [
        for (var i = 0; i < 900; i++)
          'Oración número $i del libro largo.${i % 7 == 6 ? '\n\n' : ' '}',
      ].join();
      await h.vault.saveSource('largo', text: long);

      ok(await h.process.passUnchanged('largo'));

      final pages = (await h.repository.partsOf(
        processedDocumentIdFor('largo'),
      )).getRight().toNullable()!;
      expect(pages.length, greaterThan(2));
      expect(pages.map((p) => p.content).join(), long);
      for (final page in pages) {
        expect(page.content.length, lessThanOrEqualTo(kProcessedTextPageChars));
        expect(
          long.substring(page.anchor!.start, page.anchor!.end),
          page.content,
        );
      }
      expect(
        [for (final p in pages) p.position],
        [for (var i = 0; i < pages.length; i++) i],
      );
    });

    test('el resumen, la síntesis, las notas y los fragmentos elegidos, cada '
        'uno con su origen y su ancla', () async {
      await sentence('m-cesar', 'César cruzó el Rubicón.');
      await sentence('m-cayo', 'La república romana cayó.');
      await sentence(
        'm-augusto',
        'Augusto fundó el imperio.',
        kind: StudyMarkKind.synthesis,
      );

      ok(
        await h.process('libro', {
          ProcessedSection.summary: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
          ProcessedSection.synthesis: SectionEdit.add(
            const SectionInput.sentences({'m-augusto'}),
          ),
          ProcessedSection.notes: SectionEdit.add(
            SectionInput.drafts([
              const ProcessedDraft.written('  Leer más sobre el Senado.  '),
              ProcessedDraft.cut(anchorOf('El Senado lo declaró enemigo.')),
            ]),
          ),
          ProcessedSection.fragments: SectionEdit.add(
            SectionInput.drafts([
              ProcessedDraft.cut(anchorOf('Su paz duró dos siglos.')),
            ]),
          ),
        }),
      );

      final summary = await parts(ProcessedSection.summary);
      // En el orden del texto, no en el de las marcas.
      expect(summary.map((p) => p.content), [
        'La república romana cayó.',
        'César cruzó el Rubicón.',
      ]);
      expect(summary.first.anchor, anchorOf('La república romana cayó.'));
      expect(
        (await parts(ProcessedSection.synthesis)).single.content,
        'Augusto fundó el imperio.',
      );
      final notes = await parts(ProcessedSection.notes);
      expect(notes.map((p) => (p.content, p.origin, p.anchor)), [
        ('Leer más sobre el Senado.', ProcessedPartOrigin.user, null),
        (
          'El Senado lo declaró enemigo.',
          ProcessedPartOrigin.copied,
          anchorOf('El Senado lo declaró enemigo.'),
        ),
      ]);
      final fragment = (await parts(ProcessedSection.fragments)).single;
      expect(fragment.content, 'Su paz duró dos siglos.');
      expect(fragment.origin, ProcessedPartOrigin.copied);
      // Sin texto: no se pidió.
      expect(await parts(ProcessedSection.text), isEmpty);
    });

    test(
      'lo que nace es solo lo procesado: sin los temas de la fuente',
      () async {
        await h.vault.addSpace('esp', 'Historia');
        await h.vault.saveSource('otro', text: text, spaceId: 'esp');

        ok(await h.process.passUnchanged('otro'));

        final spaces = await (h.db.select(
          h.db.itemSpaces,
        )..where((s) => s.itemId.equals(processedDocumentIdFor('otro')))).get();
        expect(spaces, isEmpty);
      },
    );

    test('si no hay nada que guardar, no nace nada', () async {
      final result = await h.process('libro', {
        ProcessedSection.summary: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      });

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await h.db.select(h.db.processedDocuments).get(), isEmpty);
      expect(
        await (h.db.select(
          h.db.knowledgeEntries,
        )..where((e) => e.id.equals(docId))).get(),
        isEmpty,
      );
    });

    group('falla sin escribir nada', () {
      Future<void> expectRefused(
        Map<ProcessedSection, SectionEdit> edits, {
        String source = 'libro',
      }) async {
        final result = await h.process(source, edits);
        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        expect(await h.db.select(h.db.processedDocuments).get(), isEmpty);
        expect(await h.db.select(h.db.processedParts).get(), isEmpty);
      }

      test('si no se pide nada', () => expectRefused({}));

      test('si el pedido no vale para la sección', () async {
        await expectRefused({ProcessedSection.notes: SectionEdit.update()});
        await expectRefused({
          ProcessedSection.text: SectionEdit.add(
            SectionInput.drafts([ProcessedDraft.cut(anchorOf('César'))]),
          ),
        });
      });

      test('si lo que se procesa no es una fuente', () async {
        await h.vault.saveNote('nota');
        await expectRefused({
          ProcessedSection.text: SectionEdit.update(),
        }, source: 'nota');
      });

      test('si la fuente está en la papelera', () async {
        await h.vault.writer.trash(['libro']);
        await expectRefused({ProcessedSection.text: SectionEdit.update()});
      });

      test('si un corte no cae dentro del texto', () async {
        await expectRefused({
          ProcessedSection.fragments: SectionEdit.add(
            const SectionInput.drafts([
              ProcessedDraft.cut(
                ProcessedAnchor(
                  renditionId: 'rend-libro',
                  start: 120,
                  end: 999,
                ),
              ),
            ]),
          ),
        });
      });

      test('si un corte es de un texto de otra fuente', () async {
        await h.vault.saveSource('ajena', text: text);
        await expectRefused({
          ProcessedSection.fragments: SectionEdit.add(
            const SectionInput.drafts([
              ProcessedDraft.cut(
                ProcessedAnchor(renditionId: 'rend-ajena', start: 0, end: 5),
              ),
            ]),
          ),
        });
      });

      test('si un corte es solo espacios', () async {
        await expectRefused({
          ProcessedSection.fragments: SectionEdit.add(
            SectionInput.drafts([
              ProcessedDraft.cut(
                ProcessedAnchor(
                  renditionId: 'rend-libro',
                  start: text.indexOf('\n\n'),
                  end: text.indexOf('\n\n') + 2,
                ),
              ),
            ]),
          ),
        });
      });

      test('si una oración elegida no es de esta fuente', () async {
        await sentence('m-cesar', 'César cruzó el Rubicón.');
        await expectRefused({
          ProcessedSection.summary: SectionEdit.add(
            const SectionInput.sentences({'m-cesar', 'm-otra'}),
          ),
        });
        // Ni una de síntesis pedida como resumen.
        await sentence(
          'm-sintesis',
          'Augusto fundó el imperio.',
          kind: StudyMarkKind.synthesis,
        );
        await expectRefused({
          ProcessedSection.summary: SectionEdit.add(
            const SectionInput.sentences({'m-sintesis'}),
          ),
        });
      });
    });
  });

  group('uno por fuente', () {
    test('volver a procesar cambia el mismo documento', () async {
      ok(await h.process.passUnchanged('libro'));
      final again = ok(
        await h.process('libro', {
          ProcessedSection.notes: SectionEdit.add(
            const SectionInput.drafts([ProcessedDraft.written('Otra idea.')]),
          ),
        }),
      );

      expect(again.created, isFalse);
      expect(again.documentId, docId);
      expect(await h.db.select(h.db.processedDocuments).get(), hasLength(1));
    });

    test('la base no deja un segundo procesado de la misma fuente', () async {
      ok(await h.process.passUnchanged('libro'));
      await h.vault.saveNote('intruso');

      await expectLater(
        h.db
            .into(h.db.processedDocuments)
            .insert(
              ProcessedDocumentsCompanion.insert(
                itemId: 'intruso',
                sourceItemId: const Value('libro'),
                sourceKind: SourceKind.webPage,
                createdAt: h.vault.now,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('si la fuente se borra de verdad, el procesado queda con su texto y '
        'sin enlace', () async {
      ok(await h.process.passUnchanged('libro'));
      await h.vault.writer.trash(['libro']);
      await h.vault.writer.purge('libro');

      final link = await h.db.select(h.db.processedDocuments).getSingle();
      expect(link.sourceItemId, isNull);
      final page = (await parts(ProcessedSection.text)).single;
      expect(page.content, text);
      expect(page.anchor, isNull);
      // Sabe dónde estaba.
      expect((page.sourceStart, page.sourceEnd), (0, text.length));
    });
  });

  group('nunca toca la fuente', () {
    test('ni al crear, agregar, actualizar, reemplazar, quitar, editar ni '
        'deshacer', () async {
      await sentence('m-cesar', 'César cruzó el Rubicón.');
      await sentence(
        'm-augusto',
        'Augusto fundó el imperio.',
        kind: StudyMarkKind.synthesis,
      );
      final before = await h.sourceSnapshot('libro');
      h.vault.at(30);

      final created = ok(
        await h.process('libro', {
          ProcessedSection.text: SectionEdit.update(),
          ProcessedSection.summary: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
        }),
      );
      final added = ok(
        await h.process('libro', {
          ProcessedSection.synthesis: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
          ProcessedSection.fragments: SectionEdit.add(
            SectionInput.drafts([ProcessedDraft.cut(anchorOf('Su paz'))]),
          ),
        }),
      );
      final page = (await parts(ProcessedSection.text)).single;
      await h.repository.editPart(page.id, 'Lo reescribí.');
      ok(
        await h.process('libro', {ProcessedSection.text: SectionEdit.update()}),
      );
      ok(
        await h.process('libro', {
          ProcessedSection.summary: SectionEdit.replace(
            const SectionInput.sentences({'m-cesar'}),
          ),
          ProcessedSection.synthesis: SectionEdit.remove(),
        }),
      );
      await h.process.undo(added.undo);
      await h.process.undo(created.undo);

      expect(await h.sourceSnapshot('libro'), before);
    });
  });

  group('agregar, actualizar, reemplazar y quitar', () {
    test('agregar no repite lo que ya está', () async {
      ok(
        await h.process('libro', {
          ProcessedSection.notes: SectionEdit.add(
            const SectionInput.drafts([ProcessedDraft.written('Una idea.')]),
          ),
        }),
      );
      final again = ok(
        await h.process('libro', {
          ProcessedSection.notes: SectionEdit.add(
            const SectionInput.drafts([
              ProcessedDraft.written('una  IDEA. '),
              ProcessedDraft.written('Otra idea.'),
            ]),
          ),
        }),
      );

      expect(again.sections[ProcessedSection.notes]!.added, 1);
      expect((await parts(ProcessedSection.notes)).map((p) => p.content), [
        'Una idea.',
        'Otra idea.',
      ]);
    });

    test('actualizar el resumen trae la versión de ahora y conserva lo '
        'editado', () async {
      await sentence('m-cayo', 'La república romana cayó.');
      await sentence('m-cesar', 'César cruzó el Rubicón.');
      await sentence('m-senado', 'El Senado lo declaró enemigo.');
      ok(
        await h.process('libro', {
          ProcessedSection.summary: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
        }),
      );
      final first = await parts(ProcessedSection.summary);
      // La persona edita «César…».
      await h.repository.editPart(
        first[1].id,
        'César cruzó el Rubicón, y no volvió.',
      );
      // Se vuelve a resumir: sale «cayó» y «Senado», entra «Augusto» y una que
      // choca con la editada.
      await (h.db.delete(
        h.db.studyMarks,
      )..where((m) => m.id.isIn(['m-cayo', 'm-cesar']))).go();
      await sentence('m-augusto', 'Augusto fundó el imperio.');
      await sentence('m-cesar2', 'César cruzó el Rubicón. El Senado');

      final outcome = ok(
        await h.process('libro', {
          ProcessedSection.summary: SectionEdit.update(),
        }),
      );

      final now = await parts(ProcessedSection.summary);
      expect(now.map((p) => p.content), [
        'César cruzó el Rubicón, y no volvió.',
        'El Senado lo declaró enemigo.',
        'Augusto fundó el imperio.',
      ]);
      // La que sigue igual en la fuente no se reescribe: es la misma parte.
      expect(now[1].id, first[2].id);
      expect(now[0].id, first[1].id);
      expect(now[0].edited, isTrue);
      expect(
        outcome.sections[ProcessedSection.summary],
        isA<SectionChangeTally>().having(
          (t) => (t.added, t.removed, t.kept),
          'cambios',
          (1, 1, 2),
        ),
      );
    });

    test('actualizar un texto largo conserva la página editada y no duplica '
        'nada', () async {
      final long = List.generate(
        900,
        (i) => 'Oración número $i del libro largo.',
      ).join(' ');
      await h.vault.saveSource('largo', text: long);
      final id = processedDocumentIdFor('largo');
      ok(await h.process.passUnchanged('largo'));
      final pages = (await h.repository.partsOf(id)).getRight().toNullable()!;
      await h.repository.editPart(pages[1].id, 'PÁGINA EDITADA');

      final same = ok(await h.process.passUnchanged('largo'));

      // Con el texto igual, nada cambia: las demás páginas son las mismas.
      expect(same.unchanged, isTrue);
      final after = (await h.repository.partsOf(id)).getRight().toNullable()!;
      expect(after.map((p) => p.id), pages.map((p) => p.id));
      expect(after[1].content, 'PÁGINA EDITADA');
      expect(
        after.map((p) => p.content).join(),
        long.replaceRange(
          pages[1].sourceStart!,
          pages[1].sourceEnd,
          'PÁGINA EDITADA',
        ),
      );
    });

    test('actualizar un texto que cambió no pierde nada alrededor de lo '
        'editado', () async {
      final long = List.generate(
        900,
        (i) => 'Oración número $i del libro largo.',
      ).join(' ');
      await h.vault.saveSource('largo', text: long);
      final id = processedDocumentIdFor('largo');
      ok(await h.process.passUnchanged('largo'));
      final pages = (await h.repository.partsOf(id)).getRight().toNullable()!;
      final edited = pages[1];
      await h.repository.editPart(edited.id, 'PÁGINA EDITADA');
      // El texto de la fuente cambia antes de la página editada —que no se
      // mueve—: las páginas de ahora se cortan en otros lugares, y las que
      // pisarían lo editado no pueden llevarse el texto de al lado.
      final changed = long.replaceRange(100, 100, 'Unas palabras de más. ');
      await (h.db.update(h.db.renditions)
            ..where((r) => r.id.equals('rend-largo')))
          .write(RenditionsCompanion(content: Value(changed)));

      ok(await h.process.passUnchanged('largo'));

      final after = (await h.repository.partsOf(id)).getRight().toNullable()!;
      expect(
        after.map((p) => p.content).join(),
        changed.replaceRange(
          edited.sourceStart!,
          edited.sourceEnd,
          'PÁGINA EDITADA',
        ),
      );
    });

    test('reemplazar pisa la sección entera y quitar la saca', () async {
      ok(
        await h.process('libro', {
          ProcessedSection.fragments: SectionEdit.add(
            SectionInput.drafts([ProcessedDraft.cut(anchorOf('César cruzó'))]),
          ),
          ProcessedSection.notes: SectionEdit.add(
            const SectionInput.drafts([ProcessedDraft.written('Nota.')]),
          ),
        }),
      );

      ok(
        await h.process('libro', {
          ProcessedSection.fragments: SectionEdit.replace(
            SectionInput.drafts([ProcessedDraft.cut(anchorOf('Su paz'))]),
          ),
          ProcessedSection.notes: SectionEdit.remove(),
        }),
      );

      expect((await parts(ProcessedSection.fragments)).map((p) => p.content), [
        'Su paz',
      ]);
      expect(await parts(ProcessedSection.notes), isEmpty);
      // Quitar todo no borra el documento: sigue siendo de su fuente.
      expect(await h.db.select(h.db.processedDocuments).get(), hasLength(1));
    });

    test('la vista previa dice cómo quedaría, sin guardar nada', () async {
      await sentence('m-cesar', 'César cruzó el Rubicón.');
      await sentence('m-cayo', 'La república romana cayó.');

      final preview = (await h.process.preview('libro', {
        ProcessedSection.text: SectionEdit.update(),
        ProcessedSection.summary: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      })).getRight().toNullable()!;

      expect(preview[ProcessedSection.text]!.parts, 1);
      expect(preview[ProcessedSection.text]!.words, processedWordCount(text));
      expect(preview[ProcessedSection.summary]!.parts, 2);
      expect(preview[ProcessedSection.summary]!.words, 8);
      expect(preview[ProcessedSection.summary]!.tally.added, 2);
      expect(await h.db.select(h.db.processedDocuments).get(), isEmpty);
    });
  });

  group('deshacer', () {
    test('lo que nació con el procesado deja de existir', () async {
      final outcome = ok(await h.process.passUnchanged('libro'));

      expect(await h.process.undo(outcome.undo), isA<Right<Failure, Unit>>());

      expect(await h.db.select(h.db.processedDocuments).get(), isEmpty);
      expect(await h.db.select(h.db.processedParts).get(), isEmpty);
      expect(
        await (h.db.select(
          h.db.knowledgeEntries,
        )..where((e) => e.id.equals(docId))).get(),
        isEmpty,
      );
      expect(
        await (h.db.select(
          h.db.fieldVersions,
        )..where((f) => f.itemId.equals(docId))).get(),
        isEmpty,
      );
    });

    test(
      'lo cambiado vuelve tal como estaba, con sus ids y sus ediciones',
      () async {
        await sentence('m-cesar', 'César cruzó el Rubicón.');
        ok(
          await h.process('libro', {
            ProcessedSection.summary: SectionEdit.add(
              const SectionInput.fromSource(),
            ),
          }),
        );
        final part = (await parts(ProcessedSection.summary)).single;
        await h.repository.editPart(part.id, 'Editada.');
        final before = await parts();

        final outcome = ok(
          await h.process('libro', {
            ProcessedSection.summary: SectionEdit.replace(
              const SectionInput.fromSource(),
            ),
            ProcessedSection.notes: SectionEdit.add(
              const SectionInput.drafts([ProcessedDraft.written('Nueva.')]),
            ),
          }),
        );
        expect(await parts(), isNot(before));

        await h.process.undo(outcome.undo);

        expect(await parts(), before);
      },
    );

    test('uno que estaba en la papelera sale al procesarlo, y vuelve a ella '
        'al deshacer', () async {
      ok(await h.process.passUnchanged('libro'));
      await h.vault.writer.trash([docId]);

      final outcome = ok(
        await h.process('libro', {
          ProcessedSection.notes: SectionEdit.add(
            const SectionInput.drafts([ProcessedDraft.written('Vuelvo.')]),
          ),
        }),
      );
      expect(outcome.created, isFalse);
      expect(
        (await h.repository.statusOf(docId)).getRight().toNullable(),
        ProcessedDocumentStatus.active,
      );
      // Con lo que tenía.
      expect(await parts(ProcessedSection.text), hasLength(1));

      await h.process.undo(outcome.undo);

      expect(
        (await h.repository.statusOf(docId)).getRight().toNullable(),
        ProcessedDocumentStatus.trashed,
      );
      expect(await parts(ProcessedSection.notes), isEmpty);
    });
  });

  test('un plan armado sobre otro estado no se guarda', () async {
    final result = await h.repository.commit(
      const ProcessedCommit(
        sourceItemId: 'libro',
        plans: [],
        expectedStatus: ProcessedDocumentStatus.active,
      ),
    );

    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    expect(await h.db.select(h.db.processedDocuments).get(), isEmpty);
  });
}
