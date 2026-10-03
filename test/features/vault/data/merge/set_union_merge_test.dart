import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/vault/data/merge/ai_provenance_merge.dart';
import 'package:sinapsis/features/vault/data/merge/set_union_merge.dart';
import 'package:sinapsis/features/vault/data/merge/vocabulary_merge.dart';

import '../../../../support/test_vault.dart';

/// Lo que se une por conjuntos en la fusión (F11): vínculos, resaltados,
/// tarjetas y sus repasos, procedencias y conversaciones.
///
/// Es una UNIÓN: entra lo que esta bóveda no tiene, por su identificador, y
/// nada se quita ni se cambia. Sin lápidas, una quita hecha en un lado puede
/// reaparecer si la copia todavía la tenía: es lo conservador.
void main() {
  late TestVault tel;
  late TestVault pc;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  /// Dos fuentes, «a» y «b», que las dos bóvedas tienen.
  Future<void> shareItems() async {
    tel.at(1);
    await tel.saveSource('a');
    await tel.saveSource('b');
    pc.at(2);
    await pc.mergeFrom(tel);
  }

  Future<Set<String>> idsOf(TestVault vault, String table) async => {
    for (final r in await vault.db.customSelect('SELECT id FROM $table').get())
      r.read<String>('id'),
  };

  group('los vínculos', () {
    test('entran los que acá no hay, con lo que tienen', () async {
      await shareItems();
      pc.at(5);
      await pc.addRelation('r1', 'a', 'b');
      await pc.db.customStatement(
        "UPDATE relations SET note = 'porque sí', source_char_start = 3, "
        'source_char_end = 9',
      );

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.relationsAdded, 1);
      final row = await tel.db
          .customSelect(
            'SELECT from_item_id, to_item_id, kind, note, source_char_start, '
            'source_char_end FROM relations',
          )
          .getSingle();
      expect(row.read<String>('from_item_id'), 'a');
      expect(row.read<String>('to_item_id'), 'b');
      expect(row.read<String>('kind'), RelationKind.cites.name);
      expect(row.read<String>('note'), 'porque sí');
      expect(row.read<int>('source_char_start'), 3);
      expect(row.read<int>('source_char_end'), 9);
    });

    test(
      'uno es el mismo por su id o por unir lo mismo con el mismo tipo',
      () async {
        await shareItems();
        await tel.addRelation('r-tel', 'a', 'b');
        await pc.addRelation('r-pc', 'a', 'b'); // mismo extremo y tipo, otro id
        await pc.addRelation('r-tel', 'a', 'b', kind: RelationKind.continues);
        await pc.addRelation('r-inverso', 'b', 'a'); // otro sentido: distinto

        final result = await tel.mergeFrom(pc);

        // «r-tel» de la copia tiene el id de uno de acá: es el mismo aunque
        // cuente otra cosa; «r-pc» une lo mismo que «r-tel»; solo el inverso es
        // nuevo.
        expect(result.relationsAdded, 1);
        expect(await idsOf(tel, 'relations'), {'r-tel', 'r-inverso'});
      },
    );

    test(
      'un vínculo con un elemento nuevo de la copia también entra',
      () async {
        await shareItems();
        pc.at(5);
        await pc.saveSource('c');
        await pc.addRelation('r1', 'a', 'c');

        tel.at(9);
        final result = await tel.mergeFrom(pc);

        expect(result.itemsAdded, 1);
        expect(result.relationsAdded, 1);
      },
    );

    test(
      'lo que acá se quitó puede volver: una unión no tiene lápidas',
      () async {
        await shareItems();
        pc.at(5);
        await pc.addRelation('r1', 'a', 'b');
        tel.at(6);
        await tel.mergeFrom(pc);
        await tel.db.customStatement('DELETE FROM relations');

        tel.at(9);
        final result = await tel.mergeFrom(pc);

        // Es lo conservador y queda dicho: sin lápidas no se distingue «lo
        // quité» de «nunca lo tuve».
        expect(result.relationsAdded, 1);
      },
    );
  });

  group('los resaltados', () {
    test('entran los que acá no hay, sobre su forma', () async {
      await shareItems();
      tel.at(4);
      await tel.addHighlight('hl-tel', 'a');
      pc.at(5);
      await pc.addHighlight('hl-tel', 'a'); // el mismo, ya está acá
      await pc.addHighlight('hl-pc', 'a', start: 6, end: 9);

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.highlightsAdded, 1);
      expect(await idsOf(tel, 'highlights'), {'hl-tel', 'hl-pc'});
    });
  });

  group('las tarjetas', () {
    test('entran las que acá no hay, con su rango en la fuente', () async {
      await shareItems();
      pc.at(5);
      await pc.addFlashcard('fc', 'a', back: 'Esto.');
      await pc.db.customStatement(
        'UPDATE flashcards SET source_char_start = 4, source_char_end = 12, '
        "source_chunk_id = NULL WHERE id = 'fc'",
      );

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.flashcardsAdded, 1);
      final card = await tel.db.select(tel.db.flashcards).getSingle();
      expect(card.front, '¿Qué?');
      expect(card.sourceCharStart, 4);
      expect(card.sourceCharEnd, 12);
      // Los chunks no viajan: el identificador no apunta a nada acá.
      expect(card.sourceChunkId, isNull);
    });

    test('una tarjeta nueva entra sin marca de exportada, aunque la incoming '
        'ya la tuviera (F17, D4)', () async {
      await shareItems();
      pc.at(5);
      await pc.addFlashcard('fc', 'a');
      await pc.db.customStatement(
        'UPDATE flashcards SET last_exported_at = 1789000000',
      );

      tel.at(9);
      await tel.mergeFrom(pc);

      final card = await tel.db.select(tel.db.flashcards).getSingle();
      // Es de ESTE dispositivo: nunca exportó esta tarjeta a su propio
      // .apkg, así que no hereda la fecha de la incoming.
      expect(card.lastExportedAt, isNull);
    });

    test('con un fragmento que acá existe, lo conserva', () async {
      await shareItems();
      // Los dos tienen la tarjeta en un fragmento con el mismo identificador
      // (procesaron la misma fuente): tel tiene el chunk; la tarjeta es nueva.
      await tel.db.customStatement('''
        INSERT INTO chunks (id, item_id, seq, content, char_start, char_end)
        VALUES ('chunk-x', 'a', 99, 'Texto de la fuente.', 0, 19)''');
      await pc.db.customStatement('''
        INSERT INTO chunks (id, item_id, seq, content, char_start, char_end)
        VALUES ('chunk-x', 'a', 99, 'Texto de la fuente.', 0, 19)''');
      pc.at(5);
      await pc.addFlashcard('fc', 'a');
      await pc.db.customStatement(
        "UPDATE flashcards SET source_chunk_id = 'chunk-x'",
      );

      tel.at(9);
      await tel.mergeFrom(pc);

      expect(
        (await tel.db.select(tel.db.flashcards).getSingle()).sourceChunkId,
        'chunk-x',
      );
    });

    test(
      'la que las dos tienen toma el calendario del repaso más reciente',
      () async {
        await shareItems();
        tel.at(3);
        await tel.addFlashcard('fc', 'a', front: 'Mío', back: 'Mía');
        pc.at(4);
        await pc.mergeFrom(tel);
        pc.at(20);
        await pc.reviewCard('fc');

        tel.at(30);
        final result = await tel.mergeFrom(pc);

        expect(result.flashcardsUpdated, 1);
        final card = await tel.db.select(tel.db.flashcards).getSingle();
        expect(card.intervalDays, 6);
        expect(card.repetitions, 2);
        expect(card.lastReviewedAt, pc.now);
        // El texto de la tarjeta no se toca.
        expect(card.front, 'Mío');
      },
    );

    test('si acá se repasó después, el calendario de acá no cambia', () async {
      await shareItems();
      tel.at(3);
      await tel.addFlashcard('fc', 'a');
      pc.at(4);
      await pc.mergeFrom(tel);
      pc.at(20);
      await pc.reviewCard('fc', intervalDays: 3);
      tel.at(25);
      await tel.reviewCard('fc', intervalDays: 10);

      tel.at(30);
      final result = await tel.mergeFrom(pc);

      expect(result.flashcardsUpdated, 0);
      expect(
        (await tel.db.select(tel.db.flashcards).getSingle()).intervalDays,
        10,
      );
    });

    test('la de la copia que nunca se repasó no pisa una repasada', () async {
      await shareItems();
      tel.at(3);
      await tel.addFlashcard('fc', 'a');
      pc.at(4);
      await pc.mergeFrom(tel);
      tel.at(20);
      await tel.reviewCard('fc', intervalDays: 8);

      tel.at(30);
      final result = await tel.mergeFrom(pc);

      expect(result.flashcardsUpdated, 0);
      expect(
        (await tel.db.select(tel.db.flashcards).getSingle()).intervalDays,
        8,
      );
    });

    test('los repasos entran, y no repetidos', () async {
      await shareItems();
      tel.at(3);
      await tel.addFlashcard('fc', 'a');
      pc.at(4);
      await pc.mergeFrom(tel);
      await tel.addReview('rv-tel', 'fc');
      pc.at(20);
      await pc.reviewCard('fc');
      await pc.addReview('rv-pc', 'fc');
      await pc.addReview('rv-tel', 'fc'); // el mismo, ya está acá

      tel.at(30);
      final result = await tel.mergeFrom(pc);

      expect(result.reviewsAdded, 1);
      expect(await idsOf(tel, 'review_log'), {'rv-tel', 'rv-pc'});
    });

    test('la forma de la tarjeta (F20) viaja con ella', () async {
      await shareItems();
      pc.at(5);
      await pc.addFlashcard('fc', 'a', kind: FlashcardKind.trueFalse);

      tel.at(9);
      await tel.mergeFrom(pc);

      final card = await tel.db.select(tel.db.flashcards).getSingle();
      expect(card.kind, FlashcardKind.trueFalse);
    });

    test('las opciones de una tarjeta de opción múltiple (F20) entran junto '
        'con ella, cada una con su procedencia', () async {
      await shareItems();
      pc.at(5);
      await pc.addFlashcard('fc', 'a', kind: FlashcardKind.multipleChoice);
      await pc.addFlashcardOption(
        'op-1',
        'fc',
        content: 'Correcta',
        isCorrect: true,
      );
      await pc.addFlashcardOption(
        'op-2',
        'fc',
        content: 'Distractor',
        position: 1,
      );

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.flashcardOptionsAdded, 2);
      final options = await (tel.db.select(
        tel.db.flashcardOptions,
      )..orderBy([(o) => OrderingTerm(expression: o.position)])).get();
      expect(options.map((o) => o.content), ['Correcta', 'Distractor']);
      expect(options.map((o) => o.isCorrect), [true, false]);
    });

    test(
      'las opciones de una tarjeta que acá ya existía no se repiten',
      () async {
        await shareItems();
        tel.at(3);
        await tel.addFlashcard('fc', 'a', kind: FlashcardKind.multipleChoice);
        await tel.addFlashcardOption('op-1', 'fc', isCorrect: true);
        pc.at(4);
        await pc.mergeFrom(tel);

        tel.at(9);
        final result = await tel.mergeFrom(pc);

        expect(result.flashcardOptionsAdded, 0);
        expect(await idsOf(tel, 'flashcard_options'), {'op-1'});
      },
    );
  });

  group('las procedencias y las conversaciones', () {
    test('entran las procedencias de un elemento que acá existe', () async {
      await shareItems();
      pc.at(5);
      await pc.addProvenance('pv', 'a');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.provenancesAdded, 1);
      expect(await idsOf(tel, 'merged_provenances'), {'pv'});
    });

    test('una conversación nueva entra con sus mensajes', () async {
      pc.at(5);
      await pc.addConversation('c1', title: 'Sobre Roma');
      await pc.addMessage('m1', 'c1');
      await pc.addMessage('m2', 'c1', content: 'Chau');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.conversationsAdded, 1);
      expect(result.messagesAdded, 2);
      expect(await idsOf(tel, 'chat_messages'), {'m1', 'm2'});
      expect(
        (await tel.db.select(tel.db.conversations).getSingle()).title,
        'Sobre Roma',
      );
    });

    test('una conversación acotada a un cuaderno que no existe acá entra sin '
        'acotar, no con una clave rota (F16)', () async {
      pc.at(5);
      await pc.addNotebook('nb-1');
      await pc.addConversation('c1', notebookId: 'nb-1');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.conversationsAdded, 1);
      expect(
        (await tel.db.select(tel.db.conversations).getSingle()).notebookId,
        isNull,
      );
    });

    test('una conversación acotada a un cuaderno que también existe acá lo '
        'conserva (F16)', () async {
      pc.at(5);
      await pc.addNotebook('nb-1');
      await pc.addConversation('c1', notebookId: 'nb-1');

      tel.at(9);
      await tel.addNotebook('nb-1');
      await tel.mergeFrom(pc);

      expect(
        (await tel.db.select(tel.db.conversations).getSingle()).notebookId,
        'nb-1',
      );
    });

    test('una conversación de las dos junta los mensajes y queda la fecha más '
        'reciente', () async {
      tel.at(1);
      await tel.addConversation('c1');
      await tel.addMessage('m-tel', 'c1');
      pc.at(2);
      await pc.mergeFrom(tel);
      pc.at(20);
      await pc.addMessage('m-pc', 'c1');
      await pc.db.customStatement(
        'UPDATE conversations SET updated_at = updated_at + 1000',
      );

      tel.at(30);
      final result = await tel.mergeFrom(pc);

      expect(result.conversationsAdded, 0);
      expect(result.messagesAdded, 1);
      expect(await idsOf(tel, 'chat_messages'), {'m-tel', 'm-pc'});
      final before =
          (await pc.db.select(pc.db.conversations).getSingle()).updatedAt;
      expect(
        (await tel.db.select(tel.db.conversations).getSingle()).updatedAt,
        before,
      );
    });
  });

  group('en general', () {
    test('fusionar dos veces no duplica nada', () async {
      await shareItems();
      pc.at(5);
      await pc.addRelation('r1', 'a', 'b');
      await pc.addHighlight('hl', 'a');
      await pc.addFlashcard('fc', 'a');
      await pc.addReview('rv', 'fc');
      await pc.addProvenance('pv', 'a');
      await pc.addConversation('c1');
      await pc.addMessage('m1', 'c1');
      tel.at(9);
      await tel.mergeFrom(pc);
      final counts = await tel.counts();

      tel.at(12);
      final again = await tel.mergeFrom(pc);

      expect(again.changedNothing, isTrue);
      expect(await tel.counts(), counts);
    });

    test('un elemento que acá está en la papelera también recibe lo que cuelga '
        'de él', () async {
      await shareItems();
      tel.at(3);
      await tel.library.delete('a');
      pc.at(5);
      await pc.addFlashcard('fc', 'a');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.flashcardsAdded, 1);
      expect((await tel.entry('a')).deletedAt, isNotNull);
    });

    test('no se pierde lo de acá: la copia solo suma', () async {
      await shareItems();
      tel.at(3);
      await tel.addRelation('mio', 'a', 'b');
      await tel.addFlashcard('mia', 'a');
      await tel.addHighlight('hl-mio', 'b');
      final before = await tel.counts();

      tel.at(9);
      await tel.mergeFrom(pc);

      final after = await tel.counts();
      for (final entry in before.entries) {
        expect(
          after[entry.key],
          greaterThanOrEqualTo(entry.value),
          reason: entry.key,
        );
      }
    });

    test('la vista previa cuenta lo mismo que se une', () async {
      await shareItems();
      pc.at(5);
      await pc.addRelation('r1', 'a', 'b');
      await pc.addRelation('r2', 'b', 'a');
      await pc.addHighlight('hl', 'a');
      await pc.addFlashcard('fc', 'a');
      await pc.addConversation('c1');
      await pc.addMessage('m1', 'c1');

      tel.at(9);
      final preview = await tel.previewFrom(pc);
      final result = await tel.mergeFrom(pc);

      expect(preview.newRelations, result.relationsAdded);
      expect(preview.newHighlights, result.highlightsAdded);
      expect(preview.newFlashcards, result.flashcardsAdded);
      expect(preview.newConversations, result.conversationsAdded);
      expect(result.relationsAdded, 2);
      expect(preview.hasNothingNew, isFalse);
    });
  });

  group('las columnas que se copian', () {
    test('cubren las tablas enteras: una columna nueva no se pierde', () async {
      Future<Set<String>> columnsOf(String table) async => {
        for (final r
            in await tel.db.customSelect('PRAGMA table_info($table)').get())
          r.read<String>('name'),
      };

      expect(kRelationColumns.toSet(), await columnsOf('relations'));
      expect(kHighlightColumns.toSet(), await columnsOf('highlights'));
      expect(kFlashcardColumns.toSet(), await columnsOf('flashcards'));
      expect(
        kFlashcardOptionColumns.toSet(),
        await columnsOf('flashcard_options'),
      );
      expect(kReviewLogColumns.toSet(), await columnsOf('review_log'));
      expect(kProvenanceColumns.toSet(), await columnsOf('merged_provenances'));
      expect(kConversationColumns.toSet(), await columnsOf('conversations'));
      expect(kChatMessageColumns.toSet(), await columnsOf('chat_messages'));
      expect(kHabitEventColumns.toSet(), await columnsOf('habit_event'));
      // Las pasadas de la IA, lo que «no era» y las asignaciones de
      // propiedades, que ahora llevan su pasada (F27).
      expect(kAiRunColumns.toSet(), await columnsOf('ai_runs'));
      expect(kAiRejectionColumns.toSet(), await columnsOf('ai_rejections'));
      // Lo que cada pasada completó del tema y la referencia (v35).
      expect(
        kAiFieldChangeColumns.toSet(),
        await columnsOf('ai_field_changes'),
      );
      expect(
        kItemPropertyValueColumns.toSet(),
        await columnsOf('item_property_values'),
      );
    });
  });

  group('el rastro de la racha (F17, D6)', () {
    test('entra el que acá no hay, con lo que tiene', () async {
      pc.at(5);
      await pc.addHabitEvent('ev-pc', HabitEventKind.triage);

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.habitEventsAdded, 1);
      expect(await idsOf(tel, 'habit_event'), {'ev-pc'});
    });

    test('el mismo id no entra dos veces', () async {
      tel.at(3);
      await tel.addHabitEvent('ev-1', HabitEventKind.vocabulary);
      pc.at(4);
      await pc.mergeFrom(tel);
      await pc.addHabitEvent('ev-2', HabitEventKind.triage);

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.habitEventsAdded, 1);
      expect(await idsOf(tel, 'habit_event'), {'ev-1', 'ev-2'});
    });
  });
}
