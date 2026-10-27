import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';

import '../../../processed/processed_harness.dart';

/// La unión de bóvedas con documentos procesados (F41): uno por fuente también
/// entre dispositivos, sus partes sumadas sin repetir y el texto uno solo.
void main() {
  const text = 'El Senado y el pueblo romano. Augusto fundó el imperio.';
  late ProcessedHarness tel;
  late ProcessedHarness pc;
  final docId = processedDocumentIdFor('libro');

  setUp(() async {
    tel = await ProcessedHarness.create();
    pc = await ProcessedHarness.create(deviceId: 'pc');
    for (final h in [tel, pc]) {
      await h.vault.saveSource('libro', title: 'Roma', text: text);
    }
  });
  tearDown(() async {
    await tel.close();
    await pc.close();
  });

  Future<void> process(
    ProcessedHarness h, {
    List<String> notes = const [],
    bool withText = true,
  }) async {
    final result = await h.process('libro', {
      if (withText) ProcessedSection.text: SectionEdit.update(),
      if (notes.isNotEmpty)
        ProcessedSection.notes: SectionEdit.add(
          SectionInput.drafts([
            for (final note in notes) ProcessedDraft.written(note),
          ]),
        ),
    });
    expect(result.isRight(), isTrue, reason: '$result');
  }

  Future<List<(ProcessedSection, String, int)>> partsOf(
    ProcessedHarness h,
  ) async => [
    for (final p in (await h.repository.partsOf(
      docId,
    )).getRight().toNullable()!)
      (p.section, p.content, p.position),
  ];

  test('un procesado que acá no está entra entero, con su elemento y su '
      'enlace', () async {
    await process(tel, notes: ['Una idea.']);
    final preview = await pc.vault.previewFrom(tel.vault);
    expect(preview.newNotes, 1);
    expect(preview.newProcessedParts, 2);
    expect(preview.hasNothingNew, isFalse);

    final result = await pc.vault.mergeFrom(tel.vault);

    expect(result.processedDocumentsAdded, 1);
    expect(result.processedPartsAdded, 2);
    expect(await partsOf(pc), await partsOf(tel));
    final link = await pc.db.select(pc.db.processedDocuments).getSingle();
    expect(link.sourceItemId, 'libro');
    expect(link.sourceKind, SourceKind.webPage);
    final note = await (pc.db.select(
      pc.db.knowledgeNotes,
    )..where((n) => n.itemId.equals(docId))).getSingle();
    expect(note.noteKind, NoteKind.processed);
    final page = (await pc.repository.partsOf(
      docId,
      sections: {ProcessedSection.text},
    )).getRight().toNullable()!.single;
    expect(page.anchor?.renditionId, 'rend-libro');

    // Y una segunda vez no trae nada.
    final again = await pc.vault.previewFrom(tel.vault);
    expect(again.newProcessedParts, 0);
    expect(again.hasNothingNew, isTrue);
  });

  test('la misma fuente procesada en los dos es el mismo documento: se suman '
      'sus partes sin repetir, y el texto es uno solo', () async {
    await process(tel, notes: ['De tel.', 'Las dos.']);
    await process(pc, notes: ['Las dos.', 'De pc.']);
    final pcText = (await pc.repository.partsOf(
      docId,
      sections: {ProcessedSection.text},
    )).getRight().toNullable()!;
    // En pc la página está editada: la de tel no entra igual.
    await pc.repository.editPart(pcText.single.id, 'Texto editado en pc.');

    final preview = await pc.vault.previewFrom(tel.vault);
    expect(preview.newProcessedParts, 1);

    final result = await pc.vault.mergeFrom(tel.vault);

    expect(result.processedDocumentsAdded, 0);
    expect(result.processedPartsAdded, 1);
    expect(await pc.db.select(pc.db.processedDocuments).get(), hasLength(1));
    expect(await partsOf(pc), [
      (ProcessedSection.text, 'Texto editado en pc.', 0),
      (ProcessedSection.notes, 'Las dos.', 0),
      (ProcessedSection.notes, 'De pc.', 1),
      // Lo de la copia, después de lo de acá, en su orden.
      (ProcessedSection.notes, 'De tel.', 2),
    ]);
  });

  test('el ancla va a la forma de acá que tiene ese texto', () async {
    // En tel el mismo texto quedó guardado dos veces, con otro id: la unión
    // lo junta con el de acá.
    await tel.vault.addRendition('libro', 'rend-tel', text);
    final result = await tel.process('libro', {
      ProcessedSection.fragments: SectionEdit.add(
        const SectionInput.drafts([
          ProcessedDraft.cut(
            ProcessedAnchor(renditionId: 'rend-tel', start: 0, end: 9),
          ),
        ]),
      ),
    });
    expect(result.isRight(), isTrue);

    await pc.vault.mergeFrom(tel.vault);

    final fragment = (await pc.repository.partsOf(
      docId,
      sections: {ProcessedSection.fragments},
    )).getRight().toNullable()!.single;
    expect(fragment.content, 'El Senado');
    expect(fragment.anchor?.renditionId, 'rend-libro');
  });

  test('si acá no tenía texto, el de la copia entra', () async {
    await process(tel);
    await process(pc, notes: ['Solo una nota.'], withText: false);

    await pc.vault.mergeFrom(tel.vault);

    expect(await partsOf(pc), [
      (ProcessedSection.text, text, 0),
      (ProcessedSection.notes, 'Solo una nota.', 0),
    ]);
  });

  test('un procesado que acá perdió su fuente vuelve a enlazarse si la copia '
      'la trae', () async {
    await process(tel);
    await process(pc);
    await pc.vault.writer.trash(['libro']);
    await pc.vault.writer.purge('libro');
    expect(
      (await pc.db.select(pc.db.processedDocuments).getSingle()).sourceItemId,
      isNull,
    );

    await pc.vault.mergeFrom(tel.vault);

    expect(
      (await pc.db.select(pc.db.processedDocuments).getSingle()).sourceItemId,
      'libro',
    );
  });

  test('si acá otro procesado ya es el de esa fuente, el de la copia entra '
      'sin enlace: uno por fuente', () async {
    await process(tel, notes: ['De tel.']);
    // Un procesado de acá con otro id para la misma fuente (no lo hace la app,
    // pero una copia vieja podría traerlo así).
    await pc.vault.saveNote('otro-procesado');
    await pc.db
        .into(pc.db.processedDocuments)
        .insert(
          ProcessedDocumentsCompanion.insert(
            itemId: 'otro-procesado',
            sourceItemId: const Value('libro'),
            sourceKind: SourceKind.webPage,
            createdAt: pc.vault.now,
          ),
        );

    await pc.vault.mergeFrom(tel.vault);

    final links = {
      for (final row in await pc.db.select(pc.db.processedDocuments).get())
        row.itemId: row.sourceItemId,
    };
    expect(links, {'otro-procesado': 'libro', docId: null});
    expect(await partsOf(pc), await partsOf(tel));
  });
}
