import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/data/merge/merge_gates.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

import '../../../../support/test_vault.dart';

/// Las compuertas de la fusión (F11).
///
/// Las GUARDAS hacen imposible lo que una fusión nunca debe hacer —borrar un
/// elemento o una forma de texto, reescribir el texto de una fuente, tocar los
/// chunks de lo que no cambió—; las VERIFICACIONES miran el resultado y, si
/// algo no se cumple, la fusión se revierte entera.
void main() {
  late TestVault tel;
  late TestVault pc;
  late MergeGates gates;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
    gates = MergeGates(tel.db);
    tel.at(1);
    await tel.saveSource('a', text: 'El texto de la fuente A.');
    await tel.saveNote('n', text: 'Una nota.');
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  Matcher aGuard() => throwsA(
    predicate(
      (e) => e.toString().contains('merge-guard'),
      'un aborto de las guardas de la fusión',
    ),
  );

  Matcher aGate(String gate) => throwsA(
    isA<VaultMergeGateException>().having((e) => e.gate, 'gate', gate),
  );

  Future<void> sql(String statement) => tel.db.customStatement(statement);

  group('las guardas', () {
    setUp(() async {
      await MergeWork.create(tel.db);
      await gates.installGuards();
    });

    tearDown(() async {
      await gates.removeGuards();
      await MergeWork.drop(tel.db);
    });

    test('un elemento no se borra', () async {
      await expectLater(sql("DELETE FROM item WHERE id = 'a'"), aGuard());
      await expectLater(sql("DELETE FROM item WHERE id = 'n'"), aGuard());
      expect(await tel.count('item'), 2);
    });

    test('una forma de texto no se borra', () async {
      await expectLater(sql('DELETE FROM renditions'), aGuard());
      expect(await tel.count('renditions'), 2);
    });

    test('el texto de una fuente no se reescribe', () async {
      await expectLater(
        sql("UPDATE renditions SET content = 'otro' WHERE item_id = 'a'"),
        aGuard(),
      );
      expect(
        (await tel.renditionsOf('a')).single.content,
        'El texto de la fuente A.',
      );
    });

    test('ni el archivo de una forma de fuente', () async {
      await expectLater(
        sql("UPDATE renditions SET relative_path = 'x' WHERE item_id = 'a'"),
        aGuard(),
      );
    });

    test(
      'el texto de una nota sí puede cambiar: es lo que el usuario escribe',
      () async {
        await sql(
          "UPDATE renditions SET content = 'editada' WHERE item_id = 'n'",
        );

        expect((await tel.renditionsOf('n')).single.content, 'editada');
      },
    );

    test('lo que no es el texto de una fuente se puede escribir', () async {
      await sql("UPDATE renditions SET is_primary = 1 WHERE item_id = 'a'");
      await sql("UPDATE item SET title = 'Otro' WHERE id = 'a'");
      await sql(
        'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
        "created_at) VALUES ('extra', 'a', 'plainText', 'otra', 0, 1)",
      );
    });

    test('los chunks de lo que la fusión no marcó no se tocan', () async {
      expect(await tel.count('chunks'), greaterThan(0));
      await expectLater(
        sql("UPDATE chunks SET content = 'X' WHERE item_id = 'a'"),
        aGuard(),
      );
      await expectLater(
        sql("DELETE FROM chunks WHERE item_id = 'a'"),
        aGuard(),
      );
    });

    test('los de lo que sí marcó pueden rehacerse', () async {
      await sql("INSERT INTO ${MergeWork.touchedItems} (id) VALUES ('a')");

      await sql("DELETE FROM chunks WHERE item_id = 'a'");

      expect(await tel.count('chunks'), 0);
    });
  });

  group('sin guardas', () {
    test('todo vuelve a poder hacerse, y no queda rastro', () async {
      await MergeWork.create(tel.db);
      await gates.installGuards();
      await gates.removeGuards();
      // Soltarlas dos veces no es un problema.
      await gates.removeGuards();
      await MergeWork.drop(tel.db);

      await sql("DELETE FROM chunks WHERE item_id = 'a'");
      final triggers = await tel.db
          .customSelect(
            "SELECT name FROM sqlite_temp_master WHERE type = 'trigger'",
          )
          .get();
      expect(triggers, isEmpty);
    });
  });

  group('las verificaciones', () {
    Future<void> verify({
      required MergeSnapshot before,
      int itemsAdded = 0,
      Iterable<String> rebuilt = const [],
    }) =>
        gates.verify(before: before, itemsAdded: itemsAdded, rebuilt: rebuilt);

    test('pasan si no cambió nada', () async {
      final before = await gates.snapshot();

      await verify(before: before);
    });

    test('pasan si solo entró lo que se dijo', () async {
      final before = await gates.snapshot();
      await sql(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('nuevo', 'N', 'note', 'inbox', 1, 1, 'tel')",
      );

      await verify(before: before, itemsAdded: 1);
    });

    test('items: un elemento de más, o de menos', () async {
      final before = await gates.snapshot();
      await sql(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('colado', 'C', 'note', 'inbox', 1, 1, 'tel')",
      );

      await expectLater(verify(before: before), aGate('items'));
      await expectLater(verify(before: before, itemsAdded: 2), aGate('items'));
    });

    test('counts: una tabla con menos filas que antes', () async {
      await tel.addRelation('r', 'a', 'n');
      await tel.addFlashcard('fc', 'a');
      final before = await gates.snapshot();
      await sql("DELETE FROM flashcards WHERE id = 'fc'");

      await expectLater(verify(before: before), aGate('counts'));
    });

    test('counts: las versiones por campo sí pueden quedar en menos', () async {
      final before = await gates.snapshot();
      await sql('DELETE FROM field_version');

      await verify(before: before);
    });

    test('text: chunks que no reconstruyen el texto', () async {
      final before = await gates.snapshot();
      await sql("UPDATE chunks SET content = 'otra cosa' WHERE item_id = 'a'");

      await expectLater(verify(before: before, rebuilt: ['a']), aGate('text'));
    });

    test(
      'text: ese mismo daño en algo que no se reprocesó no lo mira',
      () async {
        // Las guardas son las que protegen lo que no se marcó; la verificación
        // solo mira lo reprocesado.
        final before = await gates.snapshot();
        await sql(
          "UPDATE chunks SET content = 'otra cosa' WHERE item_id = 'a'",
        );

        await verify(before: before);
      },
    );

    test(
      'text: una fuente que quedó sin chunks se tolera —se reintenta—',
      () async {
        final before = await gates.snapshot();
        await sql("DELETE FROM chunks WHERE item_id = 'a'");

        await verify(before: before, rebuilt: ['a']);
      },
    );

    test('references: algo que apunta a lo que no existe', () async {
      final before = await gates.snapshot();
      await sql('PRAGMA foreign_keys = OFF');
      await sql(
        'INSERT INTO relations (id, from_item_id, to_item_id, kind, '
        'created_at) '
        "VALUES ('rota', 'a', 'no-existe', 'cites', 1)",
      );
      await sql('PRAGMA foreign_keys = ON');

      await expectLater(verify(before: before), aGate('references'));
    });

    test(
      'references: lo que ya estaba roto antes no es culpa de la fusión',
      () async {
        await sql('PRAGMA foreign_keys = OFF');
        await sql(
          'INSERT INTO relations (id, from_item_id, to_item_id, kind, '
          'created_at) '
          "VALUES ('vieja', 'a', 'no-existe', 'cites', 1)",
        );
        await sql('PRAGMA foreign_keys = ON');
        final before = await gates.snapshot();

        await verify(before: before);
      },
    );
  });

  group('en la fusión', () {
    test('una guarda que salta revierte todo, hasta lo ya escrito', () async {
      final before = await tel.counts();
      pc.at(3);
      await pc.saveSource('nuevo');

      await expectLater(
        tel.mergeFrom(
          pc,
          afterWrites: (db) =>
              db.customStatement("DELETE FROM item WHERE id = 'a'"),
        ),
        aGuard(),
      );

      expect(await tel.counts(), before);
      expect(await tel.count('item'), 2);
    });

    test('una compuerta que no se cumple revierte todo', () async {
      final before = await tel.counts();
      pc.at(3);
      await pc.saveSource('nuevo');

      await expectLater(
        tel.mergeFrom(
          pc,
          afterWrites: (db) async {
            await MergeGates(db).removeGuards();
            await db.customStatement('DELETE FROM highlights');
            await db.customStatement("DELETE FROM item WHERE id = 'n'");
          },
        ),
        aGate('items'),
      );

      expect(await tel.counts(), before);
      expect((await tel.entry('n')).id, 'n');
    });

    test('después de un fallo se puede volver a fusionar', () async {
      pc.at(3);
      await pc.saveSource('nuevo');
      await expectLater(
        tel.mergeFrom(pc, afterFiles: (_) async => throw StateError('falla')),
        throwsA(isA<StateError>()),
      );

      final result = await tel.mergeFrom(pc);

      expect(result.itemsAdded, 1);
      expect(await tel.count('item'), 3);
    });

    test(
      'no queda nada de la fusión: ni guardas, ni tablas, ni la copia',
      () async {
        pc.at(3);
        await pc.saveSource('nuevo');
        await tel.mergeFrom(pc);

        final leftovers = await tel.db
            .customSelect(
              "SELECT name FROM sqlite_temp_master WHERE name LIKE 'merge_%'",
            )
            .get();
        expect(leftovers, isEmpty);
        final attached = await tel.db
            .customSelect('PRAGMA database_list')
            .get();
        expect(
          attached.map((r) => r.read<String>('name')),
          isNot(contains('incoming')),
        );
      },
    );
  });
}
