import 'package:flutter_test/flutter_test.dart';

import '../../../../support/test_vault.dart';

/// Lo que la IA hizo viaja en la fusión de bóvedas (F27): las pasadas, para
/// poder deshacer acá lo que llegó de otro dispositivo; la procedencia de cada
/// vínculo, tarjeta y propiedad; lo adoptado, que sigue siendo de la persona;
/// y lo que «no era», que hace de lápida y no deja que una copia vieja lo
/// devuelva.
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

  Future<void> addRun(TestVault vault, String id, String itemId) =>
      vault.db.customStatement(
        'INSERT INTO ai_runs (id, item_id, started_at, relations_created) '
        "VALUES ('$id', '$itemId', 1790000000, 1)",
      );

  Future<void> markAi(TestVault vault, String table, String id, String run) =>
      vault.db.customStatement(
        "UPDATE $table SET origin = 'ai', ai_run_id = '$run' WHERE id = '$id'",
      );

  Future<void> reject(
    TestVault vault, {
    required String id,
    required String kind,
    required String itemId,
    required String fingerprint,
    String? otherItemId,
    String? subjectId,
  }) => vault.db.customStatement(
    'INSERT INTO ai_rejections (id, kind, item_id, other_item_id, '
    'fingerprint, subject_id, created_at) VALUES '
    "('$id', '$kind', '$itemId', "
    "${otherItemId == null ? 'NULL' : "'$otherItemId'"}, '$fingerprint', "
    "${subjectId == null ? 'NULL' : "'$subjectId'"}, 1790000000)",
  );

  Future<Map<String, Object?>> rowOf(TestVault vault, String sql) async =>
      (await vault.db.customSelect(sql).getSingle()).data;

  group('las pasadas', () {
    test(
      'entran con su elemento, y lo que hicieron llega con su pasada',
      () async {
        await shareItems();
        pc.at(5);
        await addRun(pc, 'pasada', 'a');
        await pc.addRelation('r1', 'a', 'b');
        await markAi(pc, 'relations', 'r1', 'pasada');
        await pc.addFlashcard('t1', 'a');
        await markAi(pc, 'flashcards', 't1', 'pasada');

        tel.at(9);
        final result = await tel.mergeFrom(pc);

        expect(result.aiRunsAdded, 1);
        final relation = await rowOf(
          tel,
          "SELECT origin, ai_run_id FROM relations WHERE id = 'r1'",
        );
        expect(relation, {'origin': 'ai', 'ai_run_id': 'pasada'});
        final card = await rowOf(
          tel,
          "SELECT origin, ai_run_id FROM flashcards WHERE id = 't1'",
        );
        expect(card, {'origin': 'ai', 'ai_run_id': 'pasada'});
      },
    );

    test('fusionar dos veces no repite ninguna', () async {
      await shareItems();
      await addRun(pc, 'pasada', 'a');

      await tel.mergeFrom(pc);
      final again = await tel.mergeFrom(pc);

      expect(again.aiRunsAdded, 0);
      expect(again.changedNothing, isTrue);
    });
  });

  group('lo adoptado', () {
    test(
      'uno de la IA que en la copia la persona editó es suyo también acá',
      () async {
        await shareItems();
        await addRun(tel, 'pasada', 'a');
        await tel.addRelation('r1', 'a', 'b');
        await markAi(tel, 'relations', 'r1', 'pasada');
        await tel.addFlashcard('t1', 'a');
        await markAi(tel, 'flashcards', 't1', 'pasada');
        await pc.mergeFrom(tel);
        // En la copia, la persona los adopta.
        await pc.db.customStatement(
          "UPDATE relations SET origin = 'user', ai_run_id = NULL",
        );
        await pc.db.customStatement(
          "UPDATE flashcards SET origin = 'user', ai_run_id = NULL",
        );

        await tel.mergeFrom(pc);

        expect(await rowOf(tel, 'SELECT origin, ai_run_id FROM relations'), {
          'origin': 'user',
          'ai_run_id': null,
        });
        expect(await rowOf(tel, 'SELECT origin, ai_run_id FROM flashcards'), {
          'origin': 'user',
          'ai_run_id': null,
        });
      },
    );
  });

  group('lo que «no era»', () {
    test('viaja, y una vez es una vez', () async {
      await shareItems();
      await reject(
        pc,
        id: 'no-1',
        kind: 'relation',
        itemId: 'a',
        otherItemId: 'b',
        fingerprint: 'b:relatedTo',
      );
      await reject(
        tel,
        id: 'no-acá',
        kind: 'relation',
        itemId: 'a',
        otherItemId: 'b',
        fingerprint: 'b:relatedTo',
      );
      await reject(
        pc,
        id: 'no-2',
        kind: 'flashcard',
        itemId: 'a',
        fingerprint: 'que es',
      );

      final result = await tel.mergeFrom(pc);

      // La del vínculo ya estaba acá con otro id: entra solo la otra.
      expect(result.aiRejectionsAdded, 1);
    });

    test(
      'un vínculo de la IA que acá «no era» no vuelve de una copia vieja',
      () async {
        await shareItems();
        await addRun(pc, 'pasada', 'a');
        await pc.addRelation('r1', 'b', 'a');
        await markAi(pc, 'relations', 'r1', 'pasada');
        // Acá la persona dijo que no: «a» y «b», citan, sin orden.
        await reject(
          tel,
          id: 'no',
          kind: 'relation',
          itemId: 'a',
          otherItemId: 'b',
          fingerprint: 'b:cites',
        );

        final preview = await tel.previewFrom(pc);
        final result = await tel.mergeFrom(pc);

        expect(preview.newRelations, 0);
        expect(result.relationsAdded, 0);
      },
    );

    test('pero uno de la persona sí entra aunque coincida', () async {
      await shareItems();
      await pc.addRelation('r1', 'a', 'b');
      await reject(
        tel,
        id: 'no',
        kind: 'relation',
        itemId: 'a',
        otherItemId: 'b',
        fingerprint: 'b:cites',
      );

      final result = await tel.mergeFrom(pc);

      expect(result.relationsAdded, 1);
    });

    test('una tarjeta de la IA que acá «no era» tampoco vuelve', () async {
      await shareItems();
      await addRun(pc, 'pasada', 'a');
      await pc.addFlashcard('t1', 'a');
      await markAi(pc, 'flashcards', 't1', 'pasada');
      await reject(
        tel,
        id: 'no',
        kind: 'flashcard',
        itemId: 'a',
        fingerprint: 'que',
        subjectId: 't1',
      );

      final preview = await tel.previewFrom(pc);
      final result = await tel.mergeFrom(pc);

      expect(preview.newFlashcards, 0);
      expect(result.flashcardsAdded, 0);
    });

    test(
      'ni una propiedad de la IA que acá «no era» en ese elemento',
      () async {
        await shareItems();
        final tema = await tel.temaId();
        await tel.addPropertyValue('roma', tema, 'Roma');
        await pc.mergeFrom(tel);
        await addRun(pc, 'pasada', 'a');
        await pc.db.customStatement(
          'INSERT INTO item_property_values (item_id, property_value_id, '
          "origin, ai_run_id) VALUES ('a', 'roma', 'ai', 'pasada'), "
          "('b', 'roma', 'ai', 'pasada')",
        );
        await reject(
          tel,
          id: 'no',
          kind: 'property',
          itemId: 'a',
          fingerprint: 'tema\u001froma',
          subjectId: 'roma',
        );

        await tel.mergeFrom(pc);

        final rows = await tel.db
            .customSelect(
              'SELECT item_id, origin, ai_run_id FROM item_property_values '
              "WHERE property_value_id = 'roma'",
            )
            .get();
        expect(
          [for (final r in rows) r.data],
          [
            {'item_id': 'b', 'origin': 'ai', 'ai_run_id': 'pasada'},
          ],
        );
      },
    );
  });
}
