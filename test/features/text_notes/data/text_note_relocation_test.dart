import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/transform/data/repositories/text_anchor_relocator_impl.dart';

import '../text_notes_harness.dart';

/// Cuando el texto de una fuente se vuelve a extraer (F22), cada nota en el
/// texto (F45, mejora 19) se reubica por su pedazo citado, como un subrayado;
/// la que ya no se encuentra queda «Sin lugar» y nunca se pierde.
void main() {
  late TextNotesHarness h;

  // Como lo guardaba la app antes de F22: renglones y palabra cortada, unidos.
  const from = 'Uno. Moisés sube al monte. Las tablas de la ley. Dos.';
  const to =
      'Prólogo nuevo.\nUno.\nMoisés sube al mon-\nte.\nLas tablas de la '
      'ley.\nDos.';

  setUp(() async => h = await TextNotesHarness.create());
  tearDown(() => h.close());

  Future<void> reextract() => TextAnchorRelocatorImpl(
    h.db,
  ).relocate(itemId: 'fuente', renditionId: 'rend-fuente', from: from, to: to);

  Future<TextNote> reload(TextNoteTarget target, String id) async =>
      (await h.notesOf(target)).firstWhere((n) => n.id == id);

  test(
    'la nota del original sigue sobre su pedazo en el texto nuevo, aunque '
    'ahí esté cortado en renglones; ni lo que dice ni su fecha cambian',
    () async {
      final library = await h.source('fuente', text: from);
      final note = await h.noteOn(library, from, 'al monte', note: 'Sinaí');

      h.vault.at(30);
      await reextract();

      final moved = await reload(library, note.id);
      expect(to.substring(moved.start!, moved.end), 'al mon-\nte');
      expect(moved.note, 'Sinaí');
      expect(moved.updatedAt, note.updatedAt);
    },
  );

  test('la que ya no se encuentra queda sin lugar, con lo que dice y su '
      'pedazo: no se borra', () async {
    final library = await h.source('fuente', text: from);
    final note = await h.noteOn(library, from, 'Dos', note: 'Se fue');
    const gone = 'Uno. Moisés sube al monte. Las tablas de la ley.';

    await TextAnchorRelocatorImpl(h.db).relocate(
      itemId: 'fuente',
      renditionId: 'rend-fuente',
      from: from,
      to: gone,
    );

    final lost = await reload(library, note.id);
    expect(lost.hasPlace, isFalse);
    expect(lost.note, 'Se fue');
    expect(lost.excerpt, 'Dos');
    expect(await h.notes.watchCount(library).first, 1);
  });

  test('la que estaba sin lugar vuelve a su lugar si el texto nuevo tiene su '
      'pedazo', () async {
    final library = await h.source('fuente', text: from);
    final note = await h.noteOn(library, from, 'Las tablas');
    const without = 'Uno. Moisés sube al monte.';
    final relocator = TextAnchorRelocatorImpl(h.db);
    await relocator.relocate(
      itemId: 'fuente',
      renditionId: 'rend-fuente',
      from: from,
      to: without,
    );
    expect((await reload(library, note.id)).hasPlace, isFalse);

    await relocator.relocate(
      itemId: 'fuente',
      renditionId: 'rend-fuente',
      from: without,
      to: to,
    );

    final back = await reload(library, note.id);
    expect(to.substring(back.start!, back.end), 'Las tablas');
  });

  test('las de la copia de Procesado se reubican también —están en las '
      'posiciones del texto de la fuente—, cada una en lo suyo', () async {
    final library = await h.source('fuente', text: from);
    final documentId = await h.creations.processedDoc('fuente', text: from);
    final copy = ProcessedOriginalNotes(documentId);
    final mine = await h.noteOn(library, from, 'ley', note: 'Biblioteca');
    final theirs = await h.noteOn(copy, from, 'Moisés', note: 'Procesado');

    await reextract();

    final library2 = await reload(library, mine.id);
    final copy2 = await reload(copy, theirs.id);
    expect(to.substring(library2.start!, library2.end), 'ley');
    expect(to.substring(copy2.start!, copy2.end), 'Moisés');
    expect([for (final n in await h.notesOf(library)) n.id], [mine.id]);
    expect([for (final n in await h.notesOf(copy)) n.id], [theirs.id]);
  });

  test('las del texto procesado se reubican solo si se lee sobre el de la '
      'fuente: con su propia sección «Texto», no se tocan', () async {
    await h.source('fuente', text: from);
    await h.source('otra', text: from);
    // Sin «Texto»: solo las notas, sobre el texto de la fuente.
    final result = await h.creations.processed.process('fuente', {
      ProcessedSection.notes: SectionEdit.add(
        const SectionInput.drafts([ProcessedDraft.written('Mi nota')]),
      ),
    });
    expect(result.isRight(), isTrue);
    final bare = ProcessedTextNotes(processedDocumentIdFor('fuente'));
    final followed = await h.noteOn(bare, from, 'tablas');
    // Con su propio «Texto»: su texto es suyo, y no lo cambió nadie.
    final owned = ProcessedTextNotes(
      await h.creations.processedDoc('otra', text: from),
    );
    final kept = await h.noteOn(owned, from, 'tablas');

    await reextract();
    await TextAnchorRelocatorImpl(
      h.db,
    ).relocate(itemId: 'otra', renditionId: 'rend-otra', from: from, to: to);

    final moved = await reload(bare, followed.id);
    expect(to.substring(moved.start!, moved.end), 'tablas');
    expect(await reload(owned, kept.id), kept);
  });

  test('las notas de otra forma o de otra fuente no se tocan', () async {
    final library = await h.source('fuente', text: from);
    final other = await h.source('otra', text: from);
    final elsewhere = await h.noteOn(other, from, 'Uno');

    await reextract();

    expect(await reload(other, elsewhere.id), elsewhere);
    expect(await h.notesOf(library), isEmpty);
  });
}
