import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_section_planner.dart';

import '../../processed_harness.dart';

/// El repositorio de lo procesado (F41, paso 1): la lista de «Procesado», un
/// documento, sus partes, lo que ofrece una fuente y las ediciones a mano.
void main() {
  late ProcessedHarness h;

  setUp(() async => h = await ProcessedHarness.create());
  tearDown(() => h.close());

  Future<String> processed(
    String sourceId, {
    String text = 'Un texto cualquiera.',
    String? title,
    List<String> notes = const [],
    String? spaceId,
  }) async {
    await h.vault.saveSource(sourceId, text: text, title: title);
    final result = await h.process(sourceId, {
      ProcessedSection.text: SectionEdit.update(),
      if (notes.isNotEmpty)
        ProcessedSection.notes: SectionEdit.add(
          SectionInput.drafts([
            for (final note in notes) ProcessedDraft.written(note),
          ]),
        ),
    });
    final id = result.getRight().toNullable()!.documentId;
    if (spaceId != null) await h.vault.writer.addSpaces([id], {spaceId});
    return id;
  }

  Future<List<String>> titles(ProcessedQuery query) async => [
    for (final d in await h.repository.watchDocuments(query).first) d.title,
  ];

  group('la lista de «Procesado»', () {
    test('trae lo procesado, lo último tocado arriba, con qué partes tiene y '
        'sin el texto', () async {
      h.vault.at(1);
      final roma = await processed('roma', title: 'Roma', notes: ['Idea.']);
      h.vault.at(2);
      await processed('grecia', title: 'Grecia');

      final list = await h.repository
          .watchDocuments(const ProcessedQuery())
          .first;

      expect(list.map((d) => d.title), ['Grecia', 'Roma']);
      final row = list.last;
      expect(row.id, roma);
      expect(row.sourceItemId, 'roma');
      expect(row.sourceKind, SourceKind.webPage);
      expect(row.partCounts, {
        ProcessedSection.text: 1,
        ProcessedSection.notes: 1,
      });
      expect(row.sections, [ProcessedSection.text, ProcessedSection.notes]);
      expect(row.updatedAt, h.vault.now.subtract(const Duration(minutes: 1)));
    });

    test('nada de lo de la papelera', () async {
      final roma = await processed('roma', title: 'Roma');
      await processed('grecia', title: 'Grecia');
      await h.vault.writer.trash([roma]);

      expect(await titles(const ProcessedQuery()), ['Grecia']);
      expect(await h.repository.watchCount(const ProcessedQuery()).first, 1);
    });

    test('ni las fuentes ni las notas de la Biblioteca', () async {
      await processed('roma', title: 'Roma');
      await h.vault.saveNote('nota', title: 'Una nota');

      expect(await titles(const ProcessedQuery()), ['Roma']);
    });

    test('busca en el título y en todas las partes; con varias palabras, '
        'aunque estén en partes distintas', () async {
      await processed('roma', title: 'Roma', text: 'El Senado y el pueblo.');
      await processed(
        'kuhn',
        title: 'Estructura',
        text: 'Kuhn escribió sobre la ciencia.',
        notes: ['El paradigma cambia.'],
      );
      await processed('nada', title: 'Otro', text: 'Nada que ver.');

      expect(await titles(const ProcessedQuery(searchText: 'senado')), [
        'Roma',
      ]);
      expect(await titles(const ProcessedQuery(searchText: 'estruct')), [
        'Estructura',
      ]);
      expect(await titles(const ProcessedQuery(searchText: 'kuhn paradigma')), [
        'Estructura',
      ]);
      expect(
        await titles(const ProcessedQuery(searchText: 'kuhn senado')),
        isEmpty,
      );
      expect(await titles(const ProcessedQuery(searchText: '"')), isEmpty);
    });

    test('filtra por tema, por tipo de fuente, por qué partes tiene y por '
        'ids', () async {
      await h.vault.addSpace('esp', 'Historia');
      final roma = await processed('roma', title: 'Roma', spaceId: 'esp');
      await processed('grecia', title: 'Grecia', notes: ['Idea.']);

      expect(await titles(const ProcessedQuery(spaceId: 'esp')), ['Roma']);
      expect(
        await titles(const ProcessedQuery(sections: {ProcessedSection.notes})),
        ['Grecia'],
      );
      expect(
        await titles(const ProcessedQuery(sourceKinds: {SourceKind.youtube})),
        isEmpty,
      );
      expect(
        await titles(const ProcessedQuery(sourceKinds: {SourceKind.webPage})),
        hasLength(2),
      );
      expect(await titles(ProcessedQuery(ids: {roma})), ['Roma']);
      expect(await titles(const ProcessedQuery(ids: {})), isEmpty);
      final rows = await h.repository
          .watchDocuments(const ProcessedQuery(spaceId: 'esp'))
          .first;
      expect(rows.single.spaceIds, {'esp'});
    });

    test('ordena por título y pagina', () async {
      for (final name in ['b', 'c', 'a']) {
        await processed(name, title: name.toUpperCase());
      }

      expect(
        await titles(
          const ProcessedQuery(sortBy: ProcessedSort.title, descending: false),
        ),
        ['A', 'B', 'C'],
      );
      expect(
        await titles(
          const ProcessedQuery(
            sortBy: ProcessedSort.title,
            descending: false,
            limit: 1,
            offset: 1,
          ),
        ),
        ['B'],
      );
      expect(
        (await h.repository.matchingIds(
          const ProcessedQuery(sortBy: ProcessedSort.title, descending: false),
        )).getRight().toNullable(),
        [
          for (final s in ['a', 'b', 'c']) processedDocumentIdFor(s),
        ],
      );
    });

    test('se entera de cada cambio', () async {
      final stream = h.repository.watchDocuments(const ProcessedQuery());
      final seen = <int>[];
      final sub = stream.listen((list) => seen.add(list.length));
      await pumpEventQueue();
      await processed('roma');
      await pumpEventQueue();
      await sub.cancel();

      expect(seen.first, 0);
      expect(seen.last, 1);
    });

    test('las fuentes que ya tienen su procesado vivo', () async {
      final roma = await processed('roma');
      await processed('grecia');
      await h.vault.writer.trash([roma]);

      expect(await h.repository.watchProcessedSourceIds().first, {'grecia'});
    });
  });

  test('tocar un documento lo sube en la lista', () async {
    h.vault.at(1);
    await processed('roma', title: 'Roma');
    h.vault.at(2);
    await processed('grecia', title: 'Grecia');
    h.vault.at(3);

    await h.process('roma', {
      ProcessedSection.notes: SectionEdit.add(
        const SectionInput.drafts([ProcessedDraft.written('Más.')]),
      ),
    });

    final list = await h.repository
        .watchDocuments(const ProcessedQuery())
        .first;
    expect(list.map((d) => d.title), ['Roma', 'Grecia']);
    expect(list.first.updatedAt, h.vault.now);
  });

  test('un plan armado sobre otras partes no se guarda', () async {
    final id = await processed('roma', notes: ['Uno']);
    final notes = (await h.repository.partsOf(
      id,
      sections: {ProcessedSection.notes},
    )).getRight().toNullable()!;
    final plan = planSectionChange(
      section: ProcessedSection.notes,
      existing: notes,
      change: ProcessedChange.remove,
    );
    // Mientras tanto, alguien agregó otra.
    await h.process('roma', {
      ProcessedSection.notes: SectionEdit.add(
        const SectionInput.drafts([ProcessedDraft.written('Dos')]),
      ),
    });

    final result = await h.repository.commit(
      ProcessedCommit(
        sourceItemId: 'roma',
        plans: [plan],
        expectedStatus: ProcessedDocumentStatus.active,
      ),
    );

    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    expect(
      (await h.repository.partsOf(
        id,
        sections: {ProcessedSection.notes},
      )).getRight().toNullable()!.map((p) => p.content),
      ['Uno', 'Dos'],
    );
  });

  group('un documento', () {
    test(
      'trae cuánto hay en cada sección y su fuente, sin las partes',
      () async {
        final id = await processed(
          'roma',
          title: 'Roma',
          text: 'Diez letras',
          notes: ['Una', 'Dos'],
        );
        final note = (await h.repository.partsOf(
          id,
          sections: {ProcessedSection.notes},
        )).getRight().toNullable()!.first;
        expect(
          (await h.repository.editPart(note.id, 'Una y media')).isRight(),
          isTrue,
        );

        final doc = (await h.repository.watchDocument(id).first)!;

        expect(doc.title, 'Roma');
        expect(doc.inTrash, isFalse);
        expect(doc.stats[ProcessedSection.text]!.characters, 11);
        expect(doc.stats[ProcessedSection.notes]!.parts, 2);
        // Una nota es de la persona: editarla no la marca como «editada».
        expect(doc.stats[ProcessedSection.notes]!.edited, 0);
        expect(doc.source?.itemId, 'roma');
        expect(doc.source?.title, 'Roma');
        expect(doc.source?.inTrash, isFalse);

        await h.vault.writer.trash(['roma']);
        expect(
          (await h.repository.watchDocument(id).first)!.source?.inTrash,
          isTrue,
        );
        expect(await h.repository.watchDocument('no-existe').first, isNull);
      },
    );

    test('el de una fuente, y nada si no tiene', () async {
      final id = await processed('roma');
      await h.vault.saveSource('suelta');

      expect((await h.repository.watchForSource('roma').first)?.id, id);
      expect(await h.repository.watchForSource('suelta').first, isNull);
    });

    test('las partes de una sección, de a tramos', () async {
      final id = await processed('roma', notes: ['Uno', 'Dos', 'Tres']);

      final page = await h.repository
          .watchParts(id, ProcessedSection.notes, offset: 1, limit: 1)
          .first;

      expect(page.single.content, 'Dos');
      expect(
        (await h.repository.watchParts(id, ProcessedSection.notes).first).map(
          (p) => p.position,
        ),
        [0, 1, 2],
      );
    });
  });

  group('lo que ofrece una fuente', () {
    test('su texto —cuánto, sin traerlo— y las oraciones de su resumen y su '
        'síntesis, en orden', () async {
      const text = 'Primera idea. Segunda idea. Tercera.';
      await h.vault.saveSource('roma', text: text, title: 'Roma');
      await h.addSentence('m2', 'roma', text, start: 14, end: 27);
      await h.addSentence('m1', 'roma', text, start: 0, end: 13);
      await h.addSentence(
        's1',
        'roma',
        text,
        start: 28,
        end: 36,
        kind: StudyMarkKind.synthesis,
      );

      final material = (await h.repository.materialOf(
        'roma',
      )).getRight().toNullable()!;

      expect(material.title, 'Roma');
      expect(material.hasText, isTrue);
      expect(material.textRenditionId, 'rend-roma');
      expect(material.textCharacters, text.length);
      expect(material.textWords, 5);
      expect(material.summary.map((s) => s.content), [
        'Primera idea.',
        'Segunda idea.',
      ]);
      expect(material.summary.first.studyMarkId, 'm1');
      expect(material.synthesis.single.anchor.start, 28);
      final quick = (await h.repository.materialOf(
        'roma',
        countWords: false,
      )).getRight().toNullable()!;
      expect(quick.textWords, 0);
    });

    test('el texto es el de la forma principal, aunque haya otra más '
        'vieja', () async {
      h.vault.at(5);
      await h.vault.saveSource('roma', text: 'Principal.');
      h.vault.at(0);
      await h.vault.addRendition('roma', 'vieja', 'Más vieja y no principal.');

      final material = (await h.repository.materialOf(
        'roma',
      )).getRight().toNullable()!;

      expect(material.textRenditionId, 'rend-roma');
      expect(material.textCharacters, 'Principal.'.length);
    });

    test('sin principal, la más vieja; nunca el texto de un archivo del '
        'contenido', () async {
      h.vault.at(5);
      await h.vault.saveSource('roma', text: 'La de siempre.');
      await (h.db.update(h.db.renditions)
            ..where((r) => r.id.equals('rend-roma')))
          .write(const RenditionsCompanion(isPrimary: Value(false)));
      h.vault.at(0);
      await h.vault.addRendition('roma', 'vieja', 'Más vieja.');
      await h.db
          .into(h.db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'del-contenido',
              itemId: 'roma',
              kind: RenditionKind.plainText,
              content: const Value('El texto de un PDF enlazado.'),
              isPrimary: true,
              createdAt: h.vault.now.subtract(const Duration(days: 1)),
              textOf: const Value('vieja'),
            ),
          );

      final material = (await h.repository.materialOf(
        'roma',
      )).getRight().toNullable()!;

      expect(material.textRenditionId, 'vieja');
      expect(
        (await h.repository.sourceText('roma')).getRight().toNullable()?.text,
        'Más vieja.',
      );
    });

    test(
      'una nota o algo en la papelera no es una fuente que procesar',
      () async {
        await h.vault.saveNote('nota');
        await h.vault.saveSource('borrada');
        await h.vault.writer.trash(['borrada']);

        for (final id in ['nota', 'borrada', 'no-existe']) {
          expect(
            (await h.repository.materialOf(id)).getLeft().toNullable(),
            isA<ValidationFailure>(),
          );
        }
      },
    );

    test('el texto de una forma, solo si es de esa fuente', () async {
      await h.vault.saveSource('roma', text: 'De Roma.');
      await h.vault.saveSource('grecia', text: 'De Grecia.');

      expect(
        (await h.repository.sourceText('roma')).getRight().toNullable()?.text,
        'De Roma.',
      );
      expect(
        (await h.repository.sourceText(
          'roma',
          renditionId: 'rend-grecia',
        )).getRight().toNullable(),
        isNull,
      );
    });
  });

  group('editar a mano', () {
    late String id;
    late List<ProcessedPart> notes;

    setUp(() async {
      id = await processed('roma', notes: ['Uno', 'Dos', 'Tres']);
      notes = (await h.repository.partsOf(
        id,
        sections: {ProcessedSection.notes},
      )).getRight().toNullable()!;
    });

    test('editar una página copiada la marca como editada, y deshacer la '
        'devuelve', () async {
      final page = (await h.repository.partsOf(
        id,
        sections: {ProcessedSection.text},
      )).getRight().toNullable()!.single;
      h.vault.at(5);

      final before = (await h.repository.editPart(
        page.id,
        'Otro texto.',
      )).getRight().toNullable()!;

      final edited =
          (await h.repository.watchParts(id, ProcessedSection.text).first)
              .single;
      expect(edited.content, 'Otro texto.');
      expect(edited.edited, isTrue);
      expect(edited.updatedAt, h.vault.now);
      final doc = await (h.db.select(
        h.db.knowledgeEntries,
      )..where((e) => e.id.equals(id))).getSingle();
      expect(doc.updatedAt, h.vault.now);

      await h.repository.restorePart(before);
      expect(
        (await h.repository.watchParts(id, ProcessedSection.text).first).single,
        page,
      );
    });

    test('no deja una parte vacía', () async {
      expect(
        (await h.repository.editPart(
          notes.first.id,
          '  ',
        )).getLeft().toNullable(),
        isA<ValidationFailure>(),
      );
      expect(
        (await h.repository.editPart('no-existe', 'x')).getLeft().toNullable(),
        isA<ValidationFailure>(),
      );
    });

    test(
      'quitar corre las que siguen, y deshacer la devuelve a su lugar',
      () async {
        final removed = (await h.repository.removePart(
          notes[1].id,
        )).getRight().toNullable()!;

        final after = await h.repository
            .watchParts(id, ProcessedSection.notes)
            .first;
        expect(after.map((p) => (p.content, p.position)), [
          ('Uno', 0),
          ('Tres', 1),
        ]);

        await h.repository.restorePart(removed);
        expect(
          await h.repository.watchParts(id, ProcessedSection.notes).first,
          notes,
        );
      },
    );

    test('deshacer en un documento que ya no existe avisa', () async {
      await h.vault.writer.trash([id]);
      await h.vault.writer.purge(id);

      expect(
        (await h.repository.restorePart(notes.first)).getLeft().toNullable(),
        isA<ValidationFailure>(),
      );
    });
  });

  test('la parte que vuelve sin su forma vuelve sin el enlace, con sus '
      'posiciones', () async {
    final id = await processed('roma', text: 'Un texto.');
    final page = (await h.repository.partsOf(
      id,
    )).getRight().toNullable()!.single;
    final removed = (await h.repository.removePart(
      page.id,
    )).getRight().toNullable()!;
    await (h.db.delete(
      h.db.renditions,
    )..where((r) => r.id.equals('rend-roma'))).go();

    await h.repository.restorePart(removed);

    final back = (await h.repository.partsOf(
      id,
    )).getRight().toNullable()!.single;
    expect(back.content, 'Un texto.');
    expect(back.sourceRenditionId, isNull);
    expect((back.sourceStart, back.sourceEnd), (0, 9));
    expect(back.anchor, isNull);
  });

  test('las partes cumplen sus reglas en la base', () async {
    final id = await processed('roma');
    Future<void> insert(ProcessedPartsCompanion part) =>
        h.db.into(h.db.processedParts).insert(part);
    ProcessedPartsCompanion part({
      String content = 'x',
      ProcessedSection section = ProcessedSection.notes,
      ProcessedPartOrigin origin = ProcessedPartOrigin.user,
      bool edited = false,
      int? start,
      int? end,
    }) => ProcessedPartsCompanion.insert(
      id: 'p-${content.hashCode}-$section-$origin-$edited-$start-$end',
      documentId: id,
      section: section,
      position: 9,
      content: content,
      origin: origin,
      edited: Value(edited),
      sourceStart: Value(start),
      sourceEnd: Value(end),
      createdAt: h.vault.now,
      updatedAt: h.vault.now,
    );

    for (final bad in [
      part(content: ''),
      part(start: 1),
      part(start: 3, end: 3),
      part(start: -1, end: 2),
      // Lo copiado sabe de dónde salió; lo editado es solo lo copiado.
      part(origin: ProcessedPartOrigin.copied),
      part(edited: true),
      // La persona solo escribe notas.
      part(section: ProcessedSection.fragments),
      part(section: ProcessedSection.text),
    ]) {
      await expectLater(insert(bad), throwsA(anything), reason: '$bad');
    }
    await insert(part(content: 'Bien'));
    await h.vault.saveSource('otra');
    await expectLater(
      h.db
          .into(h.db.processedDocuments)
          .insert(
            ProcessedDocumentsCompanion.insert(
              itemId: 'otra',
              sourceItemId: const Value('otra'),
              sourceKind: SourceKind.webPage,
              createdAt: h.vault.now,
            ),
          ),
      throwsA(anything),
      reason: 'una fuente no se procesa a sí misma',
    );
  });
}
