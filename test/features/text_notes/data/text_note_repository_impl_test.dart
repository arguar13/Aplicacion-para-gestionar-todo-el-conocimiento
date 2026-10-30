import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';

import '../text_notes_harness.dart';

/// Las notas en el texto (F45, mejora 19, decisión I) sobre SQLite real: cada
/// texto por su clave, en el orden del texto, con «Deshacer», sin tocar nunca
/// el documento, y las notas de los resaltados de antes por la misma interfaz.
void main() {
  late TextNotesHarness h;

  const text = 'Moisés sube al monte. Baja con las tablas de la ley.';

  setUp(() async => h = await TextNotesHarness.create());
  tearDown(() => h.close());

  group('cada texto, por su clave', () {
    test('lo de la Biblioteca no aparece en Procesado, ni al revés, ni lo '
        'de la copia en el texto procesado, ni lo de una creación', () async {
      final library = await h.source('fuente', text: text);
      final documentId = await h.creations.processedDoc('fuente', text: text);
      final copy = ProcessedOriginalNotes(documentId);
      final own = ProcessedTextNotes(documentId);
      final creation = await h.creation();

      await h.noteOn(library, text, 'monte', note: 'De la Biblioteca');
      await h.noteOn(copy, text, 'monte', note: 'De la copia');
      await h.noteOn(own, text, 'tablas', note: 'Del texto procesado');
      await h.noteOn(creation, text, 'ley', note: 'De lo creado');

      Future<List<String>> said(TextNoteTarget target) async => [
        for (final n in await h.notesOf(target)) n.note,
      ];
      expect(await said(library), ['De la Biblioteca']);
      expect(await said(copy), ['De la copia']);
      expect(await said(own), ['Del texto procesado']);
      expect(await said(creation), ['De lo creado']);
      expect(await h.notes.watchCount(library).first, 1);
      expect(await h.notes.watchCount(copy).first, 1);
    });

    test('la nota de otra fuente no aparece', () async {
      final a = await h.source('a', text: text);
      final b = await h.source('b', text: text);
      await h.noteOn(a, text, 'monte');

      expect(await h.notesOf(b), isEmpty);
      expect(await h.notes.watchCount(b).first, 0);
    });
  });

  group('en el orden del texto', () {
    test('por dónde empiezan; las sin lugar, al final, de la más vieja a la '
        'más nueva', () async {
      final library = await h.source('fuente', text: text);
      h.vault.at(1);
      await h.noteOn(library, text, 'ley', note: 'tercera');
      h.vault.at(2);
      await h.noteOn(library, text, 'Moisés', note: 'primera');
      h.vault.at(3);
      await h.noteOn(library, text, 'tablas', note: 'segunda');
      // Dos que quedaron sin lugar (el texto cambió y su pedazo ya no está).
      for (final (minute, id) in [(5, 'perdida-nueva'), (4, 'perdida-vieja')]) {
        h.vault.at(minute);
        final lost = await h.noteOn(library, text, 'sube', note: id);
        await (h.db.update(
          h.db.textNotes,
        )..where((n) => n.id.equals(lost.id))).write(
          const TextNotesCompanion(
            startOffset: Value(null),
            endOffset: Value(null),
          ),
        );
      }

      final notes = await h.notesOf(library);
      expect(
        [for (final n in notes) n.note],
        ['primera', 'segunda', 'tercera', 'perdida-vieja', 'perdida-nueva'],
      );
      expect(notes.last.hasPlace, isFalse);
    });
  });

  group('poner, editar, cambiar de color', () {
    test('la nota guarda su texto, su lugar, el pedazo, el color y las '
        'fechas, y se ve enseguida', () async {
      final library = await h.source('fuente', text: text);
      final seen = h.notes.watchNotes(library);
      final updates = <List<TextNote>>[];
      final sub = seen.listen(updates.add);
      addTearDown(sub.cancel);

      h.vault.at(3);
      final note = await h.noteOn(
        library,
        text,
        'tablas',
        note: '  Las dos tablas  ',
        color: HighlightColor.violet,
      );
      await pumpEventQueue();

      expect(note.note, 'Las dos tablas');
      expect(text.substring(note.start!, note.end), 'tablas');
      expect(note.color, HighlightColor.violet);
      expect(note.renditionId, 'rend-fuente');
      expect(note.createdAt, h.vault.now);
      expect(updates.last, [note]);
    });

    test('editar cambia lo que dice y su fecha; el color, también', () async {
      final library = await h.source('fuente', text: text);
      final note = await h.noteOn(library, text, 'monte');

      h.vault.at(10);
      final edited = (await h.notes.edit(
        note,
        'El Sinaí',
      )).getRight().toNullable()!;
      expect(edited.note, 'El Sinaí');
      expect(edited.updatedAt, h.vault.now);
      expect(edited.createdAt, note.createdAt);

      h.vault.at(20);
      final recolored = (await h.notes.recolor(
        edited,
        HighlightColor.turquoise,
      )).getRight().toNullable()!;
      expect(recolored.color, HighlightColor.turquoise);
      expect(recolored.updatedAt, h.vault.now);

      final [stored] = await h.notesOf(library);
      expect(stored, recolored);
    });

    test('en blanco no se guarda, ni al ponerla ni al editarla', () async {
      final library = await h.source('fuente', text: text);
      final blank = await h.notes.create(
        target: library,
        start: 0,
        end: 6,
        excerpt: 'Moisés',
        note: '   ',
        color: HighlightColor.lime,
      );
      expect(blank.getLeft().toNullable(), isA<ValidationFailure>());

      final note = await h.noteOn(library, text, 'monte', note: 'Algo');
      final edit = await h.notes.edit(note, '\n ');
      expect(edit.getLeft().toNullable(), isA<ValidationFailure>());
      expect((await h.notesOf(library)).single.note, 'Algo');
    });

    test('un pedazo que no es válido no se guarda', () async {
      final library = await h.source('fuente', text: text);
      for (final (start, end) in [(-1, 4), (5, 5), (6, 2)]) {
        final result = await h.notes.create(
          target: library,
          start: start,
          end: end,
          excerpt: 'x',
          note: 'Algo',
          color: HighlightColor.lime,
        );
        expect(result.isLeft(), isTrue, reason: '[$start, $end)');
      }
      expect(await h.notesOf(library), isEmpty);
    });
  });

  group('borrar, con «Deshacer», sin tocar nunca el documento', () {
    test('se borra la nota, y «Deshacer» la devuelve igual: el mismo id, '
        'el mismo lugar y las mismas fechas', () async {
      final library = await h.source('fuente', text: text);
      h.vault.at(2);
      final note = await h.noteOn(library, text, 'monte', note: 'Clave');
      final before = await h.vault.counts();

      h.vault.at(9);
      final removed = (await h.notes.delete(note)).getRight().toNullable()!;
      expect(await h.notesOf(library), isEmpty);
      expect(removed, note);

      expect((await h.notes.restore(removed)).isRight(), isTrue);
      expect(await h.notesOf(library), [note]);
      expect(await h.vault.counts(), before);
    });

    test('borrar una nota no toca el documento: ni su texto, ni su archivo, '
        'ni sus resaltados, ni el elemento', () async {
      final library = await h.source('fuente', text: text);
      await h.highlightWithNote('r1', 'fuente', text, 'Baja');
      final note = await h.noteOn(library, text, 'monte');
      final item = await h.vault.entry('fuente');
      final renditions = await h.vault.renditionsOf('fuente');
      final highlights = await h.db.select(h.db.highlights).get();

      await h.notes.delete(note);

      expect(await h.vault.entry('fuente'), item);
      expect(await h.vault.renditionsOf('fuente'), renditions);
      expect(await h.db.select(h.db.highlights).get(), highlights);
    });

    test('«Deshacer» no puede devolver una nota cuyo texto se borró de '
        'verdad', () async {
      final library = await h.source('fuente', text: text);
      final note = await h.noteOn(library, text, 'monte');
      await h.notes.delete(note);
      await h.db.customStatement("DELETE FROM item WHERE id = 'fuente'");

      final restored = await h.notes.restore(note);
      expect(restored.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await h.db.select(h.db.textNotes).get(), isEmpty);
    });

    test('lo que ya no existe no se edita ni se borra', () async {
      final library = await h.source('fuente', text: text);
      final note = await h.noteOn(library, text, 'monte');
      await h.notes.delete(note);

      expect((await h.notes.edit(note, 'Otra')).isLeft(), isTrue);
      expect(
        (await h.notes.recolor(note, HighlightColor.gray)).isLeft(),
        isTrue,
      );
      expect((await h.notes.delete(note)).isLeft(), isTrue);
    });
  });

  group(
    'las notas de los resaltados de antes (F38), por la misma interfaz',
    () {
      test(
        'se leen con las del original de la Biblioteca y se cuentan; las sin '
        'nota o en blanco, no; en Procesado, ninguna',
        () async {
          final library = await h.source('fuente', text: text);
          final documentId = await h.creations.processedDoc(
            'fuente',
            text: text,
          );
          await h.highlightWithNote(
            'con',
            'fuente',
            text,
            'monte',
            note: 'Vieja',
          );
          await h.highlightWithNote('sin', 'fuente', text, 'tablas');
          await h.highlightWithNote(
            'blanca',
            'fuente',
            text,
            'ley',
            note: '  ',
          );
          final fresh = await h.noteOn(library, text, 'Moisés', note: 'Nueva');

          final notes = await h.notesOf(library);
          expect(
            [for (final n in notes) (n.origin, n.note)],
            [
              (TextNoteOrigin.note, 'Nueva'),
              (TextNoteOrigin.highlight, 'Vieja'),
            ],
          );
          expect(notes.first, fresh);
          final old = notes.last;
          expect(old.id, 'con');
          expect(old.color, HighlightColor.coral);
          expect(text.substring(old.start!, old.end), 'monte');
          expect(old.renditionId, 'rend-fuente');
          expect(await h.notes.watchCount(library).first, 2);

          expect(await h.notesOf(ProcessedOriginalNotes(documentId)), isEmpty);
          expect(await h.notesOf(ProcessedTextNotes(documentId)), isEmpty);
        },
      );

      test('editarla y cambiarle el color van al resaltado; borrarla le saca '
          'la nota y deja el resaltado; «Deshacer» se la devuelve', () async {
        final library = await h.source('fuente', text: text);
        await h.highlightWithNote('r1', 'fuente', text, 'monte', note: 'Vieja');
        final [old] = await h.notesOf(library);

        await h.notes.edit(old, 'Retocada');
        await h.notes.recolor(old, HighlightColor.blue);
        Future<HighlightRow> row() => (h.db.select(
          h.db.highlights,
        )..where((r) => r.id.equals('r1'))).getSingle();
        expect((await row()).note, 'Retocada');
        expect((await row()).color, HighlightColor.blue);
        expect(await h.db.select(h.db.textNotes).get(), isEmpty);

        final [current] = await h.notesOf(library);
        await h.notes.delete(current);
        expect((await row()).note, isNull);
        expect(await h.notesOf(library), isEmpty);
        expect(await h.db.select(h.db.highlights).get(), hasLength(1));

        await h.notes.restore(current);
        expect((await row()).note, 'Retocada');
        expect(await h.notesOf(library), [current]);
      });
    },
  );

  test('la clave del texto que se lee dice de qué texto son las notas', () {
    const source = (
      itemId: 'fuente',
      renditionId: 'rend-fuente',
      content: text,
      markdown: false,
    );
    expect(
      textNoteTargetOf(source),
      const TextNoteTarget.sourceOriginal(
        sourceId: 'fuente',
        renditionId: 'rend-fuente',
      ),
    );
    expect(
      textNoteTargetOf((
        itemId: 'doc',
        renditionId: processedOriginalStudyKeyFor('doc'),
        content: text,
        markdown: false,
      )),
      const TextNoteTarget.processedOriginal('doc'),
    );
    expect(
      textNoteTargetOf((
        itemId: 'doc',
        renditionId: processedStudyKeyFor('doc'),
        content: text,
        markdown: false,
      )),
      const TextNoteTarget.processedText('doc'),
    );
  });
}
