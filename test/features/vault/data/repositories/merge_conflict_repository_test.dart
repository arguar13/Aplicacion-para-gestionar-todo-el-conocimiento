import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/features/vault/data/repositories/merge_conflict_repository_impl.dart';
import 'package:sinapsis/features/vault/domain/entities/merge_conflict.dart';

import '../../../../support/test_vault.dart';

/// Resolver los conflictos que dejó una fusión (F11), con dos bóvedas de
/// verdad: los conflictos salen de fusionarlas, no de filas armadas a mano.
///
/// Lo que se protege: resolver escribe como una edición del usuario —con su
/// versión de campo nueva—, así que la otra bóveda la recibe sin que vuelva a
/// ser un conflicto; elegir la versión que ya está en uso no cambia ningún
/// dato; y en un texto ninguna de las dos versiones se borra.
void main() {
  late TestVault tel;
  late TestVault pc;
  late MergeConflictRepositoryImpl repository;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
    repository = MergeConflictRepositoryImpl(
      database: tel.db,
      clock: () => tel.now,
    );
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  Future<List<MergeConflict>> pending() => repository.watchPending().first;

  /// «a» nace en tel a las 12:01 y pc la recibe: las dos la tienen.
  Future<void> shareItem() async {
    tel.at(1);
    await tel.saveSource('a', title: 'Original');
    pc.at(2);
    await pc.mergeFrom(tel);
  }

  /// tel edita el título a las 5 y pc a las 7, sin verse; tel recibe lo de pc:
  /// queda en uso el de pc —el más reciente— y el de tel, guardado.
  Future<void> concurrentTitles() async {
    await shareItem();
    tel.at(5);
    await tel.saveSource('a', title: 'De tel');
    pc.at(7);
    await pc.saveSource('a', title: 'De pc');
    tel.at(9);
    await tel.mergeFrom(pc);
  }

  group('los conflictos pendientes', () {
    test('sin fusiones no hay ninguno', () async {
      expect(await pending(), isEmpty);
    });

    test('un campo: las dos versiones, de quién y cuál está en uso', () async {
      await concurrentTitles();

      final conflict = (await pending()).single;

      expect(conflict.itemId, 'a');
      expect(conflict.itemTitle, 'De pc');
      expect(conflict.fieldName, EntryField.title);
      expect(conflict.kind, MergeConflictKind.field);
      expect(conflict.local.text, 'De tel');
      expect(conflict.local.deviceId, 'tel');
      expect(conflict.local.inUse, isFalse);
      expect(conflict.incoming.text, 'De pc');
      expect(conflict.incoming.deviceId, 'pc');
      expect(conflict.incoming.inUse, isTrue);
      expect(conflict.canKeepBoth, isFalse);
      expect(conflict.itemInTrash, isFalse);
    });

    test(
      'un espacio se muestra por su nombre, no por su identificador',
      () async {
        await tel.addSpace('sp-a', 'Historia');
        await tel.addSpace('sp-b', 'Física');
        await pc.addSpace('sp-a', 'Historia');
        await pc.addSpace('sp-b', 'Física');
        await shareItem();
        tel.at(5);
        await tel.saveSource('a', title: 'Original', spaceId: 'sp-a');
        pc.at(7);
        await pc.saveSource('a', title: 'Original', spaceId: 'sp-b');
        tel.at(9);
        await tel.mergeFrom(pc);

        final conflict = (await pending()).single;

        expect(conflict.fieldName, EntryField.spaceId);
        expect(conflict.local.spaceName, 'Historia');
        expect(conflict.incoming.spaceName, 'Física');
        expect(conflict.incoming.inUse, isTrue);
      },
    );

    test(
      'un borrado contra una edición: el elemento vivo, y la fecha del borrado',
      () async {
        await shareItem();
        tel.at(5);
        await tel.library.delete('a');
        pc.at(6);
        await pc.saveSource('a', title: 'Editado');
        tel.at(9);
        await tel.mergeFrom(pc);

        final conflict = (await pending()).single;

        expect(conflict.fieldName, EntryField.deletedAt);
        expect(conflict.local.date, isNotNull, reason: 'acá estaba borrado');
        expect(conflict.incoming.date, isNull, reason: 'allá seguía vivo');
        expect(conflict.incoming.inUse, isTrue);
      },
    );

    test(
      'el texto de una fuente: el de acá en uso y el otro al lado',
      () async {
        await shareItem();
        pc.at(5);
        await pc.saveSource('a', text: 'Otro texto, editado en pc.');
        tel.at(9);
        await tel.mergeFrom(pc);

        final conflict = (await pending()).single;

        expect(conflict.kind, MergeConflictKind.text);
        expect(conflict.local.text, 'Texto de la fuente.');
        expect(conflict.local.inUse, isTrue);
        expect(conflict.incoming.text, 'Otro texto, editado en pc.');
        expect(conflict.incoming.length, 26);
        expect(conflict.incoming.inUse, isFalse);
      },
    );

    test('un texto largo llega como fragmento, con su largo', () async {
      await shareItem();
      pc.at(5);
      await pc.saveSource('a', text: 'x' * 5000);
      tel.at(9);
      await tel.mergeFrom(pc);

      final conflict = (await pending()).single;

      expect(conflict.incoming.text!.length, 600);
      expect(conflict.incoming.length, 5000);
    });

    test('los más nuevos primero', () async {
      await concurrentTitles();
      tel.at(12);
      await tel.saveSource('a', title: 'De tel', subtitle: 'Sub de tel');
      pc.at(14);
      await pc.saveSource('a', title: 'De pc', subtitle: 'Sub de pc');
      tel.at(20);
      await tel.mergeFrom(pc);

      final conflicts = await pending();

      expect(conflicts, hasLength(2));
      expect(conflicts.first.fieldName, EntryField.subtitle);
      expect(conflicts.last.fieldName, EntryField.title);
    });

    test(
      'se actualiza solo: aparece al fusionar y desaparece al resolver',
      () async {
        await shareItem();
        final seen = <int>[];
        final subscription = repository.watchPending().listen(
          (conflicts) => seen.add(conflicts.length),
        );
        addTearDown(subscription.cancel);
        await pumpEventQueue();
        tel.at(5);
        await tel.saveSource('a', title: 'De tel');
        pc.at(7);
        await pc.saveSource('a', title: 'De pc');
        tel.at(9);
        await tel.mergeFrom(pc);
        await pumpEventQueue();

        final id = (await pending()).single.id;
        await repository.resolve(id, MergeConflictChoice.keepLocal);
        await pumpEventQueue();

        expect(seen.first, 0);
        expect(seen, contains(1));
        expect(seen.last, 0);
      },
    );
  });

  group('resolver un campo', () {
    test('conservar el de acá: lo escribe como una edición nueva', () async {
      await concurrentTitles();
      final id = (await pending()).single.id;
      tel.at(20);

      final result = await repository.resolve(
        id,
        MergeConflictChoice.keepLocal,
      );

      expect(result.isRight(), isTrue);
      expect((await tel.entry('a')).title, 'De tel');
      final version = (await tel.version('a', EntryField.title))!;
      expect(version.deviceId, 'tel');
      expect(version.updatedAt, tel.now);
      // Resuelto: ya no está pendiente, y queda dicho cómo.
      expect(await pending(), isEmpty);
      final row = (await tel.conflicts()).single;
      expect(row.resolvedAt, tel.now);
      expect(row.resolution, 'keepLocal');
    });

    test('la otra bóveda recibe lo resuelto SIN un conflicto nuevo', () async {
      await concurrentTitles();
      final id = (await pending()).single.id;
      tel.at(20);
      await repository.resolve(id, MergeConflictChoice.keepLocal);

      pc.at(30);
      final result = await pc.mergeFrom(tel);

      expect(result.conflictsRecorded, 0);
      expect((await pc.entry('a')).title, 'De tel');
      expect(await pc.conflicts(), isEmpty);
    });

    test('usar el de la otra copia', () async {
      await concurrentTitles();
      final id = (await pending()).single.id;
      // Ahora está en uso el de tel: el usuario elige el de pc.
      tel.at(20);
      await repository.resolve(id, MergeConflictChoice.keepLocal);
      // Otro conflicto igual, resuelto al revés.
      tel.at(30);
      await tel.saveSource('a', title: 'De tel 2');
      pc.at(32);
      await pc.saveSource('a', title: 'De pc 2');
      tel.at(34);
      await tel.mergeFrom(pc);
      final second = (await pending()).single;
      expect(second.incoming.text, 'De pc 2');

      await repository.resolve(second.id, MergeConflictChoice.useIncoming);

      expect((await tel.entry('a')).title, 'De pc 2');
      expect((await tel.conflicts()).last.resolution, 'useIncoming');
    });

    test('elegir la que ya está en uso no cambia ningún dato', () async {
      await concurrentTitles();
      final before = await tel.entry('a');
      final versionBefore = await tel.version('a', EntryField.title);
      final conflict = (await pending()).single;
      expect(conflict.incoming.inUse, isTrue);

      await repository.resolve(conflict.id, MergeConflictChoice.useIncoming);

      expect(await tel.entry('a'), before);
      expect(await tel.version('a', EntryField.title), versionBefore);
      expect(await pending(), isEmpty);
    });

    test('guardar las dos, en las notas libres', () async {
      await shareItem();
      tel.at(5);
      await tel.saveSource('a', title: 'Original', notes: 'Notas de tel');
      pc.at(7);
      await pc.saveSource('a', title: 'Original', notes: 'Notas de pc');
      tel.at(9);
      await tel.mergeFrom(pc);
      final conflict = (await pending()).single;
      expect(conflict.fieldName, EntryField.notes);
      expect(conflict.canKeepBoth, isTrue);

      await repository.resolve(conflict.id, MergeConflictChoice.keepBoth);

      expect((await tel.entry('a')).notes, 'Notas de tel\n\nNotas de pc');
      expect((await tel.conflicts()).single.resolution, 'keepBoth');
    });

    test(
      'guardar las dos donde no tiene sentido es un error, y sigue pendiente',
      () async {
        await concurrentTitles();
        final id = (await pending()).single.id;

        final result = await repository.resolve(
          id,
          MergeConflictChoice.keepBoth,
        );

        expect(result.isLeft(), isTrue);
        expect(await pending(), hasLength(1));
        expect((await tel.entry('a')).title, 'De pc');
      },
    );

    test(
      'un borrado: conservar el de acá lo vuelve a mandar a la papelera',
      () async {
        await shareItem();
        tel.at(5);
        await tel.library.delete('a');
        pc.at(6);
        await pc.saveSource('a', title: 'Editado');
        tel.at(9);
        await tel.mergeFrom(pc);
        expect((await tel.entry('a')).deletedAt, isNull);
        final id = (await pending()).single.id;
        tel.at(20);

        await repository.resolve(id, MergeConflictChoice.keepLocal);

        expect((await tel.entry('a')).deletedAt, isNotNull);
      },
    );

    test('resolver dos veces, o uno que no existe, no es un error', () async {
      await concurrentTitles();
      final id = (await pending()).single.id;

      await repository.resolve(id, MergeConflictChoice.keepLocal);
      final again = await repository.resolve(
        id,
        MergeConflictChoice.useIncoming,
      );
      final missing = await repository.resolve(
        'no-existe',
        MergeConflictChoice.keepLocal,
      );

      expect(again.isRight(), isTrue);
      expect(missing.isRight(), isTrue);
      // La segunda elección no pisó a la primera.
      expect((await tel.entry('a')).title, 'De tel');
    });

    test(
      'una fusión posterior con la misma copia no lo vuelve a levantar',
      () async {
        await concurrentTitles();
        final id = (await pending()).single.id;
        await repository.resolve(id, MergeConflictChoice.keepLocal);

        tel.at(30);
        final again = await tel.mergeFrom(pc);

        expect(again.conflictsRecorded, 0);
        expect(await pending(), isEmpty);
      },
    );
  });

  group('resolver un texto', () {
    Future<String> sourceTextConflict() async {
      await shareItem();
      pc.at(5);
      await pc.saveSource('a', text: 'Otro texto, editado en pc.');
      tel.at(9);
      await tel.mergeFrom(pc);
      return (await pending()).single.id;
    }

    test(
      'conservar el de acá: nada cambia y el otro queda como forma',
      () async {
        final id = await sourceTextConflict();

        await repository.resolve(id, MergeConflictChoice.keepLocal);

        final forms = await tel.renditionsOf('a');
        expect(forms, hasLength(2));
        expect(
          forms.singleWhere((r) => r.isPrimary).content,
          'Texto de la fuente.',
        );
        expect(await pending(), isEmpty);
      },
    );

    test('usar el otro: pasa a ser el principal, y ninguno se borra', () async {
      final id = await sourceTextConflict();

      await repository.resolve(id, MergeConflictChoice.useIncoming);

      final forms = await tel.renditionsOf('a');
      expect(forms, hasLength(2));
      expect(
        forms.singleWhere((r) => r.isPrimary).content,
        'Otro texto, editado en pc.',
      );
      expect(
        forms.singleWhere((r) => !r.isPrimary).content,
        'Texto de la fuente.',
        reason: 'el texto de acá no se pierde',
      );
      expect((await tel.conflicts()).single.resolution, 'useIncoming');
    });

    test(
      'usar el otro rehace los chunks de la fuente, que reconstruyen su texto',
      () async {
        final id = await sourceTextConflict();

        await repository.resolve(id, MergeConflictChoice.useIncoming);

        final report = await verifyChunkInvariant(tel.db);
        expect(report.holds, isTrue, reason: report.violations.join('; '));
        final chunks = await tel.db
            .customSelect(
              "SELECT content FROM chunks WHERE item_id = 'a' ORDER BY seq",
            )
            .get();
        expect(
          chunks.map((c) => c.read<String>('content')).join(),
          'Otro texto, editado en pc.',
        );
      },
    );

    test(
      'la versión de la otra bóveda ya no está: no hay a qué pasar',
      () async {
        final id = await sourceTextConflict();
        await tel.db.customStatement(
          "DELETE FROM renditions WHERE id <> 'rend-a' AND item_id = 'a'",
        );
        final conflict = (await pending()).single;
        expect(conflict.incoming.text, isNull);

        final result = await repository.resolve(
          id,
          MergeConflictChoice.useIncoming,
        );

        expect(result.isRight(), isTrue);
        expect(
          (await tel.renditionsOf('a')).single.content,
          'Texto de la fuente.',
        );
        expect(await pending(), isEmpty);
      },
    );

    test(
      'el texto de una nota: usar el otro cambia cuál es el texto',
      () async {
        tel.at(1);
        await tel.saveNote('n', text: 'Idea inicial.');
        pc.at(2);
        await pc.mergeFrom(tel);
        tel.at(5);
        await tel.saveNote('n', text: 'De tel.');
        pc.at(7);
        await pc.saveNote('n', text: 'De pc.');
        tel.at(9);
        await tel.mergeFrom(pc);
        final conflict = (await pending()).single;
        expect(conflict.kind, MergeConflictKind.text);
        expect(conflict.local.text, 'De tel.');
        expect(conflict.incoming.text, 'De pc.');

        await repository.resolve(conflict.id, MergeConflictChoice.useIncoming);

        final forms = await tel.renditionsOf('n');
        expect(forms.singleWhere((r) => r.isPrimary).content, 'De pc.');
        expect(forms.where((r) => !r.isPrimary).single.content, 'De tel.');
      },
    );
  });
}
