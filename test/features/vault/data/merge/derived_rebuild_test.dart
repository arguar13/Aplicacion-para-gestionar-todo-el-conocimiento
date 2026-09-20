import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';

import '../../../../support/test_vault.dart';

/// Lo derivado en la fusión (F11): los chunks de las fuentes, los enlaces en
/// línea de las notas y el fragmento de las tarjetas.
///
/// No viaja en la copia: se calcula del texto, y sus identificadores no son
/// estables. La fusión copia lo que el usuario escribió y RECALCULA lo demás,
/// con las mismas funciones que usa guardar un elemento, solo para lo que llegó
/// o cambió.
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

  Future<Set<String>> chunkIds(TestVault vault, String itemId) async => {
    for (final r
        in await vault.db
            .customSelect(
              'SELECT id FROM chunks WHERE item_id = ?',
              variables: [Variable<String>(itemId)],
            )
            .get())
      r.read<String>('id'),
  };

  group('los chunks de una fuente', () {
    test('se rehacen del texto de acá, y lo reconstruyen exacto', () async {
      const text =
          'Primer párrafo de la fuente.\n\nSegundo párrafo, con tildes y ñ.\n\n'
          'Un tercero, para que haya más de un chunk que juntar.';
      pc.at(3);
      await pc.saveSource('a', text: text);

      final result = await tel.mergeFrom(pc);

      expect(result.sourcesChunked, 1);
      expect(result.sourcesPending, 0);
      expect(await tel.count('chunks'), greaterThan(0));
      final report = await verifyChunkInvariant(tel.db);
      expect(report.holds, isTrue, reason: report.violations.join('; '));
      expect(report.sourcesChecked, 1);
      // El texto, tal cual.
      expect((await tel.renditionsOf('a')).single.content, text);
    });

    test('no son los de la copia: sus identificadores no viajan', () async {
      pc.at(3);
      await pc.saveSource('a');
      final theirs = await chunkIds(pc, 'a');
      expect(theirs, isNotEmpty);

      await tel.mergeFrom(pc);

      final ours = await chunkIds(tel, 'a');
      expect(ours, isNotEmpty);
      expect(ours.intersection(theirs), isEmpty);
    });

    test('los embeddings no viajan', () async {
      pc.at(3);
      await pc.saveSource('a');
      final chunk = (await chunkIds(pc, 'a')).first;
      await pc.db.customStatement(
        'INSERT INTO embeddings (chunk_id, vector, model_version, created_at) '
        "VALUES ('$chunk', x'00', 'm', 1)",
      );
      expect(await pc.count('embeddings'), 1);

      await tel.mergeFrom(pc);

      expect(await tel.count('embeddings'), 0);
    });

    test('las fuentes que acá ya estaban no se tocan', () async {
      tel.at(1);
      await tel.saveSource('mia', text: 'Mi texto, que ya estaba procesado.');
      final before = {
        for (final r
            in await tel.db
                .customSelect('SELECT id, content FROM chunks')
                .get())
          r.read<String>('id'): r.read<String>('content'),
      };
      pc.at(3);
      await pc.saveSource('a');

      final result = await tel.mergeFrom(pc);

      expect(result.sourcesChunked, 1, reason: 'solo la que llegó');
      final after = {
        for (final r
            in await tel.db
                .customSelect(
                  "SELECT id, content FROM chunks WHERE item_id = 'mia'",
                )
                .get())
          r.read<String>('id'): r.read<String>('content'),
      };
      expect(after, before);
    });

    test('una fuente sin texto no falla ni deja chunks', () async {
      pc.at(3);
      await pc.saveSource('a');
      await pc.db.customStatement('DELETE FROM renditions');
      await pc.db.customStatement('DELETE FROM chunks');

      final result = await tel.mergeFrom(pc);

      expect(result.itemsAdded, 1);
      expect(result.sourcesChunked, 0);
      expect(await tel.count('chunks'), 0);
    });

    test('fusionar otra vez no vuelve a fragmentar nada', () async {
      pc.at(3);
      await pc.saveSource('a');
      await tel.mergeFrom(pc);
      final before = await chunkIds(tel, 'a');

      final again = await tel.mergeFrom(pc);

      expect(again.changedNothing, isTrue);
      expect(await chunkIds(tel, 'a'), before);
    });
  });

  group('el fragmento de las tarjetas', () {
    test('una tarjeta que entra con rango recupera su fragmento', () async {
      pc.at(3);
      await pc.saveSource(
        'a',
        text: 'Primera parte del texto.\n\nSegunda parte del texto.',
      );
      await pc.addFlashcard('fc', 'a');
      await pc.db.customStatement(
        'UPDATE flashcards SET source_char_start = 30, source_char_end = 40',
      );

      await tel.mergeFrom(pc);

      final card = await tel.db.select(tel.db.flashcards).getSingle();
      expect(card.sourceChunkId, isNotNull);
      final chunk = await tel.db
          .customSelect(
            'SELECT char_start, char_end FROM chunks WHERE id = ?',
            variables: [Variable<String>(card.sourceChunkId)],
          )
          .getSingle();
      // El fragmento contiene el comienzo del rango.
      expect(chunk.read<int>('char_start'), lessThanOrEqualTo(30));
      expect(chunk.read<int>('char_end'), greaterThan(30));
    });

    test('una sin rango se queda sin fragmento', () async {
      pc.at(3);
      await pc.saveSource('a');
      await pc.addFlashcard('fc', 'a');

      await tel.mergeFrom(pc);

      final card = await tel.db.select(tel.db.flashcards).getSingle();
      expect(card.sourceChunkId, isNull);
      expect(card.sourceCharStart, isNull);
    });
  });

  group('los enlaces en línea de las notas', () {
    test('se registran, apuntando a lo que acá existe', () async {
      pc.at(1);
      await pc.saveBlocksNote('roma', ['La ciudad.'], title: 'Roma');
      await pc.saveBlocksNote('n', ['Ver [[Roma]] y más.']);

      final result = await tel.mergeFrom(pc);

      expect(result.itemsAdded, 2);
      final link = await tel.db
          .customSelect(
            'SELECT from_item_id, to_item_id, target_title FROM inline_link',
          )
          .getSingle();
      expect(link.read<String>('from_item_id'), 'n');
      expect(link.read<String>('to_item_id'), 'roma');
    });

    test(
      'un enlace roto de una nota de acá se resuelve con la que llega',
      () async {
        tel.at(1);
        await tel.saveBlocksNote('n', ['Ver [[Cartago]].']);
        expect(
          (await tel.db
                  .customSelect('SELECT to_item_id FROM inline_link')
                  .getSingle())
              .read<String?>('to_item_id'),
          isNull,
        );
        pc.at(2);
        await pc.saveBlocksNote('cartago', ['Otra ciudad.'], title: 'Cartago');

        tel.at(3);
        await tel.mergeFrom(pc);

        final link = await tel.db
            .customSelect('SELECT to_item_id FROM inline_link')
            .getSingle();
        expect(link.read<String?>('to_item_id'), 'cartago');
      },
    );

    test('una nota sin bloques no tiene enlaces ni falla', () async {
      pc.at(1);
      await pc.saveNote(
        'n',
        text:
            'Solo texto plano, con [[algo]] que no es '
            'un enlace.',
      );

      final result = await tel.mergeFrom(pc);

      expect(result.itemsAdded, 1);
      expect(await tel.count('inline_link'), 0);
    });
  });
}
