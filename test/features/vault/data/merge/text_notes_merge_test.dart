import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';

import '../../../text_notes/text_notes_harness.dart';

/// Las notas en el texto (F45, mejora 19) en la copia de la bóveda y en la
/// unión: viajan enteras —también las sin lugar—, no se repiten, y una que las
/// dos tienen queda con lo editado más tarde.
void main() {
  late TextNotesHarness tel;
  late TextNotesHarness pc;

  const text = 'Moisés sube al monte. Baja con las tablas de la ley.';

  setUp(() async {
    tel = await TextNotesHarness.create();
    pc = await TextNotesHarness.create(deviceId: 'pc');
  });
  tearDown(() async {
    await tel.close();
    await pc.close();
  });

  test('la copia de la bóveda las lleva, de cada texto', () async {
    final library = await tel.source('fuente', text: text);
    final documentId = await tel.creations.processedDoc('fuente', text: text);
    await tel.noteOn(library, text, 'monte', note: 'De la Biblioteca');
    await tel.noteOn(
      ProcessedTextNotes(documentId),
      text,
      'tablas',
      note: 'De lo procesado',
    );

    final incoming = await IncomingVault.open(await tel.vault.zip());
    addTearDown(incoming.dispose);
    final copy = AppDatabase(NativeDatabase(incoming.databaseFile));
    addTearDown(copy.close);

    expect(
      {for (final row in await copy.select(copy.textNotes).get()) row.note},
      {'De la Biblioteca', 'De lo procesado'},
    );
  });

  test(
    'la unión trae lo que acá no hay, lo cuenta en la vista previa y en el '
    'resultado, lo encuentra la búsqueda, y una segunda vez no repite nada',
    () async {
      final library = await tel.source('fuente', text: text);
      final documentId = await tel.creations.processedDoc('fuente', text: text);
      final creation = await tel.creation();
      await tel.noteOn(library, text, 'monte', note: 'Sinaí');
      await tel.noteOn(ProcessedOriginalNotes(documentId), text, 'tablas');
      await tel.noteOn(creation, text, 'ley');

      final preview = await pc.vault.previewFrom(tel.vault);
      expect(preview.newTextNotes, 3);
      expect(preview.hasNothingNew, isFalse);

      final merged = await pc.vault.mergeFrom(tel.vault);
      expect(merged.textNotesAdded, 3);
      expect({for (final n in await pc.notesOf(library)) n.note}, {'Sinaí'});
      expect(
        await pc.notesOf(ProcessedOriginalNotes(documentId)),
        hasLength(1),
      );
      expect(await pc.notesOf(creation), hasLength(1));
      final found = await pc.db
          .customSelect(
            'SELECT note_id FROM text_note_search WHERE text_note_search '
            "MATCH 'sinai'",
          )
          .get();
      expect(found, hasLength(1));

      final again = await pc.vault.previewFrom(tel.vault);
      expect(again.newTextNotes, 0);
      final twice = await pc.vault.mergeFrom(tel.vault);
      expect(twice.textNotesAdded, 0);
      expect(await pc.db.select(pc.db.textNotes).get(), hasLength(3));
    },
  );

  test('de una nota que las dos tienen queda lo editado más tarde: lo que '
      'dice y su color; su lugar es el de cada bóveda', () async {
    final library = await tel.source('fuente', text: text);
    final note = await tel.noteOn(library, text, 'monte', note: 'Primera');
    await pc.vault.mergeFrom(tel.vault);

    // En pc la edita después; en tel, antes. Gana la de pc en tel.
    tel.vault.at(5);
    await tel.notes.edit(note, 'De tel');
    pc.vault.at(9);
    final [inPc] = await pc.notesOf(library);
    await pc.notes.edit(inPc, 'De pc');
    await pc.notes.recolor(
      (await pc.notesOf(library)).single,
      HighlightColor.violet,
    );

    await tel.vault.mergeFrom(pc.vault);
    final [winner] = await tel.notesOf(library);
    expect(winner.note, 'De pc');
    expect(winner.color, HighlightColor.violet);
    expect(winner.start, note.start);

    // Y la más vieja no pisa a la más nueva.
    await pc.vault.mergeFrom(tel.vault);
    expect((await pc.notesOf(library)).single.note, 'De pc');
  });
}
